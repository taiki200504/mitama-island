"""Blank-capture check in validate-harness-artifacts.py.

Fixtures are built in-test so no binary files live in the repository.
"""

from __future__ import annotations

import importlib.util
import pathlib
import struct
import unittest
import zlib

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "validate-harness-artifacts.py"
spec = importlib.util.spec_from_file_location("validate_harness_artifacts", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def rgba_png(pixel_at, width: int = 8, height: int = 6, filter_type: int = 0) -> bytes:
    rows = b"".join(
        bytes([filter_type]) + b"".join(bytes(pixel_at(x, y)) for x in range(width))
        for y in range(height)
    )
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        validator.PNG_SIGNATURE
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


class BlankCaptureTests(unittest.TestCase):
    def test_fully_transparent_capture_is_blank(self) -> None:
        png = rgba_png(lambda x, y: (x * 10, y * 10, 0, 0))
        self.assertEqual(validator.png_blank_reason(png), "every pixel is fully transparent")

    def test_solid_colour_capture_is_blank(self) -> None:
        png = rgba_png(lambda x, y: (20, 20, 20, 255))
        self.assertEqual(validator.png_blank_reason(png), "the whole image is a single solid colour")

    def test_normal_capture_passes(self) -> None:
        # A black pill on a transparent background, like the closed island.
        png = rgba_png(lambda x, y: (0, 0, 0, 255) if 2 <= x < 6 else (0, 0, 0, 0))
        self.assertIsNone(validator.png_blank_reason(png))

    def test_sub_filtered_rows_decode(self) -> None:
        # Filter 1 (Sub) with a constant delta turns into a gradient.
        png = rgba_png(lambda x, y: (1, 1, 1, 1), filter_type=1)
        self.assertIsNone(validator.png_blank_reason(png))

    def test_non_png_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            validator.png_blank_reason(b"not a png")


if __name__ == "__main__":
    unittest.main()
