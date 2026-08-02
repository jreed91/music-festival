import SwiftUI
import UIKit

/// The "Top songs" block on an artist page: five tracks from the Apple Music catalog,
/// each playable as a 30-second preview, with the artist's Apple Music page a tap away.
///
/// Every state this can be in gets a line of its own — asked and not answered, refused,
/// looked up and not found, no signal — because a heading with nothing under it is
/// indistinguishable from a feature that's broken, and on a phone in a field the
/// difference matters.
struct AppleMusicSection: View {
    let artist: Artist

    @Environment(AppleMusicStore.self) private var music
    @Environment(PreviewPlayer.self) private var preview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            if let error = preview.lastError {
                Text(error)
                    .appFont(12)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Cheap on every appearance: the store returns without a network call while the
        // cached lookup is fresh, and does nothing at all until access is granted.
        .task(id: artist.id) { await music.load(artist) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Top songs")
                .appFont(13, weight: .bold)
                .foregroundStyle(Theme.tertiaryText)
            Spacer(minLength: 0)
            // Apple asks for the service to be named wherever its content appears, and
            // it doubles as the way out to the full catalog.
            if let url = music.artistURL(for: artist) {
                Link(destination: url) {
                    Label("Apple Music", systemImage: "music.note")
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch music.access {
        case .ready:
            songs
        case .needsPermission:
            prompt
        case .denied:
            note("Apple Music access is off for Hinterland, so there's nothing to play here.")
            settingsButton
        case .unavailable:
            note("Apple Music isn't available on this phone.")
        }
    }

    /// The first tap is the permission prompt. Worth its own button rather than asking on
    /// arrival: the page is useful without this, and iOS only ever asks once.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            note("Play 30-second previews of their best-known songs. Nothing is added to "
               + "your library, and nothing is shared.")
            Button {
                Task {
                    await music.requestAuthorization()
                    await music.load(artist)
                }
            } label: {
                Label("Turn on previews", systemImage: "play.circle.fill")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var songs: some View {
        let entry = music.entry(for: artist)

        if let entry, !entry.topSongs.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(entry.topSongs.enumerated()), id: \.element.id) { index, track in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    TrackRow(track: track,
                             isPlaying: preview.isPlaying(track),
                             onToggle: { preview.toggle(track) })
                }
            }
            .background(Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // Said out loud, because a list of songs that hasn't changed in a week looks
            // exactly like a list that just loaded.
            if entry.isStale() {
                note("Saved \(entry.fetchedAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        } else if music.isLoading(artist) {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.tertiaryText)
                Text("Looking them up on Apple Music…")
                    .appFont(13)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 4)
        } else if let failure = music.failure(for: artist) {
            note(failure)
        } else if let entry, !entry.isMatched {
            note("We couldn't match them to an artist on Apple Music.")
        } else if entry?.topSongs.isEmpty == true {
            note("Apple Music doesn't list any top songs for them yet.")
        } else {
            note("Songs load the next time this page is open on a network.")
        }
    }

    private var settingsButton: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            Label("Open Settings", systemImage: "gear")
                .appFont(13, weight: .semibold)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .appFont(13)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One song. The whole row is the play button — a 30-second preview is not something to
/// aim at a 20pt target for, in the dark, in a crowd.
private struct TrackRow: View {
    let track: CatalogTrack
    let isPlaying: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .appFont(15, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let album = track.albumTitle {
                        Text(album)
                            .appFont(12)
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .appFont(26)
                    .foregroundStyle(Theme.accent)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPlaying
                            ? "Stop preview of \(track.title)"
                            : "Play a preview of \(track.title)")
    }

    private var artwork: some View {
        Group {
            if let url = track.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.surfaceRaised
                }
            } else {
                Theme.surfaceRaised
            }
        }
        // Deliberately not scaled with Dynamic Type: it's a piece of album art, not text.
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
