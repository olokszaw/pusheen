# Pusheen build 37

The signed-in app uses a media grid, a flat profile layout, an online friend strip,
native viewing-history charts, flat player/chat surfaces and new editor fields.
Authentication, native Liquid Glass navigation and circular genres retain their implementations.

Build: GitHub Actions → Build unsigned IPA → codex/cinema-redesign.
Backend URL: https://pulse.izanagi.online (unchanged).
Artifact: Pulse-unsigned-ipa. Unsigned IPA requires signing before installation.

Native UI preview runs XCTest on the real app, exports screenshots of authentication,
registration, rooms, friends and profile sections, and captures an additional large-text screen.
Local DEBUG fixtures are excluded from Release and do not call the backend.

Additional installed agent skills: SwiftUI Expert (AvdLee), SwiftUI Pro (Paul Hudson).
Pow 0.3.1 is used for authentication error feedback. NukeUI handles image caching.
