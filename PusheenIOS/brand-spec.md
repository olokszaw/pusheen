# Pusheen — Compact slate UI

The interface is an app, with concise functional labels and no promotional copy.

- Slate background (#0E1014), surface (#1B1E25), elevated (#2A2E37).
- Light text (#EEF0F3), secondary (#989CA4), controls (#A6B0FF), coordinated with the existing indigo navigation.
- SF system typography, title2 headers, subheadline content.
- Page inset 16 pt; card spacing 14; controls retain at least 44 pt touch targets.
- Room cards use 112 × 76 pt artwork, title and owner above a separate member/code row.
- Profile uses a 68 pt avatar alongside the name, followed by actual viewing time and friend count. Other people's profiles use 72 pt avatars.
- Authentication uses grouped input rows, a 44 pt mode switch, and a 48 pt submit button. Decorative field icons have fixed size to prevent clipping at larger text sizes.
- No serif headlines, hero sections, marketing slogans, decorative color gradients or coral accent.
- Existing Liquid Glass navigation and its gestures remain byte-identical to the original source.
- GenreOnlyCard, GenrePreferenceOrb and ViewingInsightsPager are restored verbatim from acd8bd4. Preserve their circular chart and gestures.
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
Simulator screenshots and compilation must be checked before delivery of build 35.
