#!/usr/bin/env python3
"""macOS-style "Clear" / "Tinted" app icons for the dock, Launchpad and Spotlight.

    tint-icons.py <style> <#tint> <dark 0|1> <name-or-path>...
        style = clear | tinted | border (the icon unchanged, with a thin light rim)

Each icon is pulled apart into a glyph (whatever differs from the icon's tile colour)
and redrawn as a single-colour glyph on a translucent glass tile of the same shape.
Results are cached in ~/.cache/island/tinted-icons; prints "<name>\t<png or empty>" per icon.
(The software Qt renderer Island uses can't run colourising shaders, hence pre-rendering.)
"""
import hashlib, io, json, os, re, subprocess, sys, threading
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 128
HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "island/tinted-icons")
VERSION = "3"

style, tint_hex, dark = sys.argv[1], sys.argv[2].lstrip("#")[:6], sys.argv[3] == "1"
names = sys.argv[4:]
tint = tuple(int(tint_hex[i:i + 2], 16) for i in (0, 2, 4))


# icon lookup (freedesktop icon theme spec, simplified)
def data_dirs():
    xs = [os.environ.get("XDG_DATA_HOME", HOME + "/.local/share")]
    xs += os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    xs += [HOME + "/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share"]
    return [HOME + "/.icons"] + [d + "/icons" for d in xs if d]


ICON_DIRS = [d for d in dict.fromkeys(data_dirs()) if os.path.isdir(d)]


def setting(key, fallback):
    for f in (HOME + "/.config/island/settings.json", os.path.dirname(os.path.abspath(__file__)) + "/../defaults.json"):
        try:
            v = json.load(open(f)).get(key)
            if v:
                return v
        except Exception:
            pass
    return fallback


def theme_chain(first):
    chain, todo = [], [first]
    while todo:
        t = todo.pop(0)
        if t in chain:
            continue
        chain.append(t)
        # "WhiteSur-dark" style variants often only carry small icons; the base theme has the big ones
        for suf in ("-dark", "-light", "-Dark", "-Light"):
            if t.endswith(suf):
                todo.insert(0, t[: -len(suf)])
        for d in ICON_DIRS:
            idx = f"{d}/{t}/index.theme"
            if os.path.isfile(idx):
                for line in open(idx, errors="ignore"):
                    if line.startswith("Inherits="):
                        todo += [x.strip() for x in line[9:].split(",") if x.strip()]
                break
    if "hicolor" in chain:
        chain.remove("hicolor")
    return chain + ["hicolor"]


def size_of(path):
    """Nominal size from the directory: "scalable" counts as 512, "48x48"/"48"/"48@2x" as 48(x2)."""
    for part in reversed(path.lower().split("/")[:-1]):
        if part.startswith("scalable"):
            return 512
        m = re.match(r"^(\d+)(?:x\d+)?(@2x)?$", part)
        if m:
            return int(m.group(1)) * (2 if m.group(2) else 1)
    return 256 if path.lower().endswith((".svg", ".svgz")) else 0


def score(path):
    # biggest wins; apps/ over other contexts; never symbolic
    p = path.lower()
    return size_of(path) * 10 + (5 if "/apps" in p else 0) - (100000 if "symbolic" in p else 0)


_index = {}


def theme_index(theme):
    if theme not in _index:
        best = {}
        for d in ICON_DIRS:
            root = f"{d}/{theme}"
            if not os.path.isdir(root):
                continue
            for dp, _, fs in os.walk(root, followlinks=True):
                for f in fs:
                    stem, ext = os.path.splitext(f)
                    if ext.lower() not in (".svg", ".png", ".svgz"):
                        continue
                    p = os.path.join(dp, f)
                    if stem not in best or score(p) > score(best[stem]):
                        best[stem] = p
        _index[theme] = best
    return _index[theme]


CHAIN = theme_chain(setting("iconTheme", "hicolor"))


def resolve(name):
    if not name:
        return None
    if name.startswith("file://"):
        name = name[7:]
    if name.startswith("/"):
        return name if os.path.isfile(name) else None
    small = None
    for t in CHAIN:
        p = theme_index(t).get(name)
        if p:
            if size_of(p) >= 48:
                return p
            small = small or p          # only a small (often line-art) size here; keep looking
    if small:
        return small
    for ext in (".svg", ".png", ".xpm"):
        p = f"/usr/share/pixmaps/{name}{ext}"
        if os.path.isfile(p):
            return p
    return None


