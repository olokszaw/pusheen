import Foundation

// Before AVPlayer loads duration, the server's 10:00 position must remain
// 10:00. The old `duration = 1` code converted this to 00:01.
precondition(PlaybackRejoinPolicy.clampedPosition(600, knownDuration: 0) == 600)
precondition(PlaybackRejoinPolicy.clampedPosition(600, knownDuration: 1_800) == 600)
precondition(PlaybackRejoinPolicy.clampedPosition(2_000, knownDuration: 1_800) == 1_800)

precondition(PlaybackRejoinPolicy.accepts(
    incomingSequence: 8, latestSequence: 7, authoritativeConnectionSnapshot: false
))
precondition(!PlaybackRejoinPolicy.accepts(
    incomingSequence: 6, latestSequence: 7, authoritativeConnectionSnapshot: false
))
precondition(PlaybackRejoinPolicy.accepts(
    incomingSequence: 6, latestSequence: 7, authoritativeConnectionSnapshot: true
))
precondition(PlaybackRejoinPolicy.acknowledgesPendingCommand(
    expectedSequence: 12, incomingSequence: 12, legacyPayloadMatches: false
))
precondition(!PlaybackRejoinPolicy.acknowledgesPendingCommand(
    expectedSequence: 12, incomingSequence: 11, legacyPayloadMatches: true
))
precondition(PlaybackRejoinPolicy.acknowledgesPendingCommand(
    expectedSequence: nil, incomingSequence: nil, legacyPayloadMatches: true
))
precondition(PlaybackRejoinPolicy.shouldReplayPendingCommand(
    firstStateForConnection: true, command: "state"
))
precondition(PlaybackRejoinPolicy.shouldReplayPendingCommand(
    firstStateForConnection: false, command: "stale"
))
precondition(!PlaybackRejoinPolicy.shouldReplayPendingCommand(
    firstStateForConnection: false, command: "seek"
))
precondition(PlaybackRejoinPolicy.recoversFromEnd(target: 20, duration: 100))
precondition(!PlaybackRejoinPolicy.recoversFromEnd(target: 99.9, duration: 100))
// Buffering is not a user pause: a late participant must still receive Play.
precondition(PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: true, desiredIsPlaying: true, isActuallyAdvancing: false
))
precondition(!PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: false, desiredIsPlaying: true, isActuallyAdvancing: false
))

precondition(!PlaybackRejoinPolicy.shouldSeekForRemoteState(
    firstStateForConnection: false, command: "state", isPlaying: true
))
precondition(PlaybackRejoinPolicy.shouldSeekForRemoteState(
    firstStateForConnection: true, command: "state", isPlaying: true
))
precondition(PlaybackRejoinPolicy.shouldSeekForRemoteState(
    firstStateForConnection: false, command: "seek", isPlaying: true
))
precondition(PlaybackRejoinPolicy.projectedRecoveryPosition(
    anchor: 100, elapsed: 7, isPlaying: true, knownDuration: 500
) == 107)
precondition(PlaybackRejoinPolicy.projectedRecoveryPosition(
    anchor: 498, elapsed: 7, isPlaying: true, knownDuration: 500
) == 500)
precondition(!PlaybackRejoinPolicy.shouldAttemptStallSeek(
    stalledFor: 24.9, alreadyAttempted: false
))
precondition(PlaybackRejoinPolicy.shouldAttemptStallSeek(
    stalledFor: 25, alreadyAttempted: false
))
precondition(!PlaybackRejoinPolicy.shouldAttemptStallSeek(
    stalledFor: 30, alreadyAttempted: true
))
precondition(!PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: true, desiredIsPlaying: false, isActuallyAdvancing: true
))
precondition(PlaybackRejoinPolicy.shouldRecoverUnexpectedZeroReset(
    isOwner: false, isPlaying: true, actualPosition: 0,
    previousHealthyPosition: 120, authoritativePosition: 123
))
precondition(!PlaybackRejoinPolicy.shouldRecoverUnexpectedZeroReset(
    isOwner: true, isPlaying: true, actualPosition: 0,
    previousHealthyPosition: 120, authoritativePosition: 123
))
precondition(PlaybackRejoinPolicy.shouldCatchUpParticipant(
    isOwner: false, isPlaying: true, isPlayerAdvancing: true, command: "state",
    localPosition: 100, authoritativePosition: 104
))
precondition(!PlaybackRejoinPolicy.shouldCatchUpParticipant(
    isOwner: false, isPlaying: true, isPlayerAdvancing: true, command: "state",
    localPosition: 104, authoritativePosition: 100
), "Periodic state must never rewind a participant")
precondition(!PlaybackRejoinPolicy.shouldCatchUpParticipant(
    isOwner: false, isPlaying: true, isPlayerAdvancing: false, command: "state",
    localPosition: 100, authoritativePosition: 120
), "A buffering participant must be allowed to fill its range buffer")

