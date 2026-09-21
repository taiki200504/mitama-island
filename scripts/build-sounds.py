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



# --- link-start primitives ------------------------------------------------

VARIANT = "a"   # set from --variant; see LINKSTART_VOICES


def shepard_rise(dur: float, f0: float, f1: float, voices: int = 4, curve: float = 1.5) -> np.ndarray:
    """A rise that keeps climbing without ever running out of sky.

    One glide would reach the top of hearing and thin out; stacking the same
    glide an octave apart and fading each voice in as it enters and out as it
    leaves keeps the climb going for the whole dive. Its ear-level effect is
    the point: the dive should feel like it has no floor.
    """
    x = t(dur)
    p = (x / dur) ** curve
    out = np.zeros_like(x)
    for v in range(voices):
        freq = f0 * (2 ** v) * (f1 / f0) ** p
        # A voice is loudest in the middle of its own range and silent at the
        # edges, so entries and exits are never heard as separate notes.
        centre = np.clip(np.log2(np.clip(freq, 1e-3, None) / 60) / 7, 0, 1)
        gain = np.sin(math.pi * centre) ** 2
        out += gain * np.sin(2 * math.pi * np.cumsum(freq) / SR)
    return out / max(voices * 0.6, 1)


def choir(freqs, dur: float, seed: int = 41) -> np.ndarray:
    """Breathy vowel-ish pad: filtered noise around the "aa" formants over a
    detuned sine bed. Not a voice — the point is the human-adjacent warmth a
    bare sine chord never has."""
    x = t(dur)
    bed = np.zeros_like(x)
    for i, f in enumerate(freqs):
        for detune in (0.997, 1.0, 1.003):
            bed += np.sin(2 * math.pi * f * detune * x + i * 1.7) / 3
    bed /= max(len(freqs), 1)
    breath = np.zeros_like(x)
    for centre, gain in ((700, 1.0), (1100, 0.6), (2600, 0.25)):
        breath += gain * bandpass(noise(dur, seed + int(centre)), centre * 0.85, centre * 1.18, order=2)
    breath /= 2
    return bed * 0.8 + breath * 0.12


def metal(freq: float, dur: float, decay: float, gain: float = 1.0) -> np.ndarray:
    """Struck metal: ratios far from whole numbers, so it reads as a sheet of
    something hard rather than a note."""
    x = t(dur)
    out = np.zeros_like(x)
    for i, (r, g) in enumerate(((1.0, 1.0), (1.71, 0.6), (2.46, 0.4), (3.39, 0.25), (4.61, 0.16), (6.13, 0.1))):
        out += g * np.sin(2 * math.pi * freq * r * x) * env_exp(len(x), decay / (1 + 0.5 * i), 0.001)
    return out * gain


# Per-variant weights. The three differ in what carries the sequence, not in
# its shape: A leans on the low end and the room, B on hard metal and glass,
# C on air and distance.
LINKSTART_VOICES = {
    "d": {"low": 1.0, "metal": 1.0, "air": 1.0, "room": 1.0, "bright": 1.0},
    "a": {"low": 1.25, "metal": 0.55, "air": 0.85, "room": 1.35, "bright": 0.75},
    "b": {"low": 0.85, "metal": 1.35, "air": 0.70, "room": 0.85, "bright": 1.30},
    "c": {"low": 0.95, "metal": 0.45, "air": 1.45, "room": 1.60, "bright": 0.85},
}


def v(key: str) -> float:
    return LINKSTART_VOICES[VARIANT][key]


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



# --- variant D: matched to a measured reference ---------------------------
#
# A and B and C were designed from an assumption — "not cute" meant heavy and
# low — and every one of them was wrong. Measuring the real thing (the login
# screen of the work this look comes from, analysed locally and not shipped)
# gave the opposite profile: 5.1 s long, centroid ~4.2 kHz, under 4 % of the
# energy below 120 Hz, half of it above 3 kHz, a sustained 5–16 kHz shimmer
# from the first half second, two short hits at 0.2 s and 0.8 s, then a swell
# peaking around 2.5 s and gone by 5 s. Pitch sits on C#3/C#4 with an E4 — a
# minor third, not a major chord. These cues aim at those numbers.

D_LOW, D_MID, D_HIGH = 137.0, 277.2, 329.6      # C#3 / C#4 / E4

