from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0017_telegram_sticker_packs")]

    operations = [
        migrations.AddField(
            model_name="userpresence",
            name="is_active",
            field=models.BooleanField(default=False),
        ),
    ]
