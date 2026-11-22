#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rechnet nach, wie laut die Mischung des Spiels wird, wenn viel auf einmal klingt.

Aufruf (im Projektordner):
    python tools/check_mix.py

Das Skript liest die Tondateien aus audio/ und die Lautstärken aus dem Code (Tabelle SOUNDS in
scripts/game/audio/sfx.gd, Tabelle LAYERS in scripts/game/audio/music.gd, Decke des Begrenzers in
scripts/game/audio/audio_buses.gd, Standardwerte der Regler in scripts/game/settings.gd) und legt
für drei Lagen alles so übereinander, wie es das Spiel täte:

    ruhig    Musik der Welle, Pistole (5 Schuss je Sekunde), ein paar Treffer
    Gefecht  Musik der Welle, Sturmgewehr, Treffer, sterbende Zombies, Schritte, eine Explosion
    Sturm    Musik ab Welle 10 (mit Zusatzspur), zwei Waffen im Dauerfeuer (MG und MP), Treffer,
             sterbende Zombies, eine Explosion direkt neben dem Spieler (+3 dB), noch eine in
             8 m Abstand, dazu das Brüllen eines Elite-Zombies

Gedruckt wird je Lage: die Spitze der Summe vor dem Begrenzer, wie viel der Begrenzer höchstens
wegnehmen muss, wie oft er überhaupt arbeitet, der mittlere Pegel von Musik und Geräuschen, und die
Spitze am Ausgang (nach Begrenzer und Regler "Lautstärke"). Die Explosionen drängen die Musik
dabei zurück wie im Spiel. Der Hall-Bus bleibt außen vor (sein Anteil ist klein: wet 0,16).

