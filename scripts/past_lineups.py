#!/usr/bin/env python3
"""Scrape every past Hinterland lineup into Data/past-lineups.json.

The site keeps one accordion per year, each holding a block per day: the headliner as a
heading, everyone else under it as a rich-text list. That structure is the whole data
model here — the page never says which calendar day a block was, so neither does the JSON.

The posters alongside each year are deliberately left on the site. They are a wall of
type at phone size, and every name on them is in the bill this writes out.
"""
import re, json, os, sys, datetime

from festival_source import page, clean

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "past-lineups.json")
SOURCE = "https://www.hinterlandiowa.com/past-lineups"
REFRESH = "--refresh" in sys.argv

# One accordion per year: `<div id="2025" class="dropdown">` through to the next one.
YEAR = re.compile(r'(?s)<div id="(?P<year>\d{4})" class="dropdown">'
                  r'(?P<body>.*?)(?=<div id="\d{4}" class="dropdown">|</main>)')
# A day: the headliner in the heading, the rest of the bill in the rich text under it.
# Webflow emits the unfilled slots of the template too, with both fields empty.
DAY = re.compile(r'(?s)<div class="past-lineup_flex[^"]*">'
                 r'<h3 class="h4[^"]*">(?P<headliner>.*?)</h3>'
                 r'<div class="(?:w-dyn-bind-empty )?w-richtext">(?P<bill>.*?)</div>')

# Side-stage billing is printed after the name, in brackets: "Joe Pera (Campfire Stage)".
STAGE = re.compile(r"^(?P<name>.+?)\s*\((?P<stage>[^()]*Stage)\)$")
# The 2025 bill has one of these. Left as-is it reads as a fourth stage in the app, which
# picks its stage colours by name, and sorts apart from that night's other Campfire sets.
STAGE_FIXES = {"Campire Stage": "Campfire Stage"}


def acts(bill):
    """Names in a day's rich text, with the stage split off where one is given.

    Webflow pads the shorter bills with paragraphs holding a zero-width joiner, which is
    a paragraph with nothing in it as far as anyone reading this is concerned.
    """
    parsed = []
    for paragraph in re.findall(r"<p>(.*?)</p>", bill, re.S):
        name = clean(paragraph).replace("‍", "").strip()
        if not name:
            continue
        match = STAGE.match(name)
        if not match:
            parsed.append({"name": name})
            continue
        stage = clean(match.group("stage"))
        parsed.append({"name": clean(match.group("name")),
                       "stage": STAGE_FIXES.get(stage, stage)})
    return parsed


source = page("/past-lineups", refresh=REFRESH)

years = []
for match in YEAR.finditer(source):
    year = int(match.group("year"))
    days = []
    for index, block in enumerate(DAY.finditer(match.group("body")), start=1):
        headliner = clean(block.group("headliner"))
        if not headliner:
            continue                      # an unfilled slot in the year's template
        days.append({"id": f"{year}-{index}",
                     "headliner": headliner,
                     "support": acts(block.group("bill"))})
    if days:
        years.append({"year": year, "days": days})

if not years:
    sys.exit("No lineups parsed — the past lineups page markup probably changed.")

data = {
    "version": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "source": SOURCE,
    # Newest first, which is the order the page uses and the order they're read in.
    "years": sorted(years, key=lambda entry: -entry["year"]),
}
with open(OUT, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)

total = sum(1 + len(day["support"]) for entry in years for day in entry["days"])
print(f'{OUT}: {len(years)} years, {total} acts')
for entry in data["years"]:
    print(f'  {entry["year"]}  {len(entry["days"])} days · '
          f'{sum(1 + len(day["support"]) for day in entry["days"]):3} acts · '
          f'{" / ".join(day["headliner"] for day in entry["days"])}')
