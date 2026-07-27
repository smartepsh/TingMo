import Foundation

/// Pauses system media playback while dictation records and resumes it
/// afterwards — the macOS counterpart of iOS audio-session interruption,
/// which AppKit does not provide.
///
/// Both directions go through `NowPlayingRemote`: an explicit MediaRemote
/// pause command on record start, an explicit play command on teardown.
/// Earlier versions guessed "is something playing?" from CoreAudio device
/// activity and acted by posting the hardware play/pause key — a toggle
/// that could *start* a paused track, and that makes macOS launch Apple
/// Music when no Now Playing app exists. With explicit commands neither
/// misfire is possible, so when the playback state is unknown the guard
/// simply leaves the media alone instead of guessing.
final class MediaPlaybackGuard {
    private let isNowPlayingAppPlaying: () -> Bool?
    private let nowPlayingPID: () -> pid_t?
    private let pausePlayback: () -> Void
    private let resumePlayback: () -> Void

    /// True while we owe the media app a resume. Exposed for tests.
    private(set) var pausedByUs = false
    /// The Now Playing app we paused, so resume can refuse to touch a
    /// different app the user switched to mid-recording.
    private var pausedPID: pid_t?

    init(
        isNowPlayingAppPlaying: @escaping () -> Bool? = NowPlayingRemote.isPlaying,
        nowPlayingPID: @escaping () -> pid_t? = NowPlayingRemote.nowPlayingApplicationPID,
        pausePlayback: @escaping () -> Void = { NowPlayingRemote.pause() },
        resumePlayback: @escaping () -> Void = { NowPlayingRemote.play() }
    ) {
        self.isNowPlayingAppPlaying = isNowPlayingAppPlaying
        self.nowPlayingPID = nowPlayingPID
        self.pausePlayback = pausePlayback
        self.resumePlayback = resumePlayback
    }

    /// Pause playback only when the Now Playing app is definitely playing
    /// right now. Unknown state (no Now Playing app, MediaRemote
    /// unavailable, query timeout) means do nothing: skipping a pause costs
    /// at most one noisy recording, while acting on a guess is what used to
    /// start paused tracks and summon Apple Music.
    func pauseForRecording() {
        pausedByUs = false
        pausedPID = nil
        guard isNowPlayingAppPlaying() == true else { return }
        pausedPID = nowPlayingPID()
        pausePlayback()
        pausedByUs = true
    }

    /// Resume playback, but only when `pauseForRecording()` actually paused
    /// something. Safe to call from every recording-teardown path; it
    /// resumes at most once per pause.
    func resumeAfterRecording() {
        guard pausedByUs else { return }
        pausedByUs = false
        let pausedPID = self.pausedPID
        self.pausedPID = nil

        // The user may have switched Now Playing apps or resumed playback
        // manually while we recorded; in either case the pause we owed is
        // no longer ours to undo.
        if let pausedPID, let currentPID = nowPlayingPID(), currentPID != pausedPID { return }
        if isNowPlayingAppPlaying() == true { return }
        resumePlayback()
    }
}
