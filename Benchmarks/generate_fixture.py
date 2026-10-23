#!/usr/bin/env python3
"""generate synthetic, reproducible png frames for local encoder benchmarks."""

import argparse
import json
import random
import struct
import zlib
from pathlib import Path


FPS = 24
BASE_WIDTH = 640
BASE_HEIGHT = 360
FONT = {
    " ": (0, 0, 0, 0, 0, 0, 0),
    ".": (0, 0, 0, 0, 0, 4, 4),
    ":": (0, 4, 4, 0, 4, 4, 0),
    "0": (14, 17, 19, 21, 25, 17, 14),
    "1": (4, 12, 4, 4, 4, 4, 14),
    "2": (14, 17, 1, 2, 4, 8, 31),
    "3": (30, 1, 1, 14, 1, 1, 30),
    "4": (2, 6, 10, 18, 31, 2, 2),
    "5": (31, 16, 30, 1, 1, 17, 14),
    "6": (6, 8, 16, 30, 17, 17, 14),
    "7": (31, 1, 2, 4, 8, 8, 8),
    "8": (14, 17, 17, 14, 17, 17, 14),
    "9": (14, 17, 17, 15, 1, 2, 12),
    "a": (0, 14, 1, 15, 17, 17, 15),
    "b": (16, 16, 30, 17, 17, 17, 30),
    "c": (0, 15, 16, 16, 16, 16, 15),
    "d": (1, 1, 15, 17, 17, 17, 15),
    "e": (0, 14, 17, 31, 16, 16, 14),
    "f": (6, 8, 8, 30, 8, 8, 8),
    "g": (0, 15, 17, 17, 15, 1, 14),
    "h": (16, 16, 30, 17, 17, 17, 17),
    "i": (4, 0, 12, 4, 4, 4, 14),
    "l": (12, 4, 4, 4, 4, 4, 14),
    "m": (0, 26, 21, 21, 21, 21, 21),
    "n": (0, 30, 17, 17, 17, 17, 17),
    "o": (0, 14, 17, 17, 17, 17, 14),
    "p": (0, 30, 17, 17, 30, 16, 16),
    "r": (0, 22, 24, 16, 16, 16, 16),
    "s": (0, 15, 16, 14, 1, 1, 30),
    "t": (8, 8, 30, 8, 8, 8, 6),
    "u": (0, 17, 17, 17, 17, 17, 15),
    "v": (0, 17, 17, 17, 17, 10, 4),
    "w": (0, 17, 17, 21, 21, 21, 10),
    "y": (0, 17, 17, 17, 15, 1, 14),
    "x": (0, 17, 10, 4, 10, 17, 17),
}


