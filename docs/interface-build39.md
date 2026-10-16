# App interface, build 39

The signed-in interface uses neutral charcoal surfaces, off-white actions, a restrained sage activity scale, and compact system typography. The existing circular genre renderer and glass tab navigation are preserved. Authentication and registration keep their existing flow.

- Rooms use a responsive media grid with search and an ownership filter. Existing tap, long-press, selection, deletion, creation and join actions remain connected.
- Friends use an immediately visible search control and separate rows. The empty state has a search action. Searches are debounced and discard stale responses. Friendship requests, privacy-aware presence, previews and swipe removal retain their server behavior.
- Profile identity is separate from viewing totals. Explicit genre, activity and companion tabs replace the opaque fixed-height pager. Logout lives in the profile menu with confirmation.
- HeatmapKit renders actual daily viewing seconds. One- and three-month ranges, date selection, duration details, thresholds and VoiceOver labels retain units and dates. Zero activity has zero intensity.
- Kingfisher replaces Nuke for room/catalog image caching. SwiftUI-Shimmer supplies loading feedback. Exyte PopupView drives notification transitions. Native springs handle presses, fields, statistics selection and disclosure. Reduce Motion suppresses movement.
- Lottie remains solely for decoding existing animated Telegram stickers; it is not used for the redesigned screens.

Packages are pinned in `PusheenIOS/project.yml`. DEBUG fixtures cover populated and empty friends, viewing history, player/chat, large text and Reduce Motion. Release excludes fixture code and launch flags. Fixture history totals 18,000 seconds, matching the displayed five viewing hours.

Validation: hosted macOS Release compilation and existing backend/Swift policy regressions; simulator UI checks and real screenshots covering search, statistics range switching, logout cancellation, editors, room creation/joining and player navigation. Results are recorded in GitHub Actions.
