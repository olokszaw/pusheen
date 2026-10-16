# Interface delivery, build 42

Room creation replaces the old gray control stack with three source modes, an underlined URL input, inline access selection and a persistent bottom action. Profile editing, joining and sticker import use direct input flows. The signed-in rooms, friends, public profiles and player/chat use the rebuilt layouts documented in interface-build41.md. Logout is in the profile menu with an explicit exit/cancel alert. The activity calendar has selectable ranges and daily details above navigation.

The glass tab view and circular genre renderer match build 36/38 (`9267d3a`) byte for byte. Authentication and registration flows remain intact. Kingfisher 8.3.2, PopupView 4.0.0, HeatmapKit 0.5.1 and SwiftUI-Shimmer 1.5.1 are integrated; Lottie continues to decode existing animated Telegram stickers.

## Verified results

- Release build 42 at `7dc1c9142886fbd96587826a463f2c9bc6238003`: [successful hosted build](https://github.com/olokszaw/pusheen/actions/runs/38391681137). All 55 backend regressions and eight Swift regression executables passed.
- The final room-creation/playback scenario passed on [build 42's iPhone simulator](https://github.com/olokszaw/pusheen/actions/runs/38391675885): source switching, enabled submit after entering a link, access by code, join-sheet navigation, opening fixture room/chat and returning to rooms. No production room was created.
- Profile previews, range switching, logout cancellation, editor dismissal and large text/Reduce Motion passed in build 41. That run's creation scenario exposed inherited accessibility identifiers; build 42 removes the parent identifier and reruns the changed scenario successfully. Profile sources are otherwise unchanged.
- Authentication, registration and empty-friends search passed in build 39; their relevant flows have no later changes.
- IPA metadata reports build 42 and bundle identifier `online.izanagi.pusheen`; production API URL is present and DEBUG fixture launch flags are absent from the executable.

Real native screenshots use local fixture users/history, with video placeholders when no thumbnail is supplied. They do not demonstrate production media playback or an actual gallery upload. A selected file's frame preview is implemented with AVAssetImageGenerator and compiled in Release.

Delivered unsigned IPA SHA-256: `6605003f3d73c171bd1bede96043d7ca7ece8bfc6b29c98767a512101ab30550`.
