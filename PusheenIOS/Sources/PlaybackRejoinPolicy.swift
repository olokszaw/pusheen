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

    static func acknowledgesPendingCommand(
        expectedSequence: Int64?,
        incomingSequence: Int64?,
        legacyPayloadMatches: Bool
    ) -> Bool {
        if let expectedSequence, let incomingSequence {
            return incomingSequence >= expectedSequence
        }
        return expectedSequence == nil && incomingSequence == nil && legacyPayloadMatches
    }

    /// Re-send only after a new connection authority or an explicit stale
    /// correction. An intermediate Seek acknowledgement in a rapid Seek→Play
    /// sequence must not duplicate or overwrite the newer queued Play.
    static func shouldReplayPendingCommand(
        firstStateForConnection: Bool,
        command: String
    ) -> Bool {
        firstStateForConnection || command == "stale"
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

    /// Periodic `state` heartbeats describe the clock but are not playback
    /// commands. Seeking a buffering guest on every heartbeat discards the
    /// buffer it has just accumulated and can keep that device frozen forever.
    /// Entry/reconnect and explicit owner commands remain authoritative.
    static func shouldSeekForRemoteState(
        firstStateForConnection: Bool,
        command: String,
        isPlaying: Bool
    ) -> Bool {
        firstStateForConnection || command != "state" || !isPlaying
    }

    /// A participant that has made no progress for several seconds may use the
    /// latest projected server clock as a one-off recovery target. Normal
    /// buffering never reaches this path, so it is not disrupted by polling.
    static func projectedRecoveryPosition(
        anchor: Double,
        elapsed: Double,
        isPlaying: Bool,
        knownDuration: Double
    ) -> Double {
        clampedPosition(anchor + (isPlaying ? max(0, elapsed) : 0), knownDuration: knownDuration)
    }

    static func shouldAttemptStallSeek(stalledFor: Double, alreadyAttempted: Bool) -> Bool {
        stalledFor >= 7 && !alreadyAttempted
    }
}
