#!/usr/bin/env python3
"""Generates the built-in presets' wallpapers (pure Python, no dependencies).

    python3 tools/gen_wallpapers.py            # all
    python3 tools/gen_wallpapers.py ios ubuntu # only these

Writes smooth gradient PNGs into app/assets/themes/<preset>/wallpapers/.
They are original artwork for this project (no third-party images).
"""
import math
import os
import struct
import zlib

W, H = 1920, 1200
ROOT = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "themes")


def png(path, pixel):
    rows = bytearray()
    for y in range(H):
        rows.append(0)  # filter: none
        for x in range(W):
            r, g, b = pixel(x / W, y / H)
            rows += bytes((int(r), int(g), int(b)))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    data += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print("wrote", os.path.relpath(path), f"{len(data) // 1024} KB")


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def dither(x, y):
    # Ordered dither to avoid gradient banding.
    return ((x * 7 + y * 13) % 5 - 2) * 0.35


def waves(top, bottom, band, band_dark):
    """Adwaita-like layered hills."""
    def pixel(u, v):
        c = mix(top, bottom, v)
        for i, (amp, freq, phase, off) in enumerate([(0.05, 1.6, 0.3, 0.62), (0.04, 2.3, 1.7, 0.74), (0.03, 3.1, 2.9, 0.86)]):
            edge = off + amp * math.sin(u * freq * math.pi + phase)
            if v > edge:
                c = mix(band, band_dark, i / 2.0 + (v - edge) * 1.5)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def bloom(bg, glow, glow2):
    """Windows-11-like soft bloom."""
    def pixel(u, v):
        dx, dy = (u - 0.5) * 1.6, (v - 0.62) * 1.0
        r = math.sqrt(dx * dx + dy * dy)
        c = mix(glow, bg, smooth(r * 1.4))
        petal = abs(math.sin(math.atan2(dy, dx) * 3)) * math.exp(-r * 3.2)
        c = mix(c, glow2, petal * 0.8)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def hash01(x, y):
    """Cheap deterministic per-cell noise in [0, 1)."""
    n = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n & 0xFFFF) / 65536.0


def mesh(base, blobs):
    """iOS-like soft mesh gradient: coloured light blobs over a base."""
    def pixel(u, v):
        c = base
        for (bx, by, rad, col) in blobs:
            dx, dy = (u - bx) * 1.6, v - by
            w = math.exp(-(dx * dx + dy * dy) / (rad * rad))
            c = mix(c, col, w)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def hills(sky_top, sky_bottom, layers, sun=None):
    """Material-You-like rounded tonal hills (optional flat sun disc)."""
    def pixel(u, v):
        c = mix(sky_top, sky_bottom, v)
        if sun:
            sx, sy, sr, scol = sun
            r = math.sqrt(((u - sx) * W / H) ** 2 + (v - sy) ** 2)
            c = mix(c, scol, smooth((sr - r) * 400))
        for (off, amp, freq, phase, col) in layers:
            edge = off + amp * math.sin(u * freq * math.pi + phase) * math.cos(u * 0.7 + phase)
            if v > edge:
                c = mix(col, mix(col, (0, 0, 0), 0.25), (v - edge) * 1.2)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def rays(dark, mid, warm):
    """Ubuntu-like aubergine field with a warm diagonal glow and soft rays."""
    def pixel(u, v):
        t = smooth((u * 0.55 + v * 0.75) / 1.2)
        c = mix(dark, mid, t)
        dx, dy = u - 0.78, v - 0.9
        r = math.sqrt(dx * dx * 1.6 + dy * dy)
        c = mix(c, warm, math.exp(-r * r * 9) * 0.9)
        ang = math.atan2(dy, dx)
        c = mix(c, warm, (0.5 + 0.5 * math.sin(ang * 14)) * math.exp(-r * 2.2) * 0.18)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def tidepool(deep, mid, ribbons, sparkle):
    """Tidepool: a bioluminescent night tide — luminous surf ribbons with sparks on the crests."""
    def pixel(u, v):
        c = mix(deep, mid, smooth(v * 1.2))
        # Faint moon haze, top right.
        mx, my = u - 0.82, v - 0.16
        c = mix(c, (150, 190, 220), math.exp(-(mx * mx * 2.6 + my * my) * 60) * 0.35)
        crest = 0.0
        for (base, amp, freq, phase, width, col, gain) in ribbons:
            y = base + amp * math.sin(u * freq + phase) + amp * 0.35 * math.sin(u * freq * 2.7 + phase * 1.9)
            dist = (v - y) / width
            glow = math.exp(-dist * dist)
            # The water below each ribbon keeps a little of its light.
            below = 0.18 * math.exp(-max(0.0, dist) * 0.35) if dist > 0 else 0.0
            c = mix(c, col, min(1.0, (glow + below) * gain))
            crest = max(crest, glow)
        # Sparks: sparse points, only where a ribbon glows.
        gx, gy = int(u * W) // 9, int(v * H) // 9
        h = hash01(gx, gy)
        if h > 0.93 and crest > 0.25:
            cx, cy = (gx + 0.5) * 9, (gy + 0.5) * 9
            dd = (u * W - cx) ** 2 + (v * H - cy) ** 2
            c = mix(c, sparkle, math.exp(-dd / 5.0) * crest)
        d = dither(int(u * W), int(v * H))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


