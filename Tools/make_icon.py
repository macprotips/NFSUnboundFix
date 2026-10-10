"""Draws the NFS Unbound Fix app icon into Resources/AppIcon.iconset.

A classic tan bandage on wheels, speeding along: one object on a blue tile, lit from above,
following Apple's macOS icon grid (an 824 pt continuous-corner tile on a 1024 pt canvas).

    pip install pillow
    python3 Tools/make_icon.py
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4096  # drawn at 4x of 1024, then scaled down for smooth edges
U = S / 1024  # one point on the 1024 pt icon grid
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "AppIcon.iconset")

TILE_TOP = (64, 150, 255)
TILE_BOTTOM = (18, 84, 214)
BANDAGE_TOP = (246, 206, 160)
BANDAGE_BOTTOM = (226, 176, 126)
PAD_TOP = (255, 252, 247)
PAD_BOTTOM = (238, 229, 219)
HOLE = (196, 142, 96)
TYRE_TOP = (64, 60, 66)
TYRE_BOTTOM = (26, 24, 28)
RIM_TOP = (246, 247, 250)
RIM_BOTTOM = (196, 200, 210)
CAP = (150, 156, 170)
SHADOW = (0, 30, 110)


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def gradient(top, bottom, y0=0, y1=S):
    """A vertical gradient, flat outside y0…y1."""
    column = Image.new("RGBA", (1, S))
    for y in range(S):
        t = min(max((y - y0) / max(y1 - y0, 1), 0), 1)
        column.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return column.resize((S, S))


def fill(mask, top, bottom, y0, y1):
    image = gradient(top, bottom, y0, y1)
    image.putalpha(mask)
    return image


def squircle(box, n=4.0):
    """Apple's continuous-corner tile, approximated by a superellipse."""
    x0, y0, x1, y1 = box
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    points = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        points.append((cx + a * math.copysign(abs(c) ** (2 / n), c), cy + b * math.copysign(abs(s) ** (2 / n), s)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def shape(draw_fn):
    mask = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(mask))
    return mask


def shadow_from(mask, dy, blur, opacity, color=SHADOW):
    shadow = layer()
    shadow.paste(color + (255,), (0, 0), ImageChops.offset(mask, 0, int(dy)).point(lambda v: int(v * opacity)))
    return shadow.filter(ImageFilter.GaussianBlur(blur))


def draw_car():
    """The car, level and centred on the canvas. Returns the car layer and its silhouette."""
    car = layer()
    cx, cy = S / 2, S / 2
    w, h = 520 * U, 176 * U
    body_box = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)

    # Wheels sit behind the body, so the body's lower edge reads as wheel arches.
    wheel_r = 88 * U
    wheel_y = cy + h / 2 + 22 * U
    wheels = [(cx - 168 * U, wheel_y), (cx + 168 * U, wheel_y)]

    def draw_wheels(d):
        for x, y in wheels:
            d.ellipse((x - wheel_r, y - wheel_r, x + wheel_r, y + wheel_r), fill=255)

    wheel_mask = shape(draw_wheels)
    car = Image.alpha_composite(car, fill(wheel_mask, TYRE_TOP, TYRE_BOTTOM, wheel_y - wheel_r, wheel_y + wheel_r))
    for x, y in wheels:
        rim_r, cap_r = wheel_r * 0.5, wheel_r * 0.17
        rim = shape(lambda d: d.ellipse((x - rim_r, y - rim_r, x + rim_r, y + rim_r), fill=255))
        car = Image.alpha_composite(car, fill(rim, RIM_TOP, RIM_BOTTOM, y - rim_r, y + rim_r))
        cap = layer()
        ImageDraw.Draw(cap).ellipse((x - cap_r, y - cap_r, x + cap_r, y + cap_r), fill=CAP + (255,))
        car = Image.alpha_composite(car, cap)

    # Body: a soft white bandage, lit from above, casting a faint shade onto the wheels.
    body_mask = shape(lambda d: d.rounded_rectangle(body_box, radius=h / 2, fill=255))
    car = Image.alpha_composite(car, shadow_from(body_mask, 10 * U, 10 * U, 0.35, (0, 0, 0)))
    car = Image.alpha_composite(car, fill(body_mask, BANDAGE_TOP, BANDAGE_BOTTOM, body_box[1], body_box[3]))

    # Pad, plain, like the real thing.
    pw, ph = 168 * U, 108 * U
    pad_box = (cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2)
    pad_mask = shape(lambda d: d.rounded_rectangle(pad_box, radius=22 * U, fill=255))
    car = Image.alpha_composite(car, fill(pad_mask, PAD_TOP, PAD_BOTTOM, pad_box[1], pad_box[3]))
    holes = layer()
    hd = ImageDraw.Draw(holes)
    r = 7 * U
    for dx in (-196, -164, -132, 132, 164, 196):
        for dy in (-34, 0, 34):
            x, y = cx + dx * U, cy + dy * U
            hd.ellipse((x - r, y - r, x + r, y + r), fill=HOLE + (255,))
    car = Image.alpha_composite(car, holes)

    # Two speed lines trailing behind.
    lines = layer()
    ld = ImageDraw.Draw(lines)
    for dy, length in ((-34, 92), (30, 128)):
        y = cy + dy * U
        x1 = body_box[0] - 30 * U
        ld.rounded_rectangle((x1 - length * U, y - 13 * U, x1, y + 13 * U), radius=13 * U,
                             fill=(255, 255, 255, 150))
    car = Image.alpha_composite(lines, car)

    silhouette = ImageChops.lighter(body_mask, wheel_mask)
    return car, silhouette


