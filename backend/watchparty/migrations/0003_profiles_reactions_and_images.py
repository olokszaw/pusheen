from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def create_profiles(apps, schema_editor):
    User = apps.get_model(*settings.AUTH_USER_MODEL.split("."))
    UserProfile = apps.get_model("watchparty", "UserProfile")
    for user in User.objects.all().iterator():
        UserProfile.objects.get_or_create(user_id=user.id, defaults={"nickname": user.username})


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("watchparty", "0002_roommember_active_connections_chatmessage_and_identity"),
    ]

    operations = [
        migrations.CreateModel(
            name="UserProfile",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("nickname", models.CharField(max_length=50)),
                ("avatar_data_url", models.TextField(blank=True, default="")),
                ("user", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="watch_profile", to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.AlterField(
            model_name="chatmessage",
            name="text",
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="image_data_url",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.CreateModel(
            name="MessageReaction",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("emoji", models.CharField(max_length=32)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("message", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="reactions", to="watchparty.chatmessage")),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.AddConstraint(
            model_name="messagereaction",
            constraint=models.UniqueConstraint(fields=("message", "user", "emoji"), name="unique_message_user_emoji"),
        ),
        migrations.RunPython(create_profiles, migrations.RunPython.noop),
    ]
