from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("watchparty", "0011_room_uploaded_video"),
    ]

    operations = [
        migrations.AddField(
            model_name="viewingactivity",
            name="month_increase_percent",
            field=models.PositiveIntegerField(default=0),
        ),
    ]
