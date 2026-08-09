from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0015_userpresence_roominvitation")]
    operations = [
        migrations.AddField(
            model_name="roommember",
            name="last_heartbeat_at",
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="reply_to",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="replies",
                to="watchparty.chatmessage",
            ),
        ),
    ]