Das ist eine Rechnung, kein Hörtest: Sie zeigt, ob etwas übersteuert und wie Musik und Geräusche
zueinander stehen. Wie es klingt, entscheidet das Ohr.
Endet mit Code 1, wenn die Summe am Ausgang 0 dBFS erreichen könnte oder eine Datei fehlt.
"""

import math
import os
import re
import struct
import sys
import wave

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(PROJECT_DIR, "audio")
RATE = 44100


def read_text(*parts):
    with open(os.path.join(PROJECT_DIR, *parts), "r", encoding="utf-8") as data:
        return data.read()


def number(text, name):
    found = re.search(name + r"\s*:\s*float\s*=\s*(-?[\d.]+)", text)
    if not found:
        raise SystemExit("FEHLER: %s nicht gefunden." % name)
    return float(found.group(1))


def load_mono(name):
    """Liest eine Mono-Datei und bringt sie auf 44100 Hz."""
    with wave.open(os.path.join(AUDIO_DIR, name + ".wav"), "rb") as data:
        rate = data.getframerate()
        frames = data.getnframes()
        values = struct.unpack("<%dh" % frames, data.readframes(frames))
    sig = [v / 32768.0 for v in values]
    return double_rate(sig) if rate == 22050 else sig


def load_stereo(name):
    """Liest eine Stereo-Schleife der Musik (ohne die Wächter-Werte am Ende), auf 44100 Hz."""
    with wave.open(os.path.join(AUDIO_DIR, name + ".wav"), "rb") as data:
        frames = data.getnframes()
        values = struct.unpack("<%dh" % (2 * frames), data.readframes(frames))
    left = [v / 32768.0 for v in values[0:2 * (frames - 3):2]]
    right = [v / 32768.0 for v in values[1:2 * (frames - 3):2]]
    return double_rate(left), double_rate(right)


def double_rate(sig):
    out = [0.0] * (2 * len(sig))
    out[0::2] = sig
    out[1::2] = [(a + b) * 0.5 for a, b in zip(sig, sig[1:] + sig[:1])]
    return out


def gain(db):
    return 10.0 ** (db / 20.0)


def to_db(value):
    return 20.0 * math.log10(max(value, 1e-9))


def rms(sig):
    return math.sqrt(sum(s * s for s in sig) / len(sig))


def add(dst, src, at, factor):
    first = int(at * RATE)
    if first >= len(dst):
        return
    part = src[:len(dst) - first]
    dst[first:first + len(part)] = [d + s * factor for d, s in zip(dst[first:first + len(part)], part)]


def main():
    sfx_code = read_text("scripts", "game", "audio", "sfx.gd")
    music_code = read_text("scripts", "game", "audio", "music.gd")
    buses_code = read_text("scripts", "game", "audio", "audio_buses.gd")
    settings_code = read_text("scripts", "game", "settings.gd")
    sound_db = {name: float(db) for name, db in re.findall(r'"(\w+)": \{"db": (-?[\d.]+)', sfx_code)}
    variants = {name: int(count) for name, count in re.findall(r'"(\w+)": \{"db": [^}]*"variants": (\d+)', sfx_code)}
    duck_db = {name: float(db) for name, db in re.findall(r'"(\w+)": \{"db": [^}]*"duck": (-?[\d.]+)', sfx_code)}
    layer_db = {name: (file_name, float(db)) for name, file_name, db in
                re.findall(r'"(\w+)": \{"file": "(\w+)", "db": (-?[\d.]+)', music_code)}
    ceiling_db = number(buses_code, "LIMITER_CEILING_DB")
    master = number(settings_code, "MASTER_VOLUME_DEFAULT")
    music_volume = number(settings_code, "MUSIC_VOLUME_DEFAULT")
    sfx_volume = number(settings_code, "SFX_VOLUME_DEFAULT")
    duck_attack = number(music_code, "DUCK_ATTACK_RATE")
    duck_release = number(music_code, "DUCK_RELEASE_RATE")
    print("Regler (Standard): Lautstärke %.0f %%, Musik %.0f %%, Geräusche %.0f %%. Begrenzer: Decke %.1f dBFS." % (
        master * 100.0, music_volume * 100.0, sfx_volume * 100.0, ceiling_db))
    print()

    cache = {}

    def sound(name, index=0):
        file_name = name if index == 0 else "%s_%d" % (name, index + 1)
        if file_name not in cache:
            cache[file_name] = load_mono(file_name)
        return cache[file_name]

    stems = {}
    for layer in ("wave", "late"):
        stems[layer] = load_stereo(layer_db[layer][0])

    seconds = 8.0
    total = int(seconds * RATE)

    def scene(title, layers, events, ducks):
        """layers: Spuren der Musik. events: [(Geräusch, Abstand s oder None, Beginn s, zusätzliche dB)].
        ducks: [(Beginn s, dB, Dauer s)] für das Zurückdrängen der Musik."""
        # Kurve des Zurückdrängens in dB, wie music.gd sie fährt.
        duck_curve = [0.0] * total
        current = 0.0
        step = 256
        for start in range(0, total, step):
            t = start / RATE
            goal = 0.0
            for at, db, hold in ducks:
                if at <= t < at + hold:
                    goal = min(goal, db)
            rate = duck_attack if goal < current else duck_release
            delta = rate * step / RATE
            current = max(goal, current - delta) if goal < current else min(goal, current + delta)
            for i in range(start, min(total, start + step)):
                duck_curve[i] = current
        music = [[0.0] * total, [0.0] * total]
        for layer in layers:
            factor = gain(layer_db[layer][1]) * music_volume
            for channel in range(2):
                src = stems[layer][channel]
                loop = (src * (total // len(src) + 1))[:total]
                music[channel] = [m + s * factor * gain(d) for m, s, d in zip(music[channel], loop, duck_curve)]
        sfx = [0.0] * total
        for name, every, start, extra_db in events:
            count = variants.get(name, 1)
            at = start
            index = 0
            while at < seconds:
                add(sfx, sound(name, index % count), at, gain(sound_db[name] + extra_db) * sfx_volume)
                index += 1
                if every is None:
                    break
                at += every
        peak = 0.0
        over = 0
        ceiling = gain(ceiling_db)
        for channel in range(2):
            for m, s in zip(music[channel], sfx):
                value = abs(m + s)
                if value > peak:
                    peak = value
                if value > ceiling:
                    over += 1
        music_rms = math.sqrt((rms(music[0]) ** 2 + rms(music[1]) ** 2) / 2.0)
        sfx_rms = rms(sfx)
        out_peak_db = min(to_db(peak), ceiling_db) + to_db(master)
        print("%s" % title)
        print("    Spitze vor dem Begrenzer %+.1f dBFS, der Begrenzer nimmt höchstens %.1f dB weg und arbeitet in %.2f %% der Zeit" % (
            to_db(peak), max(0.0, to_db(peak) - ceiling_db), 100.0 * over / (2.0 * total)))
        print("    Mittel: Musik %.1f dBFS, Geräusche %.1f dBFS (Geräusche %.1f dB über der Musik)" % (
            to_db(music_rms), to_db(sfx_rms), to_db(sfx_rms) - to_db(music_rms)))
        print("    Spitze am Ausgang (nach Begrenzer und Lautstärke): %.1f dBFS" % out_peak_db)
        return out_peak_db

    worst = -99.0
    worst = max(worst, scene(
        "ruhig: Musik der Welle, Pistole, Treffer",
        ["wave"],
        [("shot_pistol", 0.2, 0.5, 0.0), ("hit", 0.35, 0.55, 0.0), ("step", 0.36, 0.1, 0.0)],
        []))
    worst = max(worst, scene(
        "Gefecht: Musik der Welle, Sturmgewehr, Treffer, Tode, Schritte, eine Explosion",
        ["wave"],
        [("shot_rifle", 1.0 / 9.0, 0.3, 0.0), ("hit", 0.15, 0.35, 0.0), ("zombie_death", 0.6, 0.8, -2.0),
         ("step", 0.36, 0.1, 0.0), ("zombie_groan_1", 2.5, 1.0, -4.0), ("explosion", None, 4.0, 0.0)],
        [(4.0, duck_db["explosion"], 0.95)]))
    worst = max(worst, scene(
        "Sturm: Musik ab Welle 10, MG und MP im Dauerfeuer, Treffer, Tode, zwei Explosionen, Elite",
        ["wave", "late"],
        [("shot_lmg", 1.0 / 11.0, 0.2, 0.0), ("shot_smg", 1.0 / 12.0, 0.23, 0.0), ("hit", 0.12, 0.3, 0.0),
         ("zombie_death", 0.4, 0.5, 0.0), ("explosion", None, 3.0, 3.0), ("explosion", None, 5.2, 0.0),
         ("elite_roar", None, 4.0, 0.0), ("step", 0.26, 0.1, 2.0)],
        [(3.0, duck_db["explosion"], 0.95), (5.2, duck_db["explosion"], 0.95), (4.0, duck_db["elite_roar"], 1.1)]))
    print()
    if worst >= 0.0:
        print("FEHLER: Am Ausgang können 0 dBFS erreicht werden.")
        return 1
    print("Am Ausgang bleibt in jeder Lage Luft: lauteste Spitze %.1f dBFS." % worst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