def draw_icon():
    icon = layer()
    tile_box = (100 * U, 100 * U, 924 * U, 924 * U)
    tile_mask = squircle(tile_box)

    # Drop shadow under the tile, as on other macOS app icons.
    icon = Image.alpha_composite(icon, shadow_from(tile_mask, 10 * U, 12 * U, 0.3, (0, 0, 0)))

    tile = fill(tile_mask, TILE_TOP, TILE_BOTTOM, tile_box[1], tile_box[3])

    # The car leans back a little, nose up, as if accelerating. Nudged right so the car and
    # its speed lines sit on the optical centre together.
    car, silhouette = draw_car()
    angle = 4
    car = car.rotate(angle, resample=Image.BICUBIC, center=(S / 2, S / 2))
    silhouette = silhouette.rotate(angle, resample=Image.BICUBIC, center=(S / 2, S / 2))
    offset = (int(30 * U), int(-34 * U))
    car = ImageChops.offset(car, *offset)
    silhouette = ImageChops.offset(silhouette, *offset)

    # Soft contact shadow on the tile, cast straight down by the light from above.
    tile = Image.alpha_composite(tile, shadow_from(silhouette, 26 * U, 22 * U, 0.32))
    tile = Image.alpha_composite(tile, car)

    clipped = layer()
    clipped.paste(tile, (0, 0), ImageChops.multiply(tile.getchannel("A"), tile_mask))
    icon = Image.alpha_composite(icon, clipped)

    # Faint highlight along the tile's top edge, fading out down the sides.
    inner = squircle((tile_box[0] + 3 * U, tile_box[1] + 3 * U, tile_box[2] - 3 * U, tile_box[3] - 3 * U))
    ring = ImageChops.subtract(tile_mask, inner)
    fade = gradient((90,) * 3, (0,) * 3, tile_box[1], tile_box[1] + 300 * U).getchannel("R")
    edge = layer()
    edge.paste((255, 255, 255, 255), (0, 0), ImageChops.multiply(ring, fade))
    return Image.alpha_composite(icon, edge)


def main():
    os.makedirs(OUT, exist_ok=True)
    icon = draw_icon()
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon_{size}x{size}.png"))
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(OUT, f"icon_{size}x{size}@2x.png"))


if __name__ == "__main__":
    main()
