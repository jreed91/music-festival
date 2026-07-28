#!/usr/bin/env python3
"""Generate the app icon: a sunset over the amphitheater's rolling Iowa hills."""
import json, os, sys, math
from PIL import Image, ImageDraw

CATALOG = sys.argv[1] if len(sys.argv) > 1 else "Hinterland/Resources/Assets.xcassets"
SIZE = 1024
S = 4  # supersample factor for clean curves

W = SIZE * S
img = Image.new("RGB", (W, W), (13, 13, 18))
d = ImageDraw.Draw(img)

# Dusk sky, deep indigo at the top warming toward the horizon.
horizon = int(W * 0.62)
top, bottom = (26, 22, 54), (250, 150, 66)
for y in range(horizon):
    t = (y / horizon) ** 1.7
    d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

# Ground plane, so nothing shows through between the horizon and the first hill crest.
d.rectangle([0, horizon, W, W], fill=(92, 58, 92))

# Setting sun.
sun_r, sun_y = int(W * 0.15), int(horizon - W * 0.05)
for i in range(sun_r, 0, -1):
    t = i / sun_r
    d.ellipse([W // 2 - i, sun_y - i, W // 2 + i, sun_y + i],
              fill=(255, round(214 - 40 * (1 - t)), round(120 - 40 * (1 - t))))

# A few stars in the darkest part of the sky.
for x, y, r in [(0.17, 0.10, 3.5), (0.31, 0.19, 2.5), (0.72, 0.09, 3.0),
                (0.85, 0.21, 2.5), (0.55, 0.05, 2.5), (0.09, 0.27, 2.0)]:
    cx, cy, rr = x * W, y * W, r * S
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 246, 224))

# Layered hills, receding into haze. Each layer is flooded to the bottom edge, and the
# farthest one starts above the horizon so no sky shows through the troughs.
def hill(y_base, amp, phase, color):
    pts = [(x, y_base + amp * math.sin(x / W * math.pi * 1.6 + phase))
           for x in range(0, W + 1, 8)]
    d.polygon([(0, W)] + pts + [(W, W)], fill=color)

hill(horizon + W * 0.055, W * 0.045, 0.4, (92, 58, 92))
hill(horizon + W * 0.135, W * 0.055, 2.1, (56, 36, 68))
hill(horizon + W * 0.235, W * 0.050, 3.6, (28, 20, 40))

img = img.resize((SIZE, SIZE), Image.LANCZOS)

out = f"{CATALOG}/AppIcon.appiconset"
os.makedirs(out, exist_ok=True)
img.save(f"{out}/AppIcon.png", "PNG")
json.dump({
    "images": [{"filename": "AppIcon.png", "idiom": "universal",
                "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
}, open(f"{out}/Contents.json", "w"), indent=2)
print(f"wrote {out}/AppIcon.png")
