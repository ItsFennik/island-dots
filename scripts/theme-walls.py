#!/usr/bin/env python3
"""Generate the wallpapers for the Ember / Abyss / Sakura / Aurora / Neon Dusk themes."""
import math, random, sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

W, H = 3840, 2160
OUT = os.environ.get("WALL_OUT") or os.path.expanduser("~/Pictures/Wallpapers")


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(stops, w=W, h=H):
    stops = [(p, hx(c) if isinstance(c, str) else c) for p, c in stops]
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / (h - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                px[0, y] = lerp(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
                break
        else:
            px[0, y] = stops[-1][1] if t > stops[-1][0] else stops[0][1]
    return col.resize((w, h))


_RAD = Image.new("L", (512, 512))
_RAD.putdata([min(255, int(math.hypot(x - 255.5, y - 255.5) / 256 * 255)) for y in range(512) for x in range(512)])


def glow(img, cx, cy, r, color, strength=1.0, power=2.0):
    """Screen a soft radial glow onto img."""
    d = max(2, int(2 * r))
    m = _RAD.resize((d, d)).point(lambda v: int(255 * strength * max(0, 1 - v / 255) ** power))
    layer = Image.new("RGB", img.size, 0)
    layer.paste(Image.new("RGB", (d, d), hx(color)), (int(cx - r), int(cy - r)), m)
    return ImageChops.screen(img, layer)


def screen_mask(img, mask, color):
    layer = ImageChops.multiply(Image.new("RGB", img.size, hx(color)), mask.convert("RGB"))
    return ImageChops.screen(img, layer)


def ridge(n, rough, rnd):
    pts = [0.0] * (n + 1)
    pts[0], pts[n] = rnd.uniform(-1, 1), rnd.uniform(-1, 1)
    step, scale = n, 1.0
    while step > 1:
        half = step // 2
        for i in range(half, n, step):
            pts[i] = (pts[i - half] + pts[i + half]) / 2 + rnd.uniform(-1, 1) * scale
        scale *= rough
        step = half
    return pts


def mountain(img, base, amp, rough, seed, color, n=1024, shape=None):
    rnd = random.Random(seed)
    ys = ridge(n, rough, rnd)
    pts = []
    for i in range(n + 1):
        x = i * W / n
        off = shape(x / W) if shape else 0
        pts.append((x, base + ys[i] * amp - off))
    ImageDraw.Draw(img).polygon(pts + [(W, H), (0, H)], fill=hx(color))
    return pts


def grain(img, sigma=5):
    n = Image.effect_noise(img.size, sigma).convert("RGB")
    return ImageChops.add(img, n, 1.0, -128)


def stars(img, rnd, count, ymax, color="#ffffff", rmax=3.2):
    d = ImageDraw.Draw(img)
    c = hx(color)
    for _ in range(count):
        x, y = rnd.uniform(0, W), rnd.uniform(0, ymax) ** 1.0
        y = ymax * (rnd.random() ** 1.6)
        r = rnd.choice([1, 1, 1.4, 1.8, 2.2, rmax])
        a = rnd.uniform(0.35, 1.0) * (1 - y / ymax * 0.7)
        d.ellipse([x - r, y - r, x + r, y + r], fill=lerp((0, 0, 0), c, a))
    return img


def save(img, name):
    img = grain(img, 4)
    path = os.path.join(OUT, name)
    img.save(path, quality=94, subsampling=0)
    print(path)


# Ember: dusk dunes under a low sun, rising embers
def ember():
    rnd = random.Random(11)
    img = vgrad([(0, "#120c0b"), (0.30, "#3a1812"), (0.52, "#8a3520"), (0.64, "#e8743f"), (0.70, "#ffb070"), (1, "#ffb070")])
    sx, sy = W * 0.66, H * 0.57
    img = glow(img, sx, sy, W * 0.55, "#ff7a30", 0.55, 1.6)
    img = glow(img, sx, sy, W * 0.22, "#ffb060", 0.7, 1.8)
    ImageDraw.Draw(img).ellipse([sx - 230, sy - 230, sx + 230, sy + 230], fill=hx("#ffe2b0"))
    img = glow(img, sx, sy, 520, "#fff0d0", 0.5, 2.5)
    layers = [
        (0.63, 70, "#9a3c22", 3), (0.68, 90, "#6a2618", 5),
        (0.75, 110, "#3e1a12", 7), (0.84, 130, "#22140f", 9), (0.93, 120, "#14100e", 13),
    ]
    for base, amp, col, seed in layers:
        # dunes: smooth ridges (low roughness) with a broad swell
        ph = rnd.uniform(0, 6.28)
        mountain(img, H * base, amp, 0.42, seed, col,
                 shape=lambda t, ph=ph, a=amp: a * 1.3 * math.sin(t * 3.1 + ph))
    # embers
    lay = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lay)
    for _ in range(170):
        x, y = rnd.uniform(0, W), H * (0.2 + rnd.random() ** 1.6 * 0.8)
        r = rnd.choice([2, 3, 3, 4, 6, 9])
        d.ellipse([x - r, y - r, x + r, y + r], fill=rnd.randint(110, 255))
    img = screen_mask(img, lay.filter(ImageFilter.GaussianBlur(5)), "#ff9a50")
    img = screen_mask(img, lay.filter(ImageFilter.GaussianBlur(1)), "#ffd9a0")
    save(img, "ember-dunes-sunset.jpg")


# Abyss: deep water with light shafts, kelp and glowing plankton
def abyss():
    rnd = random.Random(23)
    img = vgrad([(0, "#2a8a8c"), (0.18, "#11505a"), (0.50, "#0a2a32"), (1, "#050d10")])
    img = glow(img, W * 0.42, -H * 0.15, W * 0.6, "#6fe0d4", 0.45, 1.4)
    rays = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(rays)
    ox, oy = W * 0.42, -H * 0.6
    for _ in range(26):
        ang = math.radians(rnd.uniform(60, 120))
        wid = math.radians(rnd.uniform(0.8, 3.2))
        L = H * 2.2
        p1 = (ox + math.cos(ang - wid) * L, oy + math.sin(ang - wid) * L)
        p2 = (ox + math.cos(ang + wid) * L, oy + math.sin(ang + wid) * L)
        d.polygon([(ox, oy), p1, p2], fill=rnd.randint(25, 70))
    rays = rays.filter(ImageFilter.GaussianBlur(28))
    fade = vgrad([(0, (255, 255, 255)), (0.75, (0, 0, 0)), (1, (0, 0, 0))]).convert("L")
    img = screen_mask(img, ImageChops.multiply(rays, fade), "#9ff3e8")
    # kelp silhouettes (two depths)
    for col, count, hmin, hmax, wid, blur in [("#0a2228", 12, 0.3, 0.55, 22, 8), ("#040a0c", 8, 0.35, 0.8, 34, 1.5)]:
        lay = Image.new("L", img.size, 0)
        d = ImageDraw.Draw(lay)
        for _ in range(count):
            x0 = rnd.uniform(-100, W + 100)
            h = H * rnd.uniform(hmin, hmax)
            ph, amp = rnd.uniform(0, 6.28), rnd.uniform(30, 90)
            pts = [(x0 + amp * math.sin(ph + s / 160) * (s / h), H + 40 - s) for s in range(0, int(h), 3)]
            for i, (x, y) in enumerate(pts):
                t = i / len(pts)
                w = wid * (0.35 + 1.1 * math.sin(math.pi * min(1, t * 1.15)) ** 0.7) * (1 - t) ** 0.3
                d.ellipse([x - w, y - w, x + w, y + w], fill=255)
        if blur:
            lay = lay.filter(ImageFilter.GaussianBlur(blur))
        img.paste(Image.new("RGB", img.size, hx(col)), (0, 0), lay)
    # seabed
    mountain(img, H * 0.95, 60, 0.5, 5, "#030708")
    # plankton
    lay = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lay)
    for _ in range(420):
        x, y = rnd.uniform(0, W), rnd.uniform(H * 0.15, H)
        r = rnd.choice([1.5, 2, 2, 3, 4, 6])
        d.ellipse([x - r, y - r, x + r, y + r], fill=rnd.randint(90, 255))
    img = screen_mask(img, lay.filter(ImageFilter.GaussianBlur(7)), "#3fd6c6")
    img = screen_mask(img, lay.filter(ImageFilter.GaussianBlur(1.2)), "#c8fff6")
    save(img, "abyss-light-rays.jpg")


