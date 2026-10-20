"""Build the ForeverSim window art (TGA textures and ForeverSimBridge/UI/ArtData.lua) from the art pack.

    python _dev/tools/build_media.py --pack <ForeverSim_Compact_ArtPack> --crystal <ForeverCore_Icon>

The pack and the icon are the user's own art (not in the repository); the generated textures are. The tool is
deterministic: the same inputs give the same files. What it makes:

* the window frame, drawn once at its fixed size (1290 x 800) with the curved top edge, cut into power-of-two tiles
* seven race banners, nine round class icons, the ForeverCore crystal (connected / not connected)
* the pack's buttons, dropdown, checkbox and panels, copied with their texture coordinates

A TGA texture in WoW must have power-of-two sides, so every image sits in the top-left corner of such a canvas and
ArtData.lua records the coordinates of the used part.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'ForeverSimBridge' / 'Media' / 'UI'
LUA = ROOT / 'ForeverSimBridge' / 'UI' / 'ArtData.lua'

# ---- the window ----------------------------------------------------------------------------------------------
W, H = 1290, 800
DY = 28                                   # how far the two corners sit below the window top; larger = flatter arc
TIP_L, TIP_R, TIP_Y = 332.6, 962.8, 101.3  # where the curve meets the spikes of the logo plaque (banner pixels 117/905)
BORDERS = (104, 124, 74, 124)             # top, right, bottom, left border of the frame in the window
SLICES = (122, 146, 87, 146)              # the same borders measured in the panel image
TILE_COLUMNS, TILE_ROWS = (1024, 256, 16), (512, 256, 32)

RACES = ['orc_troll', 'undead', 'tauren', 'human', 'dwarf_gnome', 'nightelf', 'skyborn']
CLASSES = ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid']
# pack frames used by the addon as they are (texture canvas and used part come from texture_manifest.json)
FRAMES = ['button_normal', 'button_glow', 'button_active', 'dropdown', 'checkbox', 'panel_wide_small', 'panel_square_medium',
          'notification_panel', 'portrait_round']


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def tile(img, box, x0, x1, y0, y1):
    """Repeat the part `box` of img over the area x0..x1, y0..y1."""
    piece = img.crop(box)
    for x in range(x0, x1, piece.width):
        img.paste(piece.crop((0, 0, min(piece.width, x1 - x), y1 - y0)), (x, y0))


def clean_panel(panel):
    """The pack's main panel without the gems at the middle of its top and bottom edge, so it can stretch."""
    out = panel.copy()
    tile(out, (200, 0, 260, 90), 290, 600, 0, 90)
    tile(out, (250, 476, 310, 511), 360, 520, 476, 511)
    out.paste(panel.crop((200, 86, 240, 100)), (418, 86))
    return out


def bezier(p0, p1, p2, p3, n=120):
    t = np.linspace(0, 1, n)[:, None]
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def curve():
    """The polyline of the swept top edge: medallion corner, down to the plaque, up to the crystal corner."""
    ye = TIP_Y - 5.5
    pt = lambda *p: np.array(p, float)
    left = bezier(pt(132, 24 + DY), pt(192, 8 + DY), pt(TIP_L - 85, ye), pt(TIP_L, ye))
    right = bezier(pt(TIP_R, ye), pt(TIP_R + 85, ye), pt(W - 192, 8 + DY), pt(W - 132, 24 + DY))
    return np.vstack([[(70, 36 + DY)], left, right, [(W - 70, 36 + DY)]])


def top_line(clean, pts):
    """The gold line with its two blue lines, bent along the curve; its profile is the panel's own straight edge."""
    col = np.asarray(clean).astype(float)[:, 430, :]
    r0, dmax, oy = 58.0, 44.0, 20
    ys, xs = np.mgrid[0:200, 0:W].astype(float)
    ys -= oy
    best = np.full(xs.shape, 1e9)
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy or 1
        t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / length, 0, 1)
        best = np.minimum(best, np.hypot(xs - (ax + t * dx), ys - (ay + t * dy)))
    sign = np.where(ys > np.interp(xs[0], pts[:, 0], pts[:, 1])[None, :], 1, -1)
    d = best * sign
    rows = r0 + np.clip(d, 0, dmax)
    lo = np.floor(rows).astype(int)
    f = (rows - lo)[..., None]
    pix = col[lo] * (1 - f) + col[lo + 1] * f
    alpha = pix[..., 3] / 255 * np.clip(1 + d, 0, 1) * np.clip((dmax - d) / 5, 0, 1)
    return Image.fromarray(np.dstack([pix[..., :3], alpha * 255]).clip(0, 255).astype(np.uint8), 'RGBA')


