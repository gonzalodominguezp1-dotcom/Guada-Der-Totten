#!/usr/bin/env python3
"""
Sintetiza los efectos de sonido del juego (no usa audio de ningún juego).
Uso:  python3 tools/make_sounds.py assets/sounds
Necesita numpy.
"""
import os
import sys
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(3)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(dur, decay):
    return np.exp(-t_axis(dur) / decay)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff, passes=2):
    # filtro de un polo vectorizado aproximado con convolución exponencial
    a = np.exp(-2 * np.pi * cutoff / SR)
    n = int(min(len(x), max(32, 6 / (1 - a))))
    k = (1 - a) * a ** np.arange(n)
    y = x
    for _ in range(passes):
        y = np.convolve(y, k)[: len(x)]
    return y


def highpass(x, cutoff):
    return x - lowpass_fast(x, cutoff, 1)


def bandpass(x, lo, hi):
    return highpass(lowpass_fast(x, hi), lo)


def tone(freq, dur, shape="sin"):
    t = t_axis(dur)
    if callable(freq):
        ph = 2 * np.pi * np.cumsum(freq(t)) / SR
    else:
        ph = 2 * np.pi * freq * t
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def pad(x, dur):
    n = int(SR * dur)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n] if n > len(x) else x


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, start, total):
    out = np.zeros(int(SR * total))
    s = int(SR * start)
    e = min(len(out), s + len(x))
    out[s:e] += x[: e - s]
    return out


def save(path, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = np.tanh(x / peak * 1.2) / np.tanh(1.2) * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ------------------------------------------------------------------ sonidos

def pistol_shot():
    d = 0.9
    crack = noise(d) * env_exp(d, 0.012)
    body = lowpass_fast(noise(d), 1800) * env_exp(d, 0.06) * 2.5
    thump = tone(lambda t: 110 * np.exp(-t * 8) + 45, d) * env_exp(d, 0.09) * 1.2
    tail = lowpass_fast(noise(d), 600) * env_exp(d, 0.35) * 0.9
    return mix(crack, body, thump, tail)


def click(freq=3200, dur=0.05, dec=0.004):
    return bandpass(noise(dur), freq * 0.5, freq) * env_exp(dur, dec) * 3


def dry_fire():
    return mix(click(2500), at(click(1800, 0.05, 0.006) * 0.6, 0.03, 0.1))


def reload():
    tot = 1.4
    return mix(
        at(click(1500, 0.08, 0.01), 0.05, tot),            # suelta cargador
        at(lowpass_fast(noise(0.15), 900) * env_exp(0.15, 0.03), 0.12, tot),
        at(click(2200, 0.08, 0.008) * 1.2, 0.75, tot),     # mete cargador
        at(click(1200, 0.1, 0.012) * 0.8, 0.8, tot),
        at(click(2800, 0.06, 0.005), 1.15, tot),           # corredera
        at(click(1600, 0.08, 0.01), 1.2, tot),
    )


def knife_swing():
    d = 0.35
    t = t_axis(d)
    e = np.sin(np.pi * np.clip(t / 0.25, 0, 1)) ** 2
    return bandpass(noise(d), 1500, 5000) * e * 0.8


def flesh_hit():
    d = 0.25
    return mix(lowpass_fast(noise(d), 700) * env_exp(d, 0.04) * 2,
               tone(lambda t: 90 - 40 * t, d) * env_exp(d, 0.05))


def zombie_moan(seed, dur=1.8, base=95.0):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    vib = 1 + 0.06 * np.sin(2 * np.pi * r.uniform(4, 7) * t) + 0.03 * lowpass_fast(r.uniform(-1, 1, len(t)), 8, 1) * 20
    glide = base * (1 + r.uniform(-0.25, 0.35) * np.sin(np.pi * t / dur))
    src = tone(lambda tt: glide[: len(tt)] * vib[: len(tt)], dur, "saw")
    src = src + 0.35 * noise(dur)
    # formantes aproximados (vocal "o"-"a") con filtros paso banda
    f1 = bandpass(src, 350, 750)
    f2 = bandpass(src, 900, 1400) * 0.5
    voice = f1 + f2
    env = np.clip(t / 0.15, 0, 1) * np.clip((dur - t) / 0.5, 0, 1)
    rasp = bandpass(noise(dur), 2000, 4500) * 0.12 * env
    return (voice * env + rasp)


def zombie_attack(seed):
    r = np.random.default_rng(seed)
    d = 0.8
    t = t_axis(d)
    src = tone(lambda tt: 180 + 120 * np.sin(np.pi * tt / d) + r.uniform(-20, 20), d, "saw") + 0.6 * noise(d)
    v = bandpass(src, 500, 1800) + bandpass(src, 2000, 3500) * 0.4
    return v * np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.35)


