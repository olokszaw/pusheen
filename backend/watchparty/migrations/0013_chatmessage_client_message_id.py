from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0012_viewingactivity_month_increase_percent")]

    operations = [
        migrations.AddField(
            model_name="chatmessage",
            name="client_message_id",
            field=models.CharField(blank=True, db_index=True, default="", max_length=64),
        ),
    ]
