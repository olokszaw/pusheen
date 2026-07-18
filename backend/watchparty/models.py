import secrets
from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models


def invite_code():
    return secrets.token_urlsafe(6).upper()


class Room(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="owned_rooms")
    title = models.CharField(max_length=80)
    description = models.CharField(max_length=280, blank=True)
    theme = models.CharField(max_length=30, default="movie")
    is_private = models.BooleanField(default=False)
    invite_code = models.CharField(max_length=20, unique=True, default=invite_code, editable=False)
    max_members = models.PositiveSmallIntegerField(default=12, validators=[MinValueValidator(2), MaxValueValidator(100)])
    allow_guests_control = models.BooleanField(default=False)
    vk_video_url = models.URLField(blank=True)
    thumbnail_url = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)


class RoomMember(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="watch_rooms")
    joined_at = models.DateTimeField(auto_now_add=True)
    is_muted = models.BooleanField(default=False)
    active_connections = models.PositiveSmallIntegerField(default=0)
    class Meta:
        unique_together = ("room", "user")


class PlaybackState(models.Model):
    room = models.OneToOneField(Room, on_delete=models.CASCADE, related_name="playback")
    is_playing = models.BooleanField(default=False)
    position_seconds = models.FloatField(default=0)
    # UTC time when position_seconds was authoritative; clients compensate for transport delay.
    updated_at = models.DateTimeField(auto_now=True)


class ClientIdentity(models.Model):
    """One persistent application identity per installed client."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="client_identity",
    )
    client_id = models.CharField(max_length=80, unique=True, db_index=True)
    avatar_data_url = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)


class UserProfile(models.Model):
    """Public profile. Django's username remains the unique @username."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="watch_profile",
    )
    nickname = models.CharField(max_length=50)
    avatar_data_url = models.TextField(blank=True, default="")

    def __str__(self):
        return f"{self.nickname} (@{self.user.username})"


class ChatMessage(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="messages")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    text = models.CharField(max_length=500, blank=True)
    image_data_url = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("created_at",)


class MessageReaction(models.Model):
    message = models.ForeignKey(ChatMessage, on_delete=models.CASCADE, related_name="reactions")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    emoji = models.CharField(max_length=32)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("message", "user", "emoji"),
                name="unique_message_user_emoji",
            )
        ]
