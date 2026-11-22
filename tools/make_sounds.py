#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Erzeugt alle Geräusche des Spiels als WAV-Dateien (16 Bit, Mono, 44100 Hz, das Publikum in
22050 Hz) im Ordner audio/. Die Musik kommt aus tools/make_music.py.

Aufruf (im Projektordner):
    python tools/make_sounds.py                  alle Dateien neu schreiben und prüfen
    python tools/make_sounds.py --check          nur die vorhandenen Dateien prüfen
    python tools/make_sounds.py --only=hit,land  nur diese Dateien neu schreiben, alle prüfen

Alles wird berechnet (Rauschen, Sinus, Sägezahn, Hüllkurven, einfache Filter), es gibt keine
fremden Aufnahmen. Der Zufall hat einen festen Startwert: Jeder Lauf schreibt dieselben Dateien.
Nur die Standardbibliothek von Python 3 wird benutzt. Ein ganzer Lauf dauert je nach Rechner
zehn Sekunden bis eine Minute.

Häufige Geräusche gibt es in Varianten: Die erste behält den Namen (hit.wav), die weiteren heißen
hit_2.wav, hit_3.wav. Das Spiel wählt zufällig und nie zweimal dieselbe hintereinander.
crowd_murmur.wav ist eine Schleife: Sie beginnt und endet nicht bei null, ihr Ende geht ohne
Sprung in ihren Anfang über, und die Datei trägt den Eintrag "smpl" mit den Schleifenpunkten.

Nach dem Schreiben liest das Skript jede Datei wieder ein und druckt eine Tabelle: Länge,
Spitzenpegel, mittlerer Pegel, Pegel unter etwa 250 Hz (die Wucht), Helligkeit (aus den
Nulldurchgängen), übersteuerte Werte, Pegel am Rand (erster und letzter Wert) und Gleichanteil,
bei einer Schleife den Sprung an der Naht im Vergleich zu den Sprüngen zwischen Nachbarwerten.
Stimmt etwas nicht (zu lang, zu leise, stumm, übersteuert, Knackser am Rand, Gleichanteil, Sprung
an der Naht), endet es mit Code 1.

Neue Dateien muss Godot einmal einlesen:
    Godot --headless --import --path <Projekt>
