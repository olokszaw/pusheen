from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("watchparty", "0020_playback_sequence_and_room_creation_key"),
    ]

    operations = [
        migrations.AlterModelOptions(
            name="chatmessage",
            options={"ordering": ("created_at", "id")},
        ),
    ]
