# Hinterland

An offline-first iOS app for [Hinterland Music Festival](https://www.hinterlandiowa.com)
— St. Charles, Iowa, July 30 – August 2, 2026.

Cell service at a 15,000-person festival in a rural Iowa valley is unusable, so the app
assumes there is no network. The full schedule, every artist bio, all 48 pieces of artist
artwork, the festival's maps and the vendor directory ship inside the binary and work in
airplane mode.
The network is only used to pick up set-time changes and the forecast, both of which
cache what they fetch and fall back to what's already on the phone.

## Features

- **Schedule** — all four days across the Main, Miniland and Campfire stages, filterable
  by stage, with a card at the top showing what's on now or up next.
- **My Lineup** — star sets to build a personal schedule, with automatic detection of
  sets that overlap so you know what you're choosing between.
- **Reminders** — local notifications a configurable 5–60 minutes before your starred
  sets. Scheduled on-device, so they fire with no signal.
- **Widget** — "Up Next" on the Home Screen (small and medium) and the Lock Screen
  (inline, rectangular and circular), showing the starred set that's on and what follows
  it. Falls back to the festival at large before anything is starred.
- **Live Activity** — the set you're watching on the Lock Screen and in the Dynamic
  Island from 90 minutes before it starts, with a countdown that runs on its own.
- **Artist pages** — bios and links out to Spotify and Instagram, reached by tapping any
  set on the schedule or in your lineup.
- **Rate a set** — one to five stars on any set once it's under way, with an optional line
  about it, and a ranked recap of everything you rated. Rating works with no signal and
  uploads later; scores are pooled through CloudKit so every set also carries the average
  everyone else gave it. Notes stay on your phone.
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

Three capabilities need setting up on the App ID in the
[developer portal](https://developer.apple.com/account/resources/identifiers/) before a
build does everything it should. All three are declared in `project.yml`, but the
entitlement alone isn't enough — the App ID has to carry the capability and the
provisioning profile has to be regenerated afterwards.

The **app group** `group.com.jreed91.hinterland` is the first (App Groups → register the
group, then check it on both the `com.jreed91.hinterland` and
`com.jreed91.hinterland.widgets` identifiers). Without it the app itself is unaffected —
stars, reminders, maps, everything works — but the widget reads an empty container and
sits there blank, and the Alerts sheet says so.

**WeatherKit** is the second (Certificates, Identifiers & Profiles → your identifier →
check **WeatherKit**), and it only applies to the app identifier. Without it every
forecast request fails to authenticate and the app falls back to showing no weather.
Everything else works regardless.

**CloudKit** is the third, and it's what pools the set ratings (iCloud → register the
container `iCloud.com.jreed91.hinterland`, then check **iCloud** on the app identifier
and tick that container). Without it the ratings feature still works — you rate sets, the
recap screen ranks them — but nothing uploads and no crowd average appears, and the
recap says as much rather than sitting there empty. There's a schema to create too; see
[Shared ratings](#shared-ratings).

The widget extension ships as its own bundle, `com.jreed91.hinterland.widgets`, so that
identifier has to exist alongside the app's. Change either in `project.yml` and re-run
`xcodegen generate`; the widget's ID has to stay prefixed by the app's or iOS refuses to
install the container.

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
| `concourse` | 487 × 649 m | 13.12° | 62 — every stamp in the artwork's legend: food, bars, water, toilets, merch, guest services, ticketing, concierges, lost & found, lockers, ADA viewing, shade, medical, emergency exits, plus Miniland, Art House, HinterMarket, GA+, VIP and the rest of the named venues |

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
- **Concourse pins** — one per icon stamped on the artwork, at the centre of the stamp.
  The frames are near-black on colour, so they come out of the image by thresholding for
  neutral black and keeping the ring-shaped components at badge size; the handful the
  legend panel contributes are dropped, and the four pins traced by hand before this
  landed within 5 px of where the sweep put them.

`GroundsMapView` draws each layer as a rotated `MKOverlay` with an `MKMarkerAnnotationView`
per POI, the user's location, and walking distance plus a Directions handoff for the
selected pin. The concourse layer — artwork and pins together — appears only under
`visibleBelowMeters` (1200 m): it carries its own legend panel, which from a mile up is
just a beige box sitting on a field. Zooming in therefore swaps the site map for the
inside-the-gates map, and the title changes with it.

The filter chips follow the same threshold — they list the categories the visible layers
actually carry, so the row is camping and parking from a mile up and food, water and
toilets once you're inside the gates. Where pins crowd each other MapKit drops the lower
`displayPriority` first, which is how sixty concourse pins stay readable: stages always
win, then the things you go looking for (medical, food, water, toilets, help desks),
then the ones you only want when you're standing next to them.

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

## Rating sets

`Ratings` is the same shape as `Favorites` — a small `@Observable` store over
`UserDefaults` in the app group, holding one `SetRating` per set: one to five stars, an
optional note, and when it was rated. It is the source of truth for what *you* thought,
it reads and writes with no network at all, and everything shared is built on top of it
rather than in place of it.

Ratings key off the **performance**, not the artist — an artist can play twice over the
weekend, and the 1am Campfire set isn't the main-stage set.

The stars appear on the artist page under a set once it has started (`Ratings.canRate`),
because there is nothing to say about a band that hasn't gone on yet; a 30-second ticker
on that screen means the control turns up while you're standing there rather than the next
time the page is opened. Tapping the star you already gave clears the rating, unless the
rating carries a note — the note sheet's **Remove rating** is the deliberate way to drop
one of those.

**My Ratings**, from the toolbar of My Lineup, ranks what you rated best-first, puts the
crowd average beside each one, and lists the starred sets that finished without a rating
underneath. Only starred sets: every set that has finished by Sunday night is most of the
festival, and you weren't at most of it. The share sheet hands off the ranking alone — the
notes stay on the phone.

## Shared ratings

`CommunityRatings` pools everyone's scores through the **CloudKit public database**.
CloudKit rather than a server of our own: no hosting, no keys in the binary, no accounts
to build, and the public database's default role already enforces the rule that matters —
anyone may read, but you may only write records you created.

Only the score is shared. Notes are never uploaded, which is deliberate: public free text
is a moderation problem, a report-abuse flow and a content policy, and none of that is
what this app is. The **Share my ratings** switch at the bottom of My Ratings turns
uploading off, and turning it off withdraws what's already up there rather than merely
stopping — anything else would be a lie about what the switch does.

| | |
| --- | --- |
| Record type | `SetRating` in the public database, default zone |
| Fields | `performanceID` (string), `stars` (int 1–5), `festivalYear` (int) |
| Record name | `<performanceID>_<userRecordName>` |
| Written by | the creating user only; readable by everyone |

The record name is the whole anti-ballot-stuffing story: one record per person per set, so
re-rating a set overwrites your own row instead of adding a second one, and the save uses
`.allKeys` because a row only you can write has no merge to do. Nothing identifying is
stored on it — the creator is CloudKit's own per-container opaque user ID, which is what
makes "you may only write your own" enforceable without the app knowing who anyone is.

Offline is the normal case, so a rating made in the valley goes into an **outbox** in
`UserDefaults` keyed by performance, with `0` meaning "take mine back down". It drains on
launch, on foreground and on any change to the ratings, one batch at a time, and it
survives relaunches — most ratings made at the festival upload in the car on the way home.
Writing needs an iCloud account; reading doesn't, so a phone with no account still sees
the averages and is told, once, why its own aren't going anywhere.

Reading is a sweep: the public database has no server-side aggregation, so `refresh()`
pages through this year's records asking only for `performanceID` and `stars`, counts the
averages locally, and caches the table to Application Support so it's still on screen with
no signal. Throttled to once every 15 minutes like the forecast, forced by pull-to-refresh
on My Ratings. That's the part that doesn't scale forever: past `recordCap` (20,000 rows)
the sweep stops and marks itself partial, and the fix at that point is to aggregate
somewhere else and publish the totals the way `schedule.json` is published, rather than to
raise the cap.

Setting the schema up, once, in the [CloudKit console](https://icloud.developer.apple.com):

1. Run the app once against the **development** environment and rate a set. CloudKit
   creates the `SetRating` record type from the first write.
2. Mark `performanceID`, `stars` and `festivalYear` **queryable** (the sweep filters on
   `festivalYear`, and a record type with no queryable field can't be queried at all).
3. **Deploy schema to production** before any TestFlight or App Store build. Development
   and production are separate databases; a build that skips this finds an empty container
   and shows no averages.

Shared scores are user data leaving the device, so an App Store release needs them
declared in the privacy nutrition label and in a `PrivacyInfo.xcprivacy` the project
doesn't yet carry.

## The widget and the Live Activity

Both answer the same question — what am I watching, and what's after it — so the rule for
picking those two sets lives once, in `Lineup.focus`: starred sets that haven't finished,
or the whole schedule when nothing is starred and there'd otherwise be nothing to show.
The Live Activity ignores that fallback, because a Lock Screen card about a band you
never starred is a card you turn off.

A widget runs in its own process, so everything it draws has to reach it through the
**app group** — `Favorites` writes the starred IDs there instead of `.standard`, and
`ScheduleStore` caches a refreshed `schedule.json` there instead of Application Support.
Both migrate what an older build left behind on first launch, so updating doesn't cost
anyone their lineup. `Hinterland/Shared/` is the code compiled into both targets; keeping
it to one copy is what stops the widget from disagreeing with the app about set times.

Neither one can be updated in the valley, which is the whole design constraint:

- The **widget timeline** is built ahead of time, with one entry at each remaining set
  boundary (`Lineup.transitions`). Nothing about it changes except when a set starts or
  ends, so WidgetKit has every entry it will need hours before it needs them and never
  has to wake the extension. The app reloads timelines when stars change, when a refresh
  brings new set times, and on foreground.
- The **Live Activity** can only be *started* while the app is in the foreground, so
  `LiveActivityController.sync` runs on launch, on every foreground, and on any change to
  the lineup — starting, updating or ending the card to match. Everything that moves on
  the card is a date the system animates by itself (`Text(timerInterval:)`,
  `ProgressView(timerInterval:)`), so it counts down correctly in airplane mode with the
  app long since killed. `staleDate` is the end of the set: past it, iOS dims the card
  rather than showing a confident wrong answer.

The widget deliberately carries no artist artwork. The catalog is 4.5 MB and a widget
extension has to bundle its own copy of anything it draws; stage colour and an SF Symbol
say the same thing for none of it. It does bundle `schedule.json`, so a phone that has
never had signal since installing still has the times.

Tapping either opens `hinterland://lineup`, which `RootView` turns into a jump to the
My Lineup tab rather than wherever the app was last left.

## Layout

```
Hinterland/
  App/         HinterlandApp.swift — entry point, appearance
  Shared/      compiled into the app AND the widget extension — FestivalData, Favorites,
               Theme (palette + formatting), AppGroup, ScheduleFile, Lineup,
               NowPlayingActivity (the ActivityKit attributes)
  Models/      GuideData, MapData, VendorData, WeatherData — Codable mirrors of the JSON
  Services/    ScheduleStore (loading + refresh), WeatherStore, NotificationManager,
               LiveActivityController, Ratings (yours), CommunityRatings (everyone's)
  Views/       Schedule, MyLineup, Ratings, Maps, FoodDrink, ArtistDetail, GroundsMap,
               MapImage, Weather, WeatherCard, Components
  Resources/   Assets.xcassets — 48 artist images, 4 maps, app icon
HinterlandWidgets/
               the widget extension — UpNextWidget (Home and Lock Screen),
               NowPlayingLiveActivity (Lock Screen and Dynamic Island)
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