# Sakura: cherry branch over pale hills, drifting petals
def sakura():
    rnd = random.Random(7)
    img = vgrad([(0, "#f9dfe6"), (0.45, "#fcf1f2"), (0.7, "#fbf4f4"), (1, "#f3dde2")])
    img = glow(img, W * 0.72, H * 0.38, W * 0.35, "#ffffff", 0.6, 1.6)
    mountain(img, H * 0.70, 70, 0.5, 2, "#f1d6dc", shape=lambda t: 260 * math.exp(-((t - 0.7) / 0.16) ** 2))
    mountain(img, H * 0.80, 60, 0.45, 4, "#e9c3cd", shape=lambda t: 90 * math.sin(t * 2.4 + 1))
    mountain(img, H * 0.90, 50, 0.45, 6, "#dfb0bd", shape=lambda t: 70 * math.sin(t * 3.3 + 2.5))

    bark = Image.new("L", img.size, 0)
    bd = ImageDraw.Draw(bark)
    tips = []

    def branch(x, y, ang, length, width, depth):
        if depth == 0 or length < 30:
            tips.append((x, y))
            return
        segs = 6
        for _ in range(segs):
            ang += rnd.uniform(-0.15, 0.15) + 0.01
            nx, ny = x + math.cos(ang) * length / segs, y + math.sin(ang) * length / segs
            bd.line([(x, y), (nx, ny)], fill=255, width=max(2, int(width)))
            r = width / 2
            bd.ellipse([nx - r, ny - r, nx + r, ny + r], fill=255)
            x, y = nx, ny
            width *= 0.93
            if rnd.random() < 0.4 and depth < 6:
                tips.append((x, y))
        k = rnd.choice([2, 2, 3])
        for i in range(k):
            na = ang + rnd.uniform(-0.7, 0.7)
            na = max(math.radians(-20), min(math.radians(55), na))
            branch(x, y, na, length * rnd.uniform(0.62, 0.82), width * 0.68, depth - 1)

    branch(-120, H * 0.02, math.radians(16), 900, 90, 7)
    img.paste(Image.new("RGB", img.size, hx("#3a2a30")), (0, 0), bark)

    petals = ["#f7a9bf", "#fbc4d3", "#ffdce6", "#f28fae", "#ffffff"]

    def flower(d, x, y, r, col):
        rot = rnd.uniform(0, 6.28)
        for k in range(5):
            a = rot + k * 2 * math.pi / 5
            px, py = x + math.cos(a) * r * 0.55, y + math.sin(a) * r * 0.55
            d.ellipse([px - r * 0.55, py - r * 0.55, px + r * 0.55, py + r * 0.55], fill=hx(col))
        d.ellipse([x - r * 0.22, y - r * 0.22, x + r * 0.22, y + r * 0.22], fill=hx("#d9567f"))

    d = ImageDraw.Draw(img)
    for (tx, ty) in tips:
        if rnd.random() < 0.25:
            continue
        for _ in range(rnd.randint(1, 4)):
            flower(d, tx + rnd.gauss(0, 32), ty + rnd.gauss(0, 26), rnd.uniform(24, 44), rnd.choice(petals))

    # drifting petals at three depths
    for blur, count, rng in [(10, 70, (14, 26)), (3, 90, (8, 14)), (0, 40, (16, 24))]:
        masks = {c: Image.new("L", img.size, 0) for c in petals[:4]}
        for _ in range(count):
            x, y = rnd.uniform(0, W), rnd.uniform(0, H)
            r = rnd.uniform(*rng)
            a = rnd.uniform(0, math.pi)
            pts = [(x + math.cos(a + t) * r * (1 if k % 2 == 0 else 0.45), y + math.sin(a + t) * r * (1 if k % 2 == 0 else 0.45))
                   for k, t in enumerate([i * math.pi / 2 for i in range(4)])]
            ImageDraw.Draw(masks[rnd.choice(petals[:4])]).polygon(pts, fill=rnd.randint(170, 240))
        for c, m in masks.items():
            if blur:
                m = m.filter(ImageFilter.GaussianBlur(blur))
            img.paste(Image.new("RGB", img.size, hx(c)), (0, 0), m)
    save(img, "sakura-branch-petals.jpg")


