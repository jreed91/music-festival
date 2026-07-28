#!/usr/bin/env python3
"""Scrape set times, lineup and artist pages into Data/schedule.json."""
import re, json, os, sys, datetime

from festival_source import page, clean, strip_tags, slug, full_res

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "schedule.json")
CENTRAL = datetime.timezone(datetime.timedelta(hours=-5))   # CDT; the festival is in summer
REFRESH = "--refresh" in sys.argv

# ---------------------------------------------------------------------- set times
src = page("/set-times-2026", refresh=REFRESH)

# Stage headings and set rows appear in document order, so a single ordered pass over
# these three token types reconstructs which stage each row belongs to.
TOKEN = re.compile(
    r'(?P<main>class="set-times-main-stage")'
    r'|class="set-times-stage-label">(?P<stage>[^<]+)<'
    r'|class="set-times-time">(?P<time>[^<]+)</div>\s*<div class="set-times-artist-name">(?P<artist>[^<]+)<'
)

days = []
for chunk in src.split('class="set-times-day-column"')[1:]:
    date_text = re.search(r'class="set-times-day-date">([A-Z][a-z]+ \d+, \d{4})<', chunk)
    weekday = re.search(r'class="set-times-day-heading-text[^"]*">([^<]+)<', chunk)
    if not date_text:
        continue
    base = datetime.datetime.strptime(date_text.group(1), "%B %d, %Y").date()

    stage, sets = "Main Stage", []
    for match in TOKEN.finditer(chunk):
        if match.group("main"):
            stage = "Main Stage"
        elif match.group("stage"):
            stage = clean(match.group("stage"))
        else:
            when = datetime.datetime.strptime(
                clean(match.group("time")).upper().replace(".", ""), "%I:%M %p")
            # A 12:30am Campfire set is listed under the night it belongs to but falls
            # on the next calendar day.
            date = base + datetime.timedelta(days=1) if when.hour < 6 else base
            sets.append({
                "artist": clean(match.group("artist")),
                "stage": stage,
                "start": datetime.datetime.combine(date, when.time(), tzinfo=CENTRAL),
            })

    days.append({"date": base.isoformat(),
                 "weekday": clean(weekday.group(1)) if weekday else base.strftime("%A"),
                 "sets": sets})

if not days:
    sys.exit("No days parsed — the set times page markup probably changed.")

# The site publishes start times only. Infer each end from the next set on the same
# stage, leaving a changeover gap, and give closers a fixed sensible length.
for day in days:
    by_stage = {}
    for item in day["sets"]:
        by_stage.setdefault(item["stage"], []).append(item)
    for stage, items in by_stage.items():
        items.sort(key=lambda item: item["start"])
        for index, item in enumerate(items):
            if index + 1 < len(items):
                gap = (items[index + 1]["start"] - item["start"]).total_seconds() / 60
                minutes = gap - 15 if gap > 45 else gap
            else:
                minutes = 90 if stage == "Main Stage" else 60
            item["end"] = item["start"] + datetime.timedelta(minutes=minutes)

# ------------------------------------------------------------------ artist cards
lineup = page("/lineup", refresh=REFRESH)
CARD = re.compile(
    r'href="/artist/(?P<slug>[^"]+)".*?'
    r'<img src="(?P<img>https://cdn\.prod\.website-files\.com/[^"]+?\.(?:webp|jpg|jpeg|png))".*?'
    r'class="band-card-name">(?P<name>[^<]+)<',
    re.S)

cards = {}
for match in CARD.finditer(lineup):
    name = clean(match.group("name"))
    cards.setdefault(name.lower(), {"slug": match.group("slug"),
                                    "image": full_res(match.group("img"))})

# ------------------------------------------------------------------ artist pages
def artist_details(page_slug):
    """Bio, Spotify ID and Instagram handle from an artist's own page."""
    try:
        body = page(f"/artist/{page_slug}", refresh=REFRESH)
    except Exception as error:                  # one missing page shouldn't stop the run
        print(f"  ! {page_slug}: {error}")
        return {}

    details = {}
    spotify = re.search(r"open\.spotify\.com/embed/artist/([A-Za-z0-9]+)", body)
    if spotify:
        details["spotifyArtistID"] = spotify.group(1)
    instagram = re.search(r"https://www\.instagram\.com/([A-Za-z0-9_.]+)/?", body)
    if instagram:
        details["instagram"] = instagram.group(1)

    # The bio sits between the "About" heading and the "Connect" social block.
    text = strip_tags(body)
    about = re.search(r"\bAbout\b(.*?)(?:\bConnect\b|Past Hinterlands)", text, re.S)
    if about:
        bio = re.sub(r'\s+([.,”"])', r"\1", about.group(1).strip())
        if 40 < len(bio) < 4000:
            details["bio"] = bio
    return details


artists = {}
for item in (item for day in days for item in day["sets"]):
    key = item["artist"].lower()
    if key in artists:
        continue
    card = cards.get(key, {})
    entry = {"id": slug(item["artist"]), "name": item["artist"]}
    if card.get("image"):
        entry["imageURL"] = card["image"]
    if card.get("slug"):
        entry["sourceSlug"] = card["slug"]
        entry.update(artist_details(card["slug"]))
    artists[key] = entry

# Preserve imageAsset names assigned by images.py, so re-scraping never silently
# detaches artwork that is already bundled.
if os.path.exists(OUT):
    with open(OUT, encoding="utf-8") as handle:
        previous = {a["id"]: a for a in json.load(handle).get("artists", [])}
    for entry in artists.values():
        asset = previous.get(entry["id"], {}).get("imageAsset")
        if asset:
            entry["imageAsset"] = asset

data = {
    "version": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "festival": {
        "name": "Hinterland",
        "year": 2026,
        "venue": "Avenue of the Saints Amphitheater",
        "city": "St. Charles, Iowa",
        "latitude": 41.2861,
        "longitude": -93.8130,
        "timeZone": "America/Chicago",
        "startDate": days[0]["date"],
        "endDate": days[-1]["date"],
        "website": "https://www.hinterlandiowa.com",
    },
    "artists": sorted(artists.values(), key=lambda a: a["name"].lower()),
    "days": [
        {
            "date": day["date"],
            "weekday": day["weekday"],
            "sets": [
                {
                    "id": f'{day["date"]}-{slug(item["stage"])}-{slug(item["artist"])}',
                    "artistId": slug(item["artist"]),
                    "artist": item["artist"],
                    "stage": item["stage"],
                    "start": item["start"].isoformat(),
                    "end": item["end"].isoformat(),
                }
                for item in sorted(day["sets"], key=lambda i: (i["start"], i["stage"]))
            ],
        }
        for day in days
    ],
}

with open(OUT, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)

count = len(data["artists"])
print(f'{OUT}: {len(data["days"])} days, '
      f'{sum(len(d["sets"]) for d in data["days"])} sets, {count} artists')
print(f'  images {sum(1 for a in data["artists"] if a.get("imageURL"))}/{count} · '
      f'bios {sum(1 for a in data["artists"] if a.get("bio"))}/{count} · '
      f'spotify {sum(1 for a in data["artists"] if a.get("spotifyArtistID"))}/{count}')
