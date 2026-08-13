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
precondition(PlaybackRejoinPolicy.recoversFromEnd(target: 20, duration: 100))
precondition(!PlaybackRejoinPolicy.recoversFromEnd(target: 99.9, duration: 100))
// Buffering is not a user pause: a late participant must still receive Play.
precondition(PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: true, desiredIsPlaying: true, isActuallyAdvancing: false
))
precondition(!PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: false, desiredIsPlaying: true, isActuallyAdvancing: false
))
precondition(!PlaybackRejoinPolicy.snapshotIsPlaying(
    isOwner: true, desiredIsPlaying: false, isActuallyAdvancing: true
))

print("Playback rejoin policy tests passed")
