#!/usr/bin/env python3
"""Pin every artist in schedule.json to their Apple Music catalog id, and check the pins.

`AppleMusicStore` looks an artist up by `appleMusicArtistID` when the schedule carries
one and falls back to searching their name when it doesn't. The fallback is only as good
as the name: a catalog search always returns *something*, and 18 of this lineup's 48
names are shared by more than one act on Apple Music — Geese, Wisp, Amble, Samia, MUNA,
Lorde. Showing a stranger's songs under a band's photograph is worse than showing none
and is not a mistake anyone would catch from the outside, so every artist gets a pin and
the app never has to guess.

    python3 scripts/applemusic.py            # check the pins, and find any artist missing one
    python3 scripts/applemusic.py --write    # write the pins into Data/schedule.json

Unambiguous names are resolved automatically. Names that more than one catalog artist
answers to can't be — the tie is broken by listening to the candidates, not by ranking —
so those live in RESOLVED below with the evidence that settled them. An artist who is
neither in RESOLVED nor unambiguous is reported and nothing is written for them.

This talks to the public iTunes Search API, which needs no key and returns the same
catalog ids MusicKit uses (`artistId` here is the number in a music.apple.com/artist URL).
It is not the same ranking MusicKit's search applies, which is the other reason to pin:
what this script sees is not necessarily what the phone would have picked.
"""
import argparse, json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEDULE = os.path.join(ROOT, "Data", "schedule.json")

# Mirrors AppleMusicStore.searchLimit: the band we want is at the top of a search or
# nowhere, and looking deeper only turns up more acts with the same name.
SEARCH_LIMIT = 8

# The sentinel `AppleMusicStore` reads as "we looked, and they aren't there" — it stops
# the app searching their name and matching a stranger. Keep in step with
# `Artist.appleMusicUnavailable` in AppleMusicData.swift.
NONE = "none"

# Names more than one catalog artist answers to, settled by playing the candidates and
# checking them against the artist's own bio in schedule.json where there is one. Anyone
# added to this table should carry the reason they were picked.
RESOLVED = {
    "amble":           ("1671435415", 'Irish folk trio; "Lonely Island", named in their bio'),
    "audrey-nuna":     ("1444332093", 'R&B/Soul; "Golden", named in their bio'),
    "between-friends": ("1437540157", 'the LA pop duo; "affection", "Jam!"'),
    "cmat":            ("1506697965", '"EURO-COUNTRY", named in their bio'),
    "duo-beats":       (NONE,         "two catalog acts by this name, both rap singles and "
                                      "neither the Miniland act; no bio or Spotify id to "
                                      "check either against"),
    "geese":           ("1378038472", '"Cobra" and "Taxes", off Getting Killed'),
    "jane-remover":    ("1448393745", '"Dancing with your eyes closed", "Psychoboost"'),
    "julia-wolf":      ("1482698876", '"iris", "Hot Killer"'),
    "katseye":         ("1754284416", '"Gabriela" and "Gnarly", both named in their bio'),
    "koo-koo":         ("381459658",  'Children\'s Music; "Pop See Ko" — the Miniland act'),
    "lorde":           ("602767352",  '"Royals", named in their bio'),
    "muna":            ("1042111883", '"Silk Chiffon", "I Know A Place"'),
    "porch-light":     ("127092175",  "the Minneapolis five-piece; Porch Light - EP and "
                                      '"Get A Job (Live From The Porch)", both 2025, which '
                                      "is when the bio says they formed"),
    "samia":           ("879399372",  '"Honey", "The Promise"'),
    "sarah-tonin":     (NONE,         "six catalog acts by this name, none of them the Des "
                                      "Moines avant-pop band on the Miniland stage"),
    "the-format":      ("3064903",    '"The First Single (You Know Me)"'),
    "waylon-wyatt":    ("1713519329", '"Arkansas Diamond", named in their bio'),
    "wisp":            ("1681331842", 'the shoegaze act; "Your face", "Pandora"'),
}


def normalized(name):
    """Mirrors AppleMusicStore.normalized: fold accents and case, & to and, drop the rest."""
    folded = unicodedata.normalize("NFKD", name)
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", folded.lower().replace("&", "and"))