def nine_slice(src, slices, borders, size):
    """What CSS `border-image: url() <slices> fill` with the given border widths draws: corners at border size,
    edges and middle stretched."""
    st, sr, sb, sl = slices
    bt, br, bb, bl = borders
    w, h = size
    sw, sh = src.size
    xs, ys = [0, sl, sw - sr, sw], [0, st, sh - sb, sh]
    xd, yd = [0, bl, w - br, w], [0, bt, h - bb, h]
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    for j in range(3):
        for i in range(3):
            piece = src.crop((xs[i], ys[j], xs[i + 1], ys[j + 1]))
            piece = piece.resize((xd[i + 1] - xd[i], yd[j + 1] - yd[j]), Image.LANCZOS)
            out.paste(piece, (xd[i], yd[j]))
    return out


def window_frame(clean):
    panel = clean.copy()
    panel.paste(clean.crop((0, 200, clean.width, 322)).crop((0, 0, clean.width, 122)), (0, 0))   # no top ornaments
    pts = curve()
    ring = nine_slice(panel, SLICES, BORDERS, (W, H))
    # cut along the curve with an anti-aliased mask (drawn 4x larger)
    k = 4
    mask = Image.new('L', (W * k, H * k), 0)
    poly = [(0, H), (0, 60 + DY)] + [(x, y + 2) for x, y in pts] + [(W, 60 + DY), (W, H)]
    ImageDraw.Draw(mask).polygon([(x * k, y * k) for x, y in poly], fill=255)
    mask = mask.resize((W, H), Image.LANCZOS)
    alpha = np.minimum(np.asarray(ring.split()[3]).astype(int), np.asarray(mask).astype(int)).astype(np.uint8)
    ring.putalpha(Image.fromarray(alpha))
    line = top_line(clean, pts).crop((0, 20, W, 200))      # window y 0 .. 180
    canvas = ring.copy()
    canvas.alpha_composite(line, (0, 0))
    return canvas


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name, 'TGA')


def canvas_of(img):
    """img in the top-left corner of a power-of-two canvas -> (canvas, [u0, u1, v0, v1] of the used part)."""
    cw, ch = pow2(img.width), pow2(img.height)
    canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
    canvas.paste(img, (0, 0))
    return canvas, [0, img.width / cw, 0, img.height / ch]


