from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0013_chatmessage_client_message_id")]

    operations = [
        migrations.AddConstraint(
            model_name="chatmessage",
            constraint=models.UniqueConstraint(
                condition=~models.Q(client_message_id=""),
                fields=("room", "user", "client_message_id"),
                name="unique_room_user_client_message",
            ),
        ),
    ]
