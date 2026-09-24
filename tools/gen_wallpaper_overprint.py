#!/usr/bin/env python3
"""Generates the wallpaper for the "Overprint" theme (pure Python).

    python3 tools/gen_wallpaper_overprint.py

Concept: a two-ink risograph poster — fluorescent pink and federal blue
overprinted on warm cream stock, the plates a few pixels out of register,
tones built from halftone dot screens at classic screen angles. A striped
sun, a dotted moon, ink hills. Where the two inks overlap they multiply into
a deep violet, exactly as translucent riso ink does.

Writes app/assets/themes/fable-overprint/wallpapers/overprint.png (1920×1200).
Original artwork for this project; no third-party images. Stdlib only.
"""
import math
import os
import struct
import time
import zlib

W, H = 1920, 1200
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "assets", "themes",
                   "fable-overprint", "wallpapers", "overprint.png")

# Stock and inks (multiplicative, like real translucent riso ink).
PAPER = (244, 236, 216)
PINK = (255, 72, 176)   # fluorescent pink
BLUE = (50, 85, 164)    # federal blue

# Plate misregistration in pixels (dx, dy) — the charm of the medium.
PINK_SHIFT = (-6, -4)
BLUE_SHIFT = (5, -3)

# Halftone screens: cell size and angle (30° / 60° make a pleasant rosette).
CELL = 9.0
PINK_ANGLE = math.radians(30)
BLUE_ANGLE = math.radians(60)

# Composition.
SUN = (1150.0, 548.0, 300.0)      # x, y, radius (its foot sinks into the hill)
MOON = (345.0, 330.0, 118.0)


def clamp01(t):
    return 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)


def png(path, rows):
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


def halftone(x, y, density, ca, sa):
    """Coverage (0..1) of a rotated dot screen carrying `density` tone."""
    if density <= 0.0:
        return 0.0
    if density >= 0.97:
        return 1.0
    rx = x * ca + y * sa
    ry = y * ca - x * sa
    fx = rx % CELL - CELL * 0.5
    fy = ry % CELL - CELL * 0.5
    d = math.sqrt(fx * fx + fy * fy)
    radius = CELL * 0.78 * math.sqrt(density)
    return clamp01(radius - d + 0.5)


def edge(inside):
    """Anti-aliased coverage from a signed distance (positive = inside)."""
    return clamp01(inside + 0.5)


def build_hills():
    """Per-column silhouettes for the two ink hills (they depend on x only)."""
    front, back = [], []
    for x in range(W + 16):
        u = x / W
        front.append(H * (0.745 + 0.038 * math.sin(u * 2.2 * math.pi + 0.4)
                          + 0.018 * math.sin(u * 5.3 * math.pi + 2.0)))
        back.append(H * (0.655 + 0.052 * math.sin(u * 1.5 * math.pi + 2.6)
                         + 0.012 * math.sin(u * 7.1 * math.pi + 0.9)))
    return front, back


