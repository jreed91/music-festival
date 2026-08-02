# Hinterland

An offline-first iOS app for [Hinterland Music Festival](https://www.hinterlandiowa.com)
— St. Charles, Iowa, July 30 – August 2, 2026.

Cell service at a 15,000-person festival in a rural Iowa valley is unusable, so the app
assumes there is no network. The full schedule, every artist bio, all 48 pieces of artist
artwork, the festival's maps, the vendor directory and ten years of past lineups ship
inside the binary and work in airplane mode.
The network is only used to pick up set-time changes, the forecast, the crowd's ratings
and each artist's top songs on Apple Music — all of which cache what they fetch and fall
back to what's already on the phone.

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
- **Artist pages** — bios and links out to Apple Music, Spotify and Instagram, reached by
  tapping any set on the schedule or in your lineup.
- **Top songs** — each artist's five best-known tracks from the Apple Music catalog, each
  playable as a 30-second preview without an Apple Music subscription. Looked up once and
  cached, so the list is still there in the valley.
- **Rate a set** — one to five stars on any set once it's under way, with an optional line
  about it, and a ranked recap of everything you rated. Rating works with no signal and
  uploads later; scores are pooled through CloudKit so every set also carries the average
  everyone else gave it. Notes stay on your phone.
- **Food & Drink** — all 33 stands grouped by where they're parked (East, West and South
  Concourse, VIP, GA+, Basecamp and the mobile carts), with what each one sells, where
  they're from, and combinable filters for vegetarian, vegan, gluten-free, dairy-free,
  nut-free and sugar-free.
- **Past lineups** — every Hinterland since 2015, from the Schedule tab: each year's
  headliners and its whole bill, day by day, side stages marked. Bundled, so it settles
  the argument about who played 2017 with no signal.
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

