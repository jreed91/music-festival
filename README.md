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

## Updating the schedule mid-festival

`Data/schedule.json` is the single source of truth, bundled at build time **and** fetched
at launch from:

```
https://raw.githubusercontent.com/jreed91/music-festival/main/Data/schedule.json
```

Editing that file on the default branch pushes new set times to everyone who already has
the app, without an App Store round trip. The app only accepts a remote copy whose
`generatedAt` is newer than what it already has, caches it, and falls straight back to
the bundled copy if the fetch fails — so a bad network or a 404 is harmless.

If your default branch isn't `main`, update `ScheduleStore.remoteURL` to match.

## Regenerating the data

The festival site is a Webflow build; these scripts scrape it and rewrite the JSON.
Pages are cached under `scripts/.cache`, so pass `--refresh` to re-fetch.

```sh
cd scripts
python3 scrape.py --refresh    # Data/schedule.json — set times, artists, bios, Spotify IDs
python3 guide.py  --refresh    # Data/info.json     — the festival guide
python3 images.py              # artist artwork -> asset catalog (needs `pip install Pillow`)
python3 appicon.py             # regenerates the app icon
```

Run `scrape.py` before `images.py` — the latter reads the artist list and writes each
artist's asset name back into `schedule.json`.

Both scrapers exit non-zero if they parse nothing, which is the signal that the site's
markup changed and the selectors need attention.

## Layout

```
Hinterland/
  App/         HinterlandApp.swift — entry point, appearance
  Models/      FestivalData, GuideData — Codable mirrors of the JSON
  Services/    ScheduleStore (loading + refresh), Favorites, NotificationManager
  Views/       Schedule, MyLineup, Artists, Info, ArtistDetail, Theme
  Resources/   Assets.xcassets — 48 artist images, app icon
Data/          schedule.json, info.json — bundled and remotely refreshable
scripts/       scrapers and the icon generator
```

## Notes

Artist photography is pulled from the festival's own CDN and is copyrighted by
Hinterland and the respective photographers. That's fine for a personal or
TestFlight-distributed build; it would need licensing before any public App Store
release.