def render():
    ca_p, sa_p = math.cos(PINK_ANGLE), math.sin(PINK_ANGLE)
    ca_b, sa_b = math.cos(BLUE_ANGLE), math.sin(BLUE_ANGLE)
    front, back = build_hills()

    pr, pg, pb = PAPER
    # Ink transmission factors (1 = lets all light through).
    tp = tuple(c / 255.0 for c in PINK)
    tb = tuple(c / 255.0 for c in BLUE)

    sx, sy, sr = SUN
    mx, my, mr = MOON
    pdx, pdy = PINK_SHIFT
    bdx, bdy = BLUE_SHIFT
    stripe = 28.0

    rows = bytearray(H * (W * 3 + 1))
    pos = 0
    for y in range(H):
        rows[pos] = 0  # filter: none
        pos += 1
        v = y / H
        # ---- pink plate, row-constant pieces
        ypk = y + pdy
        sky_density = 0.34 * clamp01(1.0 - v / 0.46)      # pink sky fades out
        sky_density *= sky_density                          # gentler falloff
        dy_s = ypk - sy
        # ---- blue plate, row-constant pieces
        ybl = y + bdy
        dy_m = ybl - my
        dy_r = ybl - sy
        for x in range(W):
            # ================= PINK PLATE =================
            xpk = x + pdx
            pink = 0.0
            dx_s = xpk - sx
            ds = math.sqrt(dx_s * dx_s + dy_s * dy_s)
            if ds < sr + 1.0:
                cov = edge(sr - ds)
                if dy_s > 30.0:
                    # venetian stripes that widen towards the horizon
                    t = (dy_s - 30.0) / (sr - 30.0)
                    gap = stripe * (0.12 + 0.6 * t)
                    phase = (dy_s - 30.0) % stripe
                    cut = edge(gap - phase) * edge(phase)  # 1 inside the gap
                    cov *= 1.0 - cut
                pink = cov
            elif ypk < H * 0.46:
                pink = halftone(xpk, ypk, sky_density, ca_p, sa_p)
            elif dx_s > -420.0 and dx_s < 420.0:
                # the sun's reflection: a pink dot screen sinking into the blue
                fyp = front[x + 8]
                if ypk > fyp + 14.0:
                    spread = dx_s / 175.0
                    dens = 0.62 * math.exp(-spread * spread) * clamp01(1.0 - (ypk - fyp - 14.0) / 320.0)
                    pink = halftone(xpk, ypk, dens, ca_p, sa_p)
            # a thin pink ring on the moon's rim (pink over the blue dots)
            dx_m = xpk - mx
            dm = math.sqrt(dx_m * dx_m + dy_s * 0.0 + (ypk - my) * (ypk - my))
            ring = edge(4.0 - abs(dm - (mr + 14.0)))
            if ring > pink:
                pink = ring

            # ================= BLUE PLATE =================
            xbl = x + bdx
            blue = 0.0
            fy = front[xbl + 8]
            by = back[xbl + 8]
            if ybl > fy - 1.0:
                blue = edge(ybl - fy)
            elif ybl > by - 1.0:
                # back hill: halftone that thickens towards the front hill
                t = (ybl - by) / max(1.0, fy - by)
                blue = halftone(xbl, ybl, 0.28 + 0.5 * t, ca_b, sa_b) * edge(ybl - by)
            else:
                # halo rings around the sun
                dx_r = xbl - sx
                dr = math.sqrt(dx_r * dx_r + dy_r * dy_r)
                if sr + 24.0 < dr < sr + 150.0:
                    k = (dr - sr - 24.0) % 42.0
                    blue = edge(3.0 - abs(k - 21.0)) * (1.0 - (dr - sr - 24.0) / 150.0)
                # dotted moon: tone falls from its upper-left to lower-right
                dx_m = xbl - mx
                dmb = math.sqrt(dx_m * dx_m + dy_m * dy_m)
                if dmb < mr + 1.0:
                    shade = clamp01(0.5 + 0.5 * (dx_m + dy_m) / (mr * 1.4))
                    dens = 0.12 + 0.88 * shade * shade
                    b2 = halftone(xbl, ybl, dens, ca_b, sa_b) * edge(mr - dmb)
                    if b2 > blue:
                        blue = b2

            # ================= OVERPRINT =================
            # paper grain + ordered dither (cheap, non-repeating enough)
            g = ((x * 7 + y * 13) % 5 - 2) * 0.6 + ((x * 131 + y * 71 + (x ^ y)) % 11 - 5) * 0.45
            r = (pr + g) * (1.0 - pink * (1.0 - tp[0])) * (1.0 - blue * (1.0 - tb[0]))
            gch = (pg + g) * (1.0 - pink * (1.0 - tp[1])) * (1.0 - blue * (1.0 - tb[1]))
            b = (pb + g) * (1.0 - pink * (1.0 - tp[2])) * (1.0 - blue * (1.0 - tb[2]))
            rows[pos] = int(r) if r < 255 else 255
            rows[pos + 1] = int(gch) if gch < 255 else 255
            rows[pos + 2] = int(b) if b < 255 else 255
            pos += 3
    return rows


if __name__ == "__main__":
    t0 = time.time()
    png(OUT, render())
    print(f"done in {time.time() - t0:.1f}s")
