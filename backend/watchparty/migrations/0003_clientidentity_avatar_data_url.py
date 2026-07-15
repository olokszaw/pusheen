from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("watchparty", "0002_roommember_active_connections_chatmessage_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="clientidentity",
            name="avatar_data_url",
            field=models.TextField(blank=True, default=""),
        ),
    ]
