# Pusheen build 34

Compact neutral redesign. Marketing text, serif display typography, coral coloring and
large poster tiles are removed. Room rows, profile header and form controls are smaller.
The original Liquid Glass navigation is preserved.

Build: GitHub Actions → Build unsigned IPA → codex/cinema-redesign.
Backend URL: https://pulse.izanagi.online (unchanged).
Artifact: Pulse-unsigned-ipa. Unsigned IPA requires signing before installation.

Native UI preview runs XCTest on the real app, exports screenshots of authentication,
registration, rooms, friends and profile sections, and captures an additional large-text screen.
Local DEBUG fixtures are excluded from Release and do not call the backend.

Additional installed agent skills: SwiftUI Expert (AvdLee), SwiftUI Pro (Paul Hudson).
Pow 0.3.1 is used for authentication error feedback. NukeUI handles image caching.
