from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0016_presence_heartbeat_and_message_reply")]
    operations = [
        migrations.CreateModel(
            name="TelegramStickerPack",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("short_name", models.CharField(max_length=80)),
                ("title", models.CharField(max_length=120)),
                ("imported_at", models.DateTimeField(auto_now_add=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="telegram_sticker_packs", to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name="TelegramSticker",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("telegram_file_id", models.CharField(max_length=180)),
                ("emoji", models.CharField(blank=True, default="", max_length=32)),
                ("format", models.CharField(default="static", max_length=12)),
                ("file", models.FileField(upload_to="telegram-stickers/%Y/%m/")),
                ("preview", models.FileField(blank=True, null=True, upload_to="telegram-stickers/previews/%Y/%m/")),
                ("order", models.PositiveSmallIntegerField(default=0)),
                ("pack", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="stickers", to="watchparty.telegramstickerpack")),
            ],
            options={"ordering": ("order", "id")},
        ),
        migrations.AddConstraint(model_name="telegramstickerpack", constraint=models.UniqueConstraint(fields=("user", "short_name"), name="unique_user_telegram_sticker_pack")),
        migrations.AddConstraint(model_name="telegramsticker", constraint=models.UniqueConstraint(fields=("pack", "telegram_file_id"), name="unique_pack_telegram_sticker")),
    ]
