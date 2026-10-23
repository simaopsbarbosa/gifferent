#!/usr/bin/env python3
"""check benchmark failure and cancellation cleanup without real encoders."""

import hashlib
import shlex
import tempfile
import unittest
from pathlib import Path

from generate_fixture import draw_frame
from run_encoder_benchmark import (
    command_for,
    expected_frame_delays,
    fixture_digest,
    gif_metadata,
    run_one,
)


def tiny_gif_with_delays(delays):
    header = bytes.fromhex("47494638396101000100800000000000ffffff")
    image = bytes.fromhex("2c0000000001000100000202440100")
    frames = b"".join(
        bytes.fromhex("21f90401")
        + int(delay).to_bytes(2, "little")
        + bytes.fromhex("0000")
        + image
        for delay in delays
    )
    return header + frames + bytes.fromhex("3b")


MANIFEST = {"fps": 24, "width": 1, "height": 1, "duration_seconds": 2 / 24}
SIX_FRAME_MANIFEST = {"fps": 24, "width": 1, "height": 1, "duration_seconds": 6 / 24}


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
            result = run_one("imageio", tools, MANIFEST, [frame], output, "probe", timeout, False)
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
            gif.write_bytes(tiny_gif_with_delays([4]))
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            result = run_one(
                "imageio",
                tools,
                {**MANIFEST, "duration_seconds": 1 / 24},
                [frame],
                output,
                "valid",
                2,
                False,
            )

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["gif"]["frame_count"], 1)
            self.assertEqual(result["gif"]["frame_delays_centiseconds"], [4])
            self.assertTrue(Path(result["output"]).is_file())
            self.assertFalse((output / "work" / "imageio-valid").exists())

    def test_frame_count_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "valid.gif"
            gif.write_bytes(tiny_gif_with_delays([4]))
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frames = [output / "frame-0.png", output / "frame-1.png"]
            for frame in frames:
                frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            result = run_one("imageio", tools, MANIFEST, frames, output, "short", 2, False)

            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("differs from fixture count", result["error"])
            self.assertFalse((output / "work" / "imageio-short").exists())
            self.assertFalse((output / "gifs" / "imageio" / "short.gif").exists())

    def test_reordered_delays_with_same_duration_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "timing.gif"
            gif.write_bytes(tiny_gif_with_delays([4, 5, 4, 4, 4, 4]))
            encoder.write_text("#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n")
            encoder.chmod(0o755)
            frames = [output / f"frame-{index}.png" for index in range(6)]
            for frame in frames:
                frame.write_bytes(b"synthetic")
            result = run_one(
                "imageio",
                {"imageio": {"path": str(encoder)}},
                SIX_FRAME_MANIFEST,
                frames,
                output,
                "reordered",
                2,
                False,
            )
            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("per-frame centisecond delay differs at frame 1", result["error"])
            self.assertEqual(sum(gif_metadata(gif)["frame_delays_centiseconds"]), 25)
            self.assertEqual(expected_frame_delays(24, 6), [4, 4, 5, 4, 4, 4])

    def test_incorrect_delays_with_same_duration_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "timing.gif"
            gif.write_bytes(tiny_gif_with_delays([3, 6, 4, 4, 4, 4]))
            encoder.write_text("#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n")
            encoder.chmod(0o755)
            frames = [output / f"frame-{index}.png" for index in range(6)]
            for frame in frames:
                frame.write_bytes(b"synthetic")
            result = run_one(
                "imageio",
                {"imageio": {"path": str(encoder)}},
                SIX_FRAME_MANIFEST,
                frames,
                output,
                "incorrect",
                2,
                False,
            )
            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("per-frame centisecond delay differs at frame 0", result["error"])
            self.assertEqual(sum(gif_metadata(gif)["frame_delays_centiseconds"]), 25)

    def test_wrong_dimensions_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "valid.gif"
            gif.write_bytes(tiny_gif_with_delays([4]))
            encoder.write_text("#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n")
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            manifest = {**MANIFEST, "width": 2, "duration_seconds": 1 / 24}
            result = run_one(
                "imageio",
                {"imageio": {"path": str(encoder)}},
                manifest,
                [frame],
                output,
                "dimensions",
                2,
                False,
            )
            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("dimensions", result["error"])

    def test_24_fps_schedule_rounds_cumulative_boundaries(self):
        delays = expected_frame_delays(24, 240)
        self.assertEqual(sum(delays), 1000)
        self.assertEqual(delays[:8], [4, 4, 5, 4, 4, 4, 4, 4])

    def test_wrong_duration_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            encoder = output / "fake-encoder"
            gif = output / "duration.gif"
            gif.write_bytes(tiny_gif_with_delays([4]))
            encoder.write_text(
                "#!/bin/sh\ncp " + shlex.quote(str(gif)) + " \"$2\"\nexit 0\n"
            )
            encoder.chmod(0o755)
            frame = output / "frame.png"
            frame.write_bytes(b"synthetic")
            tools = {"imageio": {"path": str(encoder)}}

            manifest = {**MANIFEST, "duration_seconds": 1 / 6}
            result = run_one("imageio", tools, manifest, [frame], output, "duration", 2, False)

            self.assertEqual(result["status"], "invalid_output")
            self.assertIn("differs from fixture duration", result["error"])
            self.assertFalse((output / "gifs" / "imageio" / "duration.gif").exists())

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

    def test_magick_command_sets_each_quantized_frame_delay(self):
        command = command_for(
            "magick",
            {"magick": {"path": "/opt/homebrew/bin/magick"}},
            24,
            [Path("frame_0000.png"), Path("frame_0001.png"), Path("frame_0002.png")],
            Path("output.gif"),
        )
        self.assertEqual(
            command[1:7],
            [
                "-delay",
                "4x100",
                "frame_0000.png",
                "-delay",
                "4x100",
                "frame_0001.png",
            ],
        )
        self.assertEqual(command[7:10], ["-delay", "5x100", "frame_0002.png"])

    def test_magick_loop_setting_follows_input_frames(self):
        command = command_for(
            "magick",
            {"magick": {"path": "/opt/homebrew/bin/magick"}},
            24,
            [Path("frame_0000.png"), Path("frame_0001.png")],
            Path("output.gif"),
        )
        self.assertLess(command.index("frame_0001.png"), command.index("-loop"))


class FixtureProfileTests(unittest.TestCase):
    profiles = (
        "mixed",
        "mostly-static-ui",
        "fast-scrolling",
        "high-motion-gradient-cursor",
    )

    def frame_digest(self, profile, frame, seed=7):
        canvas = draw_frame(320, 180, frame, seed, profile)
        return hashlib.sha256(canvas.pixels).hexdigest()

    def test_each_profile_changes_between_adjacent_frames(self):
        for profile in self.profiles:
            with self.subTest(profile=profile):
                self.assertNotEqual(self.frame_digest(profile, 0), self.frame_digest(profile, 1))

    def test_profiles_are_repeatable_for_same_seed_and_frame(self):
        for profile in self.profiles:
            with self.subTest(profile=profile):
                self.assertEqual(self.frame_digest(profile, 37), self.frame_digest(profile, 37))

    def test_focused_profiles_have_distinct_content(self):
        digests = {profile: self.frame_digest(profile, 12) for profile in self.profiles}
        self.assertEqual(len(set(digests.values())), len(self.profiles))




if __name__ == "__main__":
    unittest.main()
