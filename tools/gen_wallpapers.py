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


def _bat(lx, ly):
    """Signed coverage of a bat silhouette in its own unit space (body at 0,0, wingtips at x = ±1)."""
    ax = abs(lx)
    # Body and head.
    if (lx / 0.12) ** 2 + ((ly - 0.0) / 0.19) ** 2 < 1.0:
        return True
    if lx * lx + (ly + 0.24) ** 2 < 0.11 ** 2:
        return True
    # Ears: small triangles on the head.
    if -0.44 < ly < -0.26 and 0.03 < ax < 0.12 and (ax - 0.03) < (ly + 0.44) * 0.5:
        return True
    # Wings: a raised leading edge, a scalloped trailing edge between the finger bones.
    if 0.08 < ax < 1.0:
        top = -0.06 - 0.26 * ax - 0.16 * math.sin(math.pi * ax)
        bottom = 0.20 - 0.52 * ax - 0.42 * abs(math.sin(ax * 3.0 * math.pi)) * ax * (1.0 - ax) * 2.2
        return top < ly < bottom
    return False


def dracula(bg_top, bg_bottom, moon, crater, rings, bat_col, eye, dots_grey, dots_ink, bats):
    """Dracula: a pale moon with halo rings, bats, and a pixel-dot field in the Dracula palette."""
    mx, my, mr = moon[0] * W, moon[1] * H, moon[2] * H
    moon_lit, moon_shade = moon[3], moon[4]
    outer = max(r * mr + math.hypot(dx * W, dy * H) for (dx, dy, r, _) in rings)
    craters = [(mx + ox * mr, my + oy * mr, cr * mr) for (ox, oy, cr) in crater]
    bat_boxes = []
    for (bx, by, size, ang) in bats:
        s = size * H
        bat_boxes.append((bx * W, by * H, s, math.cos(ang), math.sin(ang)))
    cell, dot = 27, 8

    def pixel(u, v):
        px, py = u * W, v * H
        c = mix(bg_top, bg_bottom, smooth(v))
        # Blocky haze along the top edge, like a low-res mosaic of cloud.
        bx, by = int(px) // 48, int(py) // 48
        haze = (hash01(bx + 101, by + 7) - 0.5) * 14 * (1.0 - smooth(v * 3.2))
        haze += 26 * math.exp(-((u - 0.18) ** 2 * 5 + (v - 0.05) ** 2 * 30)) * (1.0 - smooth(v * 3.2))
        c = tuple(ch + haze for ch in c)
        # Halo rings, outermost first, each a little off-centre.
        for (dx, dy, r, col) in rings:
            d = math.hypot(px - (mx + dx * W), py - (my + dy * H))
            c = mix(c, col, clamp_edge(r * mr - d))
        # The moon: lit towards the upper left, with soft craters.
        dm = math.hypot(px - mx, py - my)
        if dm < mr + 1:
            shade = smooth(((px - mx) * 0.6 + (py - my) * 0.8) / mr * 0.5 + 0.5)
            mc = mix(moon_lit, moon_shade, shade)
            for (cx, cy, cr) in craters:
                mc = mix(mc, mix(mc, (0, 0, 0), 0.1), clamp_edge(cr - math.hypot(px - cx, py - cy)) * 0.9)
            c = mix(c, mc, clamp_edge(mr - dm))
        # Pixel dots: only outside the halo, thinning as they approach it.
        gx, gy = int(px) // cell, int(py) // cell
        fx, fy = px - gx * cell, py - gy * cell
        if fx < dot and fy < dot:
            dc = math.hypot((gx + 0.3) * cell - mx, (gy + 0.3) * cell - my)
            reach = smooth((dc - outer) / 260.0)
            h = hash01(gx, gy)
            if h < 0.78 * reach:
                k = hash01(gy + 31, gx + 17)
                if k > 0.8:
                    col = dots_ink[int(hash01(gx * 3 + 5, gy * 5 + 3) * len(dots_ink))]
                    alpha = 0.85
                else:
                    col = dots_grey
                    alpha = 0.25 + 0.55 * hash01(gx + 9, gy + 13)
                c = mix(c, col, alpha * min(1.0, reach * 1.4))
        # Bats in front of everything.
        for (bx0, by0, s, ca, sa) in bat_boxes:
            if abs(px - bx0) > s * 1.05 or abs(py - by0) > s * 1.05:
                continue
            lx = ((px - bx0) * ca + (py - by0) * sa) / s
            ly = ((py - by0) * ca - (px - bx0) * sa) / s
            if _bat(lx, ly):
                c = bat_col
                for ex in (-0.045, 0.045):
                    if (lx - ex) ** 2 + (ly + 0.25) ** 2 < 0.028 ** 2:
                        c = eye
        d = dither(int(px), int(py))
        return tuple(max(0, min(255, ch + d)) for ch in c)
    return pixel


def clamp_edge(inside):
    """Anti-aliased coverage from a signed distance in pixels (positive = inside)."""
    return max(0.0, min(1.0, inside + 0.5))


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
    "dracula": lambda: png(os.path.join(ROOT, "dracula", "wallpapers", "moon.png"),
                           dracula((52, 51, 68), (36, 36, 50),
                                   (0.64, 0.53, 0.19, (196, 195, 222), (150, 148, 182)),
                                   [(-0.30, -0.62, 0.17), (0.45, -0.30, 0.12), (-0.55, 0.28, 0.20),
                                    (0.30, 0.62, 0.10), (0.62, 0.30, 0.07)],
                                   [(-0.045, 0.015, 2.2, (46, 45, 62)), (-0.03, 0.01, 1.85, (56, 55, 76)),
                                    (-0.015, 0.0, 1.52, (72, 71, 96)), (-0.004, 0.0, 1.22, (96, 95, 126))],
                                   (40, 39, 54), (189, 147, 249),
                                   (150, 148, 176),
                                   [(255, 121, 198), (80, 250, 123), (139, 233, 253), (241, 250, 140),
                                    (255, 184, 108), (189, 147, 249), (255, 85, 85)],
                                   [(0.46, 0.41, 0.095, -0.2), (0.79, 0.70, 0.08, 0.25), (0.72, 0.84, 0.045, -0.3),
                                    (0.44, 0.70, 0.03, 0.2)])),
}

if __name__ == "__main__":
    import sys
    for name in sys.argv[1:] or JOBS:
        JOBS[name]()
