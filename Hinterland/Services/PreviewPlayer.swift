import AVFoundation
import Foundation
import Observation

/// Plays the 30-second previews on the artist page.
///
/// Previews rather than the songs themselves, which is the whole design of this feature.
/// `ApplicationMusicPlayer` can play the full track, but only for someone with an Apple
/// Music subscription, and it does it by taking over the system now-playing queue —
/// stopping whatever was on in the car on the way to the valley. A preview asset plays
/// for everyone with no subscription at all, which is the right trade for a section whose
/// job is "what does this band sound like", and full playback is one tap away through the
/// Apple Music link.
///
/// One track at a time on purpose: starting a second preview stops the first, so the row
/// showing a pause button is always the row making the noise.
@MainActor
@Observable
final class PreviewPlayer {
    /// The track playing right now, by catalog id.
    private(set) var playingID: String?
    /// Nil unless the last attempt failed. Cleared by the next one.
    private(set) var lastError: String?

    private var player: AVPlayer?
    private var observers: [NSObjectProtocol] = []

    func isPlaying(_ track: CatalogTrack) -> Bool { playingID == track.id }

    /// Tapping the row that's playing stops it; tapping any other row switches to it.
    func toggle(_ track: CatalogTrack) {
        guard playingID != track.id else {
            stop()
            return
        }
        guard let url = track.previewURL else {
            teardown()
            playingID = nil
            lastError = "Apple Music has no preview for that one."
            return
        }
        play(url, id: track.id)
    }

    /// Also clears the last failure: it belonged to the page being left, and carrying it
    /// onto the next artist would blame them for it.
    func stop() {
        teardown()
        playingID = nil
        lastError = nil
    }

    private func play(_ url: URL, id: String) {
        teardown()

        // A preview is music, so it plays through the ring/silent switch the way music
        // does rather than being silenced like a UI sound — someone checking a band on a
        // muted phone should hear something.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // Previews stream, so a phone that has the cached song list but no signal gets a
        // row that says why nothing happened instead of a button that silently does
        // nothing. Both notifications are per-item, which is why they're re-registered on
        // every play and torn down alongside the player.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            })

        playingID = id
        lastError = nil
        player.play()
    }

    private func fail() {
        teardown()
        playingID = nil
        lastError = "That preview wouldn't load — previews need a signal."
    }

    /// Hands the audio session back so whatever was playing before resumes rather than
    /// staying paused for the rest of the walk to the next stage.
    private func teardown() {
        player?.pause()
        player = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