Four capabilities need setting up on the App ID in the
[developer portal](https://developer.apple.com/account/resources/identifiers/) before a
build does everything it should. The first three are declared in `project.yml`, but the
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
container `iCloud.jreed91.hinterland`, then check **iCloud** on the app identifier and
tick that container). Without it the ratings feature still works — you rate sets, the
recap screen ranks them — but nothing uploads and no crowd average appears, and the
recap says as much rather than sitting there empty. There's a schema to create too; see
[Shared ratings](#shared-ratings).

**MusicKit** is the fourth, and it's the odd one out: there is no entitlement to declare,
so nothing about it appears in `project.yml` beyond the `NSAppleMusicUsageDescription`
string, and a build without it looks correctly signed. Tick **MusicKit** on the app
identifier (and pick the app in the media-services sheet it opens). Without it MusicKit
can't get a developer token, every catalog lookup fails, and the Top songs section on each
artist page says it couldn't reach Apple Music while the rest of the page is unaffected.

That container is **not** `iCloud.` plus the bundle ID, which is what `CKContainer`'s
default would look for, so `CommunityRatings.containerIdentifier` names it in full and
has to be changed alongside `project.yml`. A build whose entitlement points at a
container that doesn't exist compiles and archives happily and then fails at
`xcodebuild -exportArchive` with exit 70, no profile matching its entitlements.

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
python3 past_lineups.py --refresh   # Data/past-lineups.json — every lineup since 2015
python3 maps.py                # festival maps -> asset catalog, map list -> info.json
python3 images.py              # artist artwork -> asset catalog (needs `pip install Pillow`)
python3 appicon.py             # regenerates the app icon
python3 applemusic.py --write  # Apple Music catalog id per artist -> schedule.json
```

Run `scrape.py` before `images.py` — the latter reads the artist list and writes each
artist's asset name back into `schedule.json`. `applemusic.py` wants the artist list too,
and is the one script here that doesn't touch the festival site; see
[Top songs](#top-songs-from-apple-music) for what it does and why every artist needs a
pin. Run it with no arguments to check the pins already in the file without writing
anything. Run `guide.py` before `maps.py` for the
same reason: `guide.py` rewrites `info.json` wholesale and `maps.py` adds the `maps`
array back onto it.

`maps.py` picks the maps out of the guide's rich text by the file name the festival's
designer uses (`Grounds_Map`, `Concourse_Map`, `Route`, `Shuttle`), ignoring the
photography alongside them. It exits non-zero if any of the four has gone missing, which
means the artwork was renamed — update `MAPS` at the top of the script.

All four scrapers exit non-zero if they parse nothing, which is the signal that the
site's markup changed and the selectors need attention. `vendors.py` also exits on a
dietary code it doesn't recognise: the codes are printed on the vendor page with no
legend of their own, so a new one means both `DIETARY` in the script and `DietaryTag` in
the app need it added, or it would quietly disappear from the filters.

`python3 validate.py` checks all four files against what the Swift models require —
missing fields, unparseable dates, duplicate ids, dietary codes the app would drop,
Apple Music ids that aren't ids — before a bad file reaches a build. It stays offline;
checking that a catalog id still resolves is `applemusic.py`'s job.

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

## Top songs from Apple Music

`AppleMusicStore` matches each artist in the lineup to their entry in the Apple Music
catalog and keeps their five top songs; `PreviewPlayer` plays the previews.

**Every artist is pinned to a catalog id**, in `appleMusicArtistID` in `schedule.json`,
because matching by name doesn't survive contact with this lineup. A catalog search
always returns *something*, and 18 of the 48 names are shared by more than one act on
Apple Music: five Ambles, five Geese, eight Wisps, seven Samias, eight MUNAs. Showing a
stranger's songs under a band's photograph is worse than showing none, and it is not a
mistake anyone would catch from the outside.

`scripts/applemusic.py` does the pinning and re-checks it. Names only one catalog artist
answers to are resolved automatically; the rest are settled by playing the candidates and
checking them against the artist's own bio, and each one is written down in the script's
`RESOLVED` table with the evidence — *"Cobra" and "Taxes", off Getting Killed* for the
Brooklyn Geese, *Children's Music; "Pop See Ko"* for the Koo Koo on the Miniland stage.
Run with no arguments, it looks every pinned id up again and fails on one that's dead or
now points at a differently named artist.

Two acts are pinned to `"none"`, the sentinel for *we looked, and they aren't there*:
Duo Beats and Sarah Tonin, both Miniland locals whose names several strangers record
under. That is not the same as having no id — no id means "search their name" — and the
artist page drops the Top songs block entirely for them rather than explaining itself
under a heading.

The name search is still there, and it is what an artist added by a mid-festival schedule
refresh gets: an exact match once both names are normalised for case, accents,
punctuation and `&`/`and`, and nothing otherwise.

Previews, not the songs themselves. `ApplicationMusicPlayer` would play the full track,
but only for someone with an Apple Music subscription, and it does it by taking over the
system now-playing queue — cutting off whatever was on in the car. A preview asset plays
for everyone with no subscription at all, which is the right trade for a section whose
job is *what does this band sound like*; the Apple Music link is one tap away for the
rest. Previews play through the ring/silent switch like music rather than being silenced
like a UI sound, and the audio session is handed back on stop so whatever was playing
before resumes.

What comes back is flattened into `ArtistCatalog` — plain `Codable` values, the same
thing `WeatherSnapshot` does to WeatherKit's types — and written to Application Support,
keyed by our artist id. So an artist page opened once on a network still lists their
songs in a field with no signal, with the date it was saved under them; only the previews
themselves need the network. A lookup is trusted for a week. Nothing is bundled: preview
URLs and song rankings would be a year stale by the festival.

Authorization is asked for on a tap on the artist page, never at launch. iOS only ever
asks once, and a media prompt in front of the schedule on first run is one most people
would refuse for the wrong reason. Refused is a state the section says out loud, with a
button through to Settings, rather than a heading with nothing under it.

Nothing here touches the library, the listening history or any playlist — the only
request made is a public catalog lookup, and nothing is written back to Apple Music.

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
| Container | `iCloud.jreed91.hinterland`, named in `CommunityRatings.containerIdentifier` |
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
2. Under the record type's **Indexes**, add a **Queryable** index on `festivalYear`. That
   is the only field the sweep filters on, so it's the only one that needs an index —
   `performanceID` and `stars` come back through `desiredKeys`, which doesn't. Without it
   every query fails with "Field 'festivalYear' is not marked queryable".
3. **Deploy schema to production** before any TestFlight or App Store build. Development
   and production are separate databases; a build that skips this finds an empty container
   and shows no averages.

Step 1 only works from a **development** build — one run from Xcode onto a device or
simulator. Auto-schema is a development-environment convenience and doesn't exist in
production, so a TestFlight build can't create the record type; it writes to the
production database, every save bounces, and the development schema you're watching in the
console stays empty. Rate a set from Xcode, or create the type by hand: **Schema → Record
Types → +**, name it `SetRating`, add `performanceID` (String), `stars` (Int64) and
`festivalYear` (Int64).

### When nothing uploads

`push()` is deliberately quiet — it holds ratings rather than losing them — so the recap
screen's footer is where the reason shows up. In rough order of likelihood:

| What the footer says | What it means |
| --- | --- |
| Sign in to iCloud… | No iCloud account on the device. Writes need one; reads don't, which is why the averages can still appear. Simulators in particular start signed out. |
| iCloud rejected these ratings… | The record type doesn't exist in the environment being written to — usually a TestFlight build against a schema that was never deployed to production. |
| This build isn't set up… | `.badContainer`/`.missingEntitlement`: the entitlement, `CommunityRatings.containerIdentifier` and the container on the App ID don't all agree. |
| Saved on your phone… | Nothing is wrong. There's no signal, the outbox is holding, and it drains on the next foreground with a network. |
| Your ratings uploaded *(time)* | The outbox emptied. If the console still shows nothing, you're looking at the other environment. |

Shared scores are user data leaving the device, so an App Store release needs them
declared in the privacy nutrition label and in a `PrivacyInfo.xcprivacy` the project
doesn't yet carry.

## Past lineups

`Data/past-lineups.json` is the festival's own [archive
page](https://www.hinterlandiowa.com/past-lineups) — ten festivals, 2015 through 2025,
272 acts — scraped by `scripts/past_lineups.py` and bundled like `map.json` and
`vendors.json`. Bundled only: summers that already happened don't change over a weekend,
so there is nothing a refresh could usefully bring down.

It's reached from the clock button in the Schedule tab's toolbar rather than from a tab of
its own. The tab bar is already four items wide with "Food & Drink" in it, and this is
where the festival's own nav files it — under Lineup, next to the set times.

The archive's shape is the site's shape. Each year is a list of days, each day a headliner
and the rest of that day's bill under it, side stages marked the way the site marks them
(`Joe Pera (Campfire Stage)`). What the page never says is *which* day of the weekend a
bill was — there are no dates on it anywhere — so neither does the JSON, and the screen
says as much at the bottom of each year rather than inventing a Friday.

Two things worth knowing about the parsing:

- Webflow pads each year's template with empty slots and pads short bills with paragraphs
  holding a zero-width joiner. Both are dropped; a day with no headliner isn't a day.
- One 2025 Campfire billing is printed "Campire Stage". `STAGE_FIXES` in the script
  corrects it, because the app colours a stage badge by matching the name and an
  unrecognised stage comes out grey next to the Campfire sets either side of it.

The gap at 2020 isn't written down anywhere — `missingYears` derives it from the years
that are there, so the footer explains the jump from 2019 to 2021 on its own, and would
explain the next one without an edit.

The posters the site shows alongside each year are deliberately left on the site: they're
a wall of small type at phone size, and every name on them is already in the bill.

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
  Models/      GuideData, MapData, VendorData, PastLineupData, WeatherData,
               AppleMusicData — Codable mirrors of the JSON and of what's kept from the
               Apple Music catalog
  Services/    ScheduleStore (loading + refresh), WeatherStore, NotificationManager,
               LiveActivityController, Ratings (yours), CommunityRatings (everyone's),
               AppleMusicStore (catalog lookups), PreviewPlayer (30-second previews)
  Views/       Schedule, MyLineup, Ratings, Maps, FoodDrink, ArtistDetail, AppleMusic,
               PastLineups, GroundsMap, MapImage, Weather, WeatherCard, Components
  Resources/   Assets.xcassets — 48 artist images, 4 maps, app icon
HinterlandWidgets/
               the widget extension — UpNextWidget (Home and Lock Screen),
               NowPlayingLiveActivity (Lock Screen and Dynamic Island)
Data/          schedule.json, info.json — bundled and remotely refreshable
               map.json — georeference and POIs for the grounds map
               vendors.json — food & drink stands by area
               past-lineups.json — every lineup since 2015
scripts/       scrapers, the map bundler, the icon generator, the Apple Music pinner
ci_scripts/    ci_post_clone.sh — generates the Xcode project for Xcode Cloud
```

## Notes

Artist photography is pulled from the festival's own CDN and is copyrighted by
Hinterland and the respective photographers. That's fine for a personal or
TestFlight-distributed build; it would need licensing before any public App Store
release.

Song titles, album art and previews come from the Apple Music catalog and belong to
Apple and the rights holders. Apple's terms ask for the service to be named wherever its
content appears, which is what the **Apple Music** link in the Top songs header is doing
as well as being the way out to the full catalog.