def round_icon(path, size=128, zoom=1.28):
    """A class emblem cut to a circle, enlarged a little so the circle holds the artwork (as in the mock-up)."""
    img = Image.open(path).convert('RGBA')
    big = int(size * zoom)
    img = img.resize((big, big), Image.LANCZOS)
    off = (big - size) // 2
    img = img.crop((off, off, off + size, off + size))
    k = 4
    mask = Image.new('L', (size * k, size * k), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * k - 1, size * k - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    img.putalpha(Image.fromarray(np.minimum(np.asarray(img.split()[3]).astype(int), np.asarray(mask).astype(int)).astype(np.uint8)))
    return img


def crystal(path, grey):
    img = Image.open(path).convert('RGBA')
    img = img.resize((256, 256), Image.LANCZOS)
    return grey_blue(img) if grey else img


def grey_blue(img):
    """The crystal without its blue: only the blue and cyan parts lose their colour, the gold frame stays."""
    a = np.asarray(img).astype(float) / 255
    rgb = a[..., :3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn + 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    sat = d / (mx + 1e-6)
    w = np.clip((sat - .04) / .12, 0, 1) * np.clip((70 - np.abs(hue - 210)) / 15, 0, 1)
    lum = ((rgb @ np.array([.299, .587, .114])) ** 1.15 * .82)[..., None]
    grey = np.concatenate([lum * .98, lum * 1.0, lum * 1.04], -1)
    out = rgb * (1 - w[..., None]) + grey * w[..., None]
    return Image.fromarray((np.dstack([out, a[..., 3]]) * 255).clip(0, 255).astype(np.uint8), 'RGBA')



def radial(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    c = (size - 1) / 2
    return np.hypot(xs - c, ys - c) / c, np.arctan2(ys - c, xs - c)


def make_badge(size=64):
    """The gold disc behind the step numbers (1, 2, 3)."""
    r, _ = radial(size)
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    hl = np.hypot(xs - size * .38, ys - size * .32) / size      # highlight at the upper left
    t = np.clip(hl / .75, 0, 1)[..., None]
    light, mid, dark = np.array([255, 241, 176.]), np.array([216, 160, 58.]), np.array([122, 82, 16.])
    rgb = np.where(t < .55, light + (mid - light) * (t / .55), mid + (dark - mid) * ((t - .55) / .45))
    alpha = np.clip((0.94 - r) / 0.06, 0, 1)
    rim = np.clip((r - 0.80) / 0.14, 0, 1)[..., None]            # thin dark rim
    rgb = rgb * (1 - .55 * rim)
    return Image.fromarray(np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8), 'RGBA')


def make_glow(size=128):
    """A soft white glow; the addon tints it."""
    r, _ = radial(size)
    a = np.clip(1 - r, 0, 1) ** 2
    return Image.fromarray(np.dstack([np.full((size, size, 3), 255.), a * 255]).clip(0, 255).astype(np.uint8), 'RGBA')


def make_rays(size=256, rays=16):
    """A sunburst: thin rays that fade outwards. Turned slowly behind a proc."""
    r, ang = radial(size)
    step = 2 * np.pi / rays
    d = np.abs(((ang + step / 2) % step) - step / 2) / (step / 2)    # 0 on a ray's axis, 1 between rays
    ray = np.clip(1 - d / .28, 0, 1)
    fall = np.clip((1 - r) / .55, 0, 1) * np.clip((r - .30) / .12, 0, 1)
    a = ray * fall
    return Image.fromarray(np.dstack([np.full((size, size, 3), 255.), a * 255]).clip(0, 255).astype(np.uint8), 'RGBA')


def lua_table(entries):
    lines = ['-- Generated by _dev/tools/build_media.py from the ForeverSim art pack. Do not edit.',
             '-- name = {file, texture width/height, used width/height, {left,right,top,bottom} texture coordinates}',
             'ForeverSimArt=ForeverSimArt or{}',
             'local A=ForeverSimArt',
             "A.dir='Interface\\\\AddOns\\\\ForeverSimBridge\\\\Media\\\\UI\\\\'"]
    for name, e in entries.items():
        c = ','.join(('%.6f' % v).rstrip('0').rstrip('.') for v in e['coords'])
        extra = f",x={e['x']},y={e['y']}" if 'x' in e else ''
        lines.append(f"A['{name}']={{file='{e['file']}',tw={e['tw']},th={e['th']},w={e['w']},h={e['h']},coords={{{c}}}{extra}}}")
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--pack', required=True, type=Path)
    ap.add_argument('--crystal', required=True, type=Path)
    a = ap.parse_args()
    manifest = {(e['category'], e['name'], tuple(e['size'])): e for e in json.loads((a.pack / 'texture_manifest.json').read_text())}
    entries = {}

    def add(name, img, file=None):
        canvas, coords = canvas_of(img)
        file = file or name + '.tga'
        save(canvas, file)
        entries[name] = {'file': file, 'tw': canvas.width, 'th': canvas.height, 'w': img.width, 'h': img.height, 'coords': coords}

    clean = clean_panel(Image.open(a.pack / 'Frames/PNG/main_panel.png').convert('RGBA'))
    frame = window_frame(clean)
    # window frame tiles
    y = 0
    for row, th in enumerate(TILE_ROWS):
        x = 0
        for col, tw in enumerate(TILE_COLUMNS):
            part = frame.crop((x, y, min(x + tw, W), min(y + th, H)))
            canvas = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
            canvas.paste(part, (0, 0))
            name = f'frame_{row}{col}'
            save(canvas, name + '.tga')
            entries[name] = {'file': name + '.tga', 'tw': tw, 'th': th, 'w': part.width, 'h': part.height,
                             'coords': [0, part.width / tw, 0, part.height / th], 'x': x, 'y': y}
            x += tw
        y += th
    for race in RACES:
        add('banner_' + race, Image.open(a.pack / f'Banners/1024x256/PNG/{race}.png').convert('RGBA'))
    for cls in CLASSES:
        add('class_' + cls, round_icon(a.pack / f'Classes/PNG/{cls}.png'))
    add('crystal_on', crystal(a.crystal / 'ForeverCore.png', False))
    add('crystal_off', crystal(a.crystal / 'ForeverCore.png', True))
    add('badge', make_badge())
    add('glow', make_glow())
    add('rays', make_rays())
    for name in FRAMES:
        png = Image.open(a.pack / f'Frames/PNG/{name}.png').convert('RGBA')
        add(name, png)
    LUA.parent.mkdir(parents=True, exist_ok=True)
    LUA.write_text(lua_table(entries), encoding='utf-8')
    total = sum(f.stat().st_size for f in OUT.glob('*.tga'))
    print(f'{len(entries)} textures, {total / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