JOBS = {
    "gnome-adwaita": lambda: png(os.path.join(ROOT, "gnome-adwaita", "wallpapers", "day.png"),
                                 waves((94, 150, 222), (178, 206, 245), (53, 132, 228), (26, 95, 180))),
    "gnome-dark": lambda: png(os.path.join(ROOT, "gnome-dark", "wallpapers", "night.png"),
                              waves((18, 24, 38), (36, 48, 76), (38, 70, 130), (20, 38, 80))),
    "win11": lambda: png(os.path.join(ROOT, "win11", "wallpapers", "bloom.png"),
                         bloom((205, 222, 240), (40, 110, 220), (120, 170, 250))),
    "ios": lambda: png(os.path.join(ROOT, "ios", "wallpapers", "aurora.png"),
                       mesh((24, 28, 70), [(0.15, 0.2, 0.45, (88, 86, 214)), (0.85, 0.25, 0.4, (255, 45, 146)),
                                            (0.55, 0.85, 0.5, (0, 122, 255)), (0.95, 0.9, 0.3, (255, 159, 10))])),
    "android": lambda: png(os.path.join(ROOT, "android", "wallpapers", "hills.png"),
                           hills((58, 72, 44), (170, 192, 136), [(0.56, 0.07, 1.3, 0.4, (177, 209, 138)),
                                                                 (0.68, 0.06, 1.9, 2.1, (108, 140, 74)),
                                                                 (0.80, 0.05, 2.6, 4.0, (58, 82, 40))],
                                 sun=(0.72, 0.30, 0.09, (232, 240, 204)))),
    "ubuntu": lambda: png(os.path.join(ROOT, "ubuntu", "wallpapers", "aubergine.png"),
                          rays((44, 0, 30), (119, 33, 111), (233, 84, 32))),
    "opus-tidepool": lambda: png(os.path.join(ROOT, "opus-tidepool", "wallpapers", "tidepool.png"),
                                 tidepool((2, 8, 20), (4, 30, 48), [
                                     (0.58, 0.035, 5.0, 0.4, 0.010, (90, 240, 220), 0.95),
                                     (0.66, 0.030, 3.6, 2.2, 0.014, (56, 178, 230), 0.8),
                                     (0.76, 0.028, 6.4, 4.1, 0.012, (150, 120, 255), 0.7),
                                     (0.86, 0.022, 4.8, 1.3, 0.016, (255, 128, 112), 0.55),
                                 ], (235, 255, 250))),
}

if __name__ == "__main__":
    import sys
    for name in sys.argv[1:] or JOBS:
        JOBS[name]()
