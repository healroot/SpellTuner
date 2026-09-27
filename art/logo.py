#!/usr/bin/env python3
"""The SpellTuner logo, drawn from code so it can be regenerated at any size.

    python3 art/logo.py [out_dir]

Writes SpellTuner-logo-1024.png / -512.png (with the wordmark, for the CurseForge
project image and the README) and SpellTuner-icon-1024.png / -512.png (no text, for
the small avatar where a wordmark would not be legible).

The picture: a tuner's gauge whose ticks are the eleven ranks of a spell, its arc
running from mana blue through the addon's purple (the |cff9966ff of the chat prefix)
to heal green, and a needle resting on the rank the addon would suggest. The spark
at the pivot is the spell being tuned.

Only Pillow. Everything is drawn at 4x and downsampled, glows are blurred layers.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4                       # supersampling
BASE = 1024                 # the size the layout is described in
W = BASE * S

PURPLE = (153, 102, 255)    # 9966ff
BLUE = (72, 132, 255)
GREEN = (94, 227, 138)
INK = (18, 16, 31)
INK2 = (30, 25, 58)
PALE = (233, 228, 255)
GOLD = (255, 214, 120)

FONT_CANDIDATES = [
    "/mnt/c/Windows/Fonts/georgiab.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
]


def px(v):
    """Unit coordinate (0..1 of the canvas) to supersampled pixels."""
    return v * W


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def arc_colour(t):
    """Blue at the left end, purple in the middle, green at the right."""
    if t < 0.5:
        return lerp(BLUE, PURPLE, t / 0.5)
    return lerp(PURPLE, GREEN, (t - 0.5) / 0.5)


def font(size_units):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, int(px(size_units)))
    return ImageFont.load_default()


def background():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = px(0.19)
    d.rounded_rectangle([0, 0, W - 1, W - 1], radius=r, fill=INK + (255,))
    # a soft purple bloom behind the gauge, and a darker vignette at the bottom
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    cx, cy, rr = px(0.5), px(0.52), px(0.34)
    g.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=INK2 + (255,))
    glow = glow.filter(ImageFilter.GaussianBlur(px(0.12)))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=r, fill=255)
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (W, W), 0), mask))
    img.alpha_composite(glow)
    # a hairline border that reads at small sizes
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([px(0.012), px(0.012), W - px(0.012), W - px(0.012)],
                        radius=r - px(0.01), outline=(60, 50, 105, 255), width=int(px(0.006)))
    return img


def gauge(img, cx, cy, radius, sweep_from, sweep_to, thickness, suggested_index, ranks=11):
    """The arc in graded colour, the rank ticks, the needle and the spark."""
    d = ImageDraw.Draw(img)
    steps = 240
    for i in range(steps):
        a0 = sweep_from + (sweep_to - sweep_from) * i / steps
        a1 = sweep_from + (sweep_to - sweep_from) * (i + 1.5) / steps
        col = arc_colour(i / (steps - 1))
        d.arc([cx - radius, cy - radius, cx + radius, cy + radius], a0, a1,
              fill=col + (255,), width=int(thickness))
    # the inner dark rim that separates the arc from the face
    inner = radius - thickness
    d.arc([cx - inner, cy - inner, cx + inner, cy + inner], sweep_from, sweep_to,
          fill=(40, 34, 70, 255), width=int(px(0.006)))

    # rank ticks: eleven of them on the outside of the arc, the suggested one gold and long
    for k in range(ranks):
        t = k / (ranks - 1)
        ang = math.radians(sweep_from + (sweep_to - sweep_from) * t)
        long = k == suggested_index
        r0 = radius + px(0.018)
        r1 = radius + px(0.06 if long else 0.042)
        x0, y0 = cx + r0 * math.cos(ang), cy + r0 * math.sin(ang)
        x1, y1 = cx + r1 * math.cos(ang), cy + r1 * math.sin(ang)
        col = GOLD if long else (150, 140, 200)
        d.line([x0, y0, x1, y1], fill=col + (255,), width=int(px(0.012 if long else 0.008)))

    # the needle, on its own layer so it can glow
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    t = suggested_index / (ranks - 1)
    ang = math.radians(sweep_from + (sweep_to - sweep_from) * t)
    tip_r = radius - thickness / 2
    tail_r = px(0.07)
    tip = (cx + tip_r * math.cos(ang), cy + tip_r * math.sin(ang))
    tail = (cx - tail_r * math.cos(ang), cy - tail_r * math.sin(ang))
    half = px(0.016)
    nx, ny = -math.sin(ang) * half, math.cos(ang) * half
    ld.polygon([tip, (cx + nx, cy + ny), tail, (cx - nx, cy - ny)], fill=PALE + (255,))
    glow = layer.filter(ImageFilter.GaussianBlur(px(0.02)))
    img.alpha_composite(Image.blend(Image.new("RGBA", (W, W), (0, 0, 0, 0)), glow, 0.9))
    img.alpha_composite(layer)

    # the pivot and the spark: a four-pointed star, the spell being tuned
    d = ImageDraw.Draw(img)
    pr = px(0.052)
    d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=INK2 + (255,),
              outline=PURPLE + (255,), width=int(px(0.008)))
    spark = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spark)
    long_r, short_r = px(0.036), px(0.009)
    pts = []
    for i in range(8):
        a = math.radians(i * 45 - 90)
        r = long_r if i % 2 == 0 else short_r
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    sd.polygon(pts, fill=(255, 255, 255, 255))
    sglow = spark.filter(ImageFilter.GaussianBlur(px(0.02)))
    tint = Image.new("RGBA", (W, W), PURPLE + (0,))
    tint.putalpha(sglow.getchannel("A"))
    img.alpha_composite(tint)
    img.alpha_composite(spark)


def wordmark(img, text, y, size_units):
    d = ImageDraw.Draw(img)
    f = font(size_units)
    # letter-spaced by hand so the mark breathes at small sizes
    spacing = px(0.006)
    widths = [d.textbbox((0, 0), ch, font=f)[2] for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = (W - total) / 2
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    bbox = d.textbbox((0, 0), text, font=f)
    top = y - (bbox[3] - bbox[1]) / 2 - bbox[1]
    for ch, w in zip(text, widths):
        ld.text((x, top), ch, font=f, fill=PALE + (255,))
        x += w + spacing
    glow = layer.filter(ImageFilter.GaussianBlur(px(0.012)))
    tint = Image.new("RGBA", (W, W), PURPLE + (0,))
    tint.putalpha(glow.getchannel("A").point(lambda a: int(a * 0.8)))
    img.alpha_composite(tint)
    img.alpha_composite(layer)


def render(with_text):
    img = background()
    if with_text:
        cx, cy, radius = px(0.5), px(0.55), px(0.315)
        gauge(img, cx, cy, radius, 200, 340, px(0.054), suggested_index=7)
        wordmark(img, "SpellTuner", px(0.845), 0.118)
    else:
        # no wordmark: the gauge sits lower and larger so the square is filled
        cx, cy, radius = px(0.5), px(0.665), px(0.365)
        gauge(img, cx, cy, radius, 200, 340, px(0.062), suggested_index=7)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    for name, with_text in (("logo", True), ("icon", False)):
        big = render(with_text)
        for size in (1024, 512):
            small = big.resize((size, size), Image.LANCZOS)
            path = os.path.join(out, f"SpellTuner-{name}-{size}.png")
            small.save(path, optimize=True)
            print(path)


if __name__ == "__main__":
    main()
