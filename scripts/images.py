#!/usr/bin/env python3
"""Download artist artwork and build the bundled asset catalog.

Requires Pillow (`pip install Pillow`). Run after scrape.py, since it reads the artist
list from Data/schedule.json and writes each artist's asset name back into it.
"""
import json, os, urllib.request
from PIL import Image

from festival_source import UA

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEDULE = os.path.join(ROOT, "Data", "schedule.json")
CATALOG = os.path.join(ROOT, "Hinterland", "Resources", "Assets.xcassets")
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache", "images")
MAX_WIDTH = 900   # ~2x a full-width phone card; keeps the bundle a few megabytes

os.makedirs(RAW, exist_ok=True)
with open(SCHEDULE, encoding="utf-8") as handle:
    data = json.load(handle)

for artist in data["artists"]:
    url = artist.get("imageURL")
    if not url:
        continue

    original = os.path.join(RAW, f'{artist["id"]}.img')
    if not os.path.exists(original) or os.path.getsize(original) < 1000:
        request = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(request, timeout=30) as response:
            with open(original, "wb") as out:
                out.write(response.read())

    image = Image.open(original).convert("RGB")
    if image.width > MAX_WIDTH:
        height = round(image.height * MAX_WIDTH / image.width)
        image = image.resize((MAX_WIDTH, height), Image.LANCZOS)

    name = f'artist-{artist["id"]}'
    folder = os.path.join(CATALOG, "Artists", f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.jpg"), "JPEG",
               quality=82, optimize=True, progressive=True)
    with open(os.path.join(folder, "Contents.json"), "w") as out:
        json.dump({
            "images": [{"filename": f"{name}.jpg", "idiom": "universal", "scale": "2x"}],
            "info": {"author": "xcode", "version": 1},
        }, out, indent=2)

    artist["imageAsset"] = name

for folder in (CATALOG, os.path.join(CATALOG, "Artists")):
    with open(os.path.join(folder, "Contents.json"), "w") as out:
        json.dump({"info": {"author": "xcode", "version": 1}}, out, indent=2)

with open(SCHEDULE, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)

total = sum(os.path.getsize(os.path.join(root, name))
            for root, _, names in os.walk(os.path.join(CATALOG, "Artists"))
            for name in names)
bundled = len([a for a in data["artists"] if a.get("imageAsset")])
print(f"{bundled} artist images bundled ({total / 1024 / 1024:.1f} MB)")
