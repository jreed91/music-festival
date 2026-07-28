#!/usr/bin/env python3
"""Check Data/*.json against what the Swift models require.

The Swift side decodes with `JSONDecoder.dateDecodingStrategy = .iso8601`, which accepts
RFC 3339 internet date-times *without* fractional seconds. A missing non-optional field
or an unparseable date is a crash at launch, so this mirrors those rules exactly.
"""
import json, os, re, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []

# Field name -> required, mirroring the non-optional properties in the Swift models.
FESTIVAL = ["name", "year", "venue", "city", "latitude", "longitude",
            "timeZone", "startDate", "endDate", "website"]
PERFORMANCE = ["id", "artistId", "artist", "stage", "start", "end"]

ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$")


def require(obj, fields, where):
    for field in fields:
        if obj.get(field) is None:
            errors.append(f"{where}: missing required field '{field}'")


def check_date(value, where):
    """ISO8601DateFormatter with .withInternetDateTime — no fractional seconds."""
    if not isinstance(value, str) or not ISO.match(value):
        errors.append(f"{where}: '{value}' is not an RFC 3339 date the app can decode")
        return None
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


# ------------------------------------------------------------------- schedule.json
with open(os.path.join(ROOT, "Data", "schedule.json"), encoding="utf-8") as handle:
    schedule = json.load(handle)

require(schedule, ["version", "generatedAt", "festival", "artists", "days"], "schedule")
check_date(schedule.get("generatedAt"), "schedule.generatedAt")
require(schedule.get("festival", {}), FESTIVAL, "schedule.festival")

artist_ids = set()
for artist in schedule.get("artists", []):
    require(artist, ["id", "name"], f'artist {artist.get("name", "?")}')
    if artist["id"] in artist_ids:
        errors.append(f'duplicate artist id: {artist["id"]}')
    artist_ids.add(artist["id"])

performance_ids, total = set(), 0
for day in schedule.get("days", []):
    require(day, ["date", "weekday", "sets"], "day")
    for performance in day.get("sets", []):
        total += 1
        label = f'{day.get("date")} {performance.get("artist", "?")}'
        require(performance, PERFORMANCE, label)

        start = check_date(performance.get("start"), f"{label}.start")
        end = check_date(performance.get("end"), f"{label}.end")
        if start and end and end <= start:
            errors.append(f"{label}: end {end} is not after start {start}")

        if performance["id"] in performance_ids:
            errors.append(f'duplicate set id: {performance["id"]}')
        performance_ids.add(performance["id"])

        # ArtistDetailView looks the artist up by this ID; a miss renders an empty screen.
        if performance.get("artistId") not in artist_ids:
            errors.append(f'{label}: artistId "{performance.get("artistId")}" has no artist')

# Every artist should actually be playing, or they'd be unreachable from the schedule.
playing = {p["artistId"] for day in schedule["days"] for p in day["sets"]}
for orphan in artist_ids - playing:
    errors.append(f"artist '{orphan}' has no sets")

# ----------------------------------------------------------------------- info.json
with open(os.path.join(ROOT, "Data", "info.json"), encoding="utf-8") as handle:
    info = json.load(handle)

require(info, ["version", "categories"], "info")
topic_ids, topics = set(), 0
for category in info.get("categories", []):
    require(category, ["id", "name", "topics"], "info category")
    for topic in category.get("topics", []):
        topics += 1
        require(topic, ["id", "title", "body"], f'topic {topic.get("title", "?")}')
        # InfoView resolves navigation by topic id, so collisions would misroute.
        if topic["id"] in topic_ids:
            errors.append(f'duplicate topic id: {topic["id"]}')
        topic_ids.add(topic["id"])

# ------------------------------------------------------------ bundled artwork
catalog = os.path.join(ROOT, "Hinterland", "Resources", "Assets.xcassets")
for artist in schedule["artists"]:
    asset = artist.get("imageAsset")
    if asset and not os.path.exists(os.path.join(catalog, "Artists", f"{asset}.imageset")):
        errors.append(f'artist {artist["id"]}: imageAsset "{asset}" is not in the catalog')

if not os.path.exists(os.path.join(catalog, "AppIcon.appiconset", "AppIcon.png")):
    errors.append("AppIcon.png is missing — TestFlight will reject the upload")

# ----------------------------------------------------------------------- report
if errors:
    print(f"{len(errors)} problem(s):")
    for error in errors:
        print(f"  ✗ {error}")
    sys.exit(1)

print(f"OK — {len(schedule['days'])} days, {total} sets, {len(artist_ids)} artists, "
      f"{topics} guide topics, artwork and icon present")
