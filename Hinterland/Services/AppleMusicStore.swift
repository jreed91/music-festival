import Foundation
import MusicKit
import Observation

/// Resolves each artist in the lineup to their Apple Music catalog entry and remembers
/// their top songs.
///
/// Note the two `Artist` types in this file. Bare `Artist` is ours, out of
/// `schedule.json`; MusicKit has one of its own and it is always written
/// `MusicKit.Artist` here. Swift resolves the unqualified name to this module's type, so
/// the two never get mixed up, but the qualification is worth the noise given how close
/// together they sit.
///
/// The same offline-first bargain as everything else in here: whatever was last looked up
/// is loaded from disk at launch and drawn immediately, the network is an upgrade path,
/// and a failed lookup leaves the cached songs on screen. Unlike the schedule there is
/// nothing to bundle — song rankings and preview URLs would be a year stale by the
/// festival, and Apple's terms don't allow shipping catalog data in a binary anyway — so
/// before an artist's page has ever been opened with signal there is simply nothing to
/// show, and the section says so.
///
/// Nothing here touches the user's library, their listening history or their playlists.
/// The only thing it asks Apple Music for is a public catalog lookup.
@MainActor
@Observable
final class AppleMusicStore {
    /// Enough to tell what a band sounds like while standing in front of a stage
    /// deciding whether to stay. A full discography is what the Apple Music link is for.
    private static let songLimit = 5
    /// Search results to consider before giving up on a name. Apple ranks by popularity,
    /// so the band we want is at the top or nowhere.
    private static let searchLimit = 8

