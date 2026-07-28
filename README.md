# Hinterland

An offline-first iOS app for [Hinterland Music Festival](https://www.hinterlandiowa.com)
— St. Charles, Iowa, July 30 – August 2, 2026.

Cell service at a 15,000-person festival in a rural Iowa valley is unusable, so the app
assumes there is no network. The full schedule, every artist bio, all 48 pieces of artist
artwork, and the entire festival guide ship inside the binary and work in airplane mode.
The network is only ever used to pick up set-time changes.

## Features

- **Schedule** — all four days across the Main, Miniland and Campfire stages, filterable
  by stage, with a card at the top showing what's on now or up next.
- **My Lineup** — star sets to build a personal schedule, with automatic detection of
  sets that overlap so you know what you're choosing between.
- **Reminders** — local notifications a configurable 5–60 minutes before your starred
  sets. Scheduled on-device, so they fire with no signal.
- **Artists** — searchable grid of the full bill, with bios and links out to Spotify
  and Instagram.
- **Info** — the complete festival guide (67 topics), searchable and fully offline:
  parking routes, gate times, box office hours, camping rules, what you can and can't
  bring, accessibility, and more.
- **Maps** — the festival's four maps (grounds, concourse, driving routes, shuttle
  parking) bundled as artwork and pinch-zoomable, plus a MapKit view that georeferences
  the grounds map so the blue dot shows where you are on it.

## Building

The Xcode project is generated rather than committed, so there's no `.pbxproj` to
conflict on.

```sh
brew install xcodegen     # once
xcodegen generate         # writes Hinterland.xcodeproj
open Hinterland.xcodeproj
```

Then in Xcode: select the **Hinterland** target → **Signing & Capabilities** → pick your
team. `PRODUCT_BUNDLE_IDENTIFIER` is `com.jreed91.hinterland`; change it in `project.yml`
if that ID is taken on your account, and re-run `xcodegen generate`.

Requires iOS 17 or later (the app uses the `@Observable` macro).

### TestFlight

1. Create the app record in App Store Connect with a matching bundle ID.
2. In Xcode: **Product → Archive**, then **Distribute App → TestFlight & App Store**.
3. Internal testers get the build once processing finishes — no review wait.

`ITSAppUsesNonExemptEncryption` is already set to `false` in `project.yml`, so uploads
skip the export-compliance prompt.

### Xcode Cloud

Xcode Cloud clones the repo and expects `Hinterland.xcodeproj` at the root, which isn't
committed here. `ci_scripts/ci_post_clone.sh` bridges that gap: it runs immediately after
the clone, downloads the XcodeGen release binary (the build image has neither XcodeGen nor
Homebrew) and generates the project before Xcode Cloud goes looking for it. Without that
script the build fails with:

```
Project Hinterland.xcodeproj does not exist at the root of the repository
```

The script is the standard hook name and location, so there is nothing to configure in the
workflow. Two things worth knowing:

- Xcode Cloud's **workflow creation** wizard in Xcode reads the project from your working
  copy, so run `xcodegen generate` locally before creating the workflow.
- Pin a different XcodeGen with the `XCODEGEN_VERSION` environment variable on the
  workflow; the script falls back to the latest release if that tag has no build.

If a cloud archive fails signing with "requires a development team", set `DEVELOPMENT_TEAM`
in `project.yml` — the local project Xcode writes your team into is never uploaded.

## Updating the schedule mid-festival

`Data/schedule.json` is the single source of truth, bundled at build time **and** fetched
at launch from:

```
https://raw.githubusercontent.com/jreed91/music-festival/main/Data/schedule.json
```

Editing that file on the default branch pushes new set times to everyone who already has
the app, without an App Store round trip. Bump `generatedAt` when you do — the app only
accepts a remote copy that is newer than what it already has. It caches what it fetches
and falls straight back to the bundled copy on any failure, so a dead network or a 404
is harmless.

That URL points at the repo's default branch, `main`. If you ever rename it, update
`ScheduleStore.remoteURL` to match or the fetch will 404.

## Regenerating the data

The festival site is a Webflow build; these scripts scrape it and rewrite the JSON.
Pages are cached under `scripts/.cache`, so pass `--refresh` to re-fetch.

```sh
cd scripts
python3 scrape.py --refresh    # Data/schedule.json — set times, artists, bios, Spotify IDs
python3 guide.py  --refresh    # Data/info.json     — the festival guide
python3 maps.py                # festival maps -> asset catalog, map list -> info.json
python3 images.py              # artist artwork -> asset catalog (needs `pip install Pillow`)
python3 appicon.py             # regenerates the app icon
```

Run `scrape.py` before `images.py` — the latter reads the artist list and writes each
artist's asset name back into `schedule.json`. Run `guide.py` before `maps.py` for the
same reason: `guide.py` rewrites `info.json` wholesale and `maps.py` adds the `maps`
array back onto it.

`maps.py` picks the maps out of the guide's rich text by the file name the festival's
designer uses (`Grounds_Map`, `Concourse_Map`, `Route`, `Shuttle`), ignoring the
photography alongside them. It exits non-zero if any of the four has gone missing, which
means the artwork was renamed — update `MAPS` at the top of the script.

Both scrapers exit non-zero if they parse nothing, which is the signal that the site's
markup changed and the selectors need attention.

## The grounds map on MapKit

`Data/map.json` is what turns the illustrated grounds map into a real map:

- `georeference` — the four corners the artwork covers. They were traced against three
  features the illustration and the world share: I-35 down the east edge (lon
  `-93.7800`), County Road G50 across the bottom (lat `41.29340`) and N Cross St on the
  west (lon `-93.8055`), all from OpenStreetMap.
- `pois` — stages, entrances, gates, camping, parking, Basecamp, medical and the box
  office, each stored as a position on the artwork (`x`/`y`, 0–1 from the top-left)
  rather than as a coordinate. The app projects them through the georeference, so the
  pins and the illustration can never drift apart.

`GroundsMapView` draws the artwork as an `MKOverlay` inside that box, with an
`MKMarkerAnnotationView` per POI, the user's location, and walking distance to whatever
is selected. Apple's tiles need a network and won't load in the valley, but the artwork
is bundled and Core Location works without signal, so the map stays useful offline —
which is why the illustration is drawn over the tiles rather than instead of them.

The artwork is an illustration, not a survey, so the pins land within roughly a field's
width of the truth and the UI says so. To improve it, correct the four corners in
`map.json` — every pin moves with them. `venue` in the same file is the coordinate the
"Open in Maps" button uses; the `festival.latitude`/`longitude` pair in `schedule.json`
is scraped and sits nearer the town of St. Charles than the site.

## Layout

```
Hinterland/
  App/         HinterlandApp.swift — entry point, appearance
  Models/      FestivalData, GuideData, MapData — Codable mirrors of the JSON
  Services/    ScheduleStore (loading + refresh), Favorites, NotificationManager
  Views/       Schedule, MyLineup, Artists, Info, ArtistDetail, GroundsMap, MapImage, Theme
  Resources/   Assets.xcassets — 48 artist images, 4 maps, app icon
Data/          schedule.json, info.json — bundled and remotely refreshable
               map.json — georeference and POIs for the grounds map
scripts/       scrapers, the map bundler and the icon generator
ci_scripts/    ci_post_clone.sh — generates the Xcode project for Xcode Cloud
```

## Notes

Artist photography is pulled from the festival's own CDN and is copyrighted by
Hinterland and the respective photographers. That's fine for a personal or
TestFlight-distributed build; it would need licensing before any public App Store
release.
