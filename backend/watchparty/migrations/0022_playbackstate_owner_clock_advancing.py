from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0021_chatmessage_stable_ordering")]

    operations = [
        migrations.AddField(
            model_name="playbackstate",
            name="owner_clock_advancing",
            field=models.BooleanField(default=False),
        ),
    ]
