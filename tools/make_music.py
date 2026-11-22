#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Erzeugt die Musik des Spiels als WAV-Dateien (16 Bit, Stereo, 22050 Hz) im Ordner audio/.

Aufruf (im Projektordner):
    python tools/make_music.py                     alle Stücke neu schreiben und prüfen
    python tools/make_music.py --check             nur die vorhandenen Dateien prüfen
    python tools/make_music.py --only=music_menu   nur dieses Stück neu schreiben, alle prüfen
    python tools/make_music.py --fix-import        nur die Import-Notizen richten (siehe unten)

Alles ist berechnet: eigene Melodien und Harmonien, Bass, Akkorde und Schlagzeug aus Sinustönen,
Obertonreihen und Rauschen. Es gibt kein fremdes Material und nichts ist nachgespielt. Der Zufall
hat einen festen Startwert: Jeder Lauf schreibt dieselben Dateien. Nur die Standardbibliothek von
Python 3 wird benutzt. Ein ganzer Lauf dauert je nach Rechner 15 Sekunden bis zwei Minuten.

Die Stücke:
    music_menu       Kandidatenwahl und Programm: lockerer Gameshow-Groove. F-Dur, 105 Schläge je
                     Minute, geschwungene Achtel, 16 Takte (36,57 s), Schleife.
    music_calm       Pause zwischen den Wellen: ruhig, tickend. d-Moll, 126 Schläge je Minute,
                     8 Takte (15,24 s), Schleife.
    music_wave       in der Welle: treibend. d-Moll, 126 Schläge je Minute, 16 Takte (30,48 s),
                     Schleife. Dieselbe Akkordfolge wie music_calm (die ersten 8 Takte).
    music_late       ab Welle 10: eine ZUSÄTZLICHE Spur, die über music_wave läuft (Arpeggio in
                     Sechzehnteln, Shaker, Puls auf den Nebenzeiten, Trommelwirbel, ein liegender,
                     anschwellender Ton). Allein klingt sie leer. 16 Takte, Schleife.
    music_game_over  kurzer Abgesang in d-Moll, etwa 8,6 s, keine Schleife.

music_calm, music_wave und music_late haben dasselbe Tempo und dieselbe Tonart und beginnen auf
demselben Taktschlag: Das Spiel lässt sie gleichzeitig laufen und blendet nur ihre Lautstärken.

Schleifen: Die Länge ist genau ein Vielfaches des Takts (bei 22050 Hz hat ein Takt in 126 Schlägen
je Minute genau 42000 Werte, in 105 Schlägen genau 50400). Jede Note, die über das Ende hinaus
klingt, läuft am Anfang weiter, und der Nachhall wird mit dem Ende der Schleife vorgewärmt: Das
Signal ist dadurch von selbst periodisch, an der Naht gibt es keinen Sprung. Wie bei
make_sounds.py stehen die ersten LOOP_GUARD Werte noch einmal hinter dem Schleifenende, und der
Eintrag "smpl" nennt die Schleifenpunkte.

Nach dem Schreiben liest das Skript jede Datei wieder ein und druckt: Länge, Spitzenpegel,
mittleren Pegel, Gleichanteil, den Sprung an der Naht im Vergleich zu den Sprüngen zwischen
Nachbarwerten, und die Lautheit über die Zeit (mittlerer Pegel in Fenstern von 0,5 s: leisestes
und lautestes Fenster). Ein Loch (ein Fenster mehr als 10 dB unter dem Mittel) oder eine Spitze
(mehr als 6 dB darüber) gilt als Fehler, bei Schleifen auch ein Sprung an der Naht.

