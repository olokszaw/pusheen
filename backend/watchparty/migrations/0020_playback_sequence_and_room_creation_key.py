from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0019_roommember_viewer_playback")]

    operations = [
        migrations.AddField(
            model_name="playbackstate",
            name="sequence",
            field=models.PositiveBigIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="room",
            name="creation_request_id",
            field=models.UUIDField(blank=True, editable=False, null=True),
        ),
        migrations.AddConstraint(
            model_name="room",
            constraint=models.UniqueConstraint(
                condition=models.Q(creation_request_id__isnull=False),
                fields=("owner", "creation_request_id"),
                name="unique_owner_room_creation_request",
            ),
        ),
    ]
