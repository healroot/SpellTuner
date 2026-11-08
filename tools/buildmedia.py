#!/usr/bin/env python3
"""tools/buildmedia.py -- writes Media/*.tga, the clock bar's art (T139).

    python3 -I tools/buildmedia.py

Bar textures are white shaded down to grey, so the game's vertex colour (the
fill you pick) is their brightest part: Soft, Smooth, Gloss, Striped, Minimal.
Masks are white with the shape in their alpha, used CLAMPTOWHITE so everything
outside them stays drawn: PillL / PillR (a half disc at the bar's end) and
RoundL / RoundR (corners of a third of the height). Uncompressed 32-bit TGA,
power-of-two sizes. Pure Python, nothing fetched.
"""
import math
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Media")


def write_tga(name, w, h, pixel):
    """pixel(x, y) -> (r, g, b, a) in 0..1, y = 0 at the top."""
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    body = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixel(x, y)
            body += bytes((round(b * 255), round(g * 255), round(r * 255), round(a * 255)))
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(head + bytes(body))


def lerp(a, b, t):
    return a + (b - a) * t


def vertical(stops):
    """A brightness down the height from (position 0..1, value) stops."""
    def at(t):
        for (p0, v0), (p1, v1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                return lerp(v0, v1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
        return stops[-1][1]
    return at


def bar(name, shade, stripes=False, w=256, h=32):
    def px(x, y):
        v = shade((y + 0.5) / h)
        if stripes and ((x + y) // 8) % 2 == 0:
            v *= 0.82
        return (v, v, v, 1.0)
    write_tga(name, w, h, px)


def coverage(inside, x, y, n=4):
    """Antialiased: the share of a pixel's n x n samples inside the shape."""
    hit = 0
    for i in range(n):
        for j in range(n):
            if inside(x + (i + 0.5) / n, y + (j + 0.5) / n):
                hit += 1
    return hit / (n * n)


def mask(name, inside, size=64):
    write_tga(name, size, size, lambda x, y: (1.0, 1.0, 1.0, coverage(inside, x, y)))


def pill_left(x, y, s=64):
    r = s / 2
    return x >= r or math.hypot(x - r, y - r) <= r


def round_left(x, y, s=64):
    r = s / 3
    if x >= r:
        return True
    if r <= y <= s - r:
        return True
    cy = r if y < r else s - r
    return math.hypot(x - r, y - cy) <= r


def main():
    os.makedirs(OUT, exist_ok=True)
    bar("Soft", vertical([(0, 1.0), (0.45, 0.88), (1, 0.66)]))
    bar("Smooth", vertical([(0, 1.0), (0.5, 0.84), (1, 0.64)]))
    bar("Gloss", vertical([(0, 1.0), (0.48, 0.9), (0.5, 0.74), (1, 0.66)]))
    bar("Striped", vertical([(0, 1.0), (1, 0.86)]), stripes=True)
    bar("Minimal", vertical([(0, 1.0), (0.04, 1.0), (0.05, 0.86), (1, 0.86)]))
    mask("PillL", pill_left)
    mask("PillR", lambda x, y: pill_left(64 - x, y))
    mask("RoundL", round_left)
    mask("RoundR", lambda x, y: round_left(64 - x, y))
    print("wrote", ", ".join(sorted(os.listdir(OUT))), "into", OUT)


if __name__ == "__main__":
    main()
