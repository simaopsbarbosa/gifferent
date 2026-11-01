"""verify orchestration without launching Xcode or touching the desktop."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import importlib.util
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent


class CIScriptTests(unittest.TestCase):
    def test_result_evidence_requires_passing_tests_and_reasoned_skips(self):
        spec = importlib.util.spec_from_file_location("result_check", ROOT / "Scripts/check-test-result.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.validate({"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0})
        module.validate({"result": "Passed", "passedTests": 174, "failedTests": 0, "skippedTests": 1},
                        "Test skipped - install the optional integration dependency")
        with self.assertRaises(ValueError):
            module.validate({"result": "Passed", "passedTests": 1, "skippedTests": 1})
        with self.assertRaises(ValueError):
            module.validate({"result": "Passed", "passedTests": 1, "skippedTests": 1},
                            "Test skipped - \n")
        for summary in ({"result": "Passed", "passedTests": 0},
                        {"result": "Failed", "passedTests": 1, "failedTests": 1}):
            with self.assertRaises(ValueError):
                module.validate(summary)

    def test_fingerprint_changes_for_sources_and_signing_but_not_prose(self):
        spec = importlib.util.spec_from_file_location("fingerprint", ROOT / "Scripts/test-build-fingerprint.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Sources").mkdir()
            source = root / "Sources/Example.swift"
            source.write_text("let value = 1\n")
            (root / "README.md").write_text("first\n")

            def output(command, **kwargs):
                if command[0] == "git":
                    return b"Sources/Example.swift\0"
                return b"test toolchain"

            with patch.object(module.subprocess, "check_output", side_effect=output):
                original = module.fingerprint(root)
                (root / "README.md").write_text("changed prose\n")
                self.assertEqual(original, module.fingerprint(root))
                source.write_text("let value = 2\n")
                changed = module.fingerprint(root)
                self.assertNotEqual(original, changed)
                with patch.dict(os.environ, {"GIFFERENT_TEST_DEVELOPMENT_TEAM": "another-team"}):
                    self.assertNotEqual(changed, module.fingerprint(root))
                source.unlink()
                self.assertNotEqual(changed, module.fingerprint(root))

    def test_filters_reject_other_targets_and_options(self):
        for selector in ("gifferentUITests/Smoke", "-skip-testing:gifferentTests"):
            result = subprocess.run(
                ["bash", "-c", 'source Scripts/common.sh; test_filters gifferentTests "$1"',
                 "test", selector], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)

    def test_focused_filters_do_not_add_the_full_target(self):
        result = subprocess.run(
            ["bash", "-c", 'source Scripts/common.sh; test_filters gifferentTests '
             'gifferentTests/GIFEditModelTests; printf "%s\\n" "${test_filter_args[@]}"'],
            cwd=ROOT, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "-only-testing:gifferentTests/GIFEditModelTests")

    def test_no_build_refuses_missing_stamp_before_launching_tests(self):
        with tempfile.TemporaryDirectory() as artifacts:
            result = subprocess.run(
                ["bash", "Scripts/test-unit.sh", "--no-build"], cwd=ROOT,
                env={**os.environ, "GIFFERENT_ARTIFACTS_DIR": artifacts},
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("test build missing or stale", result.stderr)
            self.assertNotIn("+ xcodebuild", result.stdout)

    def test_failed_xcodebuild_is_not_hidden_by_tee(self):
        with tempfile.TemporaryDirectory() as temporary:
            command = Path(temporary) / "xcodebuild"
            command.write_text('#!/bin/sh\necho "synthetic failure"\nexit 65\n')
            command.chmod(0o755)
            result = subprocess.run(
                ["bash", "-c", 'set -euo pipefail; source Scripts/common.sh; '
                 'run_xcodebuild "$1" test-without-building', "test", f"{temporary}/test.log"],
                cwd=ROOT, env={**os.environ, "PATH": f"{temporary}:{os.environ['PATH']}"},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 65)
            self.assertIn("synthetic failure", Path(temporary, "test.log").read_text())

    def run_ui_failure(self, output):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = root / "artifacts"
            binaries = root / "bin"
            binaries.mkdir()
            for name, body in {
                "xcodebuild": 'if [ "$1" = "-version" ]; then echo "test Xcode"; exit 0; fi\n'
                              'echo invoked >> "$ATTEMPT_LOG"\n'
                              'printf "%s\\n" "$SYNTHETIC_OUTPUT"\nexit 65\n',
                "xcode-select": 'echo "/test/Xcode"\n',
                "sw_vers": 'echo "test OS"\n',
                "sysctl": 'echo "test boot"\n',
                "launchctl": 'exit 0\n',
            }.items():
                executable = binaries / name
                executable.write_text("#!/bin/sh\n" + body)
                executable.chmod(0o755)
            environment = {**os.environ, "PATH": f"{binaries}:{os.environ['PATH']}",
                           "GIFFERENT_ARTIFACTS_DIR": str(artifacts),
                           "ATTEMPT_LOG": str(root / "attempts"), "SYNTHETIC_OUTPUT": output}
            stamp = artifacts / "TestDerivedData/gifferent-build-fingerprint"
            stamp.parent.mkdir(parents=True)
            fingerprint = subprocess.check_output(
                ["python3", "Scripts/test-build-fingerprint.py"], cwd=ROOT, env=environment)
            stamp.write_bytes(fingerprint)
            first = subprocess.run(["bash", "Scripts/test-ui.sh", "--no-build"],
                                   cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(first.returncode, 65, first.stderr)
            second = subprocess.run(["bash", "Scripts/test-ui.sh", "--no-build"],
                                    cwd=ROOT, env=environment, capture_output=True, text=True)
            return second, (root / "attempts").read_text().splitlines()

    def test_bootstrap_failure_stops_unchanged_retries(self):
        second, attempts = self.run_ui_failure("failed before establishing XCTest connection")
        self.assertEqual(len(attempts), 1)
        self.assertEqual(second.returncode, 1)
        self.assertIn("startup remains blocked", second.stderr)

    def test_assertion_failure_does_not_poison_environment(self):
        second, attempts = self.run_ui_failure(
            "Test Case '-[gifferentUITests.MenuBarSmokeTests testExample]' started.\nXCTAssertTrue failed")
        self.assertEqual(len(attempts), 2)
        self.assertEqual(second.returncode, 65)
        self.assertNotIn("startup remains blocked", second.stderr)


if __name__ == "__main__":
    unittest.main()
