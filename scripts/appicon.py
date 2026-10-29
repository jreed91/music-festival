#!/usr/bin/env python3
"""Export the app icon, "Yard light", from appicon.svg: one sodium light over black corn
and three fireflies, from the After Dark design system.

The SVG is the source; this only rasterises it to the 1024px PNG the asset catalog wants,
flattened onto black because App Store icons may not have an alpha channel. Needs either
`rsvg-convert` (brew install librsvg) or Python Playwright with Chromium.
"""
import io, json, os, shutil, subprocess, sys
from PIL import Image

CATALOG = sys.argv[1] if len(sys.argv) > 1 else "Hinterland/Resources/Assets.xcassets"
SIZE = 1024
SVG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "appicon.svg")


def render() -> bytes:
    if shutil.which("rsvg-convert"):
        return subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), SVG],
                              check=True, capture_output=True).stdout
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": SIZE, "height": SIZE})
        page.goto("file://" + SVG)
        png = page.screenshot(clip={"x": 0, "y": 0, "width": SIZE, "height": SIZE})
        browser.close()
        return png


img = Image.open(io.BytesIO(render())).convert("RGBA")
flat = Image.new("RGB", img.size, (5, 6, 7))
flat.paste(img, mask=img.split()[3])

out = f"{CATALOG}/AppIcon.appiconset"
os.makedirs(out, exist_ok=True)
flat.save(f"{out}/AppIcon.png", "PNG")
json.dump({
    "images": [{"filename": "AppIcon.png", "idiom": "universal",
                "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
}, open(f"{out}/Contents.json", "w"), indent=2)
print(f"wrote {out}/AppIcon.png")
