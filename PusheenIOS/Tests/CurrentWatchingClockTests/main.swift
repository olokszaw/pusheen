import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let receivedAt = Date(timeIntervalSince1970: 1_000)

// A playing 44-second clip received at 10 seconds must advance only by the
// time elapsed on this device. A six-hour VPS clock offset is intentionally
// absent from the calculation and therefore cannot clamp it to the end.
let live = projectedCurrentWatchingPosition(
    positionSeconds: 10,
    isPlaying: true,
    receivedAt: receivedAt,
    now: receivedAt.addingTimeInterval(2),
    durationSeconds: 44
)
require(abs(live - 12) < 0.001, "live preview must advance from local receipt time")
require(live < 43.9, "clock skew must not clamp a live preview to EOF")

let paused = projectedCurrentWatchingPosition(
    positionSeconds: 17,
    isPlaying: false,
    receivedAt: receivedAt,
    now: receivedAt.addingTimeInterval(21_600),
    durationSeconds: 44
)
require(abs(paused - 17) < 0.001, "paused preview must not advance")

let bounded = projectedCurrentWatchingPosition(
    positionSeconds: 43.9,
    isPlaying: true,
    receivedAt: receivedAt,
    now: receivedAt.addingTimeInterval(10),
    durationSeconds: 44
)
require(bounded < 44, "preview seek target must remain before the final frame")

print("CurrentWatchingClockTests passed")
