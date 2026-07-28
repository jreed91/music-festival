#!/usr/bin/env python3
"""Bundle the festival maps into the asset catalog and record them in Data/info.json.

The guide scraper throws away the images inside each topic's rich text, which is right
for photography but drops the maps — the one thing you most want on a phone with no
signal. This pulls the map artwork out of the same page and bundles it.

Requires Pillow (`pip install Pillow`). Run after guide.py, since it writes the map list
into the info.json that guide.py rewrites wholesale.
"""
import json, os, re, sys, urllib.request
from PIL import Image

from festival_source import UA, page, full_res

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO = os.path.join(ROOT, "Data", "info.json")
CATALOG = os.path.join(ROOT, "Hinterland", "Resources", "Assets.xcassets", "Maps")
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache", "maps")
REFRESH = "--refresh" in sys.argv
MAX_WIDTH = 2000   # legible when pinched right in, without a 3 MB asset per map

# The site posts maps and photographs through the same rich-text field, so pick the maps
# out by the file name the festival's designer gives them. `topic` is the guide entry the
# map belongs to, which is how the app shows it inline while you're reading that topic.
MAPS = [
    {
        "id": "grounds",
        "title": "Festival Grounds",
        "caption": "Stages, camping, parking and the two entrances.",
        "match": "Grounds_Map",
        "topic": "festival-maps",
    },
    {
        "id": "concourse",
        "title": "Concourse",
        "caption": "Inside the gates: stage, vendors, water, toilets and medical.",
        "match": "Concourse_Map",
        "topic": "festival-maps",
    },
    {
        "id": "route",
        "title": "Driving Routes",
        "caption": "Exit 56 north for camping and 4-day parking, Exit 47 south for "
                   "single-day. Exit 52 off-ramps are closed.",
        "match": "Route.webp",
        "topic": "driving-parking",
    },
    {
        "id": "shuttle",
        "title": "Shuttle Parking",
        "caption": "Des Moines shuttle pickup at DMACC, SE Ankeny.",
        "match": "Shuttle.webp",
        "topic": "des-moines-shuttle",
    },
]


def figures(html_source):
    """Every image URL that appears inside a rich-text <figure> on the info page."""
    found = []
    for figure in re.finditer(r"<figure[^>]*>.*?</figure>", html_source, re.S):
        found += re.findall(r'<img[^>]+src="([^"]+)"', figure.group(0))
    return [full_res(url) for url in found]


def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=60) as response:
        with open(path, "wb") as handle:
            handle.write(response.read())


os.makedirs(RAW, exist_ok=True)
os.makedirs(CATALOG, exist_ok=True)

candidates = figures(page("/info", refresh=REFRESH))
if not candidates:
    sys.exit("No rich-text images found — the info page markup probably changed.")

bundled, missing = [], []
for spec in MAPS:
    url = next((u for u in candidates if spec["match"].lower() in u.lower()), None)
    if not url:
        missing.append(spec["id"])
        continue

    original = os.path.join(RAW, f'{spec["id"]}.img')
    download(url, original)

    image = Image.open(original).convert("RGB")
    if image.width > MAX_WIDTH:
        height = round(image.height * MAX_WIDTH / image.width)
        image = image.resize((MAX_WIDTH, height), Image.LANCZOS)

    name = f'map-{spec["id"]}'
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.jpg"), "JPEG",
               quality=88, optimize=True, progressive=True)
    with open(os.path.join(folder, "Contents.json"), "w") as out:
        json.dump({
            "images": [{"filename": f"{name}.jpg", "idiom": "universal", "scale": "2x"}],
            "info": {"author": "xcode", "version": 1},
        }, out, indent=2)

    bundled.append({
        "id": spec["id"],
        "title": spec["title"],
        "caption": spec["caption"],
        "asset": name,
        "topicID": spec["topic"],
        "width": image.width,
        "height": image.height,
        "sourceURL": url,
    })

if missing:
    sys.exit(f"Maps not found on the info page: {', '.join(missing)} — "
             "the artwork was probably renamed. Update MAPS in scripts/maps.py.")

with open(os.path.join(CATALOG, "Contents.json"), "w") as out:
    json.dump({"info": {"author": "xcode", "version": 1}}, out, indent=2)

with open(INFO, encoding="utf-8") as handle:
    info = json.load(handle)
info["maps"] = bundled
with open(INFO, "w", encoding="utf-8") as handle:
    json.dump(info, handle, indent=2, ensure_ascii=False)

total = sum(os.path.getsize(os.path.join(root, name))
            for root, _, names in os.walk(CATALOG) for name in names)
print(f"{len(bundled)} maps bundled ({total / 1024 / 1024:.1f} MB)")
for entry in bundled:
    print(f'  {entry["title"]:20} {entry["width"]}x{entry["height"]}')
