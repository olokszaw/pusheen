# Interface, build 41

Rooms, friends, profiles and playback use the neutral compact interface introduced in this branch. The circular genre renderer and glass tab view retain their existing implementations. Authentication and registration retain their existing flow.

Room creation now has three mutually exclusive source modes: link, gallery and files. Only the selected source is displayed. A chosen local video gets an actual thumbnail through AVAssetImageGenerator; a failed thumbnail never prevents uploading the video. Inline access choices replace the public-room toggle card. Creation and upload progress stay in the bottom action area. Existing import cancellation, temporary-file cleanup, request idempotency and backend upload handlers are retained.

Joining uses a focused invitation-code entry and native paste control. Profile editing uses a live identity preview and direct name/username fields, with stale availability responses discarded. Sticker import uses the same focused input pattern. These flows replace the previous stacks of gray field and action cards.

Profile logout uses an explicit alert with exit and cancel actions. Activity details fit above navigation, with scroll insets for lower profile facts. At accessibility text sizes, profile metrics and section controls stack vertically instead of splitting words between narrow columns. Chart annotations have a bounded visual text size while the surrounding labels remain scalable.

Dependencies: Kingfisher 8.3.2, Exyte PopupView 4.0.0, HeatmapKit 0.5.1 and SwiftUI-Shimmer 1.5.1. Pow, Nuke and ActivityIndicatorView are removed. Lottie remains for animated Telegram sticker decoding. Native spring feedback and Reduce Motion support apply to the new controls.

Hosted validation includes Release compilation, 55 backend regressions, the existing Swift calendar/playback/chat/sticker checks, and iPhone simulator scenarios. Source-mode switching, access selection, editor dismissal, logout cancellation, statistics ranges and accessibility layouts are checked without sending fixture data to the production server. DEBUG fixtures are excluded from IPA Release.
