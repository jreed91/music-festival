#!/usr/bin/env python3
"""Build Data/announced-lineup.json: next year's bill (days and artists, no set times).

The festival announces the bill months before it publishes set times. Until
/set-times-<year> exists there is nothing for scrape.py to read, so this has two sources:

- `--site` reads the festival's own /lineup page, which is the latest word: who plays,
  which day, in billing order, plus each artist's photo, Spotify ID and Instagram from
  their page. Use this whenever the site is reachable.
- otherwise scripts/lineups/<year>.txt, the announcement as first published, pasted in.

Run with no arguments to check the newest file, `--year 2027` for a specific one, and
`--write` to regenerate Data/announced-lineup.json. With `--site`, the differences from
the pasted announcement are printed, because a bill that changed since it was announced
is news. The app shows the file only while its year is later than the schedule's, so it
steps aside on its own once next year's set times land.
"""
import datetime, json, os, re, sys

from festival_source import slug, page, lineup_cards, artist_details

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Data", "announced-lineup.json")
DAY = re.compile(r"^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+([A-Z][a-z]+ \d{1,2})$")
# The poster's last line reads "And a Special Performance by …"; keep the artist, flag the billing.
SPECIAL = re.compile(r"^(?:and\s+)?a\s+special\s+performance\s+by\s+", re.I)


def parse(year):
    path = os.path.join(HERE, "lineups", f"{year}.txt")
    days, current = [], None
    for number, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        heading = DAY.match(line)
        if heading:
            date = datetime.datetime.strptime(f"{heading.group(2)} {year}", "%B %d %Y").date()
            if date.strftime("%A") != heading.group(1):
                sys.exit(f"{path}:{number}: {line} is a {date.strftime('%A')} in {year}")
            current = {"date": date.isoformat(), "weekday": heading.group(1), "artists": []}
            days.append(current)
            continue
        if current is None:
            sys.exit(f"{path}:{number}: artist before any day heading")
        special = bool(SPECIAL.match(line))
        name = SPECIAL.sub("", line).strip()
        artist = {"id": slug(name), "name": name}
        if special:
            artist["special"] = True
        current["artists"].append(artist)

    if not days or not all(day["artists"] for day in days):
        sys.exit(f"{path}: a day with no artists, or no days at all")
    ids = [artist["id"] for day in days for artist in day["artists"]]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        sys.exit(f"{path}: listed twice: {', '.join(dupes)}")
    return days


def from_site(year, announced, refresh=False):
    """The bill as /lineup shows it now, grouped by the date on each card.

    The page lists the whole bill in poster order, then each day again in another order;
    the first time an artist appears is their billing, so that order wins. The site has
    no "special performance" marker, so that flag carries over from the pasted
    announcement, matched by slug prefix ("haywire" for "Haywire in a Cornfield").
    """
    special = [artist["id"] for day in announced for artist in day["artists"]
               if artist.get("special")]
    by_date, seen = {}, set()
    for card in lineup_cards(page("/lineup", refresh=refresh)):
        if card["slug"] in seen or not card["date"]:
            continue
        seen.add(card["slug"])
        date = datetime.datetime.strptime(card["date"], "%B %d, %Y").date()
        if date.year != year:
            sys.exit(f"/lineup lists {card['name']} on {card['date']}, outside {year}")
        artist = {"id": slug(card["name"]), "name": card["name"]}
        if any(s == artist["id"] or s.startswith(artist["id"] + "-") for s in special):
            artist["special"] = True
        artist["imageURL"] = card["image"]
        details = artist_details(card["slug"], refresh=refresh)
        for key in ("spotifyArtistID", "instagram", "bio"):
            if details.get(key):
                artist[key] = details[key]
        by_date.setdefault(date, []).append(artist)
    if not by_date:
        sys.exit("/lineup has no dated artist cards; has the markup changed?")
    # Specials close the day on the poster, whatever order the site happens to list them.
    return [{"date": date.isoformat(), "weekday": date.strftime("%A"),
             "artists": sorted(artists, key=lambda a: a.get("special", False))}
            for date, artists in sorted(by_date.items())]


def differences(announced, current):
    """Who joined, who left and who moved day between the pasted announcement and now."""
    def days_of(days):
        return {a["id"]: (d["weekday"], a["name"]) for d in days for a in d["artists"]}
    was, now = days_of(announced), days_of(current)
    # "Haywire in a Cornfield" on the poster is "Haywire" on the site: the same act.
    def match(i, pool):
        return next((j for j in pool if j == i or j.startswith(i + "-") or i.startswith(j + "-")), None)
    lines = []
    for i, (day, name) in now.items():
        j = match(i, was)
        if j is None:
            lines.append(f"  + {name} ({day})")
        elif was[j][0] != day:
            lines.append(f"  ~ {name}: {was[j][0]} -> {day}")
    for j, (day, name) in was.items():
        if match(j, now) is None:
            lines.append(f"  - {name} ({day})")
    return lines


if __name__ == "__main__":
    if "--year" in sys.argv:
        year = int(sys.argv[sys.argv.index("--year") + 1])
    else:
        year = max(int(name[:4]) for name in os.listdir(os.path.join(HERE, "lineups"))
                   if re.fullmatch(r"\d{4}\.txt", name))
    days = parse(year)
    if "--site" in sys.argv:
        announced, days = days, from_site(year, days, refresh="--refresh" in sys.argv)
        changes = differences(announced, days)
        print("Changed since the announcement:" if changes else "Same bill as announced.")
        for line in changes:
            print(line)
    for day in days:
        names = ", ".join(a["name"] + (" (special)" if a.get("special") else "")
                          for a in day["artists"])
        print(f'{day["weekday"]} {day["date"]}: {names}')
    if "--write" in sys.argv:
        # Keep what images.py and applemusic.py added last time, so regenerating never
        # silently detaches bundled photos or Apple Music pins.
        if os.path.exists(OUT):
            with open(OUT, encoding="utf-8") as handle:
                previous = {a["id"]: a for d in json.load(handle)["days"] for a in d["artists"]}
            for artist in (a for day in days for a in day["artists"]):
                for key in ("imageAsset", "appleMusicArtistID"):
                    if previous.get(artist["id"], {}).get(key):
                        artist[key] = previous[artist["id"]][key]
        data = {
            "version": 1,
            "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "year": year,
            "startDate": days[0]["date"],
            "endDate": days[-1]["date"],
            "days": days,
        }
        with open(OUT, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        print(f"{OUT}: {len(days)} days, {sum(len(d['artists']) for d in days)} artists")