# Aurora: northern lights over mountains, mirrored in a lake
def aurora():
    rnd = random.Random(42)
    hor = int(H * 0.70)
    img = vgrad([(0, "#03060a"), (0.45, "#081420"), (0.70, "#0f2430"), (1, "#0f2430")])
    stars(img, rnd, 900, hor)

    strip = vgrad([(0, (0, 0, 0)), (0.85, (255, 255, 255)), (1, (255, 255, 255))], 1, 600).convert("L")

    def curtain(base, height, color, inten, seed, freq):
        r = random.Random(seed)
        ph = [r.uniform(0, 6.28) for _ in range(4)]
        mask = Image.new("L", img.size, 0)
        # smooth noise for ray texture
        knots = [r.random() for _ in range(220)]
        for x in range(0, W, 2):
            t = x / W
            y0 = base + H * (0.07 * math.sin(t * 6.28 * freq + ph[0]) + 0.035 * math.sin(t * 6.28 * 2.7 + ph[1]))
            hh = height * (0.55 + 0.45 * math.sin(t * 6.28 * 1.3 + ph[2]))
            k = t * (len(knots) - 1)
            i = int(k)
            n = knots[i] + (knots[min(i + 1, len(knots) - 1)] - knots[i]) * (k - i)
            env = max(0, math.sin(t * math.pi * 1.0 + 0.0)) ** 0.6 * (0.45 + 0.55 * math.sin(t * 6.28 * 0.9 + ph[3]) ** 2)
            a = inten * env * (0.35 + 0.65 * n)
            if hh < 4 or a < 0.01:
                continue
            col = strip.resize((1, int(hh))).point(lambda v, a=a: int(v * a))
            mask.paste(col, (x, int(y0 - hh)))
            mask.paste(col, (x + 1, int(y0 - hh)))
        return mask.filter(ImageFilter.GaussianBlur(6))

    g = curtain(H * 0.42, H * 0.34, "#5ef0a8", 0.95, 1, 0.8)
    img = screen_mask(img, g.filter(ImageFilter.GaussianBlur(40)), "#2fae7a")
    img = screen_mask(img, g, "#5ef0a8")
    v = curtain(H * 0.30, H * 0.22, "#b98cff", 0.55, 2, 1.1)
    img = screen_mask(img, v.filter(ImageFilter.GaussianBlur(30)), "#b98cff")
    img = glow(img, W * 0.5, hor, W * 0.6, "#1f6a5a", 0.35, 1.5)

    mountain(img, hor - 120, 180, 0.55, 8, "#132532", shape=lambda t: 200 * math.exp(-((t - 0.3) / 0.2) ** 2))
    mountain(img, hor - 30, 130, 0.58, 12, "#0a141c", shape=lambda t: 260 * math.exp(-((t - 0.78) / 0.14) ** 2))
    ImageDraw.Draw(img).rectangle([0, hor, W, H], fill=hx("#0a0f14"))

    # lake reflection
    top = img.crop((0, hor - (H - hor), W, hor)).transpose(Image.FLIP_TOP_BOTTOM)
    top = top.filter(ImageFilter.GaussianBlur(5))
    top = top.resize((W, (H - hor) // 6)).resize((W, H - hor))  # vertical smear
    dark = vgrad([(0, (150, 160, 165)), (1, (40, 45, 50))], W, H - hor)
    img.paste(ImageChops.multiply(top, dark), (0, hor))
    d = ImageDraw.Draw(img)
    for _ in range(140):  # ripple glints
        y = rnd.uniform(hor + 10, H)
        x = rnd.uniform(0, W)
        L = rnd.uniform(40, 260) * (y - hor) / (H - hor)
        d.line([(x, y), (x + L, y)], fill=hx("#2a4a50"), width=2)
    save(img, "aurora-mountain-lake.jpg")


# Neon Dusk: striped sun over a glowing perspective grid
def neon_dusk():
    rnd = random.Random(99)
    hor = int(H * 0.62)
    img = vgrad([(0, "#0e0a18"), (0.30, "#24123a"), (0.52, "#6a1f6a"), (0.62, "#d0407e"), (1, "#d0407e")])
    stars(img, rnd, 500, H * 0.45, "#f0e6fa")
    sx, sy, sr = W * 0.5, hor - 330, 560
    img = glow(img, sx, sy, W * 0.5, "#ff5fa8", 0.55, 1.5)
    sun = vgrad([(0, "#ffe27a"), (0.45, "#ffb05c"), (1, "#ff3f8e")], 2 * sr, 2 * sr)
    m = Image.new("L", (2 * sr, 2 * sr), 0)
    md = ImageDraw.Draw(m)
    md.ellipse([0, 0, 2 * sr, 2 * sr], fill=255)
    y, gap = sr * 0.95, 8
    while y < 2 * sr:
        md.rectangle([0, y, 2 * sr, y + gap], fill=0)
        y += 64
        gap += 5
    img.paste(sun, (int(sx - sr), int(sy - sr)), m)

    rim = mountain(img, hor - 40, 110, 0.55, 21, "#1b1030",
                   shape=lambda t: 220 * (math.exp(-((t - 0.14) / 0.12) ** 2) + math.exp(-((t - 0.88) / 0.1) ** 2)))
    ImageDraw.Draw(img).rectangle([0, hor, W, H], fill=hx("#0d0816"))

    lines = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lines)
    d.line(rim, fill=170, width=3)
    d.line([(0, hor), (W, hor)], fill=255, width=5)
    vx = W / 2
    for i in range(-40, 41):
        d.line([(vx + i * 22, hor), (vx + i * 330, H)], fill=210, width=4)
    for k in range(1, 40):
        t = (k / 14) ** 2.2
        yy = hor + (H - hor) * t
        if yy > H:
            break
        d.line([(0, yy), (W, yy)], fill=210, width=max(2, int(2 + 5 * t)))
    fade = vgrad([(0, (0, 0, 0)), (hor / H - 0.001, (0, 0, 0)), (hor / H, (255, 255, 255)), (1, (120, 120, 120))]).convert("L")
    rimkeep = Image.new("L", img.size, 0)
    ImageDraw.Draw(rimkeep).line(rim, fill=170, width=3)
    lines = ImageChops.lighter(ImageChops.multiply(lines, fade), rimkeep)
    img = screen_mask(img, lines.filter(ImageFilter.GaussianBlur(16)), "#ff2f8e")
    img = screen_mask(img, lines, "#ff7fc0")
    img = glow(img, W / 2, hor, W * 0.45, "#ff5fa8", 0.4, 2.2)
    save(img, "neon-dusk-grid-sun.jpg")


ALL = {"ember": ember, "abyss": abyss, "sakura": sakura, "aurora": aurora, "neon-dusk": neon_dusk}
if __name__ == "__main__":
    for name in (sys.argv[1:] or ALL):
        ALL[name]()
