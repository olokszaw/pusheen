# Сборка Pulse IPA

Проект собирает unsigned IPA на macOS через GitHub Actions. Такой файл можно
подписать и установить через Sideloadly.

1. Загрузить содержимое папки `rave` в GitHub-репозиторий.
2. Открыть `Actions` → `Build unsigned IPA` → `Run workflow`.
3. Указать URL backend, доступный с iPhone. Для текущей Wi-Fi сети:
   `http://192.168.50.63:8000`.
4. Скачать artifact `Pulse-unsigned-ipa` и распаковать ZIP.
5. Перед установкой запустить backend на компьютере:

   ```cmd
   cd /d C:\Users\luiin\OneDrive\Desktop\rave\backend
   .venv_verify\Scripts\python.exe manage.py runserver 0.0.0.0:8000
   ```

Компьютер и iPhone должны находиться в одной Wi-Fi сети. При смене локального
IP нужно собрать IPA заново с новым `api_base_url` либо использовать публичный
HTTPS backend.
