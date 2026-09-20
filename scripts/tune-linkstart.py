#!/usr/bin/env python3
"""Tunes the link-start cues against a measured reference.

The five cues are shaped by three gains each — body under 120 Hz, the
120-800 Hz middle, the air above 3 kHz. This searches those gains for the
values whose rendered cue lands closest to the reference's own measured
spectrum, so the sound is set by measurement rather than by taste (nobody
here can hear it).

The targets come from analysing the reference clip's audio: spectral centroid,
the share of energy below 120 Hz, and the share above 3 kHz, per beat.

Usage:
    python3 scripts/tune-linkstart.py            # search and print the winners
    python3 scripts/tune-linkstart.py --apply    # ...and write them into build-sounds.py
"""
from __future__ import annotations

import argparse
import importlib.util
import itertools
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build-sounds.py")

# centroid Hz, % below 120 Hz, % above 3 kHz
TARGETS = {
    "rise": (4500, 3, 55),
    "warp": (3400, 8, 40),
    "flash": (4000, 7, 50),
    "tick": (3600, 1, 55),
    "resolve": (2100, 33, 24),
}

GRID = {
    "low": [0.0, 0.1, 0.25, 0.45, 0.7, 1.0, 1.4],
    "mid": [0.2, 0.4, 0.6, 0.9, 1.3, 1.8],
    "air": [0.05, 0.15, 0.3, 0.5, 0.8],
}


def load_builder():
    spec = importlib.util.spec_from_file_location("build_sounds", BUILD)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.VARIANT = "d"
    return module


def measure(signal: np.ndarray, sr: int) -> tuple[float, float, float]:
    mono = signal.mean(axis=1) if signal.ndim > 1 else signal
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    freqs = np.fft.rfftfreq(len(mono), 1 / sr)
    total = max(spectrum.sum(), 1e-9)
    return (
        float((spectrum * freqs).sum() / total),
        float(spectrum[freqs < 120].sum() / total * 100),
        float(spectrum[freqs >= 3000].sum() / total * 100),
    )


def error(measured, target) -> float:
    centroid, low, high = measured
    t_centroid, t_low, t_high = target
    # Relative on the centroid (it spans an octave and a half across the cues),
    # absolute on the two shares, which are already percentages.
    return (
        abs(math.log2(max(centroid, 1) / t_centroid)) * 2.2
        + abs(low - t_low) / 12
        + abs(high - t_high) / 18
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    module = load_builder()
    winners: dict[str, dict[str, float]] = {}

    for cue, target in TARGETS.items():
        render = getattr(module, f"d_{cue}")
        best = None
        for low, mid, air in itertools.product(GRID["low"], GRID["mid"], GRID["air"]):
            module.D_GAINS[cue] = {"low": low, "mid": mid, "air": air}
            measured = measure(render(), module.SR)
            score = error(measured, target)
            if best is None or score < best[0]:
                best = (score, {"low": low, "mid": mid, "air": air}, measured)
        score, gains, measured = best
        winners[cue] = gains
        module.D_GAINS[cue] = gains
        print(
            f"{cue:8} low={gains['low']:<5} mid={gains['mid']:<5} air={gains['air']:<5}"
            f"  → 重心 {measured[0]:6.0f}/{target[0]}  低域 {measured[1]:5.1f}/{target[1]}"
            f"  3k超 {measured[2]:5.1f}/{target[2]}  (誤差 {score:.2f})"
        )

    if not args.apply:
        return 0

    source = open(BUILD).read()
    block = "D_GAINS = {\n" + "".join(
        f'    "{cue}": {{"low": {g["low"]}, "mid": {g["mid"]}, "air": {g["air"]}}},\n'
        for cue, g in winners.items()
    ) + "}"
    source = re.sub(r"D_GAINS = \{.*?\n\}", block, source, count=1, flags=re.S)
    open(BUILD, "w").write(source)
    print("\nwrote the winning gains into build-sounds.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