def board_break():
    d = 0.6
    snap = bandpass(noise(d), 800, 4000) * env_exp(d, 0.02) * 2
    wood = sum(tone(f, d) * env_exp(d, 0.07) * a for f, a in ((220, 1), (370, 0.6), (510, 0.4)))
    debris = mix(*(at(click(r_f, 0.05, 0.008) * 0.5, r_t, d)
                   for r_f, r_t in ((1800, 0.12), (1300, 0.2), (2100, 0.28), (900, 0.35))))
    return mix(snap, wood, debris)


def board_place():
    d = 0.4
    knock = lambda st: at(mix(tone(160, 0.15) * env_exp(0.15, 0.03) * 1.5,
                             lowpass_fast(noise(0.15), 1200) * env_exp(0.15, 0.015) * 2), st, d)
    return mix(knock(0.0), knock(0.12) * 0.7, knock(0.22) * 0.6)


def purchase():
    d = 0.9
    bell = sum(tone(f, d) * env_exp(d, 0.25) * a for f, a in ((1318, 0.6), (1975, 0.4), (2637, 0.25)))
    drawer = at(lowpass_fast(noise(0.25), 1200) * env_exp(0.25, 0.08), 0.0, d)
    coins = mix(*(at(click(4000 + i * 300, 0.04, 0.006) * 0.4, 0.05 + i * 0.04, d) for i in range(5)))
    return mix(at(bell, 0.12, d), drawer, coins)


def deny():
    d = 0.4
    return tone(110, d, "square") * env_exp(d, 0.12) * 0.4 + tone(104, d, "square") * env_exp(d, 0.12) * 0.4


def door_open():
    d = 2.2
    t = t_axis(d)
    creak_f = 300 + 180 * np.sin(2 * np.pi * 0.7 * t) + 60 * np.sin(2 * np.pi * 9 * t)
    creak = bandpass(tone(lambda tt: creak_f[: len(tt)], d, "saw"), 400, 2500) * np.clip(t / 0.2, 0, 1) * np.clip((1.6 - t) / 0.3, 0, 1)
    slam = at(mix(lowpass_fast(noise(0.6), 400) * env_exp(0.6, 0.12) * 3,
                  tone(55, 0.6) * env_exp(0.6, 0.15) * 2), 1.55, d)
    return mix(creak * 0.6, slam)


def jingle_notes(notes, step=0.16, wave_shape="square"):
    total = step * len(notes) + 0.6
    out = np.zeros(int(SR * total))
    for i, n in enumerate(notes):
        if n is None:
            continue
        f = 440 * 2 ** ((n - 69) / 12)
        x = tone(f, 0.5, wave_shape) * 0.25 + tone(f * 2, 0.5) * 0.15 + tone(f, 0.5) * 0.4
        x *= env_exp(0.5, 0.18)
        out += at(x, i * step, total)
    return out


def perk_jingle():
    # melodía propia, alegre y un poco siniestra (estilo máquina de feria)
    notes = [72, 76, 79, 76, 77, 74, 71, 74, 72, None, 67, 72, 76, 79, 84]
    mel = jingle_notes(notes, 0.15)
    bass = jingle_notes([48, None, 55, None, 50, None, 55, None, 48, None, 43, None, 48, None, 48], 0.15, "sin")
    return mix(mel, bass * 0.7)


def perk_drink():
    d = 2.4
    cap = at(click(3000, 0.06, 0.01), 0.1, d)
    gulps = mix(*(at(lowpass_fast(noise(0.18), 500) * np.sin(np.pi * t_axis(0.18) / 0.18) * 2
                     + tone(140 - i * 8, 0.18) * np.sin(np.pi * t_axis(0.18) / 0.18), 0.6 + i * 0.33, d) for i in range(4)))
    bottle = at(tone(880, 0.3) * env_exp(0.3, 0.05) * 0.4 + tone(1320, 0.3) * env_exp(0.3, 0.04) * 0.2, 2.0, d)
    return mix(cap, gulps, bottle)


def round_start():
    d = 5.0
    t = t_axis(d)
    env = np.clip(t / 1.2, 0, 1) * np.clip((d - t) / 2.0, 0, 1)
    chord = sum(tone(f * (1 + 0.003 * k), d, "saw") for k, f in enumerate((55, 65.4, 82.4, 110)))
    low = lowpass_fast(chord, 500) * env
    bell = sum(tone(f, d) * env_exp(d, 1.2) * a for f, a in ((220, 0.5), (329.6, 0.3), (440, 0.2)))
    return mix(low * 0.8, bell * 0.6)


