from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0003_profiles_reactions_and_images")]

    operations = [
        migrations.AddField(
            model_name="room",
            name="thumbnail_url",
            field=models.TextField(blank=True, default=""),
        ),
    ]
