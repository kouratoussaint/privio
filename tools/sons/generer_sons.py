#!/usr/bin/env python3
"""Sons de Privio (lot 7.2b2) : courts, discrets, créés ici (aucun droit d'auteur tiers).

Usage : python3 tools/sons/generer_sons.py  → apps/mobile/assets/sounds/*.wav
Mono 22,05 kHz, 16 bits, crête à -14 dBFS ; chaque son dure moins d'une demi-seconde.
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "apps" / "mobile" / "assets" / "sounds"
RNG = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(n, attack=0.005, release=0.06):
    """Enveloppe douce : montée rapide, descente exponentielle."""
    x = np.arange(n) / RATE
    a = np.clip(x / attack, 0, 1)
    r = np.exp(-x / release)
    return a * r


def tone(freq, seconds, release=0.06, harm=0.25):
    x = t(seconds)
    s = np.sin(2 * np.pi * freq * x) + harm * np.sin(4 * np.pi * freq * x)
    return s * env(len(x), release=release)


def chirp(f0, f1, seconds, release=0.08):
    x = t(seconds)
    f = np.linspace(f0, f1, len(x))
    phase = 2 * np.pi * np.cumsum(f) / RATE
    return np.sin(phase) * env(len(x), release=release)


def noise(seconds, lowpass_from, lowpass_to, release=0.2):
    """Souffle filtré (passe-bas qui glisse) : balayage, froissement."""
    n = int(RATE * seconds)
    w = RNG.standard_normal(n)
    out = np.zeros(n)
    y = 0.0
    for i in range(n):
        fc = lowpass_from + (lowpass_to - lowpass_from) * i / n
        a = 1 - np.exp(-2 * np.pi * fc / RATE)
        y += a * (w[i] - y)
        out[i] = y
    return out * env(n, attack=0.02, release=release)


def seq(*parts, gap=0.0):
    pad = np.zeros(int(RATE * gap))
    res = []
    for p in parts:
        res += [p, pad]
    return np.concatenate(res)


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(np.pad(p, (0, n - len(p))) for p in parts)


def save(name, s):
    s = s / (np.max(np.abs(s)) or 1) * 10 ** (-14 / 20)
    fade = min(len(s), int(RATE * 0.01))
    s[-fade:] *= np.linspace(1, 0, fade)
    data = (s * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


OUT.mkdir(parents=True, exist_ok=True)
# Message envoyé : petit glissement montant, léger souffle.
save("envoye", mix(chirp(700, 1250, 0.12, release=0.05), 0.15 * noise(0.12, 3000, 6000, 0.04)))
# Message reçu (discussion ouverte) : « pop » à deux notes.
save("recu", seq(tone(880, 0.07, 0.03), tone(1320, 0.09, 0.04)))
# Vider la discussion : balayage (souffle qui s'éteint vers le grave).
save("vider", noise(0.45, 5000, 300, 0.18))
# Supprimer pour tout le monde : froissement (petits craquements).
crack = np.concatenate([noise(0.03, 4000, 2500, 0.012) * RNG.uniform(0.5, 1) for _ in range(6)])
save("supprime", crack)
# Réaction : tic clair.
save("reaction", tone(1600, 0.05, 0.015, harm=0.1))
# Vocal : début (aigu) et fin (plus grave).
save("vocal_debut", tone(988, 0.08, 0.03))
save("vocal_fin", tone(740, 0.08, 0.03))
# Déverrouillage : double clic doux.
save("deverrouille", seq(tone(1200, 0.025, 0.008), tone(1500, 0.03, 0.01), gap=0.04))
# Code faux : bourdonnement grave, deux fois.
buzz = np.sign(np.sin(2 * np.pi * 170 * t(0.09))) * env(len(t(0.09)), release=0.05)
save("code_faux", seq(buzz, buzz, gap=0.05))
# Succès (groupe rejoint, demande acceptée…) : carillon do-mi-sol.
save("succes", seq(tone(1046, 0.08, 0.05), tone(1318, 0.08, 0.05), tone(1568, 0.16, 0.09)))
print("Sons écrits dans", OUT)
