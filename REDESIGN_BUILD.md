# Редизайн Pusheen, build 33

Локальный Xcode не нужен для получения IPA. Сборка выполняется в GitHub Actions
на macOS через существующий `.github/workflows/build-unsigned-ipa.yml`.

## Получить IPA

1. Поместить обновлённые `PusheenIOS` и этот документ в репозиторий приложения.
2. Открыть Actions → Build unsigned IPA → Run workflow, выбрать нужную ветку.
3. Оставить существующий backend URL `https://pulse.izanagi.online`.
4. Дождаться успешной сборки и скачать ZIP-artifact `Pulse-unsigned-ipa`.

Для установки unsigned IPA требуется подпись. Существующая инструкция проекта
предлагает Sideloadly; сам артефакт GitHub Actions не является подписанным приложением.

## Что входит в изменения

- SwiftUI редизайн комнат, авторизации, списка друзей, профиля и статистики.
- Общие поверхности для чата, редакторов и служебных окон.
- Контекстные spring-анимации и обработка Reduce Motion.
- NukeUI для обложек, 64 MiB disk cache и Exyte loading indicator.
- Существующая glass-навигация сохранена дословно.
- Backend, API, realtime transport и логика загрузки видео не изменены.

В `PusheenIOS/brand-spec.md` записаны дизайн-токены, motion и пределы локальной проверки.

## Состояние на 12 октября 2026

Исходники подготовлены; локальные синтаксические и регрессионные проверки прошли.
IPA собирается существующим macOS workflow в ветке редизайна.
Авторизация через Git Credential Manager под `olokszaw` подтверждена.
Исходная версия: commit `acd8bd4f9e221aa2a0db09e1de9717569be4759c`.