# Three knobs per cue — body below 120 Hz, the 120–800 Hz middle, and the air
# above 3 kHz. Tuned by `scripts/tune-linkstart.py`, which measures the
# rendered cue and searches for the values that land on the reference's own
# measured spectrum rather than on someone's idea of what it should sound like.
D_GAINS = {
    "rise": {"low": 0.1, "mid": 1.8, "air": 0.05},
    "warp": {"low": 1.4, "mid": 1.3, "air": 0.05},
    "flash": {"low": 0.7, "mid": 1.8, "air": 0.05},
    "tick": {"low": 0.0, "mid": 1.8, "air": 0.05},
    "resolve": {"low": 1.0, "mid": 1.8, "air": 0.05},
    "dive": {"low": 0.7, "mid": 1.2, "air": 0.35},
}


def g(cue: str, knob: str) -> float:
    return D_GAINS[cue][knob]
D_SPARKLE = (6200, 9000, 12500)                  # the air that never stops


def d_sparkle(dur: float, gain: float = 1.0, seed: int = 61) -> np.ndarray:
    """The constant top end: narrow noise bands up high, gently beating."""
    x = t(dur)
    out = np.zeros_like(x)
    for i, centre in enumerate(D_SPARKLE):
        band = bandpass(noise(dur, seed + i * 7), centre * 0.8, centre * 1.25, order=2)
        beat = 0.72 + 0.28 * np.sin(2 * math.pi * (0.7 + 0.4 * i) * x + i)
        out += band * beat / (1 + i)
    return out * gain


def d_bell(freq: float, dur: float, decay: float, gain: float = 1.0) -> np.ndarray:
    """Bright struck partials — the 3 kHz ping the reference opens on."""
    x = t(dur)
    out = np.zeros_like(x)
    for i, (r, g) in enumerate(((1.0, 1.0), (2.01, 0.7), (3.02, 0.5), (4.5, 0.3), (6.1, 0.18))):
        out += g * np.sin(2 * math.pi * freq * r * x) * env_exp(len(x), decay / (1 + 0.45 * i), 0.0015)
    return out * gain


def d_rise():
    """Two short hits and the shimmer coming up under them."""
    dur = 1.2
    x = t(dur)
    hit_a = d_bell(3118, 0.5, 0.11, 0.9)
    hit_b = d_bell(2340, 0.55, 0.14, 0.7)
    pad = sum(np.sin(2 * math.pi * f * x + i) for i, f in enumerate((D_MID, D_HIGH, D_MID * 2)))
    pad = lowpass_sweep(pad / 3, 500, 6000) * env_adsr(len(x), 0.5, 0.15, 1.0, 0.1) * g("rise", "mid")
    sparkle = d_sparkle(dur, g("rise", "air")) * env_adsr(len(x), 0.45, 0.1, 1.0, 0.08)
    body = stack((hit_a, 0.02), (hit_b, 0.34), (pad, 0), (sparkle, 0))[: len(x)]
    body += (np.sin(2 * math.pi * D_LOW * x) + 0.7 * np.sin(2 * math.pi * (D_LOW / 2) * x)) \
        * env_adsr(len(x), 0.5, 0.2, 0.8, 0.1) * g("rise", "low")
    return stereo(reverb(body, 1.1, wet=0.3)[: len(x)], 0.9)


def d_tick():
    """One sense confirmed — the reference's own opening ping, shortened."""
    dur = 0.15
    ping = d_bell(2080, 0.14, 0.034, g("tick", "mid"))
    edge = bandpass(noise(0.006, 13), 2600, 9000, order=2) * env_exp(int(SR * 0.006), 0.0015)
    return stack((ping, 0.001), (edge * g("tick", "air"), 0))[: int(SR * dur)]