precondition(PlaybackRejoinPolicy.participantCatchUpRate(
    isOwner: false, isPlaying: true, isPlayerAdvancing: true,
    isPlaybackLikelyToKeepUp: true, command: "state",
    localPosition: 100, authoritativePosition: 109
) == 1.06)
precondition(PlaybackRejoinPolicy.participantCatchUpRate(
    isOwner: false, isPlaying: true, isPlayerAdvancing: true,
    isPlaybackLikelyToKeepUp: true, command: "state",
    localPosition: 100, authoritativePosition: 104
) == 1.03)
precondition(PlaybackRejoinPolicy.participantCatchUpRate(
    isOwner: false, isPlaying: true, isPlayerAdvancing: false,
    isPlaybackLikelyToKeepUp: false, command: "state",
    localPosition: 100, authoritativePosition: 109
) == 1, "A buffering guest must not be forced to consume data faster")
precondition(PlaybackRejoinPolicy.nonRewindingRecoveryPosition(
    projectedAuthoritativePosition: 98,
    localPosition: 101,
    previousHealthyPosition: 103,
    knownDuration: 500
) == 103)
precondition(PlaybackRejoinPolicy.shouldUseBufferedExactCatchUp(
    isOwner: false, isPlaying: true, command: "state",
    lag: 4, targetIsBuffered: true
))
precondition(!PlaybackRejoinPolicy.shouldUseBufferedExactCatchUp(
    isOwner: false, isPlaying: true, command: "state",
    lag: 4, targetIsBuffered: false
), "Never seek a weak connection into an unloaded range")
precondition(PlaybackRejoinPolicy.shouldHoldParticipantForOwner(
    isOwner: false, isPlaying: true, ownerClockIsFresh: false, ownerClockAdvancing: true,
    localPosition: 1_585, authoritativePosition: 1_513
), "A guest must stop when the owner's physical clock disappears")
precondition(!PlaybackRejoinPolicy.shouldHoldParticipantForOwner(
    isOwner: false, isPlaying: true, ownerClockIsFresh: true, ownerClockAdvancing: true,
    localPosition: 1_515, authoritativePosition: 1_513
), "An ahead guest must seek to the owner instead of merely waiting")
precondition(!PlaybackRejoinPolicy.shouldHoldParticipantForOwner(
    isOwner: false, isPlaying: true, ownerClockIsFresh: true, ownerClockAdvancing: true,
    localPosition: 1_513.5, authoritativePosition: 1_513
))
precondition(PlaybackRejoinPolicy.shouldHoldParticipantForOwner(
    isOwner: false, isPlaying: true, ownerClockIsFresh: true, ownerClockAdvancing: false,
    localPosition: 1_513, authoritativePosition: 1_513
), "Guests must buffer on the same frame as the owner")
precondition(PlaybackRejoinPolicy.shouldSeekToExactOwnerClock(
    isOwner: false, command: "owner_clock", drift: -600,
    ownerClockAdvancing: true
), "A guest ten minutes ahead must immediately seek back to the owner")
precondition(PlaybackRejoinPolicy.shouldSeekToExactOwnerClock(
    isOwner: false, command: "owner_clock", drift: 0.36,
    ownerClockAdvancing: true
))
precondition(!PlaybackRejoinPolicy.shouldSeekToExactOwnerClock(
    isOwner: false, command: "owner_clock", drift: 0.30,
    ownerClockAdvancing: true
))
precondition(PlaybackRejoinPolicy.exactSyncRate(
    isOwner: false, command: "owner_clock", drift: 0.20,
    ownerClockAdvancing: true, targetIsBuffered: true
) == 1.03)
precondition(PlaybackRejoinPolicy.exactSyncRate(
    isOwner: false, command: "owner_clock", drift: -0.20,
    ownerClockAdvancing: true, targetIsBuffered: true
) == 0.97)

print("Playback rejoin policy tests passed")
