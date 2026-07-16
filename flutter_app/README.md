# pulse_watch_party

## Video sources

Room creation offers two isolated sources:

- **VK Видео** — resolved only by the VK backend pipeline.
- **Сайт / Google** — opens the search browser, then resolves the selected page through the WEB pipeline. If a public direct stream cannot be extracted, the mobile app uses a separate embedded-page fallback with popup and common ad-container filtering.

The providers do not fall through into each other, so a VK failure never opens
the VK website in the player.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
