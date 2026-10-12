# Pusheen — Compact neutral UI

The interface is an app, with concise functional labels and no promotional copy.

- Neutral dark background (#0C0D0F), surface (#17191C), elevated (#22252A).
- Light neutral text (#EEF0F3), secondary (#989CA4), controls (#D5DAE2).
- SF system typography, title3 headers (20 pt at standard Dynamic Type), subheadline content.
- Page inset 16 pt; list spacing 10; controls retain 44 pt touch targets.
- Rooms use 80 × 56 pt artwork in compact rows. No large poster tiles.
- Profile uses a 64 pt avatar alongside the name. Other people's profiles use 72 pt avatars.
- Forms have labeled 44 pt fields, a 44 pt mode switch, and a 44 pt submit button.
- No serif headlines, hero sections, marketing slogans, decorative color gradients or coral accent.
- Existing Liquid Glass navigation and its gestures remain byte-identical to the original source.
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
Simulator screenshots and compilation must be checked before delivery of build 34.