def d_warp():
    """The dive as the reference builds it: a long swell of bright air rather
    than a low rumble, with the shimmer riding on top the whole way."""
    dur = 2.5
    x = t(dur)
    p = x / dur
    n = noise(dur, 23)
    air = np.zeros_like(n)
    chunks = 64
    edges = np.linspace(0, len(n), chunks + 1).astype(int)
    for i in range(chunks):
        q = i / (chunks - 1)
        centre = 900 * (11000 / 900) ** (q ** 0.85)
        seg = n[max(0, edges[i] - 512):edges[i + 1]]
        filtered = bandpass(seg, centre * 0.55, min(centre * 2.0, 20000), order=2)
        air[edges[i]:edges[i + 1]] = filtered[-(edges[i + 1] - edges[i]):]
    swell = np.clip(p / 0.35, 0, 1) ** 1.2
    tone = shepard_rise(dur, 150, 3600, voices=3, curve=1.2) * g("warp", "mid")
    sparkle = d_sparkle(dur, g("warp", "air"))
    low = (np.sin(2 * math.pi * 47 * x) + 0.8 * np.sin(2 * math.pi * 63 * x)) * g("warp", "low") * swell
    body = (air * 0.45 + tone + sparkle * 0.5 + low) * swell
    hold = int(SR * 0.12)
    body[-hold:] *= np.linspace(1, 0.15, hold)
    return stereo(body, 1.0)


def d_flash():
    """Arrival: a bright crystalline burst, not a boom. The reference's peak
    is at 9 kHz, with the low end barely present."""
    dur = 1.8
    x = t(dur)
    # The burst is most of this cue's brightness, so the air knob has to reach
    # it — tuning only the sparkle left the flash stuck an octave too high.
    burst = bandpass(noise(0.35, 29), 700, 9000) * env_exp(int(SR * 0.35), 0.09) * (0.4 + g("flash", "air"))
    bells = stack(*[
        (d_bell(f, 1.4, 0.45, 0.6 + g("flash", "air")), 0.012 * i)
        for i, f in enumerate((1560, 2080, 3120))
    ])
    pad = sum(np.sin(2 * math.pi * f * x) for f in (D_MID, D_HIGH, D_MID * 2, D_HIGH * 2)) / 4
    pad = lowpass_sweep(pad, 700, 7000, 20) * env_adsr(len(x), 0.05, 0.25, 0.65, 0.7) * g("flash", "mid")
    thump = (np.sin(2 * math.pi * 74 * x) + 0.7 * np.sin(2 * math.pi * 44 * x)) * env_exp(len(x), 0.3) * g("flash", "low")
    body = stack((burst * 0.7, 0), (bells, 0), (pad, 0.01), (thump, 0))[: len(x)]
    body += d_sparkle(dur, g("flash", "air")) * env_adsr(len(x), 0.02, 0.4, 0.7, 0.6)
    return stereo(reverb(body, 2.0, wet=0.42)[: len(x)], 1.0)


def d_dive():
    """Leaving the interface: the second dive, brighter and shorter than the
    first, ending in the white-out the sequence closes on."""
    dur = 1.8
    x = t(dur)
    p = x / dur
    riser = shepard_rise(dur, 180, 4200, voices=3, curve=1.1) * g("dive", "mid")
    n = noise(dur, 37)
    air = np.zeros_like(n)
    chunks = 48
    edges = np.linspace(0, len(n), chunks + 1).astype(int)
    for i in range(chunks):
        q = i / (chunks - 1)
        centre = 600 * (12000 / 600) ** (q ** 0.9)
        seg = n[max(0, edges[i] - 512):edges[i + 1]]
        air[edges[i]:edges[i + 1]] = bandpass(seg, centre * 0.5, min(centre * 2.2, 20000), order=2)[
            -(edges[i + 1] - edges[i]):
        ]
    swell = np.clip(p / 0.2, 0, 1) ** 1.1
    low = np.sin(2 * math.pi * 52 * x) * g("dive", "low") * swell
    sparkle = d_sparkle(dur, g("dive", "air"))
    body = (air * 0.5 + riser * 0.35 + sparkle * 0.5 + low) * swell
    tail = int(SR * 0.25)
    body[-tail:] *= np.linspace(1, 0.05, tail)
    return stereo(reverb(body, 1.4, wet=0.35)[: len(x)], 1.0)


