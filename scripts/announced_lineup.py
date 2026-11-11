#!/usr/bin/env python3
"""Parse an announced lineup (days and artists, no set times) from scripts/lineups/<year>.txt.

The festival announces the bill months before it publishes set times. Until
/set-times-<year> exists there is nothing for scrape.py to read, so the announcement is
kept here as the source input instead of being typed into Data/. Run with no arguments to
check the newest file, `--year 2027` for a specific one, and `--write` to regenerate
Data/announced-lineup.json from it. The app shows that file only while its year is later
than the schedule's, so it steps aside on its own once next year's set times land.
"""
import datetime, json, os, re, sys

from festival_source import slug

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


if __name__ == "__main__":
    if "--year" in sys.argv:
        year = int(sys.argv[sys.argv.index("--year") + 1])
    else:
        year = max(int(name[:4]) for name in os.listdir(os.path.join(HERE, "lineups"))
                   if re.fullmatch(r"\d{4}\.txt", name))
    days = parse(year)
    for day in days:
        names = ", ".join(a["name"] + (" (special)" if a.get("special") else "")
                          for a in day["artists"])
        print(f'{day["weekday"]} {day["date"]}: {names}')
    if "--write" in sys.argv:
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
