#!/usr/bin/env python3
"""check benchmark failure and cancellation cleanup without real encoders."""

import tempfile
import shlex
import unittest
from pathlib import Path

from run_encoder_benchmark import command_for, fixture_digest, run_one


ONE_FRAME_GIF = bytes.fromhex(
    "47494638396101000100800000000000ffffff21f90401040000002c00000000010001000002024401003b"
)
ZERO_DELAY_GIF = bytes.fromhex(
    "47494638396101000100800000000000ffffff21f90401000000002c00000000010001000002024401003b"
)


class CleanupTests(unittest.TestCase):
    def run_fake(self, body, timeout):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            encoder.write_text("#!/bin/sh\n" + body)
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}
            result = run_one("imageio", tools, 24, [frame], output, "probe", timeout, False)
            self.assertFalse((output / "work" / "imageio-probe").exists())
            self.assertFalse((output / "gifs" / "imageio" / "probe.gif").exists())
            return result

    def test_failed_encoder_removes_partial_output(self):
        result = self.run_fake('printf "partial" > "$2"\nexit 7\n', 2)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["exit_code"], 7)

    def test_timeout_removes_partial_output(self):
        result = self.run_fake('printf "partial" > "$2"\nsleep 3\n', 0.05)
        self.assertEqual(result["status"], "timeout")
        self.assertTrue(result["timed_out"])

    def test_invalid_gif_removes_output(self):
        result = self.run_fake('printf "GIF89a" > "$2"\nexit 0\n', 2)
        self.assertEqual(result["status"], "invalid_output")

    def test_valid_gif_is_retained_with_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "valid.gif"
            gif.write_bytes(ONE_FRAME_GIF)
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            result = run_one("imageio", tools, 24, [frame], output, "valid", 2, False)

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["gif"]["frame_count"], 1)
            self.assertTrue(Path(result["output"]).is_file())
            self.assertFalse((output / "work" / "imageio-valid").exists())

    def test_frame_count_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "valid.gif"
            gif.write_bytes(ONE_FRAME_GIF)
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frames = [output / "frame-0.png", output / "frame-1.png"]
            for frame in frames:
                frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            result = run_one("imageio", tools, 24, frames, output, "short", 2, False)

            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("differs from fixture count", result["error"])
            self.assertFalse((output / "work" / "imageio-short").exists())
            self.assertFalse((output / "gifs" / "imageio" / "short.gif").exists())

    def test_wrong_duration_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "zero-delay.gif"
            gif.write_bytes(ZERO_DELAY_GIF)
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            result = run_one("imageio", tools, 24, [frame], output, "zero-delay", 2, False)

            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("differs from fixture duration", result["error"])
            self.assertFalse((output / "gifs" / "imageio" / "zero-delay.gif").exists())

    def test_fixture_digest_tracks_frame_names_and_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "frame-0.png"
            second = Path(directory) / "frame-1.png"
            first.write_bytes(b"first")
            second.write_bytes(b"second")
            original = fixture_digest([first, second])
            self.assertEqual(fixture_digest([first, second]), original)
            second.write_bytes(b"changed")
            self.assertNotEqual(fixture_digest([first, second]), original)

    def test_imageio_command_orders_fps_output_and_frames(self):
        command = command_for(
            "imageio",
            {"imageio": {"path": "/tmp/imageio_encode"}},
            24,
            [Path("frame-0.png"), Path("frame-1.png")],
            Path("output.gif"),
        )
        self.assertEqual(
            command,
            ["/tmp/imageio_encode", "24", "output.gif", "frame-0.png", "frame-1.png"],
        )

    def test_gifski_command_pins_quality_and_preserves_frame_order(self):
        command = command_for(
            "gifski",
            {"gifski": {"path": "/opt/homebrew/bin/gifski"}},
            24,
            [Path("frame_0000.png"), Path("frame_0001.png")],
            Path("output.gif"),
        )
        self.assertEqual(
            command,
            [
                "/opt/homebrew/bin/gifski",
                "--fps",
                "24",
                "--quality",
                "90",
                "--repeat",
                "0",
                "--no-sort",
                "-o",
                "output.gif",
                "frame_0000.png",
                "frame_0001.png",
            ],
        )

    def test_magick_loop_setting_follows_input_frames(self):
        command = command_for(
            "magick",
            {"magick": {"path": "/opt/homebrew/bin/magick"}},
            24,
            [Path("frame_0000.png"), Path("frame_0001.png")],
            Path("output.gif"),
        )
        self.assertLess(command.index("frame_0001.png"), command.index("-loop"))


if __name__ == "__main__":
    unittest.main()
