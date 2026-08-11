from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0018_userpresence_is_active")]

    operations = [
        migrations.AddField(
            model_name="roommember",
            name="viewer_duration_seconds",
            field=models.FloatField(default=0),
        ),
        migrations.AddField(
            model_name="roommember",
            name="viewer_is_playing",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="roommember",
            name="viewer_playback_at",
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name="roommember",
            name="viewer_position_seconds",
            field=models.FloatField(default=0),
        ),
    ]