def d_resolve():
    """Identity. The reference's tail: B3/A4/C5 over a shimmer that keeps
    going, fading out rather than landing on a chord."""
    dur = 1.8
    x = t(dur)
    pad = sum(
        np.sin(2 * math.pi * f * x + i * 0.6)
        for i, f in enumerate((123.5, 164.8, 220, 246.9, 329.6))
    ) / 5
    pad = lowpass_sweep(pad, 300, 2600, 24) * env_adsr(len(x), 0.1, 0.3, 0.7, 0.8) * g("resolve", "mid")
    bells = stack(
        (d_bell(1046, 1.2, 0.4, 0.5), 0.0),
        (d_bell(1568, 1.0, 0.3, 0.35), 0.18),
    )
    sparkle = d_sparkle(dur, g("resolve", "air")) * env_adsr(len(x), 0.05, 0.3, 0.8, 0.7)
    low = (np.sin(2 * math.pi * 61.7 * x) + 0.8 * np.sin(2 * math.pi * 82.4 * x)) \
        * env_adsr(len(x), 0.15, 0.3, 0.6, 0.7) * g("resolve", "low")
    body = stack((pad, 0), (bells, 0.02), (sparkle, 0), (low, 0))[: len(x)]
    return stereo(reverb(body, 1.8, wet=0.45)[: len(x)], 1.0)


def c_linkstart_rise():
    if VARIANT == "d":
        return d_rise()
    """The light arriving. Two octaves of sub under a suspended chord that
    never resolves — the old one opened on a plain major triad, which is what
    made the sequence sound friendly rather than about to swallow you."""
    dur = 1.2
    x = t(dur)
    sub = (
        np.sin(2 * math.pi * 27.5 * x) * 0.7
        + np.sin(2 * math.pi * 41.2 * x) * 0.5
    ) * env_adsr(len(x), 0.35, 0.2, 0.9, 0.1) * v("low")
    # A2 / E3 / B3 / E4: fifths and a ninth, nothing that settles.
    pad = sum(np.sin(2 * math.pi * f * x + i * 0.8) for i, f in enumerate((110, 164.8, 246.9, 329.6)))
    pad = lowpass_sweep(pad / 4, 180, 5200) * env_adsr(len(x), 0.45, 0.1, 1.0, 0.05)
    sheet = metal(329.6, dur, 0.9, 0.35 * v("metal")) * env_adsr(len(x), 0.5, 0.2, 0.8, 0.1)
    air = bandpass(noise(dur, 5), 1200, 13000) * env_adsr(len(x), 0.85, 0.1, 1.0, 0.05) * 0.35 * v("air")
    body = sub * 1.15 + pad * 0.75 + sheet + air * 0.8
    return stereo(reverb(body, 0.9 * v("room"), wet=0.3)[: len(x)], 0.85)


def c_linkstart_tick():
    if VARIANT == "d":
        return d_tick()
    """One sense confirmed. A narrow digital blip rather than the old glass
    chime: five bell tones in a row are what read as cute."""
    dur = 0.15
    blip = bandpass(noise(0.008, 13), 900, 2200, order=2) * env_exp(int(SR * 0.008), 0.0018)
    tone = np.sin(2 * math.pi * 1180 * t(0.045)) * env_exp(int(SR * 0.045), 0.012, 0.0008)
    edge = metal(2360, 0.09, 0.02, 0.28 * v("metal"))
    return stack((blip * 0.9, 0), (tone * 0.75, 0.001), (edge * v("bright"), 0.002))[: int(SR * dur)]


def c_linkstart_warp():
    if VARIANT == "d":
        return d_warp()
    """The dive. A Shepard rise that never tops out, rushing air that widens
    as it goes, streaks passing left and right — and a held breath just
    before the white-out, because the arrival lands harder out of silence."""
    dur = 2.5
    x = t(dur)
    p = x / dur
    riser = shepard_rise(dur, 55, 2400, voices=4, curve=1.45)

    n = noise(dur, 23)
    air = np.zeros_like(n)
    chunks = 64
    edges = np.linspace(0, len(n), chunks + 1).astype(int)
    for i in range(chunks):
        q = i / (chunks - 1)
        centre = 180 * (9000 / 180) ** (q ** 1.25)
        seg = n[max(0, edges[i] - 512):edges[i + 1]]
        filtered = bandpass(seg, centre * 0.45, min(centre * 2.4, 20000), order=2)
        air[edges[i]:edges[i + 1]] = filtered[-(edges[i + 1] - edges[i]):]

    flutter = 0.7 + 0.3 * np.sin(2 * math.pi * np.cumsum(3 + 30 * p ** 2) / SR)
    swell = np.clip(p / 0.12, 0, 1) * (0.2 + 0.8 * p ** 2)
    sub = (np.sin(2 * math.pi * 36 * x) + 0.6 * np.sin(2 * math.pi * 27 * x)) * 0.8 * swell * v("low")

    body = (riser * 0.4 + air * 0.5 * flutter * v("air") + sub) * swell
    # The suck-out: the last 180 ms drop away to nothing, so `flash` arrives
    # into a hole rather than on top of a wall of noise.
    hold = int(SR * 0.18)
    body[-hold:] *= np.linspace(1, 0.04, hold) ** 2

    # Streaks: the same rush, delayed the other way per channel, so light
    # appears to pass the listener instead of sitting in the middle.
    d = int(SR * 0.013)
    echo = 0.18 * v("air")
    left = body.copy()
    right = body.copy()
    left[d:] += body[:-d] * echo
    right[:-d] += body[d:] * echo
    return np.stack([left, right], axis=1)


