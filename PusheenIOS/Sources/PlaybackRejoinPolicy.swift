import Foundation

/// Pure playback decisions shared by the room lifecycle and executable tests.
enum PlaybackRejoinPolicy {
    static func clampedPosition(_ remote: Double, knownDuration: Double) -> Double {
        let nonnegative = max(0, remote.isFinite ? remote : 0)
        guard knownDuration.isFinite, knownDuration > 0 else { return nonnegative }
        return min(nonnegative, knownDuration)
    }

    static func accepts(
        incomingSequence: Int64,
        latestSequence: Int64?,
        authoritativeConnectionSnapshot: Bool
    ) -> Bool {
        authoritativeConnectionSnapshot || latestSequence.map { incomingSequence >= $0 } ?? true
    }

    /// AVPlayer keeps an item in its terminal state after the final frame. A
    /// seek sufficiently behind the end is an explicit recovery from it.
    static func recoversFromEnd(target: Double, duration: Double) -> Bool {
        guard target.isFinite, duration.isFinite, duration > 0 else { return false }
        return target < duration - 0.25
    }

    /// The owner's logical play/pause intent is the shared room state. AVPlayer
    /// may temporarily report `waitingToPlayAtSpecifiedRate` while buffering;
    /// publishing that transient condition as Pause freezes late joiners until
    /// the next manual seek. Guests still report their real advancing state for
    /// their own muted profile preview.
    static func snapshotIsPlaying(
        isOwner: Bool,
        desiredIsPlaying: Bool,
        isActuallyAdvancing: Bool
    ) -> Bool {
        isOwner ? desiredIsPlaying : isActuallyAdvancing
    }
}
