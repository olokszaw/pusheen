# Pusheen build 38 � restored build 36 interface

Grouped authentication fields, artwork room cards, grouped friend rows and a profile
identity card use compact system typography and slate surfaces. Promotional copy is removed.
The original circular genre chart and Liquid Glass navigation are restored verbatim.
The statistics pager retains its original gestures, with additional height to fit the genre legend.

Build: GitHub Actions → Build unsigned IPA → codex/cinema-redesign.
Backend URL: https://pulse.izanagi.online (unchanged).
Artifact: Pulse-unsigned-ipa. Unsigned IPA requires signing before installation.

Native UI preview runs XCTest on the real app, exports screenshots of authentication,
registration, rooms, friends and profile sections, and captures an additional large-text screen.
Local DEBUG fixtures are excluded from Release and do not call the backend.

Additional installed agent skills: SwiftUI Expert (AvdLee), SwiftUI Pro (Paul Hudson).
Pow 0.3.1 is used for authentication error feedback. NukeUI handles image caching.
