import Foundation

/// What the app keeps from the Apple Music catalog about one artist.
///
/// The same flattening `WeatherSnapshot` does to WeatherKit's types, and for the same
/// reason: MusicKit's `Artist` and `Song` can't be archived, and the whole point of
/// caching is that the artist page still lists their songs on a phone with no signal.
/// Everything here is a plain `Codable` value written to Application Support.
struct ArtistCatalog: Codable, Equatable {
    /// How long a lookup is trusted before the artist page fetches a fresher one. Top
    /// songs move over weeks, not over a festival weekend, so this is deliberately long —
    /// the cache is what makes the section work in the valley.
    static let freshness: TimeInterval = 7 * 24 * 3600

    /// Our artist id, from `schedule.json`.
    let artistID: String
    /// Apple's catalog id. Nil records the other outcome — we searched and found nothing
    /// we were confident enough about to show — so a support act nobody has released
    /// anything for isn't re-searched on every visit to their page.
    let catalogID: String?
    /// Their page in Apple Music, for the link button.
    let artistURL: URL?
    let topSongs: [CatalogTrack]
    let fetchedAt: Date

    var isMatched: Bool { catalogID != nil }

    func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) > Self.freshness
    }
}

/// One song, reduced to what a row on the artist page draws and what the preview player
/// needs to play it.
struct CatalogTrack: Codable, Equatable, Identifiable, Hashable {
    /// Apple's catalog id for the song, which is also what the player uses to say which
    /// row is playing.
    let id: String
    let title: String
    let albumTitle: String?
    let artworkURL: URL?
    /// The 30-second preview. Optional because the catalog occasionally has a song with
    /// no preview asset, and a row that can't play says so rather than doing nothing.
    let previewURL: URL?
    /// The song in Apple Music, where the whole thing can be played.
    let url: URL?
    let duration: TimeInterval?
}

extension Artist {
    /// What `appleMusicArtistID` says for an artist who was checked against the catalog
    /// and isn't in it — a local act on the Miniland stage whose name several strangers
    /// also record under. It isn't the same as having no id at all: no id means "find
    /// them by name", and this means "don't, we already looked".
    ///
    /// `scripts/applemusic.py` writes it, and carries the reason next to each one.
    static let appleMusicUnavailable = "none"

    var isOnAppleMusic: Bool { appleMusicArtistID != Self.appleMusicUnavailable }

    /// The Apple Music search page for this artist, which is the fallback for the link
    /// button before — or without — a catalog lookup. It works with no authorization at
    /// all, so the button is never dead.
    var appleMusicSearchURL: URL? {
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: name)]
        return components?.url
    }
}