Die Namen der Dateien stehen auch in scripts/game/audio/sfx.gd (SOUNDS). Wer eine Datei durch
eine echte Aufnahme ersetzen will, legt sie unter demselben Namen in audio/ ab.
"""

import math
import os
import random
import struct
import sys
import wave

SAMPLE_RATE = 44100
## Spitzenpegel jeder Datei in dBFS.
PEAK_DB = -3.0
## Prüfung: Lauter als so (dBFS) dürfen der erste und der letzte Wert und der Gleichanteil nicht sein.
EDGE_LIMIT_DB = -60.0
DC_LIMIT_DB = -50.0
SEED = 20261121
TWO_PI = 2.0 * math.pi

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")


# --- Bausteine ------------------------------------------------------------------------------

def count(duration):
    return max(1, int(round(duration * SAMPLE_RATE)))


def noise(duration, rng):
    """Weißes Rauschen zwischen -1 und 1."""
    return [rng.uniform(-1.0, 1.0) for _ in range(count(duration))]


def osc(duration, freq, shape="sine", phase=0.0):
    """Schwingung. freq ist eine Zahl in Hz, eine Funktion Zeit -> Hz oder eine Liste mit
    einem Wert je Abtastwert (siehe ramp)."""
    out = []
    table = isinstance(freq, list)
    moving = callable(freq)
    step = 0.0 if (moving or table) else freq / SAMPLE_RATE
    total = min(count(duration), len(freq)) if table else count(duration)
    for i in range(total):
        if table:
            step = freq[i] / SAMPLE_RATE
        elif moving:
            step = freq(i / SAMPLE_RATE) / SAMPLE_RATE
        phase += step
        x = phase - math.floor(phase)
        if shape == "sine":
            out.append(math.sin(TWO_PI * x))
        elif shape == "saw":
            out.append(2.0 * x - 1.0)
        elif shape == "square":
            out.append(1.0 if x < 0.5 else -1.0)
        else:
            out.append(4.0 * abs(x - 0.5) - 1.0)
    return out


def sweep(start, end, tau):
    """Tonhöhe, die von start nach end fällt oder steigt (tau = Zeit bis etwa zwei Drittel)."""
    return lambda t: end + (start - end) * math.exp(-t / tau)


def line(points):
    """Stückweise gerade Kurve durch [(Zeit, Wert), ...] als Funktion der Zeit."""
    def value(t):
        if t <= points[0][0]:
            return points[0][1]
        for (t0, v0), (t1, v1) in zip(points, points[1:]):
            if t <= t1:
                return v0 + (v1 - v0) * (t - t0) / max(t1 - t0, 1e-9)
        return points[-1][1]
    return value


def ramp(points, duration):
    """Stückweise gerade Kurve durch [(Zeit, Wert), ...] als Liste mit einem Wert je Abtastwert.
    Viel schneller als line(), wenn die Kurve viele Punkte hat."""
    n = count(duration)
    out = [points[-1][1]] * n
    first = min(n, int(points[0][0] * SAMPLE_RATE))
    for i in range(first):
        out[i] = points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        a = max(0, int(t0 * SAMPLE_RATE))
        b = min(n, int(t1 * SAMPLE_RATE))
        if b <= a:
            continue
        slope = (v1 - v0) / (b - a)
        for i in range(a, b):
            out[i] = v0 + slope * (i - a)
    return out


def decay(sig, tau):
    """Lässt das Signal mit exp(-t/tau) ausklingen."""
    return [s * math.exp(-i / (tau * SAMPLE_RATE)) for i, s in enumerate(sig)]


def shape_amp(sig, points):
    """Lautstärke-Verlauf über [(Zeit, Wert), ...]."""
    curve = line(points)
    return [s * curve(i / SAMPLE_RATE) for i, s in enumerate(sig)]


def gain(sig, factor):
    return [s * factor for s in sig]


def lowpass(sig, cutoff):
    """Einfacher Tiefpass (6 dB je Oktave). cutoff: Hz oder Funktion Zeit -> Hz."""
    out = []
    y = 0.0
    moving = callable(cutoff)
    a = 0.0 if moving else 1.0 - math.exp(-TWO_PI * cutoff / SAMPLE_RATE)
    for i, x in enumerate(sig):
        if moving:
            a = 1.0 - math.exp(-TWO_PI * max(cutoff(i / SAMPLE_RATE), 10.0) / SAMPLE_RATE)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    low = lowpass(sig, cutoff)
    return [x - y for x, y in zip(sig, low)]


def resonant(sig, cutoff, q=1.0, mode="band"):
    """Filter mit Resonanz (Zustandsvariablen-Filter, doppelt abgetastet, damit er stabil bleibt).
    mode: "low", "band" oder "high". cutoff: Hz, Funktion Zeit -> Hz oder Liste (siehe ramp)."""
    out = []
    low = 0.0
    band = 0.0
    high = 0.0
    damp = 1.0 / max(q, 0.7)
    table = isinstance(cutoff, list)
    moving = callable(cutoff)
    rate = 2.0 * SAMPLE_RATE

    def coefficient(hz):
        return 2.0 * math.sin(math.pi * min(max(hz, 20.0), 9000.0) / rate)

    f = 0.0 if (moving or table) else coefficient(cutoff)
    for i, x in enumerate(sig):
        if table:
            f = coefficient(cutoff[min(i, len(cutoff) - 1)])
        elif moving:
            f = coefficient(cutoff(i / SAMPLE_RATE))
        for _ in range(2):
            low += f * band
            high = x - low - damp * band
            band += f * high
        if mode == "low":
            out.append(low)
        elif mode == "high":
            out.append(high)
        else:
            out.append(band)
    return out


def mix(layers, duration=None):
    """Mischt Schichten (Signal, Faktor, Beginn in Sekunden) zu einem Signal."""
    total = 0
    for sig, _factor, offset in layers:
        total = max(total, count(offset) + len(sig) if offset > 0.0 else len(sig))
    if duration is not None:
        total = count(duration)
    out = [0.0] * total
    for sig, factor, offset in layers:
        start = int(round(offset * SAMPLE_RATE))
        for i, s in enumerate(sig):
            j = start + i
            if j >= total:
                break
            out[j] += s * factor
    return out


def peak_of(sig):
    return max(1e-12, max(abs(s) for s in sig))


def to_peak(sig, peak=1.0):
    factor = peak / peak_of(sig)
    return [s * factor for s in sig]


def drive(sig, amount):
    """Weiche Sättigung: macht Schläge dichter, ohne hart zu kappen."""
    sig = to_peak(sig)
    norm = math.tanh(amount)
    return [math.tanh(s * amount) / norm for s in sig]


def fade(sig, fade_in, fade_out):
    """Kurzes Ein- und Ausblenden gegen Knackser an den Rändern."""
    n = len(sig)
    n_in = min(n, count(fade_in)) if fade_in > 0.0 else 0
    n_out = min(n, count(fade_out)) if fade_out > 0.0 else 0
    out = list(sig)
    for i in range(n_in):
        out[i] *= i / n_in
    for i in range(n_out):
        out[n - 1 - i] *= i / n_out
    return out


def bell(duration, freq, tau, partials=((1.0, 1.0), (2.0, 0.45), (3.01, 0.2), (4.2, 0.1))):
    """Glocken-Ton: mehrere Teiltöne, die hohen klingen schneller aus."""
    n = count(duration)
    out = [0.0] * n
    for multiple, level in partials:
        w = TWO_PI * freq * multiple / SAMPLE_RATE
        part_tau = tau / (0.6 + 0.4 * multiple) * SAMPLE_RATE
        for i in range(n):
            out[i] += level * math.sin(w * i) * math.exp(-i / part_tau)
    return fade(out, 0.002, 0.01)


def pluck(duration, freq, tau):
    """Weicher, heller Ton für Melodien (Dreieck plus Oktave)."""
    base = osc(duration, freq, "tri")
    octave = osc(duration, freq * 2.0, "sine")
    fifth = osc(duration, freq * 3.0, "sine")
    sig = [a + 0.4 * b + 0.15 * c for a, b, c in zip(base, octave, fifth)]
    return fade(decay(sig, tau), 0.004, 0.02)


def brass(duration, freq, bright=2200.0, vibrato=0.0, attack=0.03, release=0.06):
    """Bläser: zwei leicht verstimmte Sägezähne durch einen Tiefpass, der mit dem Anblasen aufgeht."""
    pitch = freq if callable(freq) else (lambda _t: freq)

    def wobble(t):
        return pitch(t) * (1.0 + vibrato * math.sin(TWO_PI * 5.5 * t) * min(1.0, t / 0.25))

    a = osc(duration, wobble, "saw")
    b = osc(duration, lambda t: wobble(t) * 1.007, "saw", 0.31)
    raw = [(x + y) * 0.5 for x, y in zip(a, b)]

    def cutoff(t):
        return 400.0 + bright * min(1.0, t / attack) * (0.55 + 0.45 * math.exp(-t / 0.25))

    sig = resonant(raw, cutoff, 1.2, "low")
    hold = max(attack, duration - release)
    return shape_amp(sig, [(0.0, 0.0), (attack, 1.0), (hold, 0.8), (duration, 0.0)])


NOTE_STEPS = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    """Tonhöhe einer Note, z. B. "A4" = 440 Hz."""
    step = NOTE_STEPS[name[:-1]]
    octave = int(name[-1])
    return 440.0 * 2.0 ** ((12 * (octave + 1) + step - 69) / 12.0)


def click(rng, freqs, tau, noise_tau=0.004, knock=None):
    """Metallisches Klicken: kurzes Rauschen, ein paar klingende Töne, auf Wunsch ein dumpfer Schlag."""
    duration = max(tau * 6.0, 0.03)
    layers = [(decay(highpass(noise(duration, rng), 2500.0), noise_tau), 0.8, 0.0)]
    for freq in freqs:
        layers.append((decay(osc(duration, freq, "sine", rng.random()), tau), 0.5, 0.0))
    if knock is not None:
        layers.append((decay(osc(duration, sweep(knock, knock * 0.6, 0.02)), 0.02), 0.9, 0.0))
    return fade(mix(layers), 0.0003, 0.005)


# --- Schüsse --------------------------------------------------------------------------------

## Varianten eines Schusses: (Tonhöhe des Schlags, Länge des Knalls, Gewicht der Nachhall-Fahne).
## Variante 1 ist die Grundform, 2 ist tiefer und voller, 3 höher, knapper und trockener. Dazu hat
## jede Datei ihr eigenes Rauschen (eigener Zufall je Dateiname).
VARIANT_TWEAKS = ((1.0, 1.0, 1.0), (0.93, 1.18, 1.25), (1.08, 0.85, 0.80))


def gun(rng, duration, body, crack, tail=None, drive_amount=2.5, body_shape="sine", echo=None,
        variant=0, sub=None, slap=None, bright=6500.0):
    """Schuss aus Schichten: Schlag, Knall und Nachhall-Fahne.
    body = (Start-Hz, End-Hz, Ausklingzeit, Anteil): der Schlag, ein kurzer, fallender tiefer Ton.
    crack = (untere Grenze Hz, obere Grenze Hz, Ausklingzeit, Anteil): der Knall aus Rauschen mit
    schneller Hüllkurve.
    tail = (Grenze Hz, Ausklingzeit, Anteil): die Nachhall-Fahne, dumpfes Rauschen, das 8 ms nach
    dem Knall einsetzt und langsamer ausklingt.
    sub = (Hz, Ausklingzeit, Anteil): tiefer Stoß unter dem Schlag (nur schwere Waffen).
    slap = (Abstand s, Anteil): eine frühe, dumpfe Rückwurf-Kopie (Studiowand).
    echo = (Abstand s, Anteil): spätes Echo (Gewehre). bright: Grenze des letzten Tiefpasses in Hz.
    variant: 0 bis 2, siehe VARIANT_TWEAKS."""
    pitch, snap, ring = VARIANT_TWEAKS[variant]
    f0, f1, body_tau, body_level = body
    low, high, crack_tau, crack_level = crack
    f0 *= pitch
    f1 *= pitch
    crack_tau *= snap
    layers = [
        (to_peak(decay(osc(duration, sweep(f0, f1, body_tau * 0.5), body_shape), body_tau)), body_level, 0.0),
        (to_peak(decay(highpass(lowpass(noise(duration, rng), high), low), crack_tau)), crack_level, 0.0),
        (to_peak(decay(highpass(noise(0.004, rng), 4000.0), 0.0015)), 0.5, 0.0),
    ]
    if sub is not None:
        sub_hz, sub_tau, sub_level = sub
        thump = shape_amp(decay(osc(duration, sub_hz * pitch), sub_tau), [(0.0, 0.0), (0.004, 1.0), (duration, 1.0)])
        layers.append((thump, sub_level, 0.0))
    if tail is not None:
        cut, tail_tau, tail_level = tail
        fan = decay(highpass(lowpass(noise(duration, rng), cut), 180.0), tail_tau * ring)
        layers.append((to_peak(fan), tail_level * ring, 0.008))
    # Die Sättigung macht das Rauschen oben herum scharf: ein sanfter Tiefpass nimmt das Zischen.
    sig = lowpass(drive(mix(layers, duration), drive_amount), bright)
    if slap is not None:
        sig = mix([(sig, 1.0, 0.0), (lowpass(sig, 1800.0), slap[1] * ring, slap[0])], duration)
    if echo is not None:
        sig = mix([(sig, 1.0, 0.0), (lowpass(sig, 2500.0), echo[1], echo[0])], duration)
    return fade(sig, 0.0004, 0.02)


def shot_pistol(rng, variant=0):
    return gun(rng, 0.26, (280.0, 105.0, 0.045, 1.25), (900.0, 5200.0, 0.028, 2.0), (1600.0, 0.07, 0.7), 2.5,
               variant=variant, slap=(0.045, 0.18))


def shot_revolver(rng):
    return gun(rng, 0.34, (200.0, 66.0, 0.065, 1.2), (600.0, 4000.0, 0.045, 2.2), (1100.0, 0.10, 1.1), 3.3,
               sub=(62.0, 0.05, 0.7), slap=(0.06, 0.22))


def shot_smg(rng, variant=0):
    return gun(rng, 0.17, (330.0, 150.0, 0.026, 1.35), (1300.0, 6200.0, 0.016, 2.0), (2300.0, 0.04, 0.6), 2.2,
               variant=variant, slap=(0.035, 0.14))


def shot_sawed_off(rng):
    return gun(rng, 0.36, (165.0, 58.0, 0.065, 1.1), (400.0, 4600.0, 0.055, 2.6), (900.0, 0.10, 1.2), 4.0,
               sub=(55.0, 0.06, 0.7), slap=(0.07, 0.2))


def shot_shotgun(rng):
    return gun(rng, 0.40, (125.0, 45.0, 0.09, 1.3), (250.0, 3200.0, 0.07, 2.2), (600.0, 0.13, 1.5), 3.6,
               sub=(50.0, 0.08, 0.9))


def shot_rifle(rng, variant=0):
    return gun(rng, 0.28, (235.0, 88.0, 0.042, 1.15), (1200.0, 6200.0, 0.028, 2.2), (1800.0, 0.08, 0.9), 2.8,
               echo=(0.07, 0.22), variant=variant)


def shot_sniper(rng):
    return gun(rng, 0.40, (175.0, 52.0, 0.075, 1.1), (1800.0, 8000.0, 0.018, 2.8), (1400.0, 0.15, 1.4), 3.2,
               echo=(0.11, 0.3), sub=(48.0, 0.07, 0.7), bright=7500.0)


def shot_minigun(rng, variant=0):
    return gun(rng, 0.13, (175.0, 118.0, 0.024, 1.0), (800.0, 4600.0, 0.014, 1.8), (1500.0, 0.03, 0.35), 2.4,
               "saw", variant=variant)


def shot_rocket_launcher(rng):
    duration = 0.40
    whoosh = resonant(noise(duration, rng), lambda t: 300.0 + 2600.0 * (t / duration) ** 0.7, 1.5)
    whoosh = shape_amp(whoosh, [(0.0, 0.0), (0.03, 1.0), (0.15, 0.7), (duration, 0.0)])
    thump = decay(osc(duration, sweep(110.0, 45.0, 0.05)), 0.07)
    hiss = shape_amp(highpass(noise(duration, rng), 3000.0), [(0.0, 0.0), (0.05, 1.0), (duration, 0.0)])
    sig = mix([(to_peak(whoosh), 1.0, 0.0), (thump, 1.0, 0.0), (to_peak(hiss), 0.2, 0.0)], duration)
    return fade(drive(sig, 2.0), 0.0005, 0.03)


# --- Waffe, Treffer -------------------------------------------------------------------------

def reload_start(rng):
    scrape = resonant(noise(0.16, rng), line([(0.0, 1200.0), (0.16, 2600.0)]), 2.0)
    scrape = shape_amp(scrape, [(0.0, 0.0), (0.03, 1.0), (0.12, 0.6), (0.16, 0.0)])
    return mix([
        (click(rng, (2400.0, 1500.0), 0.011), 1.0, 0.0),
        (to_peak(scrape), 0.22, 0.05),
        (click(rng, (900.0, 1400.0), 0.012, knock=200.0), 0.9, 0.23),
    ], 0.32)


def reload_done(rng):
    return mix([
        (click(rng, (1100.0, 1900.0), 0.012, knock=220.0), 0.8, 0.0),
        (click(rng, (1700.0, 2900.0), 0.022), 1.0, 0.09),
    ], 0.25)


def hit(rng, variant=0):
    """Kugel trifft Zombie: heller Tick, dumpfer Schlag in den Körper, kurzes nasses Schmatzen.
    Variante 2 ist tiefer und nasser, Variante 3 höher und trockener."""
    duration = 0.09
    pitch = (1.0, 0.86, 1.15)[variant]
    tick = decay(osc(duration, sweep(900.0 * pitch, 350.0 * pitch, 0.012)), 0.014)
    thud = decay(osc(duration, sweep(210.0 * pitch, 95.0 * pitch, 0.02)), 0.022)
    flesh = decay(highpass(lowpass(noise(duration, rng), 4000.0), 1000.0), (0.009, 0.012, 0.007)[variant])
    squelch = resonant(noise(0.05, rng), sweep(2600.0 * pitch, 700.0, 0.015), 2.0)
    squelch = shape_amp(squelch, [(0.0, 0.0), (0.004, 1.0), (0.05, 0.0)])
    return fade(mix([(tick, 1.0, 0.0), (thud, 0.7, 0.0), (to_peak(flesh), 0.6, 0.0),
                     (to_peak(squelch), (0.25, 0.45, 0.15)[variant], 0.006)], duration), 0.0003, 0.01)


def headshot(rng):
    duration = 0.40
    ding = mix([(bell(duration, 1568.0, 0.11), 1.0, 0.0), (bell(duration, 2349.3, 0.09), 0.6, 0.0)], duration)
    pop = decay(osc(0.05, sweep(520.0, 200.0, 0.01)), 0.012)
    return fade(mix([(ding, 1.0, 0.0), (pop, 0.8, 0.0)], duration), 0.0003, 0.03)


# --- Zombies --------------------------------------------------------------------------------

def voice(rng, duration, pitch_points, formant_a, formant_b, growl_hz, growl_depth, breath, drive_amount):
    """Kehliger Laut: Sägezahn mit Flattern und Hauch durch zwei wandernde Resonanzen."""
    pitch = line(pitch_points)

    def wobble(t):
        return pitch(t) * (1.0 + 0.03 * math.sin(TWO_PI * 5.5 * t))

    source = osc(duration, wobble, "saw")
    air = lowpass(noise(duration, rng), 3500.0)
    raw = []
    for i, s in enumerate(source):
        t = i / SAMPLE_RATE
        flutter = 1.0 - growl_depth + growl_depth * abs(math.sin(math.pi * growl_hz * t))
        raw.append((s + breath * air[i]) * flutter)
    first = resonant(raw, line([(0.0, formant_a[0]), (duration, formant_b[0])]), 4.0)
    second = resonant(raw, line([(0.0, formant_a[1]), (duration, formant_b[1])]), 5.0)
    sig = lowpass([a + 0.6 * b for a, b in zip(first, second)], 3200.0)
    return drive(sig, drive_amount)


def zombie_groan_1(rng):
    duration = 0.85
    sig = voice(rng, duration, [(0.0, 92.0), (0.35, 108.0), (duration, 78.0)], (560.0, 980.0), (420.0, 820.0),
                26.0, 0.45, 0.5, 1.6)
    return shape_amp(sig, [(0.0, 0.0), (0.12, 1.0), (0.55, 0.8), (duration, 0.0)])


def zombie_groan_2(rng):
    duration = 0.70
    sig = voice(rng, duration, [(0.0, 120.0), (0.2, 132.0), (duration, 95.0)], (700.0, 1150.0), (500.0, 900.0),
                31.0, 0.35, 0.7, 1.4)
    return shape_amp(sig, [(0.0, 0.0), (0.08, 1.0), (0.4, 0.7), (duration, 0.0)])


def zombie_groan_3(rng):
    duration = 0.95
    sig = voice(rng, duration, [(0.0, 74.0), (0.5, 86.0), (duration, 66.0)], (430.0, 760.0), (520.0, 1000.0),
                21.0, 0.55, 0.4, 1.9)
    return shape_amp(sig, [(0.0, 0.0), (0.2, 0.9), (0.6, 1.0), (duration, 0.0)])


def elite_roar(rng):
    duration = 1.10
    sig = voice(rng, duration, [(0.0, 62.0), (0.3, 96.0), (0.6, 88.0), (duration, 48.0)], (480.0, 1150.0),
                (340.0, 760.0), 19.0, 0.6, 0.9, 3.2)
    rumble = lowpass(noise(duration, rng), 220.0)
    sig = mix([(sig, 1.0, 0.0), (to_peak(rumble), 0.35, 0.0)], duration)
    return shape_amp(sig, [(0.0, 0.0), (0.07, 1.0), (0.7, 0.85), (duration, 0.0)])


def zombie_death(rng, variant=0):
    """Zombie stirbt: abfallender Schrei, dumpfes Platschen, Schmatzen. Variante 2 ist ein tieferes,
    längeres Gurgeln, Variante 3 ein kurzes, hohes Kreischen."""
    duration = (0.48, 0.56, 0.40)[variant]
    pitch = (1.0, 0.80, 1.22)[variant]
    growl_hz, growl_depth, breath = ((34.0, 0.4, 0.8), (24.0, 0.6, 1.0), (41.0, 0.3, 0.6))[variant]
    form_a, form_b = (((760.0, 1250.0), (320.0, 640.0)), ((620.0, 1050.0), (280.0, 560.0)),
                      ((880.0, 1500.0), (420.0, 800.0)))[variant]
    sig = voice(rng, duration, [(0.0, 165.0 * pitch), (0.15, 120.0 * pitch), (duration, 58.0 * pitch)],
                form_a, form_b, growl_hz, growl_depth, breath, 2.2)
    sig = shape_amp(sig, [(0.0, 0.0), (0.02, 1.0), (duration * 0.52, 0.6), (duration, 0.0)])
    splat = decay(lowpass(noise(0.2, rng), 1400.0 * pitch), 0.035)
    thud = decay(osc(0.12, sweep(150.0 * pitch, 60.0, 0.03)), 0.035)
    squish = resonant(noise(0.25, rng), sweep(2200.0, 300.0, 0.07), 2.5)
    squish = shape_amp(squish, [(0.0, 0.0), (0.02, 1.0), (0.25, 0.0)])
    return fade(mix([(to_peak(sig), 0.8, 0.0), (to_peak(splat), 0.9, 0.0), (thud, 0.5, 0.0),
                     (to_peak(squish), (0.5, 0.7, 0.35)[variant], 0.03)], duration), 0.0005, 0.03)


# --- Spieler --------------------------------------------------------------------------------

def player_hurt(rng):
    duration = 0.28
    thump = decay(osc(duration, sweep(170.0, 60.0, 0.04)), 0.05)
    punch = decay(lowpass(noise(duration, rng), 900.0), 0.03)
    oof = voice(rng, 0.22, [(0.0, 195.0), (0.22, 118.0)], (620.0, 1050.0), (430.0, 800.0), 40.0, 0.2, 0.3, 1.5)
    oof = shape_amp(oof, [(0.0, 0.0), (0.02, 1.0), (0.12, 0.7), (0.22, 0.0)])
    sig = mix([(thump, 1.0, 0.0), (to_peak(punch), 0.7, 0.0), (to_peak(oof), 0.7, 0.02)], duration)
    return fade(drive(sig, 2.0), 0.0005, 0.03)


def shield_hit(rng):
    duration = 0.28
    layers = [(decay(highpass(noise(duration, rng), 5000.0), 0.008), 0.7, 0.0)]
    for freq, level in ((1480.0, 1.0), (2217.0, 0.6), (3322.0, 0.35)):
        layers.append((decay(osc(duration, freq), 0.05), level, 0.0))
    buzz = [a * b for a, b in zip(osc(duration, 1480.0), osc(duration, 90.0, "square"))]
    layers.append((decay(buzz, 0.07), 0.5, 0.0))
    return fade(mix(layers, duration), 0.0003, 0.03)


def shield_recharge(_rng):
    duration = 0.60

    def rise(t):
        return 500.0 * (3.0 ** (t / duration))

    base = osc(duration, rise)
    top = osc(duration, lambda t: rise(t) * 2.0)
    sig = []
    for i, (a, b) in enumerate(zip(base, top)):
        t = i / SAMPLE_RATE
        sig.append((a + 0.35 * b) * (0.75 + 0.25 * math.sin(TWO_PI * 14.0 * t)))
    return shape_amp(sig, [(0.0, 0.0), (0.15, 1.0), (0.45, 1.0), (duration, 0.0)])


def dash(rng):
    duration = 0.28
    center = line([(0.0, 600.0), (0.11, 3200.0), (duration, 900.0)])
    wind = resonant(noise(duration, rng), center, 1.6)
    wind = [s * math.sin(math.pi * i / len(wind)) ** 1.5 for i, s in enumerate(wind)]
    hum = shape_amp(osc(duration, line([(0.0, 200.0), (duration, 520.0)])), [(0.0, 0.0), (0.1, 1.0), (duration, 0.0)])
    return mix([(to_peak(wind), 1.0, 0.0), (hum, 0.25, 0.0)], duration)


# --- Kisten, Karten, Rucksack ---------------------------------------------------------------

def thunk(rng, level):
    duration = 0.2
    body = decay(osc(duration, sweep(190.0, 85.0, 0.03)), 0.05)
    wood = decay(highpass(lowpass(noise(duration, rng), 1400.0), 200.0), 0.035)
    return gain(drive(mix([(body, 0.8, 0.0), (to_peak(wood), 1.6, 0.0)], duration), 2.0), level)


def chest_drop(rng):
    return fade(mix([
        (thunk(rng, 1.0), 1.0, 0.0),
        (thunk(rng, 0.45), 1.0, 0.16),
        (bell(0.3, 2637.0, 0.08), 0.3, 0.08),
        (bell(0.3, 3136.0, 0.08), 0.25, 0.21),
    ], 0.55), 0.0005, 0.03)


def chest_open(rng):
    layers = [(click(rng, (700.0, 1100.0), 0.015, knock=160.0), 0.8, 0.0)]
    for i, name in enumerate(("C6", "E6", "G6", "C7")):
        layers.append((bell(0.5, hz(name), 0.16), 0.55, 0.10 + 0.06 * i))
    shimmer = shape_amp(highpass(noise(0.6, rng), 6000.0), [(0.0, 0.0), (0.2, 1.0), (0.6, 0.0)])
    layers.append((shimmer, 0.12, 0.1))
    return fade(mix(layers, 0.80), 0.0005, 0.05)


def card_chosen(rng):
    swish = resonant(noise(0.14, rng), line([(0.0, 800.0), (0.14, 4000.0)]), 1.5)
    swish = [s * math.sin(math.pi * i / len(swish)) for i, s in enumerate(swish)]
    return fade(mix([
        (to_peak(swish), 0.5, 0.0),
        (bell(0.2, 1318.5, 0.07), 0.9, 0.09),
        (bell(0.2, 1975.5, 0.06), 0.5, 0.09),
    ], 0.30), 0.0005, 0.02)


def upgrade(_rng):
    return fade(mix([
        (pluck(0.20, hz("G5"), 0.07), 0.8, 0.0),
        (pluck(0.20, hz("C6"), 0.07), 0.9, 0.08),
        (pluck(0.45, hz("E6"), 0.20), 1.0, 0.16),
        (bell(0.45, hz("C6"), 0.20), 0.3, 0.16),
    ], 0.62), 0.001, 0.05)


def synergy(rng):
    layers = []
    for i, name in enumerate(("D5", "F#5", "A5", "D6", "F#6")):
        layers.append((pluck(0.25, hz(name), 0.08), 0.75, 0.055 * i))
    for name, level in (("D6", 1.0), ("F#6", 0.8), ("A6", 0.7), ("D5", 0.5)):
        layers.append((bell(0.95, hz(name), 0.40), 0.5 * level, 0.30))
    shimmer = shape_amp(highpass(noise(0.9, rng), 7000.0), [(0.0, 0.0), (0.1, 1.0), (0.9, 0.0)])
    layers.append((shimmer, 0.10, 0.30))
    return fade(mix(layers, 1.28), 0.001, 0.08)


def zipper(rng, rising):
    """Reißverschluss: schnelle Rausch-Zähne, deren Takt und Klangfarbe steigt oder fällt."""
    duration = 0.26
    ends = (38.0, 95.0) if rising else (95.0, 38.0)
    tone = (1500.0, 4200.0) if rising else (4200.0, 1500.0)
    rate = line([(0.0, ends[0]), (duration, ends[1])])
    raw = noise(duration, rng)
    phase = 0.0
    teeth = []
    for i, s in enumerate(raw):
        phase += rate(i / SAMPLE_RATE) / SAMPLE_RATE
        x = phase - math.floor(phase)
        teeth.append(s * math.exp(-x * 9.0))
    sig = resonant(teeth, line([(0.0, tone[0]), (duration, tone[1])]), 1.8)
    return shape_amp(sig, [(0.0, 0.0), (0.02, 1.0), (duration - 0.05, 0.8), (duration, 0.0)])


def backpack_open(rng):
    cloth = shape_amp(lowpass(noise(0.2, rng), 1200.0), [(0.0, 0.0), (0.05, 1.0), (0.2, 0.0)])
    return fade(mix([(to_peak(zipper(rng, True)), 1.0, 0.0), (to_peak(cloth), 0.2, 0.0)], 0.30), 0.0005, 0.02)


def backpack_close(rng):
    snap = click(rng, (600.0, 950.0), 0.012, knock=190.0)
    return fade(mix([(to_peak(zipper(rng, False)), 1.0, 0.0), (snap, 0.9, 0.25)], 0.32), 0.0005, 0.02)


def item_sold(rng):
    return fade(mix([
        (click(rng, (2000.0, 3100.0), 0.006), 0.6, 0.0),
        (bell(0.3, hz("B5"), 0.10), 0.8, 0.03),
        (bell(0.35, hz("E6"), 0.13), 1.0, 0.11),
    ], 0.46), 0.0005, 0.04)


def purchase(rng):
    return fade(mix([
        (thunk(rng, 0.8), 1.0, 0.0),
        (click(rng, (1200.0, 1800.0), 0.008, knock=240.0), 0.8, 0.09),
        (bell(0.36, hz("E6"), 0.14), 0.8, 0.13),
        (bell(0.36, hz("G#6"), 0.14), 0.6, 0.13),
    ], 0.50), 0.0005, 0.04)


# --- Wellen, Ende ---------------------------------------------------------------------------

def wave_start(_rng):
    layers = []
    for i in range(3):
        layers.append((brass(0.12, hz("G4"), 2600.0, attack=0.015, release=0.03), 0.8, 0.14 * i))
    for name, level in (("C5", 1.0), ("E5", 0.6), ("G5", 0.5), ("C4", 0.5)):
        layers.append((brass(0.80, hz(name), 3000.0, vibrato=0.006), 0.6 * level, 0.42))
    return fade(mix(layers, 1.25), 0.001, 0.05)


def wave_cleared(rng):
    layers = []
    for i, name in enumerate(("C5", "E5", "G5")):
        layers.append((pluck(0.2, hz(name), 0.07), 0.8, 0.09 * i))
    for name, level in (("C6", 1.0), ("E6", 0.7), ("G5", 0.7), ("C5", 0.5)):
        layers.append((bell(0.8, hz(name), 0.32), 0.5 * level, 0.27))
        layers.append((brass(0.6, hz(name) * 0.5, 1800.0, vibrato=0.005), 0.22 * level, 0.27))
    shimmer = shape_amp(highpass(noise(0.6, rng), 7000.0), [(0.0, 0.0), (0.05, 1.0), (0.6, 0.0)])
    layers.append((shimmer, 0.08, 0.27))
    return fade(mix(layers, 1.10), 0.001, 0.08)


def countdown_tick(_rng):
    duration = 0.11
    tone = [a + 0.25 * b for a, b in zip(osc(duration, 880.0), osc(duration, 880.0, "square"))]
    sig = lowpass(tone, 4000.0)
    return shape_amp(sig, [(0.0, 0.0), (0.004, 1.0), (0.07, 0.8), (duration, 0.0)])


def game_over(_rng):
    """Die traurige Posaune: vier fallende Töne, der letzte lang und absackend."""
    layers = []
    starts = (0.0, 0.38, 0.76)
    for start, name in zip(starts, ("A#3", "A3", "G#3")):
        base = hz(name)
        layers.append((brass(0.34, lambda t, b=base: b * (1.0 - 0.02 * t / 0.34), 1500.0, attack=0.04), 1.0, start))
    last = hz("G3")

    def sag(t):
        return last * (1.0 - 0.10 * max(0.0, t - 0.25) / 0.45)

    layers.append((brass(0.70, sag, 1300.0, vibrato=0.022, attack=0.05, release=0.25), 1.0, 1.14))
    return fade(mix(layers, 1.86), 0.001, 0.05)


# --- Oberfläche -----------------------------------------------------------------------------

def ui_hover(_rng):
    duration = 0.045
    return fade(decay(osc(duration, sweep(2000.0, 1700.0, 0.01)), 0.010), 0.001, 0.008)


def ui_click(rng):
    duration = 0.09
    tone = decay(osc(duration, sweep(1300.0, 800.0, 0.018)), 0.02)
    tick = decay(highpass(noise(duration, rng), 3000.0), 0.003)
    return fade(mix([(tone, 1.0, 0.0), (to_peak(tick), 0.5, 0.0)], duration), 0.0003, 0.01)


# --- Effekte --------------------------------------------------------------------------------

def debris_grains(rng, duration, grains, start=0.12):
    """Trümmer-Rieseln: viele kurze, helle Körnchen (Rauschen durch eine schmale Resonanz), dicht
    kurz nach dem Knall und zum Ende hin seltener und leiser."""
    n = count(duration)
    out = [0.0] * n
    for _ in range(grains):
        at = start + (duration - start - 0.06) * rng.random() ** 1.6
        length = rng.uniform(0.004, 0.016)
        grain = decay(resonant(noise(length, rng), rng.uniform(900.0, 5200.0), 4.0), length * 0.35)
        level = rng.uniform(0.4, 1.0) * (1.0 - at / duration)
        first = int(at * SAMPLE_RATE)
        for i, s in enumerate(grain):
            if first + i < n:
                out[first + i] += s * level
    return out


def explosion(rng, variant=0):
    """Explosion: harter Knall, Druckwelle aus Rauschen, deren Klang schnell dumpf wird, ein tiefer
    Bauch (fallender Sinus mit Oktave, lange Ausklingzeit), Grollen und danach Trümmer-Rieseln.
    Variante 2 ist tiefer und rollt länger, Variante 3 ist höher und knapper."""
    duration = 0.95
    pitch = (1.0, 0.86, 1.14)[variant]
    blast = lowpass(noise(duration, rng), sweep(3800.0, 140.0, (0.16, 0.21, 0.12)[variant]))
    blast = decay(blast, (0.26, 0.30, 0.21)[variant])
    belly_pitch = sweep(88.0 * pitch, 34.0 * pitch, 0.16)
    belly = [a + 0.45 * b for a, b in zip(osc(duration, belly_pitch),
                                          osc(duration, lambda t: belly_pitch(t) * 2.0))]
    belly = decay(shape_amp(belly, [(0.0, 0.0), (0.006, 1.0), (duration, 1.0)]), (0.30, 0.36, 0.24)[variant])
    punch = decay(osc(0.12, sweep(240.0 * pitch, 70.0, 0.02)), 0.03)
    crack = decay(highpass(noise(0.05, rng), 2000.0), 0.012)
    rumble = lowpass(lowpass(noise(duration, rng), 180.0), 180.0)
    rumble = shape_amp(rumble, [(0.0, 0.0), (0.08, 1.0), (duration, 0.0)])
    sig = mix([(to_peak(blast), 2.0, 0.0), (belly, 1.3, 0.0), (punch, 0.8, 0.0), (to_peak(crack), 1.0, 0.0),
               (to_peak(rumble), 0.6, 0.0)], duration)
    sig = lowpass(drive(sig, 3.5), 5000.0)
    # Das Rieseln kommt nach der Sättigung dazu, damit die Körnchen einzeln hörbar bleiben.
    debris = debris_grains(rng, duration, (30, 38, 22)[variant])
    return fade(mix([(sig, 1.0, 0.0), (to_peak(debris), 0.17, 0.0)], duration), 0.0005, 0.1)


def lightning(rng):
    duration = 0.32
    n = count(duration)
    hold = count(0.006)
    freq = 900.0
    level = 1.0
    phase = 0.0
    buzz = []
    for i in range(n):
        if i % hold == 0:
            freq = rng.uniform(300.0, 1800.0)
            level = 1.0 if rng.random() < 0.8 else 0.15
        phase += freq / SAMPLE_RATE
        x = phase - math.floor(phase)
        buzz.append((1.0 if x < 0.5 else -1.0) * level)
    buzz = decay(highpass(buzz, 500.0), 0.12)
    crackle = decay(highpass(noise(duration, rng), 3000.0), 0.02)
    hiss = decay(highpass(noise(duration, rng), 1500.0), 0.10)
    sig = mix([(to_peak(buzz), 0.8, 0.0), (to_peak(crackle), 0.9, 0.0), (to_peak(hiss), 0.4, 0.0)], duration)
    return fade(lowpass(sig, 7000.0), 0.0003, 0.03)


def drone_shot(_rng):
    duration = 0.13
    pitch = sweep(2600.0, 500.0, 0.035)
    tone = [a + 0.3 * b for a, b in zip(osc(duration, pitch), osc(duration, pitch, "square"))]
    return fade(decay(lowpass(tone, 5000.0), 0.04), 0.0005, 0.015)


# --- Ausbau 3: Schüsse der zehn neuen Waffen ------------------------------------------------

def half_sine(sig):
    """Lautstärke als halbe Sinuswelle über die ganze Länge (für Dauerfeuer-Geräusche).
    Starten solche Stücke in gleichem Abstand übereinander (Abstand höchstens die halbe Länge),
    bleibt die Summe ihrer Leistung gleich: Aus vielen Stücken wird ein durchgehender Klang."""
    n = len(sig)
    return [s * math.sin(math.pi * i / n) for i, s in enumerate(sig)]


def shot_burst_pistol(rng, variant=0):
    """Dreierpack: knapper, heller Pistolenschuss mit kurzem Klingen des Verschlusses."""
    duration = 0.18
    shot = gun(rng, duration, (330.0, 150.0, 0.026, 1.1), (1100.0, 5500.0, 0.020, 2.0), (2000.0, 0.04, 0.5), 2.2,
               variant=variant, slap=(0.04, 0.14))
    ping = decay(osc(duration, 2350.0 * VARIANT_TWEAKS[variant][0], "sine", rng.random()), 0.018)
    return fade(mix([(shot, 1.0, 0.0), (ping, 0.18, 0.004)], duration), 0.0004, 0.02)


def shot_nail_gun(rng, variant=0):
    """Bühnenbau: Klacken des Schlagbolzens, ein kurzer Stoß Druckluft und ein dumpfer Rückstoß.
    Die Varianten klacken etwas tiefer bzw. höher und haben mehr bzw. weniger Luft."""
    duration = 0.12
    pitch, _snap, ring = VARIANT_TWEAKS[variant]
    clack = click(rng, (1750.0 * pitch, 2900.0 * pitch, 4100.0 * pitch), 0.006, noise_tau=0.002, knock=310.0 * pitch)
    air = resonant(noise(0.07, rng), 3200.0 * pitch, 1.2)
    air = shape_amp(air, [(0.0, 0.0), (0.004, 1.0), (0.025, 0.35), (0.07, 0.0)])
    kick = decay(osc(0.06, sweep(170.0 * pitch, 80.0, 0.015)), 0.016)
    return fade(mix([(clack, 1.0, 0.0), (to_peak(air), 0.45 * ring, 0.006), (kick, 0.5, 0.0)], duration),
                0.0003, 0.015)


def shot_machine_pistol(rng, variant=0):
    """Werbeblock: sehr kurzer, hoher, dünner Schuss (Rechteck statt Sinus im Schlag, nur ein Hauch
    Nachhall)."""
    return gun(rng, 0.12, (430.0, 210.0, 0.015, 0.75), (1700.0, 7000.0, 0.011, 2.2), (3000.0, 0.025, 0.3), 1.8,
               "square", variant=variant, bright=7500.0)


def shot_crossbow(rng):
    """Zielgerade: Die Sehne schnellt vor (tiefer, schnell fallender Ton mit Obertönen), das Holz
    klackt, der Bolzen zischt los."""
    duration = 0.30
    pitch = sweep(260.0, 150.0, 0.03)
    string = [a + 0.5 * b + 0.25 * c for a, b, c in zip(
        osc(duration, pitch, "tri"),
        osc(duration, lambda t: pitch(t) * 2.0),
        osc(duration, lambda t: pitch(t) * 3.02))]
    string = decay(string, 0.07)
    snap = click(rng, (900.0, 1500.0), 0.008, knock=240.0)
    whoosh = resonant(noise(0.14, rng), line([(0.0, 1800.0), (0.14, 5200.0)]), 2.0)
    whoosh = [s * math.sin(math.pi * i / len(whoosh)) for i, s in enumerate(whoosh)]
    return fade(mix([(string, 0.9, 0.0), (snap, 0.5, 0.0), (to_peak(whoosh), 0.35, 0.01)], duration), 0.0004, 0.03)


def shot_grenade_launcher(rng):
    """Knalleffekt: dumpfes Plopp aus dem Rohr (fallender Sinus, hohles Rohr, Luftstoß)."""
    duration = 0.28
    pop = decay(osc(duration, sweep(240.0, 85.0, 0.035)), 0.055)
    tube = decay(resonant(noise(duration, rng), 330.0, 5.0), 0.05)
    puff = decay(lowpass(noise(duration, rng), 700.0), 0.03)
    sig = mix([(pop, 1.0, 0.0), (to_peak(tube), 0.5, 0.0), (to_peak(puff), 0.4, 0.0)], duration)
    return fade(lowpass(drive(sig, 1.6), 2600.0), 0.0006, 0.03)


def shot_flamethrower(rng):
    """Heiße Phase: ein Stück gleichmäßiges Fauchen (Rauschen um 900 Hz, dumpfes Grollen, etwas
    Zischen). Nichts darin bewegt sich: Die Stücke überlappen sich im Dauerfeuer (siehe half_sine),
    und jede Bewegung im Stück würde sich mit dem Takt der Starts wiederholen."""
    duration = 0.40
    roar = resonant(noise(duration, rng), 900.0, 1.0)
    rumble = lowpass(lowpass(noise(duration, rng), 260.0), 260.0)
    hiss = highpass(lowpass(noise(duration, rng), 6000.0), 2200.0)
    sig = mix([(to_peak(roar), 1.0, 0.0), (to_peak(rumble), 0.7, 0.0), (to_peak(hiss), 0.35, 0.0)], duration)
    return half_sine(drive(sig, 1.5))


def shot_beam(rng):
    """Rotlicht: ein Stück Summton. Alle Töne sind Vielfache von 55 Hz (Sägezähne auf 110, 165 und
    220 Hz, ein leiser Pfeifton auf 2200 Hz), der Klang steht also still und lässt sich im
    Dauerfeuer überlappen (siehe half_sine)."""
    duration = 0.40
    low = osc(duration, 110.0, "saw", rng.random())
    fifth = osc(duration, 165.0, "saw", rng.random())
    octave = osc(duration, 220.0, "saw", rng.random())
    raw = [a + 0.6 * b + 0.5 * c for a, b, c in zip(low, fifth, octave)]
    body = to_peak(resonant(raw, 1500.0, 2.0, "low"))
    whine = osc(duration, lambda t: 2200.0 * (1.0 + 0.004 * math.sin(TWO_PI * 27.5 * t)))
    sig = []
    for i, (a, b) in enumerate(zip(body, whine)):
        # Leichtes Brummen im Takt von 110 Hz, wie ein Netzteil.
        buzz = 0.85 + 0.15 * math.sin(TWO_PI * 110.0 * i / SAMPLE_RATE)
        sig.append((a + 0.12 * b) * buzz)
    return half_sine(sig)


def shot_tesla(rng):
    """Kurzschluss: harter Funke, dann ein knackendes Sirren aus springenden Rechtecktönen mit
    Aussetzern, darunter kurz ein Trafo-Brummen."""
    duration = 0.24
    n = count(duration)
    hold = count(0.0035)
    freq = 1500.0
    level = 1.0
    phase = 0.0
    buzz = []
    for i in range(n):
        if i % hold == 0:
            freq = rng.uniform(500.0, 3200.0)
            level = 1.0 if rng.random() < 0.7 else 0.0
        phase += freq / SAMPLE_RATE
        x = phase - math.floor(phase)
        buzz.append((1.0 if x < 0.5 else -1.0) * level)
    buzz = decay(highpass(buzz, 700.0), 0.045)
    snap = decay(highpass(noise(0.03, rng), 3500.0), 0.004)
    hum = decay(lowpass(osc(duration, 100.0, "square"), 1200.0), 0.06)
    thump = decay(osc(duration, sweep(180.0, 70.0, 0.03)), 0.04)
    sig = mix([(to_peak(buzz), 0.9, 0.0), (to_peak(snap), 1.0, 0.0), (to_peak(hum), 0.35, 0.0),
               (thump, 0.6, 0.0)], duration)
    return fade(lowpass(sig, 7500.0), 0.0003, 0.03)


def shot_lmg(rng, variant=0):
    """Marathonsendung: tiefer, satter, kurzer Schlag (tiefer als das Sturmgewehr, ohne Echo) mit
    einem tiefen Stoß darunter."""
    return gun(rng, 0.22, (150.0, 60.0, 0.05, 1.1), (650.0, 4200.0, 0.026, 2.2), (950.0, 0.06, 1.1), 3.3,
               variant=variant, sub=(58.0, 0.045, 0.45))


def shot_auto_shotgun(rng, variant=0):
    """Zuschauerfrage: Schrotschuss, kürzer als die Flinte, danach klackt der Verschluss."""
    duration = 0.27
    blast = gun(rng, duration, (140.0, 55.0, 0.06, 1.0), (320.0, 3600.0, 0.045, 2.4), (750.0, 0.07, 1.2), 3.8,
                variant=variant, sub=(52.0, 0.05, 0.45))
    clack = click(rng, (1250.0, 2050.0), 0.009, knock=260.0)
    return fade(mix([(blast, 1.0, 0.0), (clack, 0.22, 0.12 * VARIANT_TWEAKS[variant][1])], duration), 0.0004, 0.03)


# --- Ausbau 3: Kameras ----------------------------------------------------------------------

def cam_tele(rng):
    """Tele-Kamera: ein kräftiger, scharfer Schuss mit hellem Pfiff am Anfang und Nachhall."""
    duration = 0.34
    shot = gun(rng, duration, (220.0, 80.0, 0.05, 0.8), (1500.0, 7000.0, 0.020, 2.6), (1300.0, 0.10, 1.1), 2.8,
               echo=(0.09, 0.25))
    zing = decay(osc(0.09, sweep(3400.0, 1100.0, 0.02)), 0.022)
    return fade(mix([(shot, 1.0, 0.0), (zing, 0.3, 0.0)], duration), 0.0004, 0.03)


def cam_flash(rng):
    """Blitzlicht: Klick des Verschlusses, dann das kurze helle Zischen der Blitzröhre mit einem
    dumpfen Puff und einem leisen, steigenden Pfeifton."""
    duration = 0.30
    shutter = click(rng, (1900.0, 3100.0), 0.007, knock=280.0)
    hiss = highpass(noise(0.22, rng), 3500.0)
    hiss = shape_amp(hiss, [(0.0, 0.0), (0.004, 1.0), (0.05, 0.4), (0.22, 0.0)])
    pop = decay(lowpass(noise(0.05, rng), 1500.0), 0.008)
    whine = osc(0.26, line([(0.0, 2600.0), (0.26, 5200.0)]))
    whine = shape_amp(whine, [(0.0, 0.0), (0.05, 1.0), (0.26, 0.0)])
    return fade(mix([(shutter, 0.8, 0.0), (to_peak(hiss), 0.8, 0.02), (to_peak(pop), 0.6, 0.02),
                     (whine, 0.10, 0.03)], duration), 0.0004, 0.03)


def cam_slow(rng):
    """Zeitlupen-Kamera: tiefes Wumm, dessen Ton absackt (Sinus mit Oktave), dazu ein dumpfer
    Luftstoß, der mit absinkt."""
    duration = 0.45
    pitch = sweep(150.0, 42.0, 0.11)
    boom = [a + 0.35 * b for a, b in zip(osc(duration, pitch), osc(duration, lambda t: pitch(t) * 2.0))]
    boom = shape_amp(boom, [(0.0, 0.0), (0.008, 1.0), (0.12, 0.7), (duration, 0.0)])
    air = resonant(noise(duration, rng), sweep(900.0, 160.0, 0.10), 1.5)
    air = shape_amp(air, [(0.0, 0.0), (0.02, 1.0), (duration, 0.0)])
    return fade(mix([(boom, 1.0, 0.0), (to_peak(air), 0.3, 0.0)], duration), 0.001, 0.05)


def cam_director(_rng):
    """Regie-Kamera: kurzer, klarer Piep (höher als das Ticken des Countdowns)."""
    duration = 0.10
    tone = [a + 0.2 * b for a, b in zip(osc(duration, 1568.0), osc(duration, 3136.0))]
    return shape_amp(tone, [(0.0, 0.0), (0.004, 1.0), (0.07, 0.9), (duration, 0.0)])


# --- Ausbau 3: Gegenstände und Fortschritt --------------------------------------------------

def mine_placed(rng):
    """Mine gelegt: zwei leise Klicks (Absetzen mit dumpfem Schlag, dann Scharfstellen)."""
    return mix([
        (click(rng, (1100.0, 1700.0), 0.008, knock=170.0), 0.8, 0.0),
        (click(rng, (2300.0, 3400.0), 0.006), 0.6, 0.075),
    ], 0.12)


def mine_triggered(_rng):
    """Mine ausgelöst: zwei schnelle, hohe Warntöne, der zweite höher."""
    def beep(freq):
        length = 0.05
        tone = [a + 0.3 * b for a, b in zip(osc(length, freq), osc(length, freq, "square"))]
        return shape_amp(lowpass(tone, 6000.0), [(0.0, 0.0), (0.003, 1.0), (0.04, 1.0), (length, 0.0)])

    return mix([(beep(2350.0), 1.0, 0.0), (beep(2800.0), 1.0, 0.075)], 0.13)


def player_revived(rng):
    """Zweite Staffel: aufsteigende Fanfare. Vier schnelle Bläsertöne nach oben über einem
    aufsteigenden Rauschen, dann ein strahlender Akkord mit Glocken."""
    layers = []
    for i, name in enumerate(("A4", "D5", "F#5", "A5")):
        layers.append((brass(0.13, hz(name), 2800.0, attack=0.012, release=0.03), 0.8, 0.10 * i))
    for name, level in (("D6", 1.0), ("A5", 0.6), ("F#5", 0.6), ("D5", 0.5)):
        layers.append((brass(0.80, hz(name), 3200.0, vibrato=0.006), 0.55 * level, 0.42))
    for name, level in (("D6", 1.0), ("A6", 0.6)):
        layers.append((bell(0.8, hz(name), 0.30), 0.3 * level, 0.42))
    rise = resonant(noise(0.45, rng), line([(0.0, 400.0), (0.45, 5000.0)]), 2.0)
    rise = shape_amp(rise, [(0.0, 0.0), (0.38, 1.0), (0.45, 0.0)])
    layers.append((to_peak(rise), 0.25, 0.0))
    return fade(mix(layers, 1.28), 0.001, 0.06)


def pack_unlocked(rng):
    """Paket freigeschaltet: Kassenklingeln (Schublade, zwei helle Glocken), dann ein Tusch der
    Bläser (kurzer Akkord, langer Akkord)."""
    layers = [
        (thunk(rng, 0.7), 0.8, 0.0),
        (click(rng, (1500.0, 2300.0), 0.008), 0.6, 0.02),
        (bell(0.5, hz("B6"), 0.16), 0.7, 0.05),
        (bell(0.5, hz("E7"), 0.18), 0.6, 0.12),
    ]
    for name, level in (("G4", 0.7), ("B4", 0.7), ("D5", 0.8), ("G5", 1.0)):
        layers.append((brass(0.11, hz(name), 2600.0, attack=0.012, release=0.03), 0.5 * level, 0.36))
        layers.append((brass(0.55, hz(name), 3000.0, vibrato=0.005), 0.55 * level, 0.52))
    return fade(mix(layers, 1.12), 0.001, 0.06)


def bank_coins(rng):
    """Gutschrift: Münzen fallen nacheinander in die Kasse (acht helle Klimpertöne, immer
    schneller und höher), am Ende ein Glockenton."""
    layers = []
    start = 0.0
    step = 0.075
    for i in range(8):
        freq = 3300.0 * (1.0 + 0.035 * i) * rng.uniform(0.97, 1.03)
        coin = bell(0.12, freq, 0.03, partials=((1.0, 1.0), (1.48, 0.6), (2.31, 0.35), (3.6, 0.15)))
        layers.append((coin, 0.5 + 0.03 * i, start))
        layers.append((decay(highpass(noise(0.01, rng), 5000.0), 0.002), 0.25, start))
        start += step
        step *= 0.93
    layers.append((bell(0.45, hz("E7"), 0.16), 0.8, start + 0.02))
    return fade(mix(layers, start + 0.47), 0.0005, 0.05)


def ricochet(rng):
    """Querschläger: heller Ton, der schnell abfällt und dabei zittert, mit dünnem Luftzug."""
    duration = 0.22
    pitch = sweep(4200.0, 1500.0, 0.07)

    def wobble(t):
        return pitch(t) * (1.0 + 0.03 * math.sin(TWO_PI * 45.0 * t))

    tone = shape_amp(osc(duration, wobble), [(0.0, 0.0), (0.004, 1.0), (0.08, 0.5), (duration, 0.0)])
    air = resonant(noise(duration, rng), pitch, 3.0)
    air = shape_amp(air, [(0.0, 0.0), (0.01, 1.0), (duration, 0.0)])
    tick = decay(highpass(noise(0.01, rng), 4000.0), 0.002)
    return fade(mix([(tone, 1.0, 0.0), (to_peak(air), 0.3, 0.0), (to_peak(tick), 0.5, 0.0)], duration), 0.0003, 0.03)


def thorns(rng):
    """Dornen: kurzer, spitzer Stich (schnell fallender Ton, feines Klingen, Knacks)."""
    duration = 0.12
    stab = decay(osc(duration, sweep(2900.0, 1000.0, 0.012)), 0.016)
    ring = decay([a + 0.6 * b for a, b in zip(osc(duration, 3350.0), osc(duration, 5020.0))], 0.022)
    tick = decay(highpass(noise(duration, rng), 3500.0), 0.004)
    return fade(mix([(stab, 1.0, 0.0), (ring, 0.35, 0.0), (to_peak(tick), 0.6, 0.0)], duration), 0.0003, 0.02)


# --- Ausbau 4: Schritte, Landen, Herzschlag ---------------------------------------------------

def footstep(rng, variant=0):
    """Schritt auf dem Bühnenboden: dumpfer Tritt der Ferse (fallender tiefer Ton), der hohle Boden
    schwingt kurz nach, die Sohle klatscht, danach rollt der Fuß leise ab. Vier Varianten mit
    etwas anderer Tonhöhe, anderem Klatschen und anderem Abrollen."""
    duration = 0.16
    pitch = (1.0, 0.91, 1.09, 0.96)[variant]
    heel = decay(osc(duration, sweep(125.0 * pitch, 62.0 * pitch, 0.02)), 0.022)
    boards = decay(resonant(noise(duration, rng), 210.0 * pitch, 3.0), 0.03)
    slap = decay(highpass(lowpass(noise(duration, rng), 2600.0), 700.0), (0.012, 0.010, 0.014, 0.011)[variant])
    scuff = resonant(noise(0.07, rng), 1900.0 * pitch, 1.2)
    scuff = shape_amp(scuff, [(0.0, 0.0), (0.015, 1.0), (0.07, 0.0)])
    sig = mix([(heel, 1.0, 0.0), (to_peak(boards), 0.7, 0.0), (to_peak(slap), 0.5, 0.0),
               (to_peak(scuff), (0.14, 0.22, 0.10, 0.18)[variant], (0.035, 0.030, 0.040, 0.045)[variant])],
              duration)
    return fade(lowpass(sig, 4500.0), 0.0005, 0.03)


def land(rng):
    """Landen nach einem Sprung: beide Füße kurz nacheinander (zwei tiefe Schläge), der Boden
    dröhnt nach, die Kleidung raschelt."""
    duration = 0.30
    layers = []
    for at, level in ((0.0, 1.0), (0.022, 0.8)):
        layers.append((decay(osc(0.2, sweep(105.0, 46.0, 0.03)), 0.05), level, at))
        layers.append((to_peak(decay(highpass(lowpass(noise(0.1, rng), 2200.0), 500.0), 0.014)), 0.45 * level, at))
    boards = decay(resonant(noise(duration, rng), 150.0, 4.0), 0.07)
    cloth = shape_amp(lowpass(noise(0.16, rng), 1200.0), [(0.0, 0.0), (0.04, 1.0), (0.16, 0.0)])
    layers.append((to_peak(boards), 0.8, 0.0))
    layers.append((to_peak(cloth), 0.18, 0.02))
    return fade(lowpass(drive(mix(layers, duration), 1.8), 4000.0), 0.0005, 0.05)


def heartbeat(rng):
    """Herzschlag bei wenig Leben: zwei dumpfe Schläge (der zweite höher, kürzer und leiser). Jeder
    Schlag ist ein fallender tiefer Ton mit zwei Obertönen, damit er auch auf kleinen Lautsprechern
    zu hören ist, und einem dumpfen Stoß aus Rauschen."""
    duration = 0.42

    def beat(start_hz, tau, length):
        pitch = sweep(start_hz, start_hz * 0.6, 0.04)
        tone = [a + 0.5 * b + 0.2 * c for a, b, c in zip(
            osc(length, pitch), osc(length, lambda t: pitch(t) * 2.0), osc(length, lambda t: pitch(t) * 3.0))]
        tone = decay(shape_amp(tone, [(0.0, 0.0), (0.008, 1.0), (length, 1.0)]), tau)
        puff = decay(lowpass(lowpass(noise(length, rng), 160.0), 160.0), tau)
        return mix([(tone, 1.0, 0.0), (to_peak(puff), 0.4, 0.0)], length)

    sig = mix([(beat(78.0, 0.05, 0.2), 1.0, 0.0), (beat(92.0, 0.04, 0.2), 0.7, 0.17)], duration)
    return fade(lowpass(lowpass(sig, 420.0), 420.0), 0.002, 0.05)


# --- Ausbau 4: Material, Reparieren, Verschrotten ---------------------------------------------

def item_repaired(rng):
    """Reparieren: eine Ratsche (sechs Klicks, die schneller und höher werden, darunter ein leises
    Drehgeräusch), dann rastet etwas ein und ein kurzer heller Ton meldet: fertig."""
    layers = []
    at = 0.0
    step = 0.07
    for i in range(6):
        k = 1.0 + 0.04 * i
        layers.append((click(rng, (2100.0 * k, 3300.0 * k), 0.006, noise_tau=0.002, knock=420.0), 0.7 + 0.05 * i, at))
        at += step
        step *= 0.84
    turn = resonant(noise(0.30, rng), line([(0.0, 1500.0), (0.30, 2600.0)]), 2.0)
    turn = shape_amp(turn, [(0.0, 0.0), (0.03, 1.0), (0.26, 0.8), (0.30, 0.0)])
    layers.append((to_peak(turn), 0.10, 0.0))
    layers.append((click(rng, (900.0, 1500.0), 0.014, knock=180.0), 1.0, at + 0.03))
    layers.append((bell(0.22, hz("E6"), 0.07), 0.35, at + 0.04))
    return fade(mix(layers, at + 0.27), 0.0005, 0.04)


def item_scrapped(rng):
    """Verschrotten: Blech wird zerknüllt. Rauschen mit einer zackigen Hüllkurve aus vielen
    einzelnen Knicken läuft durch fünf schmale Resonanzen (jede mit eigenen Knicken), am Ende
    fällt das Knäuel dumpf in die Tonne."""
    duration = 0.55
    n = count(duration)
    layers = []
    for band_hz in (520.0, 1130.0, 1870.0, 2950.0, 4100.0):
        env = [0.0] * n
        for _ in range(7):
            at = 0.36 * rng.random() ** 1.3
            tau = rng.uniform(0.006, 0.025) * SAMPLE_RATE
            level = rng.uniform(0.4, 1.0)
            first = int(at * SAMPLE_RATE)
            for i in range(min(int(tau * 6.0), n - first)):
                env[first + i] += level * math.exp(-i / tau)
        raw = [s * e for s, e in zip(noise(duration, rng), env)]
        layers.append((to_peak(resonant(raw, band_hz * rng.uniform(0.94, 1.06), 7.0)), 1.0 if band_hz < 2000.0 else 0.7, 0.0))
    crumple = drive(mix(layers, duration), 2.0)
    thud = thunk(rng, 0.9)
    rattle = click(rng, (1400.0, 2250.0, 3600.0), 0.02, knock=None)
    return fade(mix([(crumple, 1.0, 0.0), (thud, 0.75, 0.38), (rattle, 0.3, 0.40)], duration), 0.0005, 0.04)


def material_gain(rng):
    """Material kommt dazu: drei kleine Metallteile klimpern kurz nacheinander (helle Töne mit
    unharmonischen Obertönen, sehr kurz)."""
    layers = []
    for freq, at, level in ((2400.0, 0.0, 0.8), (3100.0, 0.05, 1.0), (2750.0, 0.095, 0.7)):
        tone = bell(0.14, freq * rng.uniform(0.97, 1.03), 0.035, partials=((1.0, 1.0), (2.76, 0.5), (5.4, 0.25)))
        layers.append((tone, level, at))
        layers.append((decay(highpass(noise(0.008, rng), 5000.0), 0.0015), 0.3 * level, at))
    return fade(mix(layers, 0.26), 0.0005, 0.03)


# --- Ausbau 4: Publikum (22050 Hz) ------------------------------------------------------------

## Vokale als (erste Resonanz, zweite Resonanz) in Hz: a, e, i, o, u, offenes o.
VOWELS = ((700.0, 1200.0), (500.0, 1700.0), (350.0, 2100.0), (450.0, 850.0), (350.0, 800.0), (600.0, 1000.0))


def crowd_voice(rng, duration, pitch_points, first_points, second_points, breath=0.15, vibrato=0.02):
    """Eine Stimme im Publikum: weicher Sägezahn mit etwas Hauch durch zwei wandernde Resonanzen
    (Vokal). Die drei Kurven sind Listen [(Zeit, Hz), ...]."""
    rate = rng.uniform(4.5, 6.5)
    shift = rng.random()
    pitch = ramp(pitch_points, duration)
    freq = [p * (1.0 + vibrato * math.sin(TWO_PI * (rate * i / SAMPLE_RATE + shift))) for i, p in enumerate(pitch)]
    source = lowpass(osc(duration, freq, "saw", rng.random()), 1800.0)
    air = lowpass(noise(duration, rng), 3000.0)
    raw = [s + breath * a for s, a in zip(source, air)]
    first = resonant(raw, ramp(first_points, duration), 5.0)
    second = resonant(raw, ramp(second_points, duration), 6.0)
    return [a + 0.5 * b for a, b in zip(first, second)]


def room(sig):
    """Zwei frühe, dumpfe Rückwürfe: Die Stimmen stehen in einem Saal, nicht am Ohr."""
    return mix([(sig, 1.0, 0.0), (lowpass(sig, 2000.0), 0.30, 0.06), (lowpass(sig, 1400.0), 0.20, 0.11)], len(sig) / SAMPLE_RATE)


def applause(rng, duration, people, density_points):
    """Klatschen: Jeder Mensch klatscht in seinem eigenen Takt (3,6 bis 5,2 Mal je Sekunde). Die
    Schläge sind kurze Stöße aus Rauschen in drei Klangfarben (hohle bis flache Hand).
    density_points: Anteil der Menschen, die gerade klatschen, über die Zeit."""
    n = count(duration)
    density = line(density_points)
    out = [0.0] * n
    for band_hz in (1000.0, 1500.0, 2300.0):
        env = [0.0] * n
        for _ in range(max(1, people // 3)):
            at = rng.uniform(0.0, 0.3)
            rate = rng.uniform(3.6, 5.2)
            level = rng.uniform(0.5, 1.0)
            tau = rng.uniform(0.006, 0.012) * SAMPLE_RATE
            while at < duration - 0.05:
                if rng.random() < density(at):
                    first = int(at * SAMPLE_RATE)
                    for i in range(min(int(tau * 5.0), n - first)):
                        env[first + i] += level * math.exp(-i / tau)
                at += rng.uniform(0.9, 1.1) / rate
        band = resonant([s * e for s, e in zip(noise(duration, rng), env)], band_hz * rng.uniform(0.95, 1.05), 1.4)
        out = [a + b for a, b in zip(out, band)]
    return highpass(out, 500.0)


def crowd_cheer(rng):
    """Welle geschafft: Das Publikum klatscht (30 Leute, schnell anschwellend, langsam abebbend) und
    jubelt (neun Stimmen mit steigendem Ton, "jaa" und "wuu"), dazu zwei Pfiffe."""
    duration = 2.4
    layers = [(to_peak(applause(rng, duration, 30, [(0.0, 0.5), (0.2, 1.0), (1.2, 0.9), (2.3, 0.15)])), 3.0, 0.0)]
    for i in range(9):
        woo = i % 3 == 0
        base = rng.uniform(300.0, 430.0) if woo else rng.uniform(130.0, 260.0)
        length = rng.uniform(0.5, 1.0)
        start = rng.uniform(0.0, 0.55)
        vowel_a, vowel_b = ((VOWELS[4], VOWELS[3]) if woo else (VOWELS[1], VOWELS[0]))
        voice_sig = crowd_voice(rng, length, [(0.0, base), (length * 0.3, base * 1.35), (length, base * 1.15)],
                                [(0.0, vowel_a[0]), (length * 0.3, vowel_b[0]), (length, vowel_b[0])],
                                [(0.0, vowel_a[1]), (length * 0.3, vowel_b[1]), (length, vowel_b[1])], 0.2, 0.025)
        voice_sig = shape_amp(voice_sig, [(0.0, 0.0), (0.06, 1.0), (length * 0.6, 0.8), (length, 0.0)])
        layers.append((to_peak(voice_sig), rng.uniform(0.6, 1.0), start))
    for start, low, high in ((0.25, 1700.0, 2500.0), (0.9, 2000.0, 2900.0)):
        pitch = line([(0.0, low), (0.12, high), (0.32, high * 0.97)])
        whistle = shape_amp(osc(0.32, lambda t, p=pitch: p(t) * (1.0 + 0.012 * math.sin(TWO_PI * 7.0 * t))),
                            [(0.0, 0.0), (0.03, 1.0), (0.26, 0.8), (0.32, 0.0)])
        layers.append((whistle, 0.35, start))
    sig = shape_amp(room(mix(layers, duration)), [(0.0, 1.0), (1.5, 1.0), (duration, 0.0)])
    return fade(sig, 0.004, 0.2)


def crowd_gasp(rng):
    """Schwerer Treffer am Spieler: Das Publikum zieht scharf die Luft ein und ruft erschrocken
    "Oh!" (zehn Stimmen, der Ton springt kurz hoch und fällt dann ab)."""
    duration = 0.75
    layers = []
    for i in range(10):
        base = rng.uniform(105.0, 150.0) if i % 2 == 0 else rng.uniform(200.0, 290.0)
        length = rng.uniform(0.42, 0.58)
        start = 0.10 + rng.uniform(0.0, 0.07)
        voice_sig = crowd_voice(rng, length, [(0.0, base), (0.07, base * 1.18), (length, base * 0.78)],
                                [(0.0, 560.0 * rng.uniform(0.92, 1.08)), (length, 430.0)],
                                [(0.0, 920.0 * rng.uniform(0.92, 1.08)), (length, 780.0)], 0.2, 0.01)
        voice_sig = shape_amp(voice_sig, [(0.0, 0.0), (0.04, 1.0), (length * 0.45, 0.75), (length, 0.0)])
        layers.append((to_peak(voice_sig), rng.uniform(0.6, 1.0), start))
    inhale = resonant(noise(0.16, rng), ramp([(0.0, 1100.0), (0.16, 2600.0)], 0.16), 1.5)
    inhale = shape_amp(inhale, [(0.0, 0.0), (0.10, 1.0), (0.16, 0.0)])
    layers.append((to_peak(inhale), 1.2, 0.0))
    return fade(room(mix(layers, duration)), 0.002, 0.08)


def crowd_aww(rng):
    """Game Over: enttäuschtes "Ohhh" (zwölf Stimmen, deren Ton lang abfällt, der Vokal wandert
    von o nach u), darunter drei tiefe Buh-Rufe."""
    duration = 1.6
    layers = []
    for i in range(12):
        base = rng.uniform(110.0, 160.0) if i % 2 == 0 else rng.uniform(210.0, 300.0)
        length = rng.uniform(1.0, 1.4)
        start = rng.uniform(0.0, 0.15)
        voice_sig = crowd_voice(rng, length, [(0.0, base * 1.05), (0.12, base), (length, base * 0.70)],
                                [(0.0, 480.0 * rng.uniform(0.92, 1.08)), (length, 350.0)],
                                [(0.0, 860.0 * rng.uniform(0.92, 1.08)), (length, 720.0)], 0.15, 0.012)
        voice_sig = shape_amp(voice_sig, [(0.0, 0.0), (0.08, 1.0), (length * 0.5, 0.8), (length, 0.0)])
        layers.append((to_peak(voice_sig), rng.uniform(0.6, 1.0), start))
    for _ in range(3):
        base = rng.uniform(95.0, 125.0)
        length = rng.uniform(1.0, 1.3)
        boo = crowd_voice(rng, length, [(0.0, base), (length, base * 0.9)], [(0.0, 320.0), (length, 300.0)],
                          [(0.0, 760.0), (length, 700.0)], 0.1, 0.01)
        boo = shape_amp(boo, [(0.0, 0.0), (0.15, 1.0), (length * 0.7, 0.9), (length, 0.0)])
        layers.append((to_peak(boo), 0.8, rng.uniform(0.1, 0.3)))
    return fade(room(mix(layers, duration)), 0.004, 0.15)


def loop_blend(sig, overlap):
    """Macht aus einem Stück eine nahtlose Schleife: Das Ende (overlap Sekunden) wird in den Anfang
    geblendet (gleiche Leistung, passend für Rauschen und Stimmengewirr) und dann abgeschnitten.
    Der letzte Wert der Schleife ist der Wert direkt vor dem neuen ersten."""
    n_over = count(overlap)
    length = len(sig) - n_over
    out = list(sig[:length])
    for i in range(n_over):
        x = i / n_over
        out[i] = sig[i] * math.sin(0.5 * math.pi * x) + sig[length + i] * math.cos(0.5 * math.pi * x)
    return out


def crowd_murmur(rng):
    """Leises Raunen im Studio als Schleife (8 s): zehn Stimmen murmeln durcheinander (Silben mit
    wechselnden Vokalen, Pausen zum Atmen), weit weg und deshalb dumpf, darunter das Rauschen der
    Lüftung. Nichts sticht heraus, damit man die Wiederholung nicht hört."""
    length = 8.0
    overlap = 1.0
    total = length + overlap
    layers = []
    for i in range(10):
        base = rng.uniform(95.0, 140.0) if i % 2 == 0 else rng.uniform(180.0, 250.0)
        at = rng.uniform(0.0, 0.4)
        amp_points = [(0.0, 0.0)]
        pitch_points = [(0.0, base)]
        first_points = [(0.0, 500.0)]
        second_points = [(0.0, 1300.0)]
        while at < total:
            if rng.random() < 0.2:
                at += rng.uniform(0.25, 0.8)
                continue
            syllable = rng.uniform(0.10, 0.24)
            level = rng.uniform(0.35, 1.0)
            amp_points += [(at, 0.0), (at + syllable * 0.3, level), (at + syllable * 0.75, level * 0.7),
                           (at + syllable, 0.0)]
            vowel = VOWELS[rng.randrange(len(VOWELS))]
            first_points.append((at + syllable * 0.5, vowel[0] * rng.uniform(0.9, 1.1)))
            second_points.append((at + syllable * 0.5, vowel[1] * rng.uniform(0.9, 1.1)))
            pitch_points.append((at + syllable * 0.5, base * rng.uniform(0.85, 1.2)))
            at += syllable + rng.uniform(0.0, 0.05)
        voice_sig = crowd_voice(rng, total, pitch_points, first_points, second_points, 0.25, 0.0)
        amp = ramp(amp_points, total)
        layers.append((to_peak([s * a for s, a in zip(voice_sig, amp)]), rng.uniform(0.5, 1.0), 0.0))
    bed = lowpass(lowpass(noise(total, rng), 350.0), 350.0)
    layers.append((to_peak(bed), 0.5, 0.0))
    sig = room(lowpass(lowpass(mix(layers, total), 2200.0), 2200.0))
    return loop_blend(sig[:count(total)], overlap)


# --- Liste aller Geräusche ------------------------------------------------------------------

## Abtastrate der Publikums-Geräusche: Sie sind dumpf und weit weg, 22050 Hz reichen.
CROWD_RATE = 22050
## So viele Werte vom Anfang einer Schleife stehen noch einmal an ihrem Ende (hinter dem
## Schleifenende): Der Abspieler findet beim Glätten über die Naht die richtigen Nachbarn.
LOOP_GUARD = 3


def sound(name, build, shortest, longest, rate=44100, loop=False):
    return {"name": name, "build": build, "shortest": shortest, "longest": longest, "rate": rate, "loop": loop}


def with_variants(name, build, shortest, longest, variants):
    """Ein Geräusch mit Varianten: Die erste behält den Namen, die weiteren heißen name_2, name_3."""
    rows = [sound(name, lambda rng: build(rng, 0), shortest, longest)]
    for index in range(1, variants):
        rows.append(sound("%s_%d" % (name, index + 1), lambda rng, v=index: build(rng, v), shortest, longest))
    return rows


SOUNDS = (
    with_variants("shot_pistol", shot_pistol, 0.1, 0.4, 3)
    + [sound("shot_revolver", shot_revolver, 0.1, 0.4)]
    + with_variants("shot_smg", shot_smg, 0.1, 0.4, 3)
    + [
        sound("shot_sawed_off", shot_sawed_off, 0.1, 0.4),
        sound("shot_shotgun", shot_shotgun, 0.1, 0.4),
    ]
    + with_variants("shot_rifle", shot_rifle, 0.1, 0.4, 3)
    + [sound("shot_sniper", shot_sniper, 0.1, 0.4)]
    + with_variants("shot_minigun", shot_minigun, 0.1, 0.4, 3)
    + [
        sound("shot_rocket_launcher", shot_rocket_launcher, 0.1, 0.4),
        sound("reload_start", reload_start, 0.05, 1.0),
        sound("reload_done", reload_done, 0.05, 1.0),
    ]
    + with_variants("hit", hit, 0.03, 0.2, 3)
    + [sound("headshot", headshot, 0.05, 1.0)]
    + with_variants("zombie_death", zombie_death, 0.05, 1.0, 3)
    + [
        sound("zombie_groan_1", zombie_groan_1, 0.05, 1.0),
        sound("zombie_groan_2", zombie_groan_2, 0.05, 1.0),
        sound("zombie_groan_3", zombie_groan_3, 0.05, 1.0),
        sound("elite_roar", elite_roar, 0.05, 1.2),
        sound("player_hurt", player_hurt, 0.05, 1.0),
        sound("shield_hit", shield_hit, 0.05, 1.0),
        sound("shield_recharge", shield_recharge, 0.05, 1.0),
        sound("dash", dash, 0.05, 1.0),
        sound("chest_drop", chest_drop, 0.05, 1.0),
        sound("chest_open", chest_open, 0.05, 1.0),
        sound("card_chosen", card_chosen, 0.05, 1.0),
        sound("upgrade", upgrade, 0.05, 1.0),
        sound("synergy", synergy, 0.05, 2.0),
        sound("backpack_open", backpack_open, 0.05, 1.0),
        sound("backpack_close", backpack_close, 0.05, 1.0),
        sound("item_sold", item_sold, 0.05, 1.0),
        sound("purchase", purchase, 0.05, 1.0),
        sound("wave_start", wave_start, 0.05, 2.0),
        sound("wave_cleared", wave_cleared, 0.05, 2.0),
        sound("countdown_tick", countdown_tick, 0.03, 1.0),
        sound("game_over", game_over, 0.05, 2.0),
        sound("ui_hover", ui_hover, 0.03, 1.0),
        sound("ui_click", ui_click, 0.03, 1.0),
    ]
    + with_variants("explosion", explosion, 0.05, 1.0, 3)
    + [
        sound("lightning", lightning, 0.05, 1.0),
        sound("drone_shot", drone_shot, 0.05, 1.0),
    ]
    # Ausbau 3: Schüsse der neuen Waffen.
    + with_variants("shot_burst_pistol", shot_burst_pistol, 0.1, 0.4, 3)
    + with_variants("shot_nail_gun", shot_nail_gun, 0.1, 0.4, 3)
    + with_variants("shot_machine_pistol", shot_machine_pistol, 0.1, 0.4, 3)
    + [
        sound("shot_crossbow", shot_crossbow, 0.1, 0.4),
        sound("shot_grenade_launcher", shot_grenade_launcher, 0.1, 0.4),
        sound("shot_flamethrower", shot_flamethrower, 0.1, 0.4),
        sound("shot_beam", shot_beam, 0.1, 0.4),
        sound("shot_tesla", shot_tesla, 0.1, 0.4),
    ]
    + with_variants("shot_lmg", shot_lmg, 0.1, 0.4, 3)
    + with_variants("shot_auto_shotgun", shot_auto_shotgun, 0.1, 0.4, 3)
    + [
        # Ausbau 3: Kameras (die Drohne behält drone_shot).
        sound("cam_tele", cam_tele, 0.05, 1.0),
        sound("cam_flash", cam_flash, 0.05, 1.0),
        sound("cam_slow", cam_slow, 0.05, 1.0),
        sound("cam_director", cam_director, 0.05, 1.0),
        # Ausbau 3: Gegenstände und Fortschritt.
        sound("mine_placed", mine_placed, 0.05, 1.0),
        sound("mine_triggered", mine_triggered, 0.05, 1.0),
        sound("player_revived", player_revived, 0.05, 2.0),
        sound("pack_unlocked", pack_unlocked, 0.05, 2.0),
        sound("bank_coins", bank_coins, 0.05, 2.0),
        sound("ricochet", ricochet, 0.05, 1.0),
        sound("thorns", thorns, 0.05, 1.0),
    ]
    # Ausbau 4: Schritte (vier Varianten), Landen, Herzschlag.
    + with_variants("step", footstep, 0.05, 0.3, 4)
    + [
        sound("land", land, 0.05, 0.5),
        sound("heartbeat", heartbeat, 0.05, 0.6),
        # Ausbau 4: Material.
        sound("item_repaired", item_repaired, 0.05, 1.0),
        sound("item_scrapped", item_scrapped, 0.05, 1.0),
        sound("material_gain", material_gain, 0.05, 0.5),
        # Ausbau 4: Publikum.
        sound("crowd_cheer", crowd_cheer, 0.5, 3.0, CROWD_RATE),
        sound("crowd_gasp", crowd_gasp, 0.2, 1.5, CROWD_RATE),
        sound("crowd_aww", crowd_aww, 0.5, 3.0, CROWD_RATE),
        sound("crowd_murmur", crowd_murmur, 4.0, 12.0, CROWD_RATE, True),
    ]
)


# --- Schreiben und Prüfen -------------------------------------------------------------------

def finish(sig, loop=False):
    """Gleichanteil entfernen und auf den Spitzenpegel PEAK_DB bringen. Eine Schleife wird an den
    Rändern nicht geblendet: Ihr Ende geht ohne Pause in ihren Anfang über."""
    mean = sum(sig) / len(sig)
    sig = [s - mean for s in sig]
    if not loop:
        # Der Abzug des Mittelwerts verschiebt die ausgeblendeten Ränder: noch einmal kurz blenden.
        sig = fade(sig, 0.0003, 0.003)
    return to_peak(sig, 10.0 ** (PEAK_DB / 20.0))


def write_wav(path, sig, rate=44100, loop=False):
    """Schreibt 16 Bit Mono. Eine Schleife bekommt LOOP_GUARD Werte vom Anfang noch einmal ans Ende
    und einen Eintrag "smpl" mit Schleifenanfang 0 und Schleifenende = Länge der Schleife: Godot
    liest daraus beim Einlesen (Import-Einstellung Loop Mode "Detect From WAV") die Schleife."""
    values = [int(round(max(-1.0, min(1.0, s)) * 32767.0)) for s in sig]
    period = len(values)
    if loop:
        values += values[:LOOP_GUARD]
    frames = struct.pack("<%dh" % len(values), *values)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(frames)
    if loop:
        add_loop_chunk(path, period, rate)


def add_loop_chunk(path, period, rate):
    """Hängt den Eintrag "smpl" an eine fertige WAV-Datei: eine Schleife vorwärts von Wert 0 bis
    vor Wert period. (Godot spielt die Werte vor dem Schleifenende und springt dann zum Anfang.)"""
    head = struct.pack("<9I", 0, 0, int(round(1e9 / rate)), 60, 0, 0, 0, 1, 0)
    one_loop = struct.pack("<6I", 0, 0, 0, period, 0, 0)
    with open(path, "r+b") as out:
        out.seek(0, 2)
        out.write(b"smpl" + struct.pack("<I", len(head) + len(one_loop)) + head + one_loop)
        size = out.tell()
        out.seek(4)
        out.write(struct.pack("<I", size - 8))


def read_loop_chunk(path):
    """Liest (Schleifenanfang, Schleifenende) aus dem Eintrag "smpl", None wenn er fehlt."""
    with open(path, "rb") as data:
        raw = data.read()
    at = 12
    while at + 8 <= len(raw):
        name = raw[at:at + 4]
        size = struct.unpack("<I", raw[at + 4:at + 8])[0]
        if name == b"smpl" and size >= 60:
            begin, end = struct.unpack("<2I", raw[at + 8 + 44:at + 8 + 52])
            return begin, end
        at += 8 + size + (size & 1)
    return None


def to_db(value):
    return 20.0 * math.log10(max(value, 1e-9))


def measure(path, loop=False):
    """Liest die Datei wieder ein und misst sie."""
    with wave.open(path, "rb") as data:
        channels = data.getnchannels()
        width = data.getsampwidth()
        rate = data.getframerate()
        frames = data.getnframes()
        raw = data.readframes(frames)
    if channels != 1 or width != 2 or frames == 0:
        return {"ok_format": False, "duration": 0.0, "peak_db": -99.0, "rms_db": -99.0, "clipped": 0,
                "brightness": 0.0, "rate": rate, "edge_db": 0.0, "dc_db": 0.0, "low_db": -99.0, "seam": 0.0,
                "loop_ok": False}
    values = struct.unpack("<%dh" % frames, raw)
    seam = 0.0
    loop_ok = True
    if loop:
        # Die Wächter-Werte am Ende gehören nicht zur Schleife.
        period = frames - LOOP_GUARD
        loop_ok = read_loop_chunk(path) == (0, period) and tuple(values[period:]) == tuple(values[:LOOP_GUARD])
        values = values[:period]
        frames = period
        # Sprung an der Naht (letzter Wert -> erster Wert) im Vergleich zum größten Sprung zwischen
        # Nachbarn in der Nähe: Über 1 heißt, die Naht ist rauer als das Signal selbst.
        near = max(max(abs(values[i + 1] - values[i]) for i in range(0, 400)),
                   max(abs(values[i + 1] - values[i]) for i in range(frames - 401, frames - 1)))
        seam = abs(values[0] - values[-1]) / max(near, 1)
    peak = max(abs(v) for v in values)
    rms = math.sqrt(sum(v * v for v in values) / frames)
    clipped = sum(1 for v in values if abs(v) >= 32767)
    crossings = sum(1 for a, b in zip(values, values[1:]) if (a < 0) != (b < 0))
    # Anteil unter etwa 250 Hz (zwei einfache Tiefpässe hintereinander): das Maß für die Wucht.
    a = 1.0 - math.exp(-TWO_PI * 250.0 / rate)
    y1 = 0.0
    y2 = 0.0
    low_sum = 0.0
    for v in values:
        y1 += a * (v - y1)
        y2 += a * (y1 - y2)
        low_sum += y2 * y2
    return {
        "ok_format": True,
        "duration": frames / rate,
        "peak_db": to_db(peak / 32768.0),
        "rms_db": to_db(rms / 32768.0),
        "clipped": clipped,
        # Mittlere Frequenz aus den Nulldurchgängen: grobes Maß dafür, wie hell es klingt.
        "brightness": crossings / 2.0 / (frames / rate),
        "rate": rate,
        # Erster und letzter Wert: Ist einer davon nicht nahe null, knackt es beim Start oder am Ende.
        "edge_db": to_db(max(abs(values[0]), abs(values[-1])) / 32768.0),
        # Mittelwert aller Werte (Gleichanteil): verschiebt die Membran und knackt ebenfalls.
        "dc_db": to_db(abs(sum(values) / frames) / 32768.0),
        "low_db": to_db(math.sqrt(low_sum / frames) / 32768.0),
        "seam": seam,
        "loop_ok": loop_ok,
    }


def problems_of(result, shortest, longest, loop=False):
    found = []
    if not result["ok_format"]:
        return ["kein 16-Bit-Mono"]
    if result["rate"] not in (22050, 44100):
        found.append("Abtastrate %d" % result["rate"])
    if result["duration"] < shortest:
        found.append("zu kurz")
    if result["duration"] > longest:
        found.append("zu lang")
    if abs(result["peak_db"] - PEAK_DB) > 0.3:
        found.append("Spitzenpegel")
    if result["rms_db"] < -40.0:
        found.append("zu leise oder stumm")
    if result["clipped"] > 0:
        found.append("übersteuert")
    if loop:
        # Eine Schleife beginnt und endet nicht bei null: Geprüft wird stattdessen die Naht.
        if not result["loop_ok"]:
            found.append("Schleifen-Eintrag oder Wächter-Werte fehlen")
        if result["seam"] > 1.5:
            found.append("Sprung an der Naht")
    elif result["edge_db"] > EDGE_LIMIT_DB:
        found.append("Knackser am Rand")
    if result["dc_db"] > DC_LIMIT_DB:
        found.append("Gleichanteil")
    return found


def main():
    global SAMPLE_RATE
    args = sys.argv[1:]
    check_only = "--check" in args
    only = None
    for arg in args:
        if arg.startswith("--only="):
            only = set(arg[len("--only="):].split(","))
    os.makedirs(OUT_DIR, exist_ok=True)
    print("%-26s %7s %9s %9s %9s %9s %6s %7s %7s  %s" % (
        "Datei", "Länge", "Spitze", "Mittel", "Tief", "Hell", "Über", "Rand", "Gleich", "Urteil"))
    print("%-26s %7s %9s %9s %9s %9s %6s %7s %7s" % ("", "s", "dBFS", "dBFS", "dBFS", "Hz", "Werte", "dBFS", "dBFS"))
    failed = 0
    for row in SOUNDS:
        name = row["name"]
        path = os.path.join(OUT_DIR, name + ".wav")
        if not check_only and (only is None or name in only):
            # Eigener Zufall je Geräusch: Eine Änderung an einem Geräusch lässt die anderen gleich.
            rng = random.Random("%d:%s" % (SEED, name))
            SAMPLE_RATE = row["rate"]
            write_wav(path, finish(row["build"](rng), row["loop"]), row["rate"], row["loop"])
            SAMPLE_RATE = 44100
        if not os.path.exists(path):
            failed += 1
            print("%-26s %s" % (name + ".wav", "FEHLER: Datei fehlt"))
            continue
        result = measure(path, row["loop"])
        found = problems_of(result, row["shortest"], row["longest"], row["loop"])
        if found:
            failed += 1
        verdict = "ok" if not found else "FEHLER: " + ", ".join(found)
        if row["loop"]:
            verdict += " (Schleife, Naht %.2f)" % result["seam"]
        print("%-26s %7.3f %9.2f %9.2f %9.2f %9.0f %6d %7.0f %7.0f  %s" % (
            name + ".wav", result["duration"], result["peak_db"], result["rms_db"], result["low_db"],
            result["brightness"], result["clipped"], result["edge_db"], result["dc_db"], verdict))
        sys.stdout.flush()
    print()
    if failed:
        print("%d von %d Dateien haben Fehler." % (failed, len(SOUNDS)))
        return 1
    print("Alle %d Dateien sind in Ordnung: %s" % (len(SOUNDS), OUT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
