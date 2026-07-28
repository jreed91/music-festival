#!/usr/bin/env python3
"""Scrape the food & drink vendor directory into Data/vendors.json.

The vendor list lives on its own page rather than in the guide CMS, so it needs its own
pass: `/food-drink` groups vendors under the part of the site they're parked in (East
Concourse, GA+, Basecamp, and so on), and each card carries the vendor's home town, what
they're selling, and a set of dietary codes.
"""
import re, html, json, os, sys

from festival_source import page, slug

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "vendors.json")
SOURCE = "https://www.hinterlandiowa.com/food-drink"
REFRESH = "--refresh" in sys.argv

# The site prints bare codes with no legend. These are the ones it uses; an unknown code
# is worth failing on rather than dropping, since it would vanish from the app's filter.
DIETARY = {"GF": "Gluten-free", "DF": "Dairy-free", "VG": "Vegan",
           "V": "Vegetarian", "NF": "Nut-free", "SF": "Sugar-free"}

SECTION = re.compile(
    r'(?s)vendor-location-heading">(?P<area>[^<]*)<(?P<body>.*?)(?=vendor-location-heading">|$)')
CARD = re.compile(
    r'(?s)<div class="food-vendor-card">(?P<card>.*?)(?=<div role="listitem"|\Z)')
NAME = re.compile(r'(?s)food-vendor-name-link">.*?<a href="(?P<url>[^"]*)"[^>]*>(?P<name>.*?)</a>')
CITY = re.compile(r'(?s)food-vendor-city-state-2">(?P<cell>.*?)</div></div>')
OFFERINGS = re.compile(r'(?s)vendor-offerings">(?P<text>.*?)</div>')
DIETARY_FIELD = re.compile(r'(?s)vendor-dietary">.*?</div><div>(?P<text>.*?)</div>')


def text(fragment):
    return html.unescape(re.sub(r"(?s)<[^>]+>", "", fragment)).replace("\xa0", " ").strip()


def link(url):
    """Drop the placeholder hrefs and the one typo'd host the site ships with."""
    url = url.strip()
    host = re.sub(r"^https?://", "", url).split("/")[0]
    if not url.startswith("http") or not re.match(r"^[\w.-]+\.[a-z]{2,}$", host, re.I):
        return None
    # Several are typed with a capitalised host ("https://Morub.com"), which is legal but
    # looks like a mistake next to the rest.
    return url.replace(host, host.lower(), 1)


def dietary(raw):
    """"GF option, DF, VG" -> always-available codes and option-only codes."""
    if not raw or "," not in raw and raw.upper() not in DIETARY:
        return [], [], raw or None       # free text like "Various Offerings"

    always, options, unknown = [], [], []
    for token in raw.split(","):
        token = token.strip()
        code, _, qualifier = token.partition(" ")
        code = code.upper()
        if code not in DIETARY:
            unknown.append(token)
        elif qualifier.strip().lower().startswith("option"):
            options.append(code)
        else:
            always.append(code)

    if unknown:
        sys.exit(f"Unknown dietary code(s) {unknown} in '{raw}' — update DIETARY.")
    return always, options, None


src = page("/food-drink", refresh=REFRESH)

areas, total = [], 0
for section in SECTION.finditer(src):
    area = html.unescape(section.group("area")).strip()
    vendors = []

    for match in CARD.finditer(section.group("body")):
        card = match.group("card")
        name = NAME.search(card)
        offerings = OFFERINGS.search(card)
        if not name:
            continue

        city = CITY.search(card)
        parts = [p for p in (text(city.group("cell")) if city else "").split(",")]
        raw_dietary = DIETARY_FIELD.search(card)
        always, options, note = dietary(text(raw_dietary.group("text")) if raw_dietary else "")

        vendor = {
            "id": slug(text(name.group("name"))),
            "name": text(name.group("name")),
            "offerings": text(offerings.group("text")) if offerings else "",
        }
        if len(parts) == 2 and parts[0].strip():
            vendor["city"] = parts[0].strip()
            vendor["state"] = parts[1].strip()
        if always:
            vendor["dietary"] = always
        if options:
            vendor["dietaryOptions"] = options
        if note:
            vendor["dietaryNote"] = note
        if url := link(name.group("url")):
            vendor["url"] = url
        vendors.append(vendor)

    if vendors:
        areas.append({"id": slug(area), "name": area, "vendors": vendors})
        total += len(vendors)

if not areas:
    sys.exit("No vendors parsed — the food & drink page markup probably changed.")

data = {
    "version": 1,
    "source": SOURCE,
    "dietaryLegend": DIETARY,
    "areas": areas,
}

with open(OUT, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)

print(f"{OUT}: {total} vendors in {len(areas)} areas")
for area in areas:
    print(f'  {area["name"]:22} {len(area["vendors"]):2}')