def c_linkstart_flash():
    if VARIANT == "d":
        return d_flash()
    """Arrival. A deeper drop than before, a hard shatter on the transient,
    and a room that keeps ringing long after the hit."""
    dur = 1.8
    x = t(dur)
    drop = 140 * (32 / 140) ** np.clip(x / 0.4, 0, 1)
    boom = np.sin(2 * math.pi * np.cumsum(drop) / SR) * env_exp(len(x), 0.5, attack=0.003) * v("low")
    hit = bandpass(noise(0.3, 29), 120, 11000) * env_exp(int(SR * 0.3), 0.045)
    shatter = stack(*[
        (metal(f, 0.7, 0.22, 0.5 * v("metal")), 0.004 * i)
        for i, f in enumerate((1860, 2480, 3310, 4420))
    ])
    shimmer = stack(*[
        (glass(f, 1.3, 0.55, v("bright")), 0.02 + i * 0.03)
        for i, f in enumerate((1568, 2093, 2637))
    ])
    s = stack((boom, 0), (hit * 0.8, 0), (shatter, 0), (shimmer * 0.22, 0))
    s = reverb(s, 2.2 * v("room"), wet=0.5)[: int(SR * dur)]
    return stereo(s, 1.0)


def c_linkstart_dive():
    """Leaving the interface — only the measured variant has one."""
    return d_dive()


def c_linkstart_resolve():
    if VARIANT == "d":
        return d_resolve()
    """Identity. The old one ended on a plain major chord — the single most
    "cute" thing in the sequence. This holds a suspended second and opens to
    a bare fifth, the way an arrival is stated rather than celebrated."""
    dur = 1.8
    x = t(dur)
    half = len(x) // 2
    # A2/E3/B3 (sus2) for the first half → A2/E3/A3 (open fifth) for the rest.
    susp = choir((110, 164.8, 246.9), dur)
    fifth = choir((110, 164.8, 220), dur)
    cross = np.clip((np.arange(len(x)) - half) / (SR * 0.35), 0, 1)
    chord = susp * (1 - cross) + fifth * cross
    chord = lowpass_sweep(chord, 600, 7000, 24) * env_adsr(len(x), 0.12, 0.25, 0.75, 0.8)
    bells = stack(
        (metal(880, 1.1, 0.4, 0.45 * v("metal")), 0.0),
        (glass(1319, 0.9, 0.35, 0.8 * v("bright")), 0.22),
    )
    sub = np.sin(2 * math.pi * 55 * x) * env_adsr(len(x), 0.2, 0.3, 0.7, 0.6) * 0.5 * v("low")
    s = stack((chord * 0.9, 0), (bells * 0.4, 0.04), (sub, 0))
    s = reverb(s, 1.6 * v("room"), wet=0.42)[: int(SR * dur)]
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
    "linkstart-warp": (c_linkstart_warp, 2.50),
    "linkstart-flash": (c_linkstart_flash, 1.80),
    "linkstart-tick": (c_linkstart_tick, 0.15),
    "linkstart-resolve": (c_linkstart_resolve, 1.80),
    "linkstart-dive": (c_linkstart_dive, 1.80),
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
    ap.add_argument(
        "--variant",
        choices=sorted(LINKSTART_VOICES),
        default="a",
        help="which reading of the link-start sequence to render (see LINKSTART_VOICES)",
    )
    args = ap.parse_args()

    global VARIANT
    VARIANT = args.variant

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
