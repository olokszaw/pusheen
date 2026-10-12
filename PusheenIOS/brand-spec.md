# Pusheen — New signed-in layout, build 37

The interface is an app, with concise functional labels and no promotional copy.

- FreshPalette: near-black (#0A0B0B), charcoal (#131515), warm white (#F0F2E8), muted green-gray (#949E94), sage accent (#C9E0B3).
- SF system typography, title2 headers, subheadline content.
- Page inset 16 pt; card spacing 14; controls retain at least 44 pt touch targets.
- Rooms use a two-column media grid with artwork, title, owner and participant count.
- Profile uses a flat identity header with a 54 pt avatar, viewing totals, and underlined section controls.
- Friends have a privacy-aware online avatar strip above flat contact rows.
- Player, chat, sheets and editors use the new flat surfaces and underlined fields.
- Authentication uses grouped input rows, a 44 pt mode switch, and a 48 pt submit button. Decorative field icons have fixed size to prevent clipping at larger text sizes.
- No serif headlines, hero sections, marketing slogans, decorative color gradients or coral accent.
- Existing Liquid Glass navigation and its gestures remain byte-identical to the original source.
- The authentication implementation, native glass tabs, GenrePreferenceOrb and GenreLegend remain unchanged from build 36.
- The original genre orb is presented without the enclosing statistics card. Activity uses native Swift Charts for actual daily viewing hours and touch selection over 14 days.
- Spring feedback is short and low amplitude. Reduce Motion disables new effects.

## Libraries

- NukeUI 12.8.0: cached image loading and a short fade.
- Pow 0.3.1: one short error shake on the authentication form.
- Exyte ActivityIndicatorView: loading state; existing Lottie handles animated stickers.

## Validation

The native simulator workflow tests authentication, registration, native tab switching,
and profile sections. It exports actual XCTest screenshot attachments. Signed-in screenshots
use DEBUG-only local fixtures; Release IPA excludes the fixture file and launch flags.
The existing IPA workflow runs backend and Swift policy regressions before compiling Release.
Demo daily history totals 18,000 seconds, matching the displayed five hours. It is DEBUG-only and performs no backend writes.
Simulator screenshots and compilation must be checked before delivery of build 37.