def round_end():
    d = 4.0
    notes = [(0.0, 659.3), (0.35, 587.3), (0.7, 523.3), (1.2, 392.0)]
    out = np.zeros(int(SR * d))
    for st, f in notes:
        x = (tone(f, 2.5) * 0.5 + tone(f * 2.01, 2.5) * 0.2 + tone(f * 3.0, 2.5) * 0.1) * env_exp(2.5, 0.6)
        out += at(x, st, d)
    return out


def hurt():
    d = 0.35
    return mix(lowpass_fast(noise(d), 300) * env_exp(d, 0.06) * 3, tone(70, d) * env_exp(d, 0.08) * 1.5)


def heartbeat():
    d = 0.9
    beat = lambda st, a: at(tone(lambda t: 60 - 20 * t, 0.15) * env_exp(0.15, 0.04) * a, st, d)
    return mix(beat(0.0, 1.0), beat(0.22, 0.7))


def wind_loop():
    d = 8.0
    x = lowpass_fast(noise(d), 350) * 4
    t = t_axis(d)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / d) * np.sin(2 * np.pi * 3 * t / d)
    howl = bandpass(noise(d), 500, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / d)) * 0.6
    y = (x + howl) * swell
    fade = int(SR * 0.5)
    y[:fade] = y[:fade] * np.linspace(0, 1, fade) + y[-fade:] * np.linspace(1, 0, fade)
    return y[: len(y) - fade]


def machine_hum():
    d = 4.0
    t = t_axis(d)
    return (tone(60, d) * 0.5 + tone(120, d) * 0.3 + tone(180, d, "saw") * 0.05) * (1 + 0.05 * np.sin(2 * np.pi * 0.5 * t))


def low_ammo_ping():
    d = 0.3
    return tone(1400, d) * env_exp(d, 0.05) * 0.5


def powerup_spawn():
    d = 1.2
    out = np.zeros(int(SR * d))
    for i, f in enumerate((1568, 2093, 2637, 3136, 2637, 3136)):
        out += at(tone(f, 0.4) * env_exp(0.4, 0.08) * 0.5, i * 0.08, d)
    return out


def powerup_grab():
    d = 1.6
    out = np.zeros(int(SR * d))
    for i, n in enumerate((60, 64, 67, 72, 76, 79, 84)):
        f = 440 * 2 ** ((n - 69) / 12)
        out += at((tone(f, 0.6, "square") * 0.2 + tone(f, 0.6) * 0.5) * env_exp(0.6, 0.15), i * 0.07, d)
    voice = bandpass(tone(lambda t: 90 + 10 * np.sin(t * 5), 1.0, "saw") + 0.3 * noise(1.0), 200, 900) * env_exp(1.0, 0.4)
    return mix(out, at(voice * 0.6, 0.45, d))


def zurraspa_shot():
    d = 0.9
    t = t_axis(d)
    # "bloop" húmedo + zumbido eléctrico de tele vieja
    blop = tone(lambda tt: 420 * np.exp(-tt * 9) + 70, d) * env_exp(d, 0.12) * 1.2
    wet = bandpass(noise(d), 300, 1500) * env_exp(d, 0.08) * 1.5
    zap = tone(lambda tt: 1800 - 1400 * np.clip(tt / 0.3, 0, 1), d, "saw") * env_exp(d, 0.1) * 0.25
    hum = tone(15734, d) * env_exp(d, 0.15) * 0.05 + tone(60, d, "square") * env_exp(d, 0.2) * 0.15
    return mix(blop, wet, zap, hum)


def splat():
    d = 0.8
    body = lowpass_fast(noise(d), 900) * env_exp(d, 0.09) * 3
    drops = mix(*(at(bandpass(noise(0.08), 600, 2500) * env_exp(0.08, 0.02), 0.08 + i * 0.07 + rng.uniform(0, 0.04), d) for i in range(6)))
    thud = tone(lambda tt: 110 - 60 * tt, d) * env_exp(d, 0.07)
    return mix(body, drops, thud)


def part_pickup():
    d = 1.0
    out = np.zeros(int(SR * d))
    for i, f in enumerate((784, 988, 1175, 1568)):
        out += at(tone(f, 0.5) * env_exp(0.5, 0.15) * 0.5, i * 0.08, d)
    return out


