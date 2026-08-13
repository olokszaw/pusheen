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
let newerStateDate = Date(timeIntervalSince1970: 2_000)
let olderStateDate = Date(timeIntervalSince1970: 1_999)
precondition(!PlaybackRejoinPolicy.acceptsTimestamp(
    incomingSequence: 7,
    latestSequence: 7,
    incomingDate: olderStateDate,
    latestDate: newerStateDate
))
precondition(PlaybackRejoinPolicy.acceptsTimestamp(
    incomingSequence: 8,
    latestSequence: 7,
    incomingDate: olderStateDate,
    latestDate: newerStateDate
))
precondition(!PlaybackRejoinPolicy.acceptsTimestamp(
    incomingSequence: nil,
    latestSequence: nil,
    incomingDate: olderStateDate,
    latestDate: newerStateDate
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

precondition(PlaybackRejoinPolicy.shouldApplyRemotePosition(
    firstStateForConnection: true, isOwner: true, command: "state", isPlaying: true, drift: 0
))
precondition(!PlaybackRejoinPolicy.shouldApplyRemotePosition(
    firstStateForConnection: false, isOwner: true, command: "seek", isPlaying: true, drift: 50
))
precondition(PlaybackRejoinPolicy.shouldApplyRemotePosition(
    firstStateForConnection: false, isOwner: false, command: "seek", isPlaying: true, drift: 0.1
))
precondition(!PlaybackRejoinPolicy.shouldApplyRemotePosition(
    firstStateForConnection: false, isOwner: false, command: "state", isPlaying: true, drift: 1
))
precondition(PlaybackRejoinPolicy.shouldApplyRemotePosition(
    firstStateForConnection: false, isOwner: false, command: "state", isPlaying: true, drift: 3
))
precondition(PlaybackRejoinPolicy.shouldMaintainPlaybackIntent(
    desiredIsPlaying: true, hasPendingSeek: false, hasReachedEnd: false
))
precondition(!PlaybackRejoinPolicy.shouldMaintainPlaybackIntent(
    desiredIsPlaying: true, hasPendingSeek: true, hasReachedEnd: false
))
precondition(!PlaybackRejoinPolicy.shouldMaintainPlaybackIntent(
    desiredIsPlaying: true, hasPendingSeek: false, hasReachedEnd: true
))
// A late join is seeking to 10:00 when the owner jumps back to 00:00. The
// in-flight 10:00 target, not AVPlayer's still-rendered 00:00 frame, is the
// correct drift reference; otherwise the new command is accidentally ignored.
precondition(PlaybackRejoinPolicy.driftReferencePosition(
    pendingSeekPosition: 600,
    playerPosition: 0,
    publishedPosition: 600
) == 600)
precondition(PlaybackRejoinPolicy.driftReferencePosition(
    pendingSeekPosition: nil,
    playerPosition: 42,
    publishedPosition: 40
) == 42)

print("Playback rejoin policy tests passed")