    private(set) var authorization: MusicAuthorization.Status
    /// Keyed by our artist id.
    private(set) var catalog: [String: ArtistCatalog]
    private(set) var loading: Set<String> = []
    /// Per artist, because each page fetches on its own and one artist's failure says
    /// nothing about the next one's.
    private(set) var failures: [String: String] = [:]

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("apple-music.json")
    }

    init() {
        authorization = MusicAuthorization.currentStatus
        catalog = Self.loadCache()
    }

    // MARK: - Reading

    func entry(for artist: Artist) -> ArtistCatalog? { catalog[artist.id] }
    func isLoading(_ artist: Artist) -> Bool { loading.contains(artist.id) }
    func failure(for artist: Artist) -> String? { failures[artist.id] }

    /// Their Apple Music page once we've found them, a search for their name until then —
    /// which is what keeps the link button honest before the user has granted anything.
    /// Nil only for the artists the schedule says aren't on Apple Music at all, where a
    /// search would land on somebody else with their name.
    func artistURL(for artist: Artist) -> URL? {
        guard artist.isOnAppleMusic else { return nil }
        return catalog[artist.id]?.artistURL ?? artist.appleMusicSearchURL
    }

    // MARK: - Authorization

    /// What the artist page can offer right now. A plain enum rather than MusicKit's
    /// status so the view layer doesn't import MusicKit to draw four cases — and so the
    /// two `Artist` types never meet in a file full of SwiftUI.
    enum Access {
        /// Granted: songs load, previews play.
        case ready
        /// Never asked. The section offers the prompt.
        case needsPermission
        /// Asked and refused, which Settings is the only way back from.
        case denied
        /// Screen Time or an MDM profile; nothing the app can ask for.
        case unavailable
    }

    var access: Access {
        switch authorization {
        case .authorized: return .ready
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .needsPermission
        @unknown default: return .needsPermission
        }
    }

    /// Asked for on a tap on the artist page, never at launch. The app is a schedule
    /// first, and a media permission prompt in front of the schedule on first run is a
    /// prompt most people would refuse for the wrong reason.
    func requestAuthorization() async {
        authorization = await MusicAuthorization.request()
    }

    // MARK: - Lookup

    /// Best effort, always — a failed lookup leaves whatever was cached on screen.
    ///
    /// Cheap to call on every appearance of an artist page: it returns without touching
    /// the network while the cached entry is fresh.
    func load(_ artist: Artist, force: Bool = false) async {
        guard artist.isOnAppleMusic else { return }
        guard authorization == .authorized else { return }
        guard !loading.contains(artist.id) else { return }
        if !force, let cached = catalog[artist.id], !cached.isStale() { return }

        loading.insert(artist.id)
        defer { loading.remove(artist.id) }

        do {
            let entry: ArtistCatalog
            if let match = try await resolve(artist) {
                // `topSongs` is a relationship, so neither the search nor the id lookup
                // fills it in — the artist has to be fetched again asking for it.
                let detailed = try await match.with(.topSongs)
                let songs = detailed.topSongs.map { Array($0.prefix(Self.songLimit)) } ?? []
                entry = ArtistCatalog(artistID: artist.id,
                                      catalogID: match.id.rawValue,
                                      artistURL: match.url,
                                      topSongs: songs.map { CatalogTrack($0) },
                                      fetchedAt: Date())
            } else {
                entry = ArtistCatalog(artistID: artist.id, catalogID: nil, artistURL: nil,
                                      topSongs: [], fetchedAt: Date())
            }
            catalog[artist.id] = entry
            failures[artist.id] = nil
            persist()
        } catch {
            failures[artist.id] = Self.message(for: error)
        }
    }

    /// Finds the artist in the catalog, by the id the schedule pins them to and by name
    /// for anyone it doesn't.
    ///
    /// Every artist in the bundled lineup carries an id, checked one at a time by
    /// `scripts/applemusic.py` — 18 of the 48 share their name with another act on Apple
    /// Music, and 2 of them aren't on it at all. The search is the path for an artist a
    /// schedule refresh added after the build, and it accepts an exact match and nothing
    /// else, once both names are normalised. Apple always returns *something*; showing a
    /// stranger's songs under a band's photo is worse than showing none, and it isn't a
    /// mistake anyone would catch from the outside.
    private func resolve(_ artist: Artist) async throws -> MusicKit.Artist? {
        if let catalogID = artist.appleMusicArtistID, !catalogID.isEmpty {
            let request = MusicCatalogResourceRequest<MusicKit.Artist>(
                matching: \.id, equalTo: MusicItemID(catalogID))
            return try await request.response().items.first
        }

        var search = MusicCatalogSearchRequest(term: artist.name, types: [MusicKit.Artist.self])
        search.limit = Self.searchLimit
        let response = try await search.response()
        let wanted = Self.normalized(artist.name)
        return response.artists.first { Self.normalized($0.name) == wanted }
    }

    /// Case, accents, punctuation and spacing all differ between the festival's own
    /// listing and Apple's — "Quintron & Miss Pussycat" against "Quintron and Miss
    /// Pussycat", "AUDREY NUNA" against "Audrey Nuna". None of those are different bands.
    private static func normalized(_ name: String) -> String {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// MusicKit's failures down here mean one of three things: no signal, a build whose
    /// App ID doesn't carry the MusicKit capability, or the catalog declining the
    /// request. None of them is worth more than a line under a heading.
    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No signal — songs load next time you're on a network."
            case .timedOut:
                return "Apple Music took too long to answer."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Cache

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    private func persist() {
        guard let payload = try? Self.coder().0.encode(catalog) else { return }
        try? payload.write(to: Self.cacheURL, options: .atomic)
    }

    /// A cache we can't read is a cache we don't have — the app starts with no songs and
    /// looks them up again.
    private static func loadCache() -> [String: ArtistCatalog] {
        guard let payload = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? coder().1.decode([String: ArtistCatalog].self, from: payload)) ?? [:]
    }
}

// MARK: - MusicKit → catalog

private extension CatalogTrack {
    init(_ song: Song) {
        self.init(
            id: song.id.rawValue,
            title: song.title,
            albumTitle: song.albumTitle,
            // Artwork URLs are templated by pixel size; this is the 44pt row thumbnail at
            // 3x, which is the largest any screen asks for.
            artworkURL: song.artwork?.url(width: 132, height: 132),
            previewURL: song.previewAssets?.first?.url,
            url: song.url,
            duration: song.duration)
    }
}