class Canvas:
    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.pixels = bytearray(bytes((24, 27, 32)) * (width * height))

    def x(self, value: int) -> int:
        return value * self.width // BASE_WIDTH

    def y(self, value: int) -> int:
        return value * self.height // BASE_HEIGHT

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]):
        left = max(0, min(self.width, self.x(x0)))
        top = max(0, min(self.height, self.y(y0)))
        right = max(left, min(self.width, self.x(x1)))
        bottom = max(top, min(self.height, self.y(y1)))
        row = bytes(color) * (right - left)
        for y in range(top, bottom):
            start = (y * self.width + left) * 3
            self.pixels[start : start + len(row)] = row

    def text(self, label: str, x: int, y: int, color: tuple[int, int, int]):
        scale = max(1, min(self.width // BASE_WIDTH, self.height // BASE_HEIGHT) * 2)
        px = self.x(x)
        py = self.y(y)
        for character in label:
            if character not in FONT:
                raise ValueError(f"unsupported fixture glyph: {character!r}")
            for row_index, bits in enumerate(FONT[character]):
                for column in range(5):
                    if bits & (1 << (4 - column)):
                        left = px + column * scale
                        top = py + row_index * scale
                        self.pixel_rect(left, top, left + scale, top + scale, color)
            px += 6 * scale

    def pixel_rect(self, left: int, top: int, right: int, bottom: int, color: tuple[int, int, int]):
        left = max(0, min(self.width, left))
        right = max(left, min(self.width, right))
        top = max(0, min(self.height, top))
        bottom = max(top, min(self.height, bottom))
        row = bytes(color) * (right - left)
        for y in range(top, bottom):
            start = (y * self.width + left) * 3
            self.pixels[start : start + len(row)] = row


def gradient(canvas: Canvas, frame: int, seed: int):
    left, top, right, bottom = (canvas.x(338), canvas.y(104), canvas.x(606), canvas.y(288))
    width = right - left
    palette = []
    for value in range(256):
        palette.append(
            bytes(
                (
                    (value + seed * 13) % 256,
                    (80 + value // 3 + seed * 7) % 256,
                    (220 - value // 2 + seed * 3) % 256,
                )
            )
        )
    for y in range(top, bottom):
        phase = (frame * 5 + (y - top) * 2) % 256
        row = b"".join(palette[(x * 256 // max(width, 1) + phase) % 256] for x in range(width))
        start = (y * canvas.width + left) * 3
        canvas.pixels[start : start + len(row)] = row


def draw_frame(width: int, height: int, frame: int, seed: int, profile: str = "mixed") -> Canvas:
    if profile == "mostly-static-ui":
        return draw_static_ui(width, height, frame)
    if profile == "fast-scrolling":
        return draw_fast_scrolling(width, height, frame)
    if profile == "high-motion-gradient-cursor":
        return draw_high_motion_gradient_cursor(width, height, frame, seed)

    canvas = Canvas(width, height)
    canvas.rect(20, 16, 620, 344, (39, 43, 50))
    canvas.rect(20, 16, 620, 50, (52, 57, 65))
    canvas.rect(34, 28, 45, 39, (70, 168, 191))
    canvas.text("sample", 55, 27, (239, 239, 237))
    canvas.rect(34, 74, 310, 310, (27, 31, 37))
    canvas.text("capture", 48, 88, (225, 226, 221))
    canvas.rect(48, 116, 296, 234, (73, 81, 91))
    canvas.rect(56, 124, 288, 226, (34, 39, 45))
    canvas.rect(70, 139, 255, 151, (101, 111, 122))
    canvas.rect(70, 161, 221, 169, (85, 94, 105))
    canvas.rect(70, 180, 239, 188, (85, 94, 105))
    canvas.rect(70, 201, 114, 214, (70, 168, 191))
    canvas.rect(123, 201, 193, 214, (113, 122, 133))
    canvas.text("recording", 48, 254, (230, 231, 227))
    canvas.text(f"{frame // FPS:02d}:{frame % FPS:02d}", 48, 279, (70, 168, 191))
    canvas.rect(327, 74, 606, 310, (27, 31, 37))
    canvas.text("motion", 339, 88, (225, 226, 221))
    gradient(canvas, frame, seed)
    rng = random.Random(seed)
    for index in range(12):
        x = 343 + (rng.randrange(245) + frame * (index % 3 + 1)) % 245
        y = 109 + rng.randrange(175)
        color = (255, 238, 190) if index % 2 else (30, 44, 78)
        canvas.rect(x, y, x + 3, y + 3, color)
    cursor_x = 66 + frame * 5 % 480
    cursor_y = 131 + frame * 3 % 155
    px, py = canvas.x(cursor_x), canvas.y(cursor_y)
    size = max(8, canvas.x(14))
    for offset in range(size):
        canvas.pixel_rect(px, py + offset, px + max(2, offset // 2), py + offset + 1, (18, 19, 21))
    for offset in range(size - 2):
        canvas.pixel_rect(px + 1, py + offset + 1, px + max(2, offset // 2), py + offset + 2, (248, 248, 246))
    canvas.rect(338, 298, 606, 302, (78, 83, 89))
    canvas.rect(338, 298, 338 + frame * 268 // 239, 302, (70, 168, 191))
    return canvas


def draw_static_ui(width: int, height: int, frame: int) -> Canvas:
    canvas = Canvas(width, height)
    canvas.rect(20, 16, 620, 344, (39, 43, 50))
    canvas.rect(20, 16, 620, 50, (52, 57, 65))
    canvas.rect(34, 28, 45, 39, (70, 168, 191))
    canvas.text("capture session", 55, 27, (239, 239, 237))
    canvas.rect(34, 70, 606, 310, (27, 31, 37))
    canvas.text("recording status", 52, 88, (225, 226, 221))
    canvas.text("frames captured", 52, 126, (162, 171, 181))
    canvas.text("privacy on device", 52, 158, (162, 171, 181))
    canvas.text("ready to preview", 52, 190, (162, 171, 181))
    canvas.rect(52, 228, 542, 232, (70, 168, 191))
    canvas.rect(52, 258, 542, 262, (73, 81, 91))
    canvas.rect(52, 288, 542, 292, (73, 81, 91))
    # keep the interface static while a one-pixel caret moves on each frame.
    caret_x = 290 + (frame * 2) % 220
    canvas.pixel_rect(canvas.x(caret_x), canvas.y(126), canvas.x(caret_x) + 1, canvas.y(138), (70, 168, 191))
    return canvas


def draw_fast_scrolling(width: int, height: int, frame: int) -> Canvas:
    canvas = Canvas(width, height)
    canvas.rect(20, 16, 620, 344, (39, 43, 50))
    canvas.rect(20, 16, 620, 50, (52, 57, 65))
    canvas.text("activity feed", 42, 27, (239, 239, 237))
    canvas.rect(34, 66, 606, 320, (27, 31, 37))
    labels = ("capture", "frames", "preview", "clipboard", "export", "settings", "recording", "window")
    scroll = frame * 5
    for index in range(12):
        y = 76 + ((index * 25 - scroll) % 260)
        canvas.rect(48, y, 592, y + 18, (39, 45, 52))
        canvas.text(labels[index % len(labels)], 60, y + 5, (225, 226, 221))
        canvas.rect(190, y + 8, 250 + (index % 5) * 22, y + 11, (101, 111, 122))
        canvas.rect(526, y + 5, 535, y + 14, (70, 168, 191))
    return canvas


def draw_high_motion_gradient_cursor(width: int, height: int, frame: int, seed: int) -> Canvas:
    canvas = Canvas(width, height)
    canvas.rect(20, 16, 620, 344, (18, 22, 30))
    left, top, right, bottom = canvas.x(40), canvas.y(34), canvas.x(600), canvas.y(326)
    region_width = right - left
    palette = [
        bytes(((value + seed * 17) % 256, (255 - value + seed * 9) % 256, (value * 3 + seed * 5) % 256))
        for value in range(256)
    ]
    for y in range(top, bottom):
        phase = (frame * 17 + (y - top) * 5) % 256
        row = b"".join(palette[(x * 256 // max(region_width, 1) + phase) % 256] for x in range(region_width))
        start = (y * canvas.width + left) * 3
        canvas.pixels[start : start + len(row)] = row
    cursor_x = 48 + (frame * 17) % 520
    cursor_y = 48 + (frame * 11) % 250
    px, py = canvas.x(cursor_x), canvas.y(cursor_y)
    size = max(8, canvas.x(18))
    for offset in range(size):
        canvas.pixel_rect(px, py + offset, px + max(2, offset // 2), py + offset + 1, (10, 12, 16))
    for offset in range(size - 2):
        canvas.pixel_rect(px + 1, py + offset + 1, px + max(2, offset // 2), py + offset + 2, (255, 255, 255))
    return canvas


def write_chunk(output, name: bytes, payload: bytes):
    output.write(struct.pack(">I", len(payload)))
    output.write(name)
    output.write(payload)
    output.write(struct.pack(">I", zlib.crc32(name + payload) & 0xFFFFFFFF))


def write_png(path: Path, canvas: Canvas):
    with path.open("wb") as output:
        output.write(b"\x89PNG\r\n\x1a\n")
        write_chunk(output, b"IHDR", struct.pack(">IIBBBBB", canvas.width, canvas.height, 8, 2, 0, 0, 0))
        compressor = zlib.compressobj(level=6)
        pending = bytearray()
        stride = canvas.width * 3
        for y in range(canvas.height):
            pending.extend(compressor.compress(b"\x00" + canvas.pixels[y * stride : (y + 1) * stride]))
            if len(pending) >= 65536:
                write_chunk(output, b"IDAT", pending)
                pending.clear()
        pending.extend(compressor.flush())
        if pending:
            write_chunk(output, b"IDAT", pending)
        write_chunk(output, b"IEND", b"")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new output directory")
    parser.add_argument("--width", type=int, default=BASE_WIDTH)
    parser.add_argument("--height", type=int, default=BASE_HEIGHT)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--frames", type=int, default=240)
    parser.add_argument(
        "--profile",
        choices=("mixed", "mostly-static-ui", "fast-scrolling", "high-motion-gradient-cursor"),
        default="mixed",
        help="synthetic scene profile",
    )
    args = parser.parse_args()

    if not 320 <= args.width <= 3840 or not 180 <= args.height <= 2160:
        parser.error("dimensions must be within 320x180 and 3840x2160")
    if not 1 <= args.frames <= 2400:
        parser.error("frame count must be from 1 to 2400")

    args.output.mkdir(parents=True, exist_ok=False)
    for frame in range(args.frames):
        canvas = draw_frame(args.width, args.height, frame, args.seed, args.profile)
        write_png(args.output / f"frame_{frame:04d}.png", canvas)

    manifest = {
        "generator": "generate_fixture.py",
        "seed": args.seed,
        "profile": args.profile,
        "width": args.width,
        "height": args.height,
        "fps": FPS,
        "frame_count": args.frames,
        "duration_seconds": args.frames / FPS,
        "first_frame": "frame_0000.png",
        "timestamp_rule": "frame index / fps seconds; frame 0 starts at 0",
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.frames} frames at {FPS} fps to {args.output}")


if __name__ == "__main__":
    main()
