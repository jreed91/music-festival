#!/usr/bin/env python3
"""Build a made-up next-year schedule and check the data side of the rollover.

Installed apps fetch `Data/schedule.json` live from `main`, so next year's schedule can't
be tried out by pushing it there: every phone would pick it up. This writes a stand-in to
`scripts/rehearsal/schedule-<year>.json` instead — this year's bill moved forward 52
weeks, so the weekdays line up and the artwork is all already bundled — and checks the
things about it that the app depends on without being told:

- it passes `validate.py`, so it decodes;
- its `generatedAt` beats the live file's, or `ScheduleStore.refresh` ignores it;
- no set ID is shared with this year, because ratings, stars and `FestivalMemories` are
  keyed by set ID and a collision would hand this year's rating to next year's set;
- every set ID starts with its own year, which `CommunityRatings` reads the year off.

To try it on a phone, point a debug build's `ScheduleStore.remoteURL` at the raw URL of
this file on a branch. Never copy it over `Data/schedule.json` on `main`.
"""
import datetime, json, os, subprocess, sys

from festival_source import slug

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIVE = os.path.join(ROOT, "Data", "schedule.json")
SHIFT = datetime.timedelta(weeks=52)

with open(LIVE, encoding="utf-8") as handle:
    live = json.load(handle)

year = live["festival"]["year"] + 1
out = os.path.join(ROOT, "scripts", "rehearsal", f"schedule-{year}.json")


def moved(stamp):
    return (datetime.datetime.fromisoformat(stamp) + SHIFT).isoformat()


def moved_date(text):
    return (datetime.date.fromisoformat(text) + SHIFT).isoformat()


days = []
for day in live["days"]:
    date = moved_date(day["date"])
    days.append({
        "date": date,
        "weekday": day["weekday"],
        # Same ID recipe as scrape.py, from the new date.
        "sets": [dict(performance,
                      id=f'{date}-{slug(performance["stage"])}-{slug(performance["artist"])}',
                      start=moved(performance["start"]),
                      end=moved(performance["end"]))
                 for performance in day["sets"]],
    })

rehearsal = dict(live,
                 generatedAt=datetime.datetime.now(datetime.timezone.utc)
                     .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
                 festival=dict(live["festival"], year=year,
                               startDate=days[0]["date"], endDate=days[-1]["date"]),
                 days=days)

os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(rehearsal, handle, indent=2, ensure_ascii=False)
print(f"{out}: {year}, {rehearsal['festival']['startDate']} to {rehearsal['festival']['endDate']}")

problems = []

if subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "validate.py"), out]).returncode:
    problems.append("validate.py rejected it")

if rehearsal["generatedAt"] <= live["generatedAt"]:
    problems.append("generatedAt is not newer than the live file's, so apps would ignore it")

old_ids = {p["id"] for d in live["days"] for p in d["sets"]}
new_ids = [p["id"] for d in days for p in d["sets"]]
shared = old_ids.intersection(new_ids)
if shared:
    problems.append(f"{len(shared)} set IDs carry over from {year - 1}: {sorted(shared)[:3]}")
misfiled = [i for i in new_ids if not i.startswith(f"{year}-")]
if misfiled:
    problems.append(f"{len(misfiled)} set IDs don't start with {year}: {misfiled[:3]}")

for day in days:
    weekday = datetime.date.fromisoformat(day["date"]).strftime("%A")
    if weekday != day["weekday"]:
        problems.append(f'{day["date"]} is a {weekday}, labelled {day["weekday"]}')

if problems:
    print("Rollover problems:")
    for problem in problems:
        print(f"  ✗ {problem}")
    sys.exit(1)
print(f"Rollover OK — {len(new_ids)} sets, none shared with {year - 1}")
