"""Draws the MacPulse app icon (original design) and writes a macOS AppIcon set."""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = sys.argv[1]

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def master():
    scale = 4
    W = S * scale
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # macOS icon grid: 824 pt body inside 1024 canvas, corner radius ~185.
    inset, radius = 100 * scale, 185 * scale
    body = (inset, inset, W - inset, W - inset)
    # Vertical gradient: deep teal to indigo.
    grad = Image.new("RGBA", (W, W))
    top, bottom = (18, 160, 150), (40, 52, 140)
    gd = ImageDraw.Draw(grad)
    for y in range(W):
        gd.line([(0, y), (W, y)], fill=lerp(top, bottom, y / W) + (255,))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius=radius, fill=255)
    # Soft shadow under the body.
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((inset, inset + 18 * scale, W - inset, W - inset + 18 * scale), radius=radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * scale))
    img.alpha_composite(shadow)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    cx, cy = W // 2, int(W * 0.53)
    r = int(270 * scale)
    w = int(58 * scale)
    box = (cx - r, cy - r, cx + r, cy + r)
    # Gauge track (270° open at the bottom) and the filled part.
    track = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    td = ImageDraw.Draw(track)
    td.arc(box, start=135, end=405, fill=(255, 255, 255, 255), width=w)
    a = math.radians(405)
    x, y = cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
    td.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=(255, 255, 255, 255))
    track.putalpha(track.getchannel("A").point(lambda a: a * 60 // 255))
    img.alpha_composite(track)
    d = ImageDraw.Draw(img)
    d.arc(box, start=135, end=330, fill=(255, 255, 255, 255), width=w)
    # Round caps.
    for ang in (135, 330):
        a = math.radians(ang)
        rr = r - w / 2
        x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=(255, 255, 255, 255))
    # Pulse line across the middle of the gauge.
    pts = [(-200, 0), (-80, 0), (-40, -110), (10, 120), (55, -40), (85, 0), (200, 0)]
    line = [(cx + x * scale, cy + y * scale) for x, y in pts]
    lw = int(30 * scale)
    d.line(line, fill=(255, 214, 92, 255), width=lw, joint="curve")
    for x, y in (line[0], line[-1]):
        d.ellipse((x - lw / 2, y - lw / 2, x + lw / 2, y + lw / 2), fill=(255, 214, 92, 255))
    return img.resize((S, S), Image.LANCZOS)

m = master()
os.makedirs(out, exist_ok=True)
images = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = pt * sc
        name = f"icon_{pt}x{pt}{'@2x' if sc == 2 else ''}.png"
        m.resize((px, px), Image.LANCZOS).save(os.path.join(out, name), optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(out, "Contents.json"), "w"), indent=2)
m.save("/tmp/icon_preview.png")
