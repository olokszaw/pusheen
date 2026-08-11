import secrets
from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models.signals import post_delete
from django.dispatch import receiver


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
    # A room can use either an external URL or an owner-uploaded video.  The
    # file lives on the server; it is never treated as a VK/Web URL.
    uploaded_video = models.FileField(upload_to="room-videos/%Y/%m/", blank=True, null=True)
    thumbnail_url = models.TextField(blank=True, default="")
    duration_seconds = models.FloatField(default=0)
    genres = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


@receiver(post_delete, sender=Room)
def delete_room_uploaded_video(sender, instance, **kwargs):
    """Remove the server-side gallery video once its room no longer exists."""
    video = instance.uploaded_video
    if not video or not video.name:
        return
    try:
        video.storage.delete(video.name)
    except Exception:
        # Deleting a room must not fail merely because storage is temporarily
        # unavailable. The file is no longer reachable and can be cleaned up
        # by the storage provider if necessary.
        pass


class RoomMember(models.Model):
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="watch_rooms")
    joined_at = models.DateTimeField(auto_now_add=True)
    is_muted = models.BooleanField(default=False)
    active_connections = models.PositiveSmallIntegerField(default=0)
    last_heartbeat_at = models.DateTimeField(null=True, blank=True, db_index=True)
    # Ephemeral viewer clock used by the read-only friend preview. The shared
    # PlaybackState remains owner-controlled; these fields describe what this
    # particular member's AVPlayer is actually displaying right now.
    viewer_position_seconds = models.FloatField(default=0)
    viewer_duration_seconds = models.FloatField(default=0)
    viewer_is_playing = models.BooleanField(default=False)
    viewer_playback_at = models.DateTimeField(null=True, blank=True, db_index=True)
    class Meta:
        unique_together = ("room", "user")


class RoomMute(models.Model):
    """A durable room-local mute tied to the authenticated account, not a visit."""
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="mutes")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="room_mutes")
    muted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="issued_room_mutes",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=("room", "user"), name="unique_room_mute")]


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


class UserPresence(models.Model):
    """Privacy-aware app presence updated by the authenticated heartbeat."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="watch_presence",
    )
    last_seen = models.DateTimeField(auto_now=True)
    # `last_seen` alone cannot distinguish a user who has just closed the app
    # from one who is still connected.  Heartbeats set this flag and app
    # lifecycle/disconnect events clear it immediately; the timestamp TTL is
    # still the final safeguard for crashed clients and lost networks.
    is_active = models.BooleanField(default=False)
    show_activity = models.BooleanField(default=True)


class RoomInvitation(models.Model):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    STATUS_CHOICES = (
        (PENDING, "Pending"),
        (ACCEPTED, "Accepted"),
        (DECLINED, "Declined"),
    )
    room = models.ForeignKey(Room, on_delete=models.CASCADE, related_name="invitations")
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sent_room_invitations",
    )
    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="received_room_invitations",
    )
    status = models.CharField(max_length=12, choices=STATUS_CHOICES, default=PENDING)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("room", "recipient"),
                name="unique_room_invitation_recipient",
            ),
            models.CheckConstraint(
                condition=~models.Q(sender=models.F("recipient")),
                name="room_invitation_cannot_target_self",
            ),
        ]


class TelegramStickerPack(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="telegram_sticker_packs")
    short_name = models.CharField(max_length=80)
    title = models.CharField(max_length=120)
    imported_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=("user", "short_name"), name="unique_user_telegram_sticker_pack")]


class TelegramSticker(models.Model):
    STATIC = "static"
    ANIMATED = "animated"
    VIDEO = "video"
    pack = models.ForeignKey(TelegramStickerPack, on_delete=models.CASCADE, related_name="stickers")
    telegram_file_id = models.CharField(max_length=180)
    emoji = models.CharField(max_length=32, blank=True, default="")
    format = models.CharField(max_length=12, default=STATIC)
    file = models.FileField(upload_to="telegram-stickers/%Y/%m/")
    preview = models.FileField(upload_to="telegram-stickers/previews/%Y/%m/", blank=True, null=True)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ("order", "id")
        constraints = [models.UniqueConstraint(fields=("pack", "telegram_file_id"), name="unique_pack_telegram_sticker")]


class ViewingActivity(models.Model):
    """Aggregated private viewing statistics for one profile."""
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="viewing_activity")
    app_seconds = models.PositiveIntegerField(default=0)
    watched_seconds = models.PositiveIntegerField(default=0)
    longest_movie_seconds = models.PositiveIntegerField(default=0)
    genre_counts = models.JSONField(default=dict, blank=True)
    daily_seconds = models.JSONField(default=dict, blank=True)
    month_increase_percent = models.PositiveIntegerField(default=0)
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
    client_message_id = models.CharField(max_length=64, blank=True, default="", db_index=True)
    reply_to = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.SET_NULL, related_name="replies"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("created_at",)
        constraints = [
            # HTTP persistence and the live socket can race for the same user
            # action. Only non-empty ids participate so legacy socket messages
            # without an id stay valid.
            models.UniqueConstraint(
                fields=("room", "user", "client_message_id"),
                condition=~models.Q(client_message_id=""),
                name="unique_room_user_client_message",
            )
        ]


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