def call(path, params):
    """One iTunes API call, retried through the rate limiter rather than failing the run."""
    url = f"https://itunes.apple.com/{path}?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=25) as response:
                return json.loads(response.read().decode("utf-8"))["results"]
        except Exception as error:  # noqa: BLE001 — any failure here is worth one more try
            if attempt == 3:
                raise SystemExit(f"iTunes API failed for {params}: {error}")
            time.sleep(2 ** attempt)


def search(name):
    """Catalog artists whose name matches `name` exactly, once both are normalised."""
    results = call("search", {"term": name, "entity": "musicArtist",
                              "limit": SEARCH_LIMIT, "country": "US"})
    wanted = normalized(name)
    hits = {}
    for result in results:
        if normalized(result.get("artistName", "")) == wanted:
            hits[str(result["artistId"])] = result
    return hits


def lookup(catalog_id):
    """The catalog artist a pinned id points at, or None if the id is dead."""
    results = call("lookup", {"id": catalog_id, "country": "US"})
    return results[0] if results else None


def check(artists, write):
    changes, problems = [], []

    for artist in artists:
        name, pinned = artist["name"], artist.get("appleMusicArtistID")

        # An id already in the schedule is checked, not re-derived — that's the point of
        # pinning. A pin that no longer resolves, or that now points at a differently
        # named artist, is a data bug worth failing on.
        if pinned == NONE:
            print(f"  none      {name:26} not on Apple Music (by hand)")
            continue
        if pinned:
            found = lookup(pinned)
            if not found:
                problems.append(f"{name}: pinned id {pinned} doesn't resolve")
            elif normalized(found.get("artistName", "")) != normalized(name):
                problems.append(f"{name}: pinned id {pinned} is "
                                f"\"{found.get('artistName')}\"")
            else:
                print(f"  pinned    {name:26} {pinned}")
            time.sleep(0.4)
            continue

        if artist["id"] in RESOLVED:
            catalog_id, why = RESOLVED[artist["id"]]
            changes.append((artist, catalog_id))
            print(f"  resolved  {name:26} {catalog_id:<12} {why}")
            continue

        hits = search(name)
        time.sleep(0.4)
        if len(hits) == 1:
            catalog_id = next(iter(hits))
            changes.append((artist, catalog_id))
            print(f"  matched   {name:26} {catalog_id}")
        elif not hits:
            problems.append(f"{name}: nothing in the catalog by that name — pin them by "
                            f"hand, or mark them \"{NONE}\"")
        else:
            listing = ", ".join(f"{i} ({h.get('primaryGenreName', '?')})"
                                for i, h in hits.items())
            problems.append(f"{name}: {len(hits)} catalog artists by that name — add the "
                            f"right one to RESOLVED: {listing}")

    if write and changes:
        for artist, catalog_id in changes:
            # Inserted next to the Spotify id rather than appended, so the artist records
            # keep reading the same way.
            keys = list(artist)
            anchor = "spotifyArtistID" if "spotifyArtistID" in keys else "sourceSlug"
            rebuilt = {}
            for key in keys:
                rebuilt[key] = artist[key]
                if key == anchor:
                    rebuilt["appleMusicArtistID"] = catalog_id
            if "appleMusicArtistID" not in rebuilt:
                rebuilt["appleMusicArtistID"] = catalog_id
            artist.clear()
            artist.update(rebuilt)

    return changes, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true",
                        help="write the pins into Data/schedule.json")
    args = parser.parse_args()

    with open(SCHEDULE, encoding="utf-8") as handle:
        schedule = json.load(handle)

    changes, problems = check(schedule["artists"], args.write)

    if args.write and changes:
        with open(SCHEDULE, "w", encoding="utf-8") as handle:
            json.dump(schedule, handle, indent=2, ensure_ascii=False)
        print(f"\nwrote {len(changes)} ids into Data/schedule.json")

    if problems:
        print("\n" + "\n".join(f"  {problem}" for problem in problems))
        print(f"\n{len(problems)} artist(s) unresolved of {len(schedule['artists'])}")
        return 1

    print(f"\nOK — all {len(schedule['artists'])} artists accounted for")
    return 0


if __name__ == "__main__":
    sys.exit(main())
