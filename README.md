# Hinterland

An offline-first iOS app for [Hinterland Music Festival](https://www.hinterlandiowa.com)
— St. Charles, Iowa, July 30 – August 2, 2026.

Cell service at a 15,000-person festival in a rural Iowa valley is unusable, so the app
assumes there is no network. The full schedule, every artist bio, all 48 pieces of artist
artwork, and the entire festival guide ship inside the binary and work in airplane mode.
The network is only used to pick up set-time changes and the forecast, both of which
cache what they fetch and fall back to what's already on the phone.

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
- **Food & Drink** — all 33 stands grouped by where they're parked (East, West and South
  Concourse, VIP, GA+, Basecamp and the mobile carts), with what each one sells, where
  they're from, and combinable filters for vegetarian, vegan, gluten-free, dairy-free,
  nut-free and sugar-free.
- **Maps** — the festival's four maps (grounds, concourse, driving routes, shuttle
  parking) bundled as artwork and pinch-zoomable, plus a MapKit view that georeferences
  the grounds map so the blue dot shows where you are on it.
- **Weather** — WeatherKit forecast for the amphitheater itself: current conditions, the
  next 24 hours, a high/low per festival day, and National Weather Service advisories.
  Severe and extreme warnings break out onto the top of the schedule; each set on an
  artist's page shows what it'll be doing while they play.

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

WeatherKit needs one thing that isn't in this repo: the capability has to be enabled on
the App ID in the [developer portal](https://developer.apple.com/account/resources/identifiers/)
(Certificates, Identifiers & Profiles → your identifier → check **WeatherKit**), and the
provisioning profile regenerated afterwards. `project.yml` already declares the
`com.apple.developer.weatherkit` entitlement, but the entitlement alone doesn't
authenticate — without the App ID capability every forecast request fails and the app
falls back to showing no weather. Everything else in the app works regardless.

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
python3 vendors.py --refresh   # Data/vendors.json  — food & drink stands by area
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

All three scrapers exit non-zero if they parse nothing, which is the signal that the
site's markup changed and the selectors need attention. `vendors.py` also exits on a
dietary code it doesn't recognise: the codes are printed on the vendor page with no
legend of their own, so a new one means both `DIETARY` in the script and `DietaryTag` in
the app need it added, or it would quietly disappear from the filters.

`python3 validate.py` checks all three files against what the Swift models require —
missing fields, unparseable dates, duplicate ids, dietary codes the app would drop —
before a bad file reaches a build.

## The maps on MapKit

`Data/map.json` is what turns the illustrations into a real map. It holds two `layers`,
wide to narrow:

| Layer | Covers | Rotation | Pins |
| --- | --- | --- | --- |
| `grounds` | 2375 × 1981 m | north-up | 22 — stages, entrances, gates, camping, parking, Basecamp, medical, box office |
| `concourse` | 487 × 649 m | 13.12° | 10 — Miniland, Art House, HinterMarket, Shade Lounge, GA+, VIP, guest services, ADA viewing, both medical tents |

Each layer carries a `georeference` (centre, size in metres, rotation clockwise from
north) and its `pois`, stored as positions on the artwork — `x`/`y`, 0–1 from the
top-left — rather than as coordinates. The app projects them through the georeference, so
pins and illustration can never drift apart, and correcting a georeference moves
everything on that layer at once.

Where the numbers come from:

- **Grounds** — traced against three features the illustration and the world share: I-35
  down the east edge (lon `-93.7800`), County Road G50 across the bottom (lat `41.29340`)
  and N Cross St on the west (lon `-93.8055`), all from OpenStreetMap.
- **Concourse** — fitted onto the grounds map by least squares through the three
  landmarks both illustrations draw (west entrance, south entrance, stage). The fit is a
  clean similarity transform: consistent scale, 13° of rotation, and all three landmarks
  land within 30 m of where the grounds map puts them.

`GroundsMapView` draws each layer as a rotated `MKOverlay` with an `MKMarkerAnnotationView`
per POI, the user's location, and walking distance plus a Directions handoff for the
selected pin. The concourse layer — artwork and pins together — appears only under
`visibleBelowMeters` (1200 m): it carries its own legend panel, which from a mile up is
just a beige box sitting on a field. Zooming in therefore swaps the site map for the
inside-the-gates map, and the title changes with it.

Apple's tiles need a network and won't load in the valley, but the artwork is bundled and
Core Location works without signal, so the map stays useful offline — which is why the
illustrations are drawn over the tiles rather than instead of them.

Both are illustrations, not surveys: grounds pins land within roughly a field's width of
the truth, concourse pins rather closer, and the UI says so on screen. `venue` in the same
file is the coordinate the "Open in Maps" button uses; the `festival.latitude`/`longitude`
pair in `schedule.json` is scraped and sits nearer the town of St. Charles than the site.

## The forecast

`WeatherStore` asks WeatherKit about the venue coordinate from `map.json` — not the
phone's location, which means no location permission and the right answer for everyone
still driving up. It fetches current conditions, hourly, daily and alerts in one call at
launch, on foreground, and on pull-to-refresh, throttled to at most one call every 15
minutes and skipped entirely while WeatherKit's own expiry hasn't passed.

WeatherKit's types can't be archived, so what comes back is flattened into
`WeatherSnapshot` — plain `Codable` values, stored metric and converted at display time —
and written to Application Support. That cache is what the UI reads, so the weather
screen opens in airplane mode showing the last forecast that got through, with the time
it was fetched under it. There's nothing bundled to fall back on the way the schedule
falls back to `Data/schedule.json`; a forecast shipped in a binary would be a year stale.
Before the first successful fetch the app simply says it has no weather yet.

Alerts are National Weather Service warnings as WeatherKit relays them. Anything
`severe` or worse gets a banner at the top of the schedule rather than waiting to be
found — in an Iowa July that's the most useful thing in here.

Apple requires the Weather trademark and a link to its legal page wherever the data
appears, so `WeatherAttributionView` sits at the bottom of the weather screen. The marks
are remote images; the cached service name and legal text stand in when there's no signal
to load them.

## Layout

```
Hinterland/
  App/         HinterlandApp.swift — entry point, appearance
  Models/      FestivalData, GuideData, MapData, VendorData, WeatherData — Codable
               mirrors of the JSON
  Services/    ScheduleStore (loading + refresh), WeatherStore, Favorites,
               NotificationManager
  Views/       Schedule, MyLineup, Artists, Info, FoodDrink, ArtistDetail, GroundsMap,
               MapImage, Weather, WeatherCard, Theme
  Resources/   Assets.xcassets — 48 artist images, 4 maps, app icon
Data/          schedule.json, info.json — bundled and remotely refreshable
               map.json — georeference and POIs for the grounds map
               vendors.json — food & drink stands by area
scripts/       scrapers, the map bundler and the icon generator
ci_scripts/    ci_post_clone.sh — generates the Xcode project for Xcode Cloud
```

## Notes

Artist photography is pulled from the festival's own CDN and is copyrighted by
Hinterland and the respective photographers. That's fine for a personal or
TestFlight-distributed build; it would need licensing before any public App Store
release.
