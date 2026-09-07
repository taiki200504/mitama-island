#!/usr/bin/env python3
"""Synthesises the island's UI sound cues from scratch.

Every cue is generated procedurally (sine/FM partials, filtered noise, simple
convolution reverb) so nothing here is sampled from, or derived from, any
existing game, anime or product. The look the app reaches for is crystalline
and holographic; these are our own reading of that, not a copy.

Usage:
    python3 scripts/build-sounds.py [--out DIR] [--only CUE ...] [--check]

Output: <out>/ui-<kebab>.caf  (LPCM 16-bit, 48 kHz, mono; boot-sequence stems stereo)
Requires numpy + scipy (present on the dev Mac) and /usr/bin/afconvert.
"""
from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 48_000


# --- primitives -----------------------------------------------------------

def t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def env_exp(n: int, decay: float, attack: float = 0.002) -> np.ndarray:
    """Percussive envelope: linear attack, exponential decay (seconds)."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-5), 0, 1)
    return a * np.exp(-x / decay)


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    x = np.arange(n) / SR
    total = n / SR
    out = np.ones(n)
    out = np.where(x < a, x / a, out)
    out = np.where((x >= a) & (x < a + d), 1 - (1 - s) * (x - a) / d, out)
    out = np.where((x >= a + d) & (x < total - r), s, out)
    out = np.where(x >= total - r, s * (total - x) / r, out)
    return np.clip(out, 0, 1)


def glass(freq: float, dur: float, decay: float, bright: float = 1.0, attack: float = 0.002) -> np.ndarray:
    """A crystalline strike: inharmonic partials that fade faster the higher they sit."""
    x = t(dur)
    ratios = (1.0, 2.32, 3.01, 4.25, 5.43)
    gains = (1.0, 0.45 * bright, 0.25 * bright, 0.14 * bright, 0.07 * bright)
    out = np.zeros_like(x)
    for i, (r, g) in enumerate(zip(ratios, gains)):
        out += g * np.sin(2 * math.pi * freq * r * x) * env_exp(len(x), decay / (1 + 0.6 * i), attack)
    return out


def sweep(f0: float, f1: float, dur: float, curve: float = 1.0) -> np.ndarray:
    x = t(dur)
    p = (x / dur) ** curve
    freq = f0 * (f1 / f0) ** p
    phase = 2 * math.pi * np.cumsum(freq) / SR
    return np.sin(phase)


def noise(dur: float, seed: int = 7) -> np.ndarray:
    return np.random.default_rng(seed).standard_normal(int(SR * dur))


def bandpass(sig: np.ndarray, lo: float, hi: float, order: int = 4) -> np.ndarray:
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, sig)


def lowpass_sweep(sig: np.ndarray, f_start: float, f_end: float, chunks: int = 48) -> np.ndarray:
    """Cheap time-varying low-pass: filter successive chunks with a rising cutoff."""
    out = np.zeros_like(sig)
    n = len(sig)
    edges = np.linspace(0, n, chunks + 1).astype(int)
    for i in range(chunks):
        cutoff = f_start * (f_end / f_start) ** (i / max(chunks - 1, 1))
        sos = butter(2, cutoff, btype="low", fs=SR, output="sos")
        seg = sig[max(0, edges[i] - 512):edges[i + 1]]
        filtered = sosfilt(sos, seg)
        out[edges[i]:edges[i + 1]] = filtered[-(edges[i + 1] - edges[i]):]
    return out


def reverb(sig: np.ndarray, tail: float, wet: float = 0.3, seed: int = 3) -> np.ndarray:
    ir = noise(tail, seed) * np.exp(-np.arange(int(SR * tail)) / SR / (tail / 4))
    ir /= np.abs(ir).sum() / 40
    wet_sig = np.convolve(sig, ir)[: len(sig) + int(SR * tail)]
    dry = np.pad(sig, (0, len(wet_sig) - len(sig)))
    return dry + wet * wet_sig


def stack(*parts: tuple[np.ndarray, float]) -> np.ndarray:
    """Overlay (signal, start_seconds) pairs into one buffer."""
    end = max(len(s) + int(SR * at) for s, at in parts)
    out = np.zeros(end)
    for s, at in parts:
        i = int(SR * at)
        out[i:i + len(s)] += s
    return out


def stereo(sig: np.ndarray, width: float = 0.6) -> np.ndarray:
    """Mono → stereo by a tiny delay and detune-free level offset."""
    d = int(SR * 0.0007)
    left = np.pad(sig, (0, d))
    right = np.pad(sig, (d, 0)) * (1 - 0.15 * width) + np.pad(sig, (0, d)) * 0.15 * width
    return np.stack([left, right], axis=1)


# --- the catalogue --------------------------------------------------------

def c_hover():
    return glass(5600, 0.06, 0.012, bright=0.4)


def c_open():
    body = sweep(600, 1900, 0.25, curve=0.7) * env_adsr(int(SR * 0.25), 0.02, 0.05, 0.6, 0.12)
    shimmer = glass(2400, 0.25, 0.08, bright=0.8) * 0.35
    return stack((body, 0), (shimmer, 0.06))


def c_close():
    body = sweep(1500, 520, 0.18, curve=1.3) * env_adsr(int(SR * 0.18), 0.005, 0.04, 0.5, 0.08)
    return body * 0.8


def c_select():
    return stack((glass(880, 0.07, 0.03, 0.7), 0), (glass(1320, 0.07, 0.035, 0.7), 0.055))


def c_confirm():
    notes = (1047, 1319, 1568)
    return stack(*[(glass(f, 0.22, 0.09, 0.9), i * 0.075) for i, f in enumerate(notes)])


def c_approve():
    s = stack((glass(660, 0.3, 0.14, 0.6, attack=0.006), 0), (glass(990, 0.3, 0.16, 0.6, attack=0.006), 0.11))
    return reverb(s, 0.15, wet=0.25)


def c_reject():
    x = t(0.3)
    a = np.sign(np.sin(2 * math.pi * 440 * x)) * 0.5 + np.sin(2 * math.pi * 443 * x) * 0.5
    b = np.sign(np.sin(2 * math.pi * 330 * x)) * 0.5 + np.sin(2 * math.pi * 332 * x) * 0.5
    a = bandpass(a, 200, 3000) * env_exp(len(x), 0.08)
    b = bandpass(b, 200, 3000) * env_exp(len(x), 0.12)
    return stack((a, 0), (b, 0.13))


def soft_square(freq: float, dur: float) -> np.ndarray:
    x = t(dur)
    out = np.zeros_like(x)
    for k in (1, 3, 5, 7):
        out += np.sin(2 * math.pi * freq * k * x) / k
    return out / 1.3


def c_warning():
    pulse = soft_square(1000, 0.09) * env_adsr(int(SR * 0.09), 0.004, 0.02, 0.8, 0.03)
    return stack((pulse, 0), (pulse, 0.21), (np.zeros(int(SR * 0.05)), 0.55))


def c_notify():
    return reverb(glass(1300, 0.7, 0.28, 1.0, attack=0.003), 0.2, wet=0.2)


def c_urgent():
    starts = (0.0, 0.32, 0.58, 0.78)
    parts = [(bandpass(glass(1760, 0.16, 0.05, 1.2), 900, 9000), s) for s in starts]
    parts.append((np.zeros(int(SR * 0.1)), 1.1))
    return stack(*parts)


def c_complete():
    notes = (784, 988, 1175, 1568)
    arp = [(glass(f, 0.35, 0.14, 0.8), i * 0.11) for i, f in enumerate(notes)]
    chord = sum(np.sin(2 * math.pi * f * t(0.95)) for f in (784, 988, 1175)) / 3
    chord *= env_adsr(int(SR * 0.95), 0.05, 0.2, 0.5, 0.5)
    return reverb(stack(*arp, (chord * 0.5, 0.42)), 0.2, wet=0.2)


def c_link():
    click = bandpass(noise(0.02, 11), 2000, 8000) * env_exp(int(SR * 0.02), 0.004)
    tone = np.sin(2 * math.pi * 1174 * t(0.26)) * env_adsr(int(SR * 0.26), 0.01, 0.05, 0.6, 0.15)
    return stack((click * 0.6, 0), (tone * 0.7, 0.03))


def c_linkstart_rise():
    dur = 1.2
    x = t(dur)
    sub = np.sin(2 * math.pi * 55 * x) * env_adsr(len(x), 0.3, 0.2, 0.8, 0.1)
    pad = sum(np.sin(2 * math.pi * f * x + i) for i, f in enumerate((220, 293.7, 440, 587.3)))  # suspended, unresolved
    pad = lowpass_sweep(pad / 4, 300, 6000) * env_adsr(len(x), 0.4, 0.1, 1.0, 0.05)
    air = bandpass(noise(dur, 5), 2000, 12000) * env_adsr(len(x), 0.8, 0.1, 1.0, 0.05) * 0.12
    return stereo(sub * 0.6 + pad * 0.8 + air, 0.8)


def c_linkstart_tick():
    click = bandpass(noise(0.01, 13), 3000, 12000) * env_exp(int(SR * 0.01), 0.002)
    ring = glass(3136, 0.15, 0.04, 0.5)
    return stack((click, 0), (ring * 0.6, 0.002))


def c_linkstart_resolve():
    dur = 1.8
    x = t(dur)
    chord = sum(np.sin(2 * math.pi * f * x) for f in (261.6, 329.6, 392, 523.3, 659.3))
    chord = lowpass_sweep(chord / 5, 800, 9000, 24) * env_adsr(len(x), 0.08, 0.3, 0.6, 0.9)
    bells = stack(*[(glass(f, 0.9, 0.35, 0.9), i * 0.06) for i, f in enumerate((1047, 1319, 1568, 2093))])
    s = stack((chord, 0), (bells * 0.45, 0.05))
    s = reverb(s, 0.7, wet=0.35)[: int(SR * dur)]
    return stereo(s, 1.0)


def c_lock_scan():
    dur = 0.9
    n = noise(dur, 17)
    up = bandpass(n[: len(n) // 2], 400, 900)
    # approximate the glide by chaining bandpasses on chunks
    chunks = 24
    out = np.zeros_like(n)
    edges = np.linspace(0, len(n), chunks + 1).astype(int)
    for i in range(chunks):
        p = i / (chunks - 1)
        centre = 400 * (4000 / 400) ** (math.sin(math.pi * p))  # up then down
        seg = bandpass(n[edges[i]:edges[i + 1]], centre * 0.8, centre * 1.25)
        out[edges[i]:edges[i + 1]] = seg
    hum = np.sin(2 * math.pi * 196 * t(dur)) * 0.15
    return (out * 0.7 + hum) * env_adsr(len(n), 0.05, 0.1, 0.9, 0.15)


def c_unlock():
    latch = bandpass(noise(0.03, 19), 1500, 6000) * env_exp(int(SR * 0.03), 0.006)
    return stack((glass(1319, 0.2, 0.08, 0.7), 0), (glass(1760, 0.2, 0.1, 0.7), 0.1), (latch * 0.5, 0.36))


def c_timer_end():
    return reverb(stack((glass(1568, 0.5, 0.18), 0), (glass(1568, 0.5, 0.18), 0.4), (glass(1568, 0.8, 0.4), 0.8)), 0.25, wet=0.2)


CUES = {
    "hover": (c_hover, 0.06),
    "open": (c_open, 0.25),
    "close": (c_close, 0.18),
    "select": (c_select, 0.12),
    "confirm": (c_confirm, 0.35),
    "approve": (c_approve, 0.40),
    "reject": (c_reject, 0.30),
    "warning": (c_warning, 0.60),
    "notify": (c_notify, 0.70),
    "urgent": (c_urgent, 1.20),
    "complete": (c_complete, 1.40),
    "link": (c_link, 0.30),
    "linkstart-rise": (c_linkstart_rise, 1.20),
    "linkstart-tick": (c_linkstart_tick, 0.15),
    "linkstart-resolve": (c_linkstart_resolve, 1.80),
    "lock-scan": (c_lock_scan, 0.90),
    "unlock": (c_unlock, 0.50),
    "timer-end": (c_timer_end, 1.60),
}


# --- finishing ------------------------------------------------------------

def finish(sig: np.ndarray, max_dur: float, peak_db: float) -> np.ndarray:
    limit = int(SR * max_dur)
    sig = sig[:limit]
    # fades: 5 ms in, 30 ms out — keeps the transients but never clicks
    n = len(sig)
    fi, fo = int(SR * 0.005), int(SR * 0.03)
    ramp_in = np.linspace(0, 1, fi)
    ramp_out = np.linspace(1, 0, fo)
    if sig.ndim == 1:
        sig[:fi] *= ramp_in
        sig[-fo:] *= ramp_out
    else:
        sig[:fi] *= ramp_in[:, None]
        sig[-fo:] *= ramp_out[:, None]
    peak = np.abs(sig).max() or 1.0
    return sig / peak * (10 ** (peak_db / 20))


def write_caf(name: str, sig: np.ndarray, out_dir: str) -> str:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (sig * 32767).astype(np.int16))
    target = os.path.join(out_dir, f"ui-{name}.caf")
    subprocess.run(["/usr/bin/afconvert", "-f", "caff", "-d", "LEI16@48000", tmp.name, target], check=True)
    os.unlink(tmp.name)
    return target


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Sources/OpenIslandApp/Resources/Sounds")
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true", help="verify every cue exists in --out and exit")
    args = ap.parse_args()

    if args.check:
        missing = [c for c in CUES if not os.path.exists(os.path.join(args.out, f"ui-{c}.caf"))]
        if missing:
            print("missing:", ", ".join(missing), file=sys.stderr)
            return 1
        print(f"ok: {len(CUES)} cues present")
        return 0

    os.makedirs(args.out, exist_ok=True)
    for name, (fn, max_dur) in CUES.items():
        if args.only and name not in args.only:
            continue
        sig = fn()
        long = max_dur >= 1.0
        sig = finish(sig, max_dur, -1.0 if long else -3.0)
        path = write_caf(name, sig, args.out)
        print(f"{path}  {len(sig) / SR:.2f}s  {'stereo' if sig.ndim == 2 else 'mono'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