def zurraspa_spray():
    # chorro corto y húmedo (el arma es automática: tiene que sonar bien repetido)
    d = 0.22
    squirt = bandpass(noise(d), 250, 1800) * env_exp(d, 0.05) * 1.8
    gurgle = tone(lambda tt: 160 + 60 * np.sin(tt * 90), d) * env_exp(d, 0.06) * 0.7
    zap = tone(lambda tt: 900 - 500 * tt / d, d, "saw") * env_exp(d, 0.03) * 0.12
    return mix(squirt, gurgle, zap)


def avalanche():
    # ola de zurraspa: rugido grave que crece y se aleja
    d = 1.6
    t = t_axis(d)
    swell = np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.25, 0) * 2.2)
    roar = lowpass_fast(noise(d), 500) * swell * 3.0
    slosh = bandpass(noise(d), 300, 1400) * swell * (0.6 + 0.4 * np.sin(t * 23)) * 1.2
    sub = tone(lambda tt: 55 + 20 * np.exp(-tt * 3), d) * swell * 0.8
    return mix(roar, slosh, sub)


def nuclear():
    # Defecación Nuclear: pedorreta gigante + explosión
    d = 3.2
    t = t_axis(d)
    brr = tone(lambda tt: 70 + 25 * np.sin(tt * 31) - 15 * tt, 1.2, "saw")
    brr = lowpass_fast(brr, 700) * env_exp(1.2, 0.6) * 1.2
    boom = lowpass_fast(noise(d), 300) * np.exp(-np.maximum(t - 0.9, 0) * 1.6) * (t > 0.9) * 4.0
    sub = tone(lambda tt: 45 * np.exp(-tt * 0.5) + 20, d) * np.exp(-np.maximum(t - 0.9, 0) * 1.2) * (t > 0.9) * 1.2
    return mix(at(brr, 0.0, d), boom, sub)


def portal():
    # zumbido que sube y "fuuum" del vórtice
    d = 1.4
    t = t_axis(d)
    sweep = tone(lambda tt: 120 + 900 * (tt / d) ** 2, d, "saw") * np.sin(np.pi * t / d) * 0.25
    swirl = bandpass(noise(d), 400, 3000) * np.sin(np.pi * t / d) * (0.6 + 0.4 * np.sin(t * 40)) * 0.9
    sub = tone(55, d) * np.sin(np.pi * t / d) * 0.6
    return mix(lowpass_fast(sweep, 3000), swirl, sub)


def bus_horn():
    # bocina de autobús: dos notas graves algo desafinadas
    d = 0.9
    t = t_axis(d)
    env = np.clip(t / 0.03, 0, 1) * np.clip((d - t) / 0.1, 0, 1)
    x = tone(311, d, "saw") * 0.5 + tone(370, d, "saw") * 0.4 + tone(155, d, "square") * 0.2
    return lowpass_fast(x, 2200) * env


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/sounds"
    os.makedirs(out, exist_ok=True)
    sounds = {
        "pistol_shot": pistol_shot(),
        "dry_fire": dry_fire(),
        "reload": reload(),
        "knife": knife_swing(),
        "flesh_hit": flesh_hit(),
        "board_break": board_break(),
        "board_place": board_place(),
        "purchase": purchase(),
        "deny": deny(),
        "door_open": door_open(),
        "perk_jingle": perk_jingle(),
        "perk_drink": perk_drink(),
        "round_start": round_start(),
        "round_end": round_end(),
        "hurt": hurt(),
        "heartbeat": heartbeat(),
        "wind_loop": wind_loop(),
        "machine_hum": machine_hum(),
        "low_ammo": low_ammo_ping(),
        "powerup_spawn": powerup_spawn(),
        "powerup_grab": powerup_grab(),
        "zurraspa_shot": zurraspa_shot(),
        "splat": splat(),
        "part_pickup": part_pickup(),
        "zurraspa_spray": zurraspa_spray(),
        "avalanche": avalanche(),
        "nuclear": nuclear(),
        "portal": portal(),
        "bus_horn": bus_horn(),
    }
    for i in range(6):
        sounds[f"zombie_moan_{i}"] = zombie_moan(10 + i, dur=1.4 + 0.3 * (i % 3), base=80 + 12 * i)
    for i in range(3):
        sounds[f"zombie_attack_{i}"] = zombie_attack(40 + i)
    gains = {"wind_loop": 0.5, "machine_hum": 0.4, "round_start": 0.8}
    only = set(sys.argv[2:])   # opcional: generar solo estos sonidos
    for name, x in sounds.items():
        if only and name not in only:
            continue
        save(os.path.join(out, name + ".wav"), x, gains.get(name, 0.9))
    print(f"{len(sounds)} sonidos en {out}")


if __name__ == "__main__":
    main()
