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
    duration_seconds = models.FloatField(default=0)
    genres = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class RoomMember(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="watch_rooms")
    joined_at = models.DateTimeField(auto_now_add=True)
    is_muted = models.BooleanField(default=False)
    active_connections = models.PositiveSmallIntegerField(default=0)
    class Meta:
        unique_together = ("room", "user")


class RoomBan(models.Model):
    """A room-local ban. It deliberately does not affect the user's account."""
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="bans")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="room_bans")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=("room", "user"), name="unique_room_ban")]


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


class FriendLink(models.Model):
    """A confirmed, directional row. Adding a friend creates both directions."""
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="friend_links"
    )
    friend = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="friend_of_links"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("user", "friend"), name="unique_user_friend_link"
            ),
            models.CheckConstraint(
                condition=~models.Q(user=models.F("friend")),
                name="friend_link_cannot_point_to_self",
            ),
        ]


class FriendRequest(models.Model):
    """A pending friendship request; a link is only created after acceptance."""
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sent_friend_requests"
    )
    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="received_friend_requests"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(fields=("sender", "recipient"), name="unique_pending_friend_request"),
            models.CheckConstraint(
                condition=~models.Q(sender=models.F("recipient")),
                name="friend_request_cannot_target_self",
            ),
        ]


class ViewingActivity(models.Model):
    """Aggregated private viewing statistics for one profile."""
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="viewing_activity")
    app_seconds = models.PositiveIntegerField(default=0)
    watched_seconds = models.PositiveIntegerField(default=0)
    longest_movie_seconds = models.PositiveIntegerField(default=0)
    genre_counts = models.JSONField(default=dict, blank=True)
    daily_seconds = models.JSONField(default=dict, blank=True)
    updated_at = models.DateTimeField(auto_now=True)


class CompanionActivity(models.Model):
    """Private aggregate of actual time two confirmed friends watched together."""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="companion_activity")
    companion = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="companion_of_activity")
    seconds = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=("user", "companion"), name="unique_user_companion_activity"),
            models.CheckConstraint(condition=~models.Q(user=models.F("companion")), name="companion_activity_not_self"),
        ]


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
