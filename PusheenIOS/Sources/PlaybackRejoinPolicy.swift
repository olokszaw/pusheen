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

    /// A REST snapshot and a WebSocket state can legitimately carry the same
    /// playback sequence.  Their projected positions are calculated at
    /// different instants, though, so a slow older REST response must not be
    /// allowed to rewind a newer WebSocket state with that same sequence.
    /// A higher sequence remains authoritative even when clocks disagree.
    static func acceptsTimestamp(
        incomingSequence: Int64?,
        latestSequence: Int64?,
        incomingDate: Date?,
        latestDate: Date?
    ) -> Bool {
        guard let incomingDate, let latestDate else { return true }
        if let incomingSequence, let latestSequence, incomingSequence != latestSequence {
            return true
        }
        return incomingDate >= latestDate
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

    /// Decides whether an incoming server clock must move the local player.
    /// The first state of every socket generation is always authoritative.
    /// Afterwards the owner keeps its optimistic local clock, while guests
    /// apply explicit commands and correct material drift from periodic state.
    static func shouldApplyRemotePosition(
        firstStateForConnection: Bool,
        isOwner: Bool,
        command: String,
        isPlaying: Bool,
        drift: Double
    ) -> Bool {
        if firstStateForConnection { return true }
        guard !isOwner else { return false }
        if command != "state" || !isPlaying { return true }
        return drift > 2.5
    }

    /// A logical Play received from the server remains the user's intent while
    /// AVPlayer is waiting for enough media. It is safe to retry only after the
    /// authoritative seek is complete and the item has not reached its end.
    static func shouldMaintainPlaybackIntent(
        desiredIsPlaying: Bool,
        hasPendingSeek: Bool,
        hasReachedEnd: Bool
    ) -> Bool {
        desiredIsPlaying && !hasPendingSeek && !hasReachedEnd
    }

    /// While AVPlayer is seeking, `currentTime()` still describes the old
    /// rendered frame. Compare a newer remote command with the in-flight seek
    /// target instead; otherwise a command back to the old frame (commonly
    /// 00:00) looks like zero drift and the stale seek wins afterwards.
    static func driftReferencePosition(
        pendingSeekPosition: Double?,
        playerPosition: Double?,
        publishedPosition: Double
    ) -> Double {
        if let pendingSeekPosition, pendingSeekPosition.isFinite {
            return pendingSeekPosition
        }
        if let playerPosition, playerPosition.isFinite {
            return playerPosition
        }
        return publishedPosition.isFinite ? publishedPosition : 0
    }
}
