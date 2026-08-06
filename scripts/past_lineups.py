#!/usr/bin/env python3
"""Scrape every past Hinterland lineup into Data/past-lineups.json.

The site keeps one accordion per year, each holding a block per day: the headliner as a
heading, everyone else under it as a rich-text list. That structure is the whole data
model here — the page never says which calendar day a block was, so neither does the JSON.

The posters alongside each year are deliberately left on the site. They are a wall of
type at phone size, and every name on them is in the bill this writes out.

The festival adds a year to that page once the weekend is over, and when it does, that
page is the festival's own account of itself and wins. What it doesn't carry is the side
stages: the published 2026 bill is the Main Stage and nothing else, while `schedule.json`
played 17 sets on Miniland and Campfire. So this year gets folded in from the schedule —
the whole bill when the site hasn't published it yet, and otherwise just the acts its page
leaves out, appended under the main-stage bill where the archive already puts side stages.
"""
import re, json, os, sys, datetime

from festival_source import page, clean, slug

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "past-lineups.json")
SCHEDULE = os.path.join(ROOT, "Data", "schedule.json")
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
# The stage `schedule.json` calls the main one. Everything else on the bill gets printed
# with its stage, which is exactly the archive's own convention.
MAIN_STAGE = "Main Stage"


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


def this_year():
    """`schedule.json` as an archive year, or None while the festival is still to come.

    The archive bills a day by its headliner, which the schedule doesn't label — so the
    last act on the Main Stage takes the heading, the way it sits at the top of a poster.
    Support reads down from there, main stage first and side stages under it: that is the
    order every scraped year is in, and a bill that interleaved the 12.30am Campfire set
    between two main-stage acts would be the one year that reads differently.
    """
    with open(SCHEDULE, encoding="utf-8") as handle:
        schedule = json.load(handle)

    sets = [performance for day in schedule["days"] for performance in day["sets"]]
    if not sets:
        return None
    # Over means the last set has ended, not that the last date has arrived: the closing
    # Campfire set runs past midnight, and the archive shouldn't open while it's playing.
    last = max(datetime.datetime.fromisoformat(performance["end"]) for performance in sets)
    if last > datetime.datetime.now(datetime.timezone.utc):
        return None

    days = []
    for index, day in enumerate(schedule["days"], start=1):
        billing = sorted(day["sets"], key=lambda performance: performance["start"], reverse=True)
        main = [p for p in billing if p["stage"] == MAIN_STAGE]
        if not main:
            # No main stage that day — whatever closed it out headlines instead.
            main = billing[:1]
        headliner, rest = main[0], main[1:] + [p for p in billing if p not in main]
        days.append({"id": f'{schedule["festival"]["year"]}-{index}',
                     "headliner": headliner["artist"],
                     "support": [act(performance) for performance in rest]})

    return {"year": schedule["festival"]["year"], "days": days}


def act(performance):
    """One name on the bill. The archive never spells out the main stage, so nor does this."""
    if performance["stage"] == MAIN_STAGE:
        return {"name": performance["artist"]}
    return {"name": performance["artist"], "stage": performance["stage"]}


def fill_gaps(scraped, derived):
    """Add acts the festival's own page leaves off its bill. Returns how many.

    Days are matched on the headliner rather than on position, because the page has been
    known to list a year's nights in an order of its own. Anything that doesn't match is
    left exactly as scraped — a bill that came off the site is never edited on a guess.
    """
    added = 0
    for day in scraped["days"]:
        match = next((other for other in derived["days"]
                      if slug(other["headliner"]) == slug(day["headliner"])), None)
        if match is None:
            print(f'  {scraped["year"]}: no schedule day for "{day["headliner"]}", left as scraped')
            continue
        billed = {slug(day["headliner"])} | {slug(entry["name"]) for entry in day["support"]}
        missing = [entry for entry in match["support"] if slug(entry["name"]) not in billed]
        # Appended rather than merged in by time, so the main-stage bill keeps the order
        # the festival printed it in and the side stages sit under it, which is where the
        # scraped years put them too. Among themselves they read in set order.
        day["support"].extend(reversed(missing))
        added += len(missing)
    return added


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

current = this_year()
if current:
    scraped = next((entry for entry in years if entry["year"] == current["year"]), None)
    if scraped is None:
        years.append(current)
        print(f'{current["year"]}: not on the site yet, folded in whole from schedule.json')
    else:
        added = fill_gaps(scraped, current)
        print(f'{current["year"]}: scraped from the site, '
              f'{added} side-stage {"act" if added == 1 else "acts"} added from schedule.json')

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