def load(path):
    if path.lower().endswith((".svg", ".svgz")):
        png = subprocess.run(["magick", "-background", "none", "-density", "384", path, "-resize", f"{SIZE}x{SIZE}", "png:-"],
                             capture_output=True, check=True).stdout
        im = Image.open(io.BytesIO(png))
    else:
        im = Image.open(path)
    im = im.convert("RGBA")
    im.thumbnail((SIZE, SIZE), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE))
    canvas.paste(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
    return canvas


# drawing
def lum(px):
    r, g, b = px[:3]
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def render(src):
    alpha = src.getchannel("A")
    px = src.load()
    opaque = sum(alpha.histogram()[201:]) / (SIZE * SIZE)

    if opaque > 0.5:
        # Icon sits on its own tile: the tile colour is the median of an inset ring.
        ring = []
        for i in range(SIZE):
            for (x, y) in ((i, 16), (i, SIZE - 17), (16, i), (SIZE - 17, i)):
                if px[x, y][3] > 230:
                    ring.append(lum(px[x, y]))
        ring.sort()
        bg_l = ring[len(ring) // 2] if ring else 0.0
        tile_mask = alpha
        glyph_src = src
    else:
        # Free-form icon: draw our own squircle and shrink the artwork onto it.
        bg_l = None
        tile_mask = Image.new("L", (SIZE * 4, SIZE * 4))
        m = round(SIZE * 4 * 0.09)
        ImageDraw.Draw(tile_mask).rounded_rectangle((m, m, SIZE * 4 - m, SIZE * 4 - m), radius=round(SIZE * 4 * 0.2), fill=255)
        tile_mask = tile_mask.resize((SIZE, SIZE), Image.LANCZOS)
        small = src.resize((round(SIZE * 0.6),) * 2, Image.LANCZOS)
        glyph_src = Image.new("RGBA", (SIZE, SIZE))
        glyph_src.paste(small, ((SIZE - small.width) // 2,) * 2)

    gp = glyph_src.load()
    diffs = []
    L = [[0.0] * SIZE for _ in range(SIZE)]
    A = [[0.0] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            p = gp[x, y]
            l = lum(p)
            L[y][x] = l
            if bg_l is None:
                A[y][x] = p[3] / 255
            else:
                d = abs(l - bg_l)
                A[y][x] = d
                if p[3] > 200:
                    diffs.append(d)
    if bg_l is not None:
        diffs.sort()
        top = diffs[int(len(diffs) * 0.97)] if diffs else 1
        gain = 1 / max(0.18, top)
        ta = tile_mask.load()
        for y in range(SIZE):
            for x in range(SIZE):
                A[y][x] = min(1.0, A[y][x] * gain) ** 0.8 * ta[x, y] / 255

    # Tile: translucent glass in the tint (tinted) or neutral (clear), with a rim highlight.
    if style == "tinted":
        if dark:
            tile_rgb, tile_a = mix(tint, (0, 0, 0), 0.55), 0.55
            hi, lo = mix(tint, (255, 255, 255), 0.72), mix(tint, (255, 255, 255), 0.35)
        else:
            tile_rgb, tile_a = mix(tint, (255, 255, 255), 0.82), 0.70
            hi, lo = tint, mix(tint, (0, 0, 0), 0.35)
    else:
        tile_rgb = (255, 255, 255) if not dark else (60, 60, 64)
        tile_a = 0.30 if dark else 0.40
        hi, lo = ((250, 250, 250), (200, 200, 205)) if dark else ((70, 70, 75), (25, 25, 30))

    out = Image.new("RGBA", (SIZE, SIZE))
    op = out.load()
    tm = tile_mask.load()
    for y in range(SIZE):
        sheen = 1 + 0.25 * (1 - y / SIZE)          # a touch brighter at the top
        for x in range(SIZE):
            t = tm[x, y] / 255
            if t <= 0 and A[y][x] <= 0:
                continue
            base = tuple(min(255, round(c * sheen)) for c in tile_rgb)
            ga = A[y][x]
            col = mix(lo, hi, L[y][x] if (bg_l is None or bg_l < 0.5) else 1 - L[y][x])
            a_tile = t * tile_a
            a = ga + a_tile * (1 - ga)
            rgb = mix(base, col, ga / a) if a > 0 else base
            op[x, y] = rgb + (round(a * 255),)

    rim = ImageChops.subtract(tile_mask, tile_mask.filter(ImageFilter.MinFilter(3)))
    edge = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    edge.putalpha(rim.point(lambda v: v * (0.35 if dark else 0.6)))
    return Image.alpha_composite(out, edge)


def bordered(src):
    """The icon as it is, with a thin light rim hugging its outline and a soft dark halo."""
    a = src.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(5))
    rim = ImageChops.subtract(grown, a)
    out = Image.new("RGBA", (SIZE, SIZE))
    halo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    halo.putalpha(grown.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(5)).point(lambda v: v * 0.35))
    out = Image.alpha_composite(out, halo)
    edge = Image.new("RGBA", (SIZE, SIZE), (235, 235, 240, 0))
    edge.putalpha(rim.point(lambda v: v * 0.55))
    out = Image.alpha_composite(out, edge)
    return Image.alpha_composite(out, src)


def make(job):
    name, path, dst = job
    if not os.path.isfile(dst):
        try:
            img = load(path)
            (bordered(img) if style == "border" else render(img)).save(dst + f".{os.getpid()}-{threading.get_ident()}.tmp.png")
            os.replace(dst + f".{os.getpid()}-{threading.get_ident()}.tmp.png", dst)
        except Exception as e:
            print(f"tint-icons: {name}: {e}", file=sys.stderr)
            return name, ""
    return name, dst


if __name__ == "__main__":
    os.makedirs(CACHE, exist_ok=True)
    jobs = []
    for name in dict.fromkeys(names):
        path = resolve(name)
        if not path:
            print(f"{name}\t", flush=True)
            continue
        st = os.stat(path)
        key = hashlib.md5(f"{VERSION}|{style}|{tint_hex}|{dark}|{path}|{st.st_mtime}".encode()).hexdigest()
        dst = f"{CACHE}/{key}.png"
        if os.path.isfile(dst):
            print(f"{name}\t{dst}", flush=True)     # cached: answer straight away
        else:
            jobs.append((name, path, dst))
    if len(jobs) > 1:
        # threads, not processes: the work is mostly magick subprocesses + PIL (releases the GIL),
        # and a process pool re-imports this script in every worker (and hung under forkserver)
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max(1, min(len(jobs), (os.cpu_count() or 2) // 2))) as pool:
            for name, dst in pool.map(make, jobs):
                print(f"{name}\t{dst}", flush=True)
    else:
        for job in jobs:
            name, dst = make(job)
            print(f"{name}\t{dst}", flush=True)
