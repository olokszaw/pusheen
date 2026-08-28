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
        // A slow connection can legitimately spend several seconds filling the
        // forward buffer. Seeking during that wait throws the partial range
        // away and may land on an earlier keyframe. Keep a seek as a last-resort
        // recovery for a genuinely wedged request, not ordinary buffering.
        stalledFor >= 25 && !alreadyAttempted
    }

    /// Catch a guest up without throwing away its HTTP/HLS buffer. A tiny rate
    /// increase is deliberately used only after AVPlayer says the buffered
    /// media is likely to keep up; a weak connection stays at 1x and continues
    /// accumulating data instead of entering another stall.
    static func participantCatchUpRate(
        isOwner: Bool,
        isPlaying: Bool,
        isPlayerAdvancing: Bool,
        isPlaybackLikelyToKeepUp: Bool,
        command: String,
        localPosition: Double,
        authoritativePosition: Double
    ) -> Float {
        guard !isOwner,
              isPlaying,
              isPlayerAdvancing,
              isPlaybackLikelyToKeepUp,
              command == "state" else { return 1 }
        let lag = authoritativePosition - localPosition
        if lag > 8 { return 1.06 }
        if lag > 2 { return 1.03 }
        return 1
    }

    /// Jump to the exact shared clock only when that frame is already on the
    /// device. A forward seek into an unloaded range is not synchronization on
    /// a weak connection—it is just another visible spinner.
    static func shouldUseBufferedExactCatchUp(
        isOwner: Bool,
        isPlaying: Bool,
        command: String,
        lag: Double,
        targetIsBuffered: Bool
    ) -> Bool {
        !isOwner
            && isPlaying
            && command == "state"
            && lag > 3
            && targetIsBuffered
    }

    /// If the owner clock stops reporting, or this device somehow gets ahead,
    /// hold the guest's frame until the authoritative clock catches up. This
    /// restores exact synchronization without ever showing a backwards seek.
    static func shouldHoldParticipantForOwner(
        isOwner: Bool,
        isPlaying: Bool,
        ownerClockIsFresh: Bool,
        localPosition: Double,
        authoritativePosition: Double
    ) -> Bool {
        !isOwner
            && isPlaying
            && (!ownerClockIsFresh || localPosition - authoritativePosition > 1.0)
    }

    /// A last-resort recovery must never move a participant behind the frame
    /// already displayed. Approximate keyframe seeking can otherwise look like
    /// a short rewind after a network stall.
    static func nonRewindingRecoveryPosition(
        projectedAuthoritativePosition: Double,
        localPosition: Double,
        previousHealthyPosition: Double,
        knownDuration: Double
    ) -> Double {
        clampedPosition(
            max(projectedAuthoritativePosition, max(localPosition, previousHealthyPosition)),
            knownDuration: knownDuration
        )
    }

    /// Some HTTP AVPlayer items jump their local clock to exactly zero while
    /// recovering a range request. A participant must return to the shared room
    /// clock instead of publishing/displaying that decoder reset.
    static func shouldRecoverUnexpectedZeroReset(
        isOwner: Bool,
        isPlaying: Bool,
        actualPosition: Double,
        previousHealthyPosition: Double,
        authoritativePosition: Double
    ) -> Bool {
        !isOwner
            && isPlaying
            && actualPosition.isFinite
            && actualPosition <= 1.25
            && previousHealthyPosition >= 5
            && authoritativePosition >= 5
    }

    /// Periodic state may pull a lagging participant forward, but never rewind
    /// it. Backward movement is reserved for an explicit owner seek command.
    static func shouldCatchUpParticipant(
        isOwner: Bool,
        isPlaying: Bool,
        isPlayerAdvancing: Bool,
        command: String,
        localPosition: Double,
        authoritativePosition: Double
    ) -> Bool {
        !isOwner
            && isPlaying
            && isPlayerAdvancing
            && command == "state"
            && authoritativePosition - localPosition > 3
    }
}