Import: Godot soll die Musik unkomprimiert einlesen (compress/mode=0), sonst rauscht sie bei
22050 Hz hörbar. Das Skript schreibt das in die Import-Notiz (.import) jeder Musikdatei. Danach
Godot die Dateien einlesen lassen: Godot --headless --import --path <Projekt>
"""

import glob
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
PEAK_DB = -3.0
DC_LIMIT_DB = -50.0
EDGE_LIMIT_DB = -60.0
SEED = 20261121
TWO_PI = 2.0 * math.pi
## Teiltöne über dieser Frequenz entfallen (kein Spiegeln an der halben Abtastrate).
TOP_HZ = 0.45 * RATE
LOOP_GUARD = 3

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT_DIR, "audio")

sin = math.sin
exp = math.exp

NOTE_STEPS = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
              "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name):
    """Tonhöhe einer Note, z. B. "A4" = 440 Hz, "Bb3" = 233,1 Hz."""
    step = NOTE_STEPS[name[:-1]]
    octave = int(name[-1])
    return 440.0 * 2.0 ** ((12 * (octave + 1) + step - 69) / 12.0)


# --- Bausteine ------------------------------------------------------------------------------

def frames_of(seconds):
    return max(1, int(round(seconds * RATE)))


def lowpass(sig, cutoff):
    a = 1.0 - exp(-TWO_PI * cutoff / RATE)
    out = []
    y = 0.0
    for x in sig:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    return [x - y for x, y in zip(sig, lowpass(sig, cutoff))]


def peak_of(sig):
    return max(1e-12, max(abs(s) for s in sig))


def to_peak(sig, peak=1.0):
    factor = peak / peak_of(sig)
    return [s * factor for s in sig]


def drive(sig, amount):
    """Weiche Sättigung, danach wieder Spitze 1."""
    sig = to_peak(sig)
    norm = math.tanh(amount)
    return [math.tanh(s * amount) / norm for s in sig]


def envelope(sig, attack, release):
    """Gerades Ein- und Ausblenden einer Note."""
    n = len(sig)
    n_in = min(n, frames_of(attack))
    n_out = min(n, frames_of(release))
    out = list(sig)
    for i in range(n_in):
        out[i] *= i / n_in
    for i in range(n_out):
        out[n - 1 - i] *= i / n_out
    return out


def tone(freq, seconds, partials, attack=0.005, release=0.03, vibrato=0.0, vib_rate=5.5):
    """Additiver Ton. partials: [(Vielfaches, Pegel, Ausklingzeit in s oder None)]. Teiltöne über
    TOP_HZ entfallen. vibrato: Tiefe als Anteil der Tonhöhe (0.004 = 0,4 %)."""
    n = frames_of(seconds)
    out = [0.0] * n
    for multiple, level, tau in partials:
        f = freq * multiple
        if f >= TOP_HZ:
            continue
        w = TWO_PI * f / RATE
        if vibrato > 0.0:
            depth = vibrato * f / vib_rate
            wv = TWO_PI * vib_rate / RATE
            if tau is None:
                out = [o + level * sin(w * i + depth * sin(wv * i)) for i, o in enumerate(out)]
            else:
                k = -1.0 / (tau * RATE)
                out = [o + level * sin(w * i + depth * sin(wv * i)) * exp(k * i) for i, o in enumerate(out)]
        elif tau is None:
            out = [o + level * sin(w * i) for i, o in enumerate(out)]
        else:
            k = -1.0 / (tau * RATE)
            out = [o + level * sin(w * i) * exp(k * i) for i, o in enumerate(out)]
    return envelope(out, attack, release)


def saw_set(count, rolloff=1.0, tau=None, tau_exp=0.0, odd_only=False):
    """Obertonreihe eines Sägezahns (oder nur die ungeraden: hohl wie ein Rechteck). rolloff 1 =
    voller Sägezahn, größer = dumpfer. tau: Ausklingzeit des Grundtons, höhere Teiltöne klingen
    mit tau / k^tau_exp schneller aus (wie ein Filter, das sich schließt)."""
    rows = []
    for k in range(1, count + 1):
        if odd_only and k % 2 == 0:
            continue
        rows.append((float(k), 1.0 / k ** rolloff, None if tau is None else tau / k ** tau_exp))
    return rows


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(frames_of(seconds))]


def decay(sig, tau):
    k = -1.0 / (tau * RATE)
    return [s * exp(k * i) for i, s in enumerate(sig)]


def sweep_tone(seconds, start, end, sweep_tau, tau):
    """Sinus, dessen Tonhöhe von start nach end fällt und der mit tau ausklingt (Trommeln)."""
    out = []
    phase = 0.0
    for i in range(frames_of(seconds)):
        t = i / RATE
        phase += (end + (start - end) * exp(-t / sweep_tau)) / RATE
        out.append(sin(TWO_PI * phase) * exp(-t / tau))
    return out


def layer(parts):
    """Legt Signale übereinander: [(Signal, Faktor, Beginn in s), ...]."""
    total = max(frames_of(offset) + len(sig) if offset > 0.0 else len(sig) for sig, _f, offset in parts)
    out = [0.0] * total
    for sig, factor, offset in parts:
        first = int(round(offset * RATE))
        out[first:first + len(sig)] = [o + s * factor for o, s in zip(out[first:first + len(sig)], sig)]
    return out


# --- Schlagzeug -----------------------------------------------------------------------------

def kick(rng, start=150.0, end=48.0, tau=0.11):
    body = sweep_tone(0.32, start, end, 0.035, tau)
    click = decay(highpass(noise(0.006, rng), 3000.0), 0.0015)
    return envelope(drive(layer([(body, 1.0, 0.0), (click, 0.35, 0.0)]), 1.8), 0.0005, 0.03)


def snare(rng):
    rattle = decay(lowpass(highpass(noise(0.22, rng), 1500.0), 7000.0), 0.06)
    body = sweep_tone(0.12, 215.0, 170.0, 0.02, 0.045)
    return envelope(layer([(to_peak(rattle), 1.0, 0.0), (body, 0.7, 0.0)]), 0.0005, 0.03)


def clap(rng):
    parts = []
    for offset, level, tau in ((0.0, 0.7, 0.006), (0.011, 0.8, 0.006), (0.022, 1.0, 0.075)):
        burst = decay(lowpass(highpass(noise(0.2, rng), 900.0), 3200.0), tau)
        parts.append((to_peak(burst), level, offset))
    return envelope(layer(parts), 0.0005, 0.03)


def hat(rng, tau):
    sig = highpass(highpass(noise(max(0.05, tau * 6.0), rng), 6500.0), 6500.0)
    return envelope(to_peak(decay(sig, tau)), 0.0003, 0.01)


def shaker(rng):
    sig = lowpass(highpass(noise(0.09, rng), 4000.0), 8000.0)
    n = len(sig)
    return to_peak([s * (min(1.0, i / (0.010 * RATE)) * exp(-i / (0.022 * RATE))) for i, s in zip(range(n), sig)])


def wood(freq, tau):
    """Kurzer Holzton (Ticken einer Uhr, Randschlag)."""
    sig = tone(freq, tau * 7.0, [(1.0, 1.0, tau), (2.42, 0.35, tau * 0.6), (4.1, 0.12, tau * 0.4)], 0.0006, 0.01)
    return to_peak(sig)


def tom(freq, tau=0.12):
    return envelope(sweep_tone(tau * 4.0, freq * 1.5, freq, 0.03, tau), 0.001, 0.03)


def crash(rng, tau=0.45):
    sig = highpass(noise(tau * 4.0, rng), 3500.0)
    return envelope(to_peak(decay(sig, tau)), 0.001, 0.05)


def swell(rng, seconds):
    """Anschwellendes Rauschen (Luftzug vor einem Akkordwechsel)."""
    sig = lowpass(highpass(noise(seconds, rng), 600.0), 3000.0)
    n = len(sig)
    return to_peak([s * (i / n) ** 2.5 * min(1.0, (n - i) / (0.02 * RATE)) for i, s in enumerate(sig)])


# --- Instrumente (alle mit Spitze nahe 1, die Lautstärke bestimmt erst die Mischung) -----------

_cache = {}


def cached(key, build):
    """Jede Note wird nur einmal berechnet."""
    if key not in _cache:
        _cache[key] = build()
    return _cache[key]


def bass_note(freq, seconds):
    """Treibender Synthesizer-Bass: Sägezahn, dessen Obertöne schnell ausklingen, über einem Sinus."""
    def build():
        sig = tone(freq, seconds, saw_set(14, 1.0, 0.5, 0.9) + [(1.0, 0.8, None)], 0.004, 0.02)
        return to_peak(sig)
    return cached(("bass", freq, seconds), build)


def soft_bass(freq, seconds):
    """Runder, gezupfter Bass (Menü): wenige Obertöne, weicher Anschlag."""
    def build():
        sig = tone(freq, seconds, [(1.0, 1.0, 0.9), (2.0, 0.5, 0.35), (3.0, 0.25, 0.2), (4.0, 0.1, 0.12)], 0.006, 0.04)
        return to_peak(sig)
    return cached(("soft_bass", freq, seconds), build)


def sub_note(freq, seconds):
    """Tiefer, langer Ton (Pause): Sinus mit etwas Oktave und Quinte darüber."""
    def build():
        sig = tone(freq, seconds, [(1.0, 1.0, seconds * 0.45), (2.0, 0.35, seconds * 0.3), (3.0, 0.12, seconds * 0.2)],
                   0.02, 0.15)
        return to_peak(sig)
    return cached(("sub", freq, seconds), build)


def pad_note(freq, seconds, detune):
    """Flächenklang: dumpfer Sägezahn mit langsamem Ein- und Ausschwingen."""
    def build():
        return to_peak(tone(freq * (1.0 + detune), seconds, saw_set(10, 1.7), 0.35, 0.5))
    return cached(("pad", freq, seconds, detune), build)


def stab_note(freq, seconds):
    """Kurzer, heller Akkordstoß (wie Bläser): voller Sägezahn, dessen Höhen sofort abklingen."""
    def build():
        return to_peak(tone(freq, seconds, saw_set(16, 1.0, 0.22, 0.6), 0.006, 0.04))
    return cached(("stab", freq, seconds), build)


def lead_note(freq, seconds):
    """Melodiestimme der Welle: hohler Klang (ungerade Obertöne) mit etwas Schweben."""
    def build():
        parts = saw_set(9, 1.15, 1.2, 0.5, True) + [(2.0, 0.12, 0.4)]
        return to_peak(tone(freq, seconds, parts, 0.008, 0.05, 0.004 if seconds > 0.3 else 0.0))
    return cached(("lead", freq, seconds), build)


def vibe_note(freq, seconds):
    """Vibraphon: Grundton, die vierte und die zehnte Teilschwingung, die schnell verklingen."""
    def build():
        sig = tone(freq, seconds, [(1.0, 1.0, 0.9), (4.0, 0.22, 0.22), (10.0, 0.06, 0.05)], 0.002, 0.08)
        return to_peak(sig)
    return cached(("vibe", freq, seconds), build)


def keys_note(freq, seconds):
    """E-Piano: weicher, glockiger Anschlag, runder Ton."""
    def build():
        sig = tone(freq, seconds, [(1.0, 1.0, 0.8), (2.0, 0.32, 0.45), (3.0, 0.1, 0.3), (7.0, 0.08, 0.04)], 0.003, 0.05)
        return to_peak(sig)
    return cached(("keys", freq, seconds), build)


def pluck_note(freq, seconds):
    """Gezupfter, heller Ton für das Arpeggio."""
    def build():
        return to_peak(tone(freq, seconds, saw_set(10, 1.0, 0.14, 0.8), 0.002, 0.02))
    return cached(("pluck", freq, seconds), build)


def pulse_note(freq, seconds):
    """Hohler Puls (ungerade Obertöne), kurz."""
    def build():
        return to_peak(tone(freq, seconds, saw_set(11, 1.3, 0.3, 0.5, True), 0.004, 0.03))
    return cached(("pulse", freq, seconds), build)


def brass_note(freq, seconds):
    """Bläser: dumpfer Grundklang, die Höhen kommen mit dem Anblasen dazu."""
    def build():
        dull = tone(freq, seconds, saw_set(12, 2.0), 0.02, 0.06)
        bright = tone(freq, seconds, saw_set(18, 1.0), min(0.07, seconds * 0.5), 0.06, 0.003)
        return to_peak([a + 0.7 * b for a, b in zip(dull, bright)])
    return cached(("brass", freq, seconds), build)


def string_note(freq, seconds, tremolo_hz, start_level=0.2, end_level=1.0):
    """Liegender Ton, der über seine Länge von start_level auf end_level anschwillt und im Takt
    zittert. Die Spitze ist end_level (nicht 1), damit sich mehrere Stücke aneinanderreihen lassen."""
    def build():
        raw = to_peak(tone(freq, seconds, saw_set(8, 1.5), 0.3, 0.3, 0.003))
        w = TWO_PI * tremolo_hz / RATE
        n = len(raw)
        return [s * (start_level + (end_level - start_level) * i / n) * (0.7 + 0.3 * sin(w * i)) for i, s in enumerate(raw)]
    return cached(("string", freq, seconds, tremolo_hz, start_level, end_level), build)


# --- Leinwand: zwei Kanäle, in die Noten gelegt werden ----------------------------------------

def add_into(dst, src, start, gain, wrap):
    """Legt src ab der Stelle start in dst. Mit wrap läuft, was über das Ende hinausragt, am
    Anfang weiter (so faltet sich jeder Ausklang über die Naht der Schleife)."""
    n = len(dst)
    m = len(src)
    start = int(round(start))
    if wrap:
        start %= n
    pos = 0
    while pos < m:
        if start >= n:
            if not wrap:
                break
            start -= n
        take = min(m - pos, n - start)
        dst[start:start + take] = [d + s * gain for d, s in zip(dst[start:start + take], src[pos:pos + take])]
        pos += take
        start += take


class Canvas:
    def __init__(self, frames, wrap=True):
        self.frames = frames
        self.wrap = wrap
        self.left = [0.0] * frames
        self.right = [0.0] * frames

    def add(self, sig, start, gain=1.0, pan=0.0):
        """pan: -1 = links, 0 = Mitte, 1 = rechts (gleiche Leistung)."""
        angle = (pan + 1.0) * math.pi / 4.0
        add_into(self.left, sig, start, gain * math.cos(angle) * 1.41421356, self.wrap)
        add_into(self.right, sig, start, gain * math.sin(angle) * 1.41421356, self.wrap)

    def add_stereo(self, left, right, start, gain=1.0):
        add_into(self.left, left, start, gain, self.wrap)
        add_into(self.right, right, start, gain, self.wrap)

    def mix_in(self, other, gain=1.0):
        self.left = [a + b * gain for a, b in zip(self.left, other.left)]
        self.right = [a + b * gain for a, b in zip(self.right, other.right)]

    def shape(self, curve):
        """Multipliziert beide Kanäle mit einer Kurve, die sich wiederholt (Länge teilt die Leinwand)."""
        times = self.frames // len(curve)
        full = curve * times
        self.left = [a * c for a, c in zip(self.left, full)]
        self.right = [a * c for a, c in zip(self.right, full)]

    def rms_db(self):
        total = sum(v * v for v in self.left) + sum(v * v for v in self.right)
        return 10.0 * math.log10(max(total / (2.0 * self.frames), 1e-18))


def comb(x, delay, g):
    """y[n] = x[n] + g * y[n - delay], blockweise gerechnet."""
    n = len(x)
    y = list(x)
    for k in range(delay, n, delay):
        end = min(k + delay, n)
        y[k:end] = [a + g * b for a, b in zip(x[k:end], y[k - delay:end - delay])]
    return y


def allpass(x, delay, g):
    """y[n] = -g * x[n] + x[n - delay] + g * y[n - delay], blockweise gerechnet."""
    n = len(x)
    y = [-g * v for v in x]
    for k in range(delay, n, delay):
        end = min(k + delay, n)
        y[k:end] = [-g * a + b + g * c for a, b, c in zip(x[k:end], x[k - delay:end - delay], y[k - delay:end - delay])]
    return y


def reverb_channel(x, combs, allpasses, seconds, wrap):
    """Nachhall eines Kanals (vier Kammfilter nebeneinander, zwei Allpässe dahinter). Bei einer
    Schleife wird er mit dem Ende des Signals vorgewärmt: Der Hall des Endes liegt dann schon auf
    dem Anfang, der Nachhall ist über die Naht gefaltet."""
    pre = min(len(x), frames_of(seconds * 2.5)) if wrap else 0
    tail = 0 if wrap else frames_of(seconds * 1.2)
    source = lowpass(highpass(x[len(x) - pre:] + x + [0.0] * tail, 250.0), 3800.0)
    total = [0.0] * len(source)
    for delay in combs:
        g = 10.0 ** (-3.0 * delay / (seconds * RATE))
        total = [a + b for a, b in zip(total, comb(source, delay, g))]
    total = [v / len(combs) for v in total]
    for delay in allpasses:
        total = allpass(total, delay, 0.5)
    return total[pre:]


def add_reverb(canvas, send, seconds=1.3, amount=1.0):
    """Mischt den Nachhall der Leinwand send in canvas. Ohne Schleife darf er ausklingen: Dann muss
    canvas hinten genug Platz haben."""
    left = reverb_channel(send.left, (558, 594, 638, 678), (278, 220), seconds, canvas.wrap)
    right = reverb_channel(send.right, (569, 605, 649, 689), (289, 231), seconds, canvas.wrap)
    n = canvas.frames
    canvas.left = [a + amount * b for a, b in zip(canvas.left, left[:n])]
    canvas.right = [a + amount * b for a, b in zip(canvas.right, right[:n])]


def pump_curve(beat_frames, depth, tau=0.10):
    """Lautstärke-Kurve über einen Schlag: sackt mit der Bassdrum ab und kommt schnell zurück."""
    return [1.0 - depth * exp(-i / (tau * RATE)) for i in range(beat_frames)]


# --- Raster ---------------------------------------------------------------------------------

class Grid:
    """Zählzeiten: Ein Takt hat 16 Schritte (Sechzehntel). swing verschiebt die Schritte innerhalb
    eines Schlags (Anteile des Schlags für die vier Sechzehntel)."""

    def __init__(self, bar_frames, bars, swing=(0.0, 0.25, 0.5, 0.75)):
        self.bar = bar_frames
        self.bars = bars
        self.beat = bar_frames // 4
        self.step = bar_frames / 16.0
        self.swing = swing
        self.frames = bar_frames * bars

    def at(self, bar, step):
        """Stelle (in Werten) von Schritt step (darf über 16 hinausgehen) in Takt bar (ab 0)."""
        beats, sub = divmod(step, 4)
        whole = int(sub)
        inside = self.swing[whole] + (sub - whole) * 0.25
        return bar * self.bar + (beats + inside) * self.beat

    def seconds(self, bar, step, length):
        """Dauer von length Schritten ab dieser Stelle in Sekunden (folgt dem Schwung)."""
        return (self.at(bar, step + length) - self.at(bar, step)) / RATE


# --- Die Spielmusik: d-Moll, 126 Schläge je Minute ----------------------------------------------
# Akkordfolge, je Akkord zwei Takte: Dm - B - Gm - A | Dm - F - Gm - A. Der letzte Akkord (A-Dur,
# die Dominante) führt an der Naht zurück nach d-Moll.

GAME_BAR = 42000
GAME_CHORDS = [
    # Name, Bass, Fläche (drei Töne), Figur (fünf Töne), Durchgangston des Basses zum nächsten Akkord
    {"bass": "D2", "pad": ("A3", "D4", "F4"), "motif": ("A4", "D5", "F5", "E5", "D5"), "walk": "A2"},
    {"bass": "Bb1", "pad": ("Bb3", "D4", "F4"), "motif": ("F4", "Bb4", "D5", "C5", "Bb4"), "walk": "A2"},
    {"bass": "G2", "pad": ("Bb3", "D4", "G4"), "motif": ("D4", "G4", "Bb4", "A4", "G4"), "walk": "G#2"},
    {"bass": "A2", "pad": ("A3", "C#4", "E4"), "motif": ("E4", "A4", "C#5", "D5", "E5"), "walk": "C#2"},
    {"bass": "D2", "pad": ("A3", "D4", "F4"), "motif": ("D5", "F5", "A5", "G5", "F5"), "walk": "E2"},
    {"bass": "F2", "pad": ("A3", "C4", "F4"), "motif": ("F5", "A5", "C6", "Bb5", "A5"), "walk": "F#2"},
    {"bass": "G2", "pad": ("Bb3", "D4", "G4"), "motif": ("G5", "Bb5", "D6", "C6", "Bb5"), "walk": "G#2"},
    {"bass": "A2", "pad": ("A3", "C#4", "E4"), "motif": ("A5", "G5", "F5", "E5", "C#5"), "walk": "C#2"},
]
## Rhythmus der Figur: (Schritt, Länge in Schritten) für ihre fünf Töne ("da da daa, da daaa").
MOTIF_RHYTHM = ((0, 2), (2, 2), (4, 4), (8, 2), (10, 6))


def add_pad(canvas, grid, bar, bars, notes, gain):
    """Akkord als Fläche über bars Takte, links und rechts leicht gegeneinander verstimmt."""
    seconds = grid.bar * bars / RATE + 0.45
    for name in notes:
        canvas.add_stereo(pad_note(hz(name), seconds, -0.0025), pad_note(hz(name), seconds, 0.0025),
                          grid.at(bar, 0) - 0.12 * RATE, gain)


def build_calm(rng):
    """Pause zwischen den Wellen: Eine Uhr tickt (Tick auf 1 und 3, Tack auf 2 und 4, dazwischen
    leise), ein tiefer Ton je Takt, eine weiche Fläche, das Vibraphon spielt die Figur, vor jedem
    Akkordwechsel zieht leise Luft an."""
    grid = Grid(GAME_BAR, 8)
    main = Canvas(grid.frames)
    wet = Canvas(grid.frames)
    tick = wood(1900.0, 0.012)
    tock = wood(1420.0, 0.015)
    ghost = wood(2500.0, 0.006)
    thump = tom(58.0, 0.09)
    air = swell(rng, grid.step * 4.0 / RATE)
    for bar in range(8):
        chord = GAME_CHORDS[(bar // 2) % 4]
        first = bar % 2 == 0
        for step in (0, 8):
            main.add(tick, grid.at(bar, step), 0.50, -0.25)
            wet.add(tick, grid.at(bar, step), 0.12, -0.25)
        for step in (4, 12):
            main.add(tock, grid.at(bar, step), 0.38, 0.25)
            wet.add(tock, grid.at(bar, step), 0.10, 0.25)
        for step in (2, 6, 10, 14):
            main.add(ghost, grid.at(bar, step), 0.10, 0.5 if step % 8 == 2 else -0.5)
        root = hz(chord["bass"]) * (2.0 if chord["bass"] == "Bb1" else 1.0)
        main.add(sub_note(root, grid.seconds(bar, 0, 7)), grid.at(bar, 0), 0.55)
        main.add(sub_note(root, grid.seconds(bar, 10, 3)), grid.at(bar, 10), 0.28)
        if first:
            add_pad(main, grid, bar, 2, chord["pad"], 0.14)
            add_pad(wet, grid, bar, 2, chord["pad"], 0.03)
            for name, (step, length) in zip(chord["motif"], MOTIF_RHYTHM):
                note = vibe_note(hz(name), grid.seconds(bar, step, length) + 0.5)
                main.add(note, grid.at(bar, step), 0.25, 0.15)
                wet.add(note, grid.at(bar, step), 0.16, 0.15)
        else:
            # Antwort: zwei tiefe Töne des Akkords und ein dumpfer Doppelschlag wie ein Herz.
            low = vibe_note(hz(chord["pad"][0]), 1.0)
            main.add(low, grid.at(bar, 8), 0.24, -0.2)
            wet.add(low, grid.at(bar, 8), 0.12, -0.2)
            main.add(thump, grid.at(bar, 0), 0.40)
            main.add(thump, grid.at(bar, 3), 0.28)
            main.add(air, grid.at(bar, 12), 0.10)
    add_reverb(main, wet, 1.6)
    return main, {}


def build_wave(rng):
    """In der Welle: Bassdrum auf jedem Schlag, Klatschen auf 2 und 4, Hi-Hat auf den Nebenzeiten,
    ein Sägezahn-Bass im Muster 3+3+2 mit Oktavsprüngen, eine Fläche, die mit der Bassdrum pumpt,
    kurze Akkordstöße als Antwort und die Figur als Melodie im ersten Takt jedes Akkords."""
    grid = Grid(GAME_BAR, 16)
    drums = Canvas(grid.frames)
    bass = Canvas(grid.frames)
    chords = Canvas(grid.frames)
    lead = Canvas(grid.frames)
    wet = Canvas(grid.frames)
    kick_sig = kick(rng)
    snare_sig = snare(rng)
    clap_sig = clap(rng)
    hats = [hat(rng, 0.022) for _ in range(3)]
    open_hat = hat(rng, 0.11)
    crash_sig = crash(rng)
    for bar in range(16):
        chord = GAME_CHORDS[bar // 2]
        first = bar % 2 == 0
        fill = bar in (7, 15)
        # Schlagzeug.
        for step in (0, 4, 8, 12):
            drums.add(kick_sig, grid.at(bar, step), 1.0)
        for step in (4, 12):
            drums.add(clap_sig, grid.at(bar, step), 0.42, 0.08)
            drums.add(snare_sig, grid.at(bar, step), 0.30, -0.05)
            wet.add(clap_sig, grid.at(bar, step), 0.10)
        for step in range(16):
            if step % 4 == 2:
                if step == 14 and not first:
                    drums.add(open_hat, grid.at(bar, step), 0.20, 0.3)
                else:
                    drums.add(hats[step % 3], grid.at(bar, step), 0.22, 0.3)
            elif step % 2 == 1:
                drums.add(hats[(step + bar) % 3], grid.at(bar, step), 0.07, -0.3)
        if fill:
            for step, level in ((10, 0.25), (13, 0.32), (14, 0.42), (15, 0.5)):
                drums.add(snare_sig, grid.at(bar, step), level, 0.1)
        if bar in (0, 8):
            drums.add(crash_sig, grid.at(bar, 0), 0.22, -0.2)
            wet.add(crash_sig, grid.at(bar, 0), 0.08, -0.2)
        # Bass: 3+3+2, die Oktave auf dem dritten Ton jeder Gruppe.
        root = hz(chord["bass"])
        if root < 60.0:
            root *= 2.0
        pattern = [(0, 1.0), (3, 1.0), (6, 2.0), (8, 1.0), (11, 1.0), (14, 2.0)]
        if not first:
            pattern = [(0, 1.0), (3, 1.0), (6, 2.0), (8, 1.0), (10, 1.5), (12, 2.0)]
        for step, factor in pattern:
            bass.add(bass_note(root * factor, grid.seconds(bar, step, 1.7)), grid.at(bar, step), 0.60 if factor == 1.0 else 0.42)
        if not first:
            bass.add(bass_note(hz(chord["walk"]), grid.seconds(bar, 14, 1.7)), grid.at(bar, 14), 0.5)
        # Fläche und Akkordstöße.
        if first:
            add_pad(chords, grid, bar, 2, chord["pad"], 0.11)
            stab_steps = ((0, 0.9),)
        else:
            stab_steps = ((3, 0.7), (6, 0.9), (11, 0.7), (14, 0.8))
        for step, level in stab_steps:
            for index, name in enumerate(chord["pad"]):
                note = stab_note(hz(name) * 2.0, 0.20)
                chords.add(note, grid.at(bar, step), 0.085 * level, (-0.35, 0.0, 0.35)[index])
                wet.add(note, grid.at(bar, step), 0.03 * level, (-0.35, 0.0, 0.35)[index])
        # Melodie.
        if first:
            for name, (step, length) in zip(chord["motif"], MOTIF_RHYTHM):
                note = lead_note(hz(name), grid.seconds(bar, step, length) * 0.92)
                lead.add(note, grid.at(bar, step), 0.30, -0.1)
                wet.add(note, grid.at(bar, step), 0.09, -0.1)
                # Leises Echo drei Schritte später auf der anderen Seite.
                lead.add(note, grid.at(bar, step + 3), 0.085, 0.5)
    chords.shape(pump_curve(grid.beat, 0.55))
    main = Canvas(grid.frames)
    for part in (drums, bass, chords, lead):
        main.mix_in(part)
    add_reverb(main, wet, 1.2)
    return main, {"Schlagzeug": drums.rms_db(), "Bass": bass.rms_db(), "Akkorde": chords.rms_db(), "Melodie": lead.rms_db()}


def build_late(rng):
    """Zusatzspur ab Welle 10 (läuft über music_wave): Arpeggio in Sechzehnteln, das zwischen links
    und rechts springt, Shaker, ein hohler Puls auf den Nebenzeiten, Trommeln am Ende jedes vierten
    Takts und ein hoher, liegender Ton, der über acht Takte anschwillt."""
    grid = Grid(GAME_BAR, 16)
    main = Canvas(grid.frames)
    wet = Canvas(grid.frames)
    shake = [shaker(rng) for _ in range(3)]
    toms = [tom(f) for f in (196.0, 165.0, 131.0, 98.0)]
    order = (0, 1, 2, 1, 0, 1, 2, 1, 3, 2, 1, 2, 3, 2, 1, 0)
    for bar in range(16):
        chord = GAME_CHORDS[bar // 2]
        tones = [hz(name) * 2.0 for name in chord["pad"]]
        tones.append(tones[0] * 2.0)
        for step in range(16):
            note = pluck_note(tones[order[step]], 0.16)
            side = 0.6 if step % 2 == 0 else -0.6
            accent = 1.0 if step % 4 == 0 else 0.75
            main.add(note, grid.at(bar, step), 0.20 * accent, side)
            main.add(note, grid.at(bar, step + 3), 0.07 * accent, -side)
            wet.add(note, grid.at(bar, step), 0.05, side)
            main.add(shake[(step + bar) % 3], grid.at(bar, step), 0.16 if step % 2 == 1 else 0.09, 0.45)
        root = hz(chord["bass"]) * (4.0 if hz(chord["bass"]) < 60.0 else 2.0)
        for step in (2, 6, 10, 14):
            main.add(pulse_note(root, grid.seconds(bar, step, 1.4)), grid.at(bar, step), 0.22, -0.15)
        if bar % 4 == 3:
            loud = 1.0 if bar % 8 == 7 else 0.7
            for index, step in enumerate((12, 13, 14, 15)):
                main.add(toms[index], grid.at(bar, step), 0.45 * loud, (-0.5, -0.2, 0.2, 0.5)[index])
                wet.add(toms[index], grid.at(bar, step), 0.10 * loud)
    # Liegender Ton: A5 über die ersten acht Takte, D6 über die nächsten sechs, E6 über die letzten
    # zwei (jeder passt zu den Akkorden darunter als Grundton, Quinte oder Spannungston; über
    # A-Dur wäre D6 ein Reibeton, deshalb dort die Quinte E6). Jedes Stück schwillt an.
    step_hz = RATE / grid.step
    for bar, bars, name, start_level, end_level in ((0, 8, "A5", 0.2, 1.0), (8, 6, "D6", 0.2, 0.8), (14, 2, "E6", 0.8, 1.0)):
        note = string_note(hz(name), grid.bar * bars / RATE + 0.3, step_hz, start_level, end_level)
        main.add(note, grid.at(bar, 0), 0.16, 0.2)
        wet.add(note, grid.at(bar, 0), 0.08, 0.2)
    add_reverb(main, wet, 1.2)
    return main, {}


# --- Menü: F-Dur, 105 Schläge je Minute, geschwungen ---------------------------------------------

MENU_BAR = 50400
## Je Takt: Akkorde als (Beginn in Schritten, Bass, drei Töne für das E-Piano).
MENU_BARS = [
    [(0, "F2", ("A3", "C4", "D4"))],
    [(0, "D2", ("A3", "C4", "F4"))],
    [(0, "G2", ("Bb3", "D4", "F4"))],
    [(0, "C2", ("Bb3", "E4", "G4"))],
    [(0, "F2", ("A3", "C4", "D4"))],
    [(0, "D2", ("A3", "C4", "F4"))],
    [(0, "Bb1", ("A3", "D4", "F4"))],
    [(0, "C2", ("Bb3", "E4", "G4"))],
    [(0, "A2", ("G3", "C4", "E4"))],
    [(0, "D2", ("A3", "C4", "F4"))],
    [(0, "G2", ("Bb3", "D4", "F4"))],
    [(0, "C2", ("Bb3", "E4", "G4"))],
    [(0, "Bb1", ("A3", "D4", "F4"))],
    [(0, "A2", ("G3", "C4", "E4")), (8, "D2", ("A3", "C4", "F4"))],
    [(0, "G2", ("Bb3", "D4", "F4")), (8, "C2", ("Bb3", "E4", "G4"))],
    [(0, "F2", ("A3", "C4", "D4")), (8, "C2", ("Bb3", "E4", "G4"))],
]
## Durchgangston des Basses am Ende jedes Takts: einen Schritt der Tonleiter über (oder unter) dem
## Grundton des nächsten Takts.
MENU_WALK = ["E2", "A2", "D2", "G2", "E2", "C3", "D2", "Bb2", "E2", "A2", "D2", "C3", "Bb2", "A2", "G2", "E2"]
## Melodie je Takt: (Schritt, Note, Länge in Schritten).
MENU_MELODY = [
    [(0, "C5", 2), (2, "D5", 2), (4, "F5", 4), (10, "A5", 2), (12, "G5", 4)],
    [(0, "F5", 2), (2, "D5", 2), (4, "A4", 6), (12, "C5", 2), (14, "D5", 2)],
    [(0, "D5", 2), (2, "F5", 2), (4, "G5", 4), (10, "Bb5", 2), (12, "A5", 4)],
    [(0, "G5", 2), (2, "E5", 2), (4, "C5", 6), (14, "C5", 2)],
    [(0, "C5", 2), (2, "D5", 2), (4, "F5", 4), (10, "A5", 2), (12, "G5", 4)],
    [(0, "F5", 2), (2, "D5", 2), (4, "A4", 4), (10, "D5", 2), (12, "F5", 4)],
    [(0, "D5", 3), (3, "F5", 3), (6, "A5", 4), (12, "G5", 2), (14, "F5", 2)],
    [(0, "E5", 4), (4, "G5", 4), (8, "C6", 6)],
    [(0, "E5", 2), (3, "E5", 1), (4, "G5", 2), (6, "A5", 4), (12, "C6", 2), (14, "A5", 2)],
    [(0, "F5", 6), (8, "D5", 2), (10, "F5", 2), (12, "A5", 4)],
    [(0, "D5", 2), (3, "D5", 1), (4, "F5", 2), (6, "G5", 4), (12, "Bb5", 2), (14, "G5", 2)],
    [(0, "E5", 6), (8, "G5", 2), (10, "Bb5", 2), (12, "C6", 4)],
    [(0, "D6", 2), (2, "C6", 2), (4, "A5", 4), (10, "F5", 2), (12, "D5", 4)],
    [(0, "C6", 2), (2, "A5", 2), (4, "G5", 4), (8, "F5", 2), (10, "E5", 2), (12, "D5", 4)],
    [(0, "Bb4", 2), (2, "D5", 2), (4, "F5", 4), (8, "E5", 2), (10, "G5", 2), (12, "Bb5", 4)],
    [(0, "A5", 2), (2, "F5", 6), (12, "A4", 2), (14, "Bb4", 2)],
]


def chord_at(bar, step):
    current = MENU_BARS[bar][0]
    for row in MENU_BARS[bar]:
        if row[0] <= step:
            current = row
    return current


def build_menu(rng):
    """Menü: geschwungener Groove (Bassdrum, Randschlag auf 2 und 4, Hi-Hat, Shaker, zwei kleine
    Trommeln), ein runder Bass, der zum nächsten Akkord läuft, E-Piano auf den Nebenzeiten, die
    Melodie auf dem Vibraphon (ab Takt 9 mit Bläsern verdoppelt) und Bläserstöße am Ende jeder
    vierten Zeile."""
    grid = Grid(MENU_BAR, 16, (0.0, 0.30, 0.60, 0.80))
    drums = Canvas(grid.frames)
    bass = Canvas(grid.frames)
    chords = Canvas(grid.frames)
    lead = Canvas(grid.frames)
    wet = Canvas(grid.frames)
    kick_sig = kick(rng, 130.0, 52.0, 0.09)
    rim = wood(820.0, 0.014)
    snare_sig = snare(rng)
    hats = [hat(rng, 0.02) for _ in range(3)]
    open_hat = hat(rng, 0.10)
    shake = [shaker(rng) for _ in range(3)]
    conga_high = tom(330.0, 0.05)
    conga_low = tom(235.0, 0.06)
    for bar in range(16):
        end_of_line = bar % 4 == 3
        # Schlagzeug.
        for step, level in ((0, 1.0), (6, 0.55), (8, 0.8)):
            drums.add(kick_sig, grid.at(bar, step), 0.85 * level)
        if bar % 2 == 1:
            drums.add(kick_sig, grid.at(bar, 14), 0.45)
        for step in (4, 12):
            drums.add(rim, grid.at(bar, step), 0.50, 0.1)
            drums.add(snare_sig, grid.at(bar, step), 0.16, -0.05)
            wet.add(rim, grid.at(bar, step), 0.10)
        for step in range(0, 16, 2):
            if step == 14 and end_of_line:
                drums.add(open_hat, grid.at(bar, step), 0.17, 0.3)
            else:
                drums.add(hats[(step // 2) % 3], grid.at(bar, step), 0.19 if step % 4 == 2 else 0.10, 0.3)
        for step in range(16):
            drums.add(shake[(step + bar) % 3], grid.at(bar, step), 0.10 if step % 2 == 1 else 0.06, -0.4)
        for step, sig in ((3, conga_high), (7, conga_low), (11, conga_high), (14, conga_low)):
            drums.add(sig, grid.at(bar, step), 0.20, 0.45 if sig is conga_high else 0.25)
        # Bass.
        for part in range(2):
            first_step = part * 8
            _start, root_name, _tones = chord_at(bar, first_step)
            root = hz(root_name) * (2.0 if hz(root_name) < 62.0 else 1.0)
            split = len(MENU_BARS[bar]) > 1
            bass.add(soft_bass(root, grid.seconds(bar, first_step, 2.6)), grid.at(bar, first_step), 0.54)
            bass.add(soft_bass(root, grid.seconds(bar, first_step + 3, 1.0)), grid.at(bar, first_step + 3), 0.30)
            if part == 0 and not split:
                bass.add(soft_bass(root * 1.5, grid.seconds(bar, 6, 1.8)), grid.at(bar, 6), 0.50)
            if part == 1 and not split:
                bass.add(soft_bass(root * 2.0, grid.seconds(bar, 10, 1.6)), grid.at(bar, 10), 0.42)
        # Durchgang zum Grundton des nächsten Takts.
        bass.add(soft_bass(hz(MENU_WALK[bar]), grid.seconds(bar, 14, 1.6)), grid.at(bar, 14), 0.45)
        # E-Piano: zwei Begleitmuster im Wechsel, immer mit dem Akkord, der an der Stelle gilt.
        comp = ((0, 3.0, 0.9), (6, 2.0, 1.0), (10, 4.0, 0.8)) if bar % 2 == 0 else ((2, 2.0, 0.9), (6, 4.0, 1.0), (14, 2.0, 0.8))
        for step, length, level in comp:
            _start, _root, tones = chord_at(bar, step)
            for index, name in enumerate(tones):
                note = keys_note(hz(name), grid.seconds(bar, step, length) + 0.15)
                chords.add(note, grid.at(bar, step), 0.17 * level, (-0.45, 0.1, 0.45)[index])
                wet.add(note, grid.at(bar, step), 0.03 * level, (-0.45, 0.1, 0.45)[index])
        # Melodie.
        for step, name, length in MENU_MELODY[bar]:
            seconds = grid.seconds(bar, step, length)
            note = vibe_note(hz(name), seconds + 0.35)
            lead.add(note, grid.at(bar, step), 0.30, -0.12)
            wet.add(note, grid.at(bar, step), 0.11, -0.12)
            if bar >= 8:
                horn = brass_note(hz(name) * 0.5, seconds * 0.9)
                lead.add(horn, grid.at(bar, step), 0.10, 0.3)
                wet.add(horn, grid.at(bar, step), 0.04, 0.3)
        # Bläserstöße: "ba-dapp" am Ende jeder Zeile.
        if end_of_line:
            _start, _root, tones = chord_at(bar, 10)
            for step, seconds, level in ((10, 0.11, 0.8), (12, 0.30, 1.0)):
                for index, name in enumerate(tones):
                    note = brass_note(hz(name) * 2.0, seconds)
                    chords.add(note, grid.at(bar, step), 0.085 * level, (0.5, 0.2, -0.3)[index])
                    wet.add(note, grid.at(bar, step), 0.04 * level)
    main = Canvas(grid.frames)
    for part in (drums, bass, chords, lead):
        main.mix_in(part)
    add_reverb(main, wet, 1.1)
    return main, {"Schlagzeug": drums.rms_db(), "Bass": bass.rms_db(), "Akkorde": chords.rms_db(), "Melodie": lead.rms_db()}


# --- Abgesang ---------------------------------------------------------------------------------

def build_game_over(rng):
    """Game Over: Eine Fläche in d-Moll schwillt an (unter der traurigen Posaune des Spiels), dann
    steigt das Vibraphon Schritt für Schritt ab, über B-Dur, g-Moll und A-Dur, und endet mit einem
    tiefen Paukenschlag auf einem langen d-Moll-Akkord."""
    frames = frames_of(8.6)
    main = Canvas(frames, False)
    wet = Canvas(frames, False)

    def pad(at, seconds, notes, gain, attack):
        for name in notes:
            for detune, side in ((-0.003, -0.5), (0.003, 0.5)):
                sig = to_peak(tone(hz(name) * (1.0 + detune), seconds, saw_set(10, 1.7), attack, 0.6))
                main.add(sig, at * RATE, gain, side)
                wet.add(sig, at * RATE, gain * 0.4, side)

    def low(at, name, seconds, gain):
        main.add(sub_note(hz(name), seconds), at * RATE, gain)

    def bell(at, name, seconds, gain, side=0.1):
        sig = vibe_note(hz(name), seconds + 0.6)
        main.add(sig, at * RATE, gain, side)
        wet.add(sig, at * RATE, gain * 0.6, side)

    pad(0.0, 2.9, ("A3", "D4", "F4"), 0.10, 1.2)
    low(0.0, "D2", 2.8, 0.40)
    for at, name, seconds in ((1.30, "F5", 0.55), (1.85, "E5", 0.55), (2.40, "D5", 0.80)):
        bell(at, name, seconds, 0.30)
    pad(2.6, 1.8, ("Bb3", "D4", "F4"), 0.10, 0.3)
    low(2.6, "Bb2", 1.6, 0.36)
    for at, name, seconds in ((3.30, "C5", 0.40), (3.70, "Bb4", 0.55)):
        bell(at, name, seconds, 0.28)
    pad(4.1, 1.4, ("Bb3", "D4", "G4"), 0.10, 0.3)
    low(4.1, "G2", 1.2, 0.36)
    for at, name, seconds in ((4.30, "A4", 0.45), (4.75, "G4", 0.45)):
        bell(at, name, seconds, 0.27)
    pad(5.2, 1.4, ("A3", "C#4", "E4"), 0.10, 0.3)
    low(5.2, "A2", 1.2, 0.36)
    for at, name, seconds in ((5.25, "E4", 0.50), (5.75, "C#4", 0.55)):
        bell(at, name, seconds, 0.27)
    pad(6.3, 2.2, ("A3", "D4", "F4"), 0.11, 0.25)
    low(6.3, "D2", 2.1, 0.50)
    drum = tom(73.4, 0.28)
    main.add(drum, 6.3 * RATE, 0.60)
    wet.add(drum, 6.3 * RATE, 0.20)
    bell(6.3, "D4", 1.6, 0.30, -0.2)
    bell(6.32, "D5", 1.6, 0.22, 0.3)
    add_reverb(main, wet, 1.8)
    # Ausblenden zum Dateiende hin.
    n_out = frames_of(1.2)
    for i in range(n_out):
        factor = (i / n_out) ** 1.5
        main.left[frames - 1 - i] *= factor
        main.right[frames - 1 - i] *= factor
    return main, {}


# --- Liste der Stücke ---------------------------------------------------------------------------

TRACKS = [
    {"name": "music_menu", "build": build_menu, "loop": True, "bar": MENU_BAR, "bars": 16, "bpm": 105, "key": "F-Dur"},
    {"name": "music_calm", "build": build_calm, "loop": True, "bar": GAME_BAR, "bars": 8, "bpm": 126, "key": "d-Moll"},
    {"name": "music_wave", "build": build_wave, "loop": True, "bar": GAME_BAR, "bars": 16, "bpm": 126, "key": "d-Moll"},
    {"name": "music_late", "build": build_late, "loop": True, "bar": GAME_BAR, "bars": 16, "bpm": 126, "key": "d-Moll"},
    {"name": "music_game_over", "build": build_game_over, "loop": False, "bar": 0, "bars": 0, "bpm": 0, "key": "d-Moll"},
]


# --- Schreiben und Prüfen -------------------------------------------------------------------

def finish(canvas, loop):
    """Gleichanteil je Kanal entfernen, beide Kanäle gemeinsam auf den Spitzenpegel bringen.
    Ein Stück ohne Schleife wird an den Rändern kurz geblendet, eine Schleife nie."""
    channels = []
    for sig in (canvas.left, canvas.right):
        mean = sum(sig) / len(sig)
        sig = [s - mean for s in sig]
        if not loop:
            sig = envelope(sig, 0.002, 0.01)
        channels.append(sig)
    peak = max(peak_of(channels[0]), peak_of(channels[1]))
    factor = 10.0 ** (PEAK_DB / 20.0) / peak
    return [[s * factor for s in sig] for sig in channels]


def write_wav(path, channels, loop):
    left = [int(round(max(-1.0, min(1.0, s)) * 32767.0)) for s in channels[0]]
    right = [int(round(max(-1.0, min(1.0, s)) * 32767.0)) for s in channels[1]]
    period = len(left)
    if loop:
        left += left[:LOOP_GUARD]
        right += right[:LOOP_GUARD]
    both = [0] * (2 * len(left))
    both[0::2] = left
    both[1::2] = right
    with wave.open(path, "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(struct.pack("<%dh" % len(both), *both))
    if loop:
        head = struct.pack("<9I", 0, 0, int(round(1e9 / RATE)), 60, 0, 0, 0, 1, 0)
        one_loop = struct.pack("<6I", 0, 0, 0, period, 0, 0)
        with open(path, "r+b") as out:
            out.seek(0, 2)
            out.write(b"smpl" + struct.pack("<I", len(head) + len(one_loop)) + head + one_loop)
            size = out.tell()
            out.seek(4)
            out.write(struct.pack("<I", size - 8))


def read_loop_chunk(path):
    with open(path, "rb") as data:
        raw = data.read()
    at = 12
    while at + 8 <= len(raw):
        name = raw[at:at + 4]
        size = struct.unpack("<I", raw[at + 4:at + 8])[0]
        if name == b"smpl" and size >= 60:
            return struct.unpack("<2I", raw[at + 8 + 44:at + 8 + 52])
        at += 8 + size + (size & 1)
    return None


def to_db(value):
    return 20.0 * math.log10(max(value, 1e-9))


def measure(path, loop):
    with wave.open(path, "rb") as data:
        channels = data.getnchannels()
        width = data.getsampwidth()
        rate = data.getframerate()
        frames = data.getnframes()
        raw = data.readframes(frames)
    if channels != 2 or width != 2 or frames == 0:
        return None
    values = struct.unpack("<%dh" % (2 * frames), raw)
    left = values[0::2]
    right = values[1::2]
    result = {"rate": rate, "loop_ok": True, "seam": 0.0}
    if loop:
        period = frames - LOOP_GUARD
        result["loop_ok"] = (read_loop_chunk(path) == (0, period)
                             and left[period:] == left[:LOOP_GUARD] and right[period:] == right[:LOOP_GUARD])
        left = left[:period]
        right = right[:period]
        frames = period
        for sig in (left, right):
            near = max(max(abs(sig[i + 1] - sig[i]) for i in range(0, 400)),
                       max(abs(sig[i + 1] - sig[i]) for i in range(frames - 401, frames - 1)))
            result["seam"] = max(result["seam"], abs(sig[0] - sig[-1]) / max(near, 1))
    result["frames"] = frames
    result["duration"] = frames / rate
    result["peak_db"] = to_db(max(max(abs(v) for v in left), max(abs(v) for v in right)) / 32768.0)
    square = [a * a + b * b for a, b in zip(left, right)]
    result["rms_db"] = to_db(math.sqrt(sum(square) / (2.0 * frames)) / 32768.0)
    result["clipped"] = sum(1 for v in left if abs(v) >= 32767) + sum(1 for v in right if abs(v) >= 32767)
    result["dc_db"] = to_db(max(abs(sum(left) / frames), abs(sum(right) / frames)) / 32768.0)
    result["edge_db"] = to_db(max(abs(left[0]), abs(left[-1]), abs(right[0]), abs(right[-1])) / 32768.0)
    # Lautheit über die Zeit: Fenster von 0,5 s, alle 0,25 s eines. Bei einer Schleife laufen die
    # Fenster über die Naht, sonst bleiben Ein- und Ausklang (erste 1,5 s, letzte 2 s) außen vor.
    window = rate // 2
    hop = window // 2
    sums = [0.0]
    for v in square:
        sums.append(sums[-1] + v)
    levels = []
    first = 0 if loop else int(1.5 * rate)
    last = frames if loop else frames - 2 * rate - window
    for start in range(first, max(first + 1, last), hop):
        end = start + window
        if end <= frames:
            total = sums[end] - sums[start]
        elif loop:
            total = sums[frames] - sums[start] + sums[end - frames]
        else:
            break
        levels.append((to_db(math.sqrt(total / (2.0 * window)) / 32768.0), start / rate))
    result["quietest"] = min(levels)
    result["loudest"] = max(levels)
    # Seitenanteil: wie breit das Stück ist (0 = Mono).
    side = sum((a - b) * (a - b) for a, b in zip(left, right))
    mid = sum((a + b) * (a + b) for a, b in zip(left, right))
    result["width"] = math.sqrt(side / max(mid, 1.0))
    return result


def problems_of(result, track):
    if result is None:
        return ["kein 16-Bit-Stereo"]
    found = []
    if result["rate"] != RATE:
        found.append("Abtastrate %d" % result["rate"])
    if abs(result["peak_db"] - PEAK_DB) > 0.3:
        found.append("Spitzenpegel")
    if result["clipped"] > 0:
        found.append("übersteuert")
    if result["dc_db"] > DC_LIMIT_DB:
        found.append("Gleichanteil")
    if track["loop"]:
        if result["frames"] != track["bar"] * track["bars"]:
            found.append("Länge ist kein Vielfaches des Takts")
        if not result["loop_ok"]:
            found.append("Schleifen-Eintrag oder Wächter-Werte fehlen")
        if result["seam"] > 1.5:
            found.append("Sprung an der Naht")
    elif result["edge_db"] > EDGE_LIMIT_DB:
        found.append("Knackser am Rand")
    if result["quietest"][0] < result["rms_db"] - 10.0:
        found.append("Loch bei %.1f s" % result["quietest"][1])
    if result["loudest"][0] > result["rms_db"] + 6.0:
        found.append("Spitze bei %.1f s" % result["loudest"][1])
    return found


def fix_import(name):
    """Sorgt dafür, dass Godot die Musikdatei unkomprimiert einliest. Gibt es die Import-Notiz noch
    nicht, entsteht eine kurze, die Godot beim Einlesen vervollständigt. Steht dort eine andere
    Kompression, wird sie geändert und das alte Ergebnis gelöscht, damit Godot neu einliest."""
    note = os.path.join(OUT_DIR, name + ".wav.import")
    if not os.path.exists(note):
        with open(note, "w", encoding="utf-8", newline="\n") as out:
            out.write('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\n'
                      'force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\n'
                      'edit/trim=false\nedit/normalize=false\nedit/loop_mode=0\nedit/loop_begin=0\n'
                      'edit/loop_end=-1\ncompress/mode=0\n')
        return "neu"
    with open(note, "r", encoding="utf-8") as data:
        lines = data.read().split("\n")
    changed = False
    for index, line in enumerate(lines):
        for key, wanted in (("compress/mode", "0"), ("edit/loop_mode", "0")):
            if line.startswith(key + "=") and line != key + "=" + wanted:
                lines[index] = key + "=" + wanted
                changed = True
    if not changed:
        return "passt"
    with open(note, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    for old in glob.glob(os.path.join(PROJECT_DIR, ".godot", "imported", name + ".wav-*")):
        os.remove(old)
    return "geändert"


def main():
    args = sys.argv[1:]
    check_only = "--check" in args or "--fix-import" in args
    only = None
    for arg in args:
        if arg.startswith("--only="):
            only = set(arg[len("--only="):].split(","))
    os.makedirs(OUT_DIR, exist_ok=True)
    failed = 0
    total_bytes = 0
    for track in TRACKS:
        name = track["name"]
        path = os.path.join(OUT_DIR, name + ".wav")
        groups = {}
        if not check_only and (only is None or name in only):
            _cache.clear()
            canvas, groups = track["build"](random.Random("%d:%s" % (SEED, name)))
            write_wav(path, finish(canvas, track["loop"]), track["loop"])
        if not os.path.exists(path):
            failed += 1
            print("%s.wav  FEHLER: Datei fehlt" % name)
            continue
        note = fix_import(name)
        result = measure(path, track["loop"])
        found = problems_of(result, track)
        if found:
            failed += 1
        total_bytes += os.path.getsize(path)
        if result is None:
            print("%s.wav  FEHLER: %s" % (name, ", ".join(found)))
            continue
        kind = "Schleife, %d Takte, %d Schläge je Minute, %s" % (track["bars"], track["bpm"], track["key"]) if track["loop"] else "keine Schleife, " + track["key"]
        print("%s.wav  (%s)" % (name, kind))
        print("    Länge %.3f s (%d Werte), Spitze %.2f dBFS, Mittel %.2f dBFS, Gleichanteil %.0f dBFS, Breite %.2f, %.2f MB" % (
            result["duration"], result["frames"], result["peak_db"], result["rms_db"], result["dc_db"], result["width"],
            os.path.getsize(path) / 1e6))
        if track["loop"]:
            print("    Naht: Sprung %.2f mal der größte Nachbarsprung" % result["seam"])
        else:
            print("    Rand: %.0f dBFS" % result["edge_db"])
        print("    Lautheit in Fenstern von 0,5 s: leisestes %.1f dBFS bei %.1f s, lautestes %.1f dBFS bei %.1f s (Spanne %.1f dB)" % (
            result["quietest"][0], result["quietest"][1], result["loudest"][0], result["loudest"][1],
            result["loudest"][0] - result["quietest"][0]))
        if groups:
            print("    Gruppen vor der Mischung (Mittel, dB): " + ", ".join("%s %.1f" % (key, groups[key]) for key in groups))
        print("    Import-Notiz: %s. Urteil: %s" % (note, "ok" if not found else "FEHLER: " + ", ".join(found)))
        sys.stdout.flush()
    print()
    print("Musik zusammen: %.2f MB" % (total_bytes / 1e6))
    if failed:
        print("%d von %d Stücken haben Fehler." % (failed, len(TRACKS)))
        return 1
    print("Alle %d Stücke sind in Ordnung: %s" % (len(TRACKS), OUT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
