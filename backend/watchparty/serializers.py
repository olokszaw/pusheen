from rest_framework import serializers

from .media_sources import detect_media_source, validate_media_url
from .models import ChatMessage, PlaybackState, Room, RoomMember


def public_profile(user):
    profile = getattr(user, "watch_profile", None)
    identity = getattr(user, "client_identity", None)
    return {
        "user_id": user.id,
        "username": user.username,
        "nickname": profile.nickname if profile else user.username,
        "avatar_data_url": (
            profile.avatar_data_url
            if profile and profile.avatar_data_url
            else getattr(identity, "avatar_data_url", "")
        ),
    }


class PlaybackSerializer(serializers.ModelSerializer):
    server_updated_at = serializers.DateTimeField(source="updated_at", read_only=True)

    class Meta:
        model = PlaybackState
        fields = ("is_playing", "position_seconds", "server_updated_at")


class RoomSerializer(serializers.ModelSerializer):
    owner_name = serializers.SerializerMethodField()
    members_count = serializers.IntegerField(source="members.count", read_only=True)
    playback = PlaybackSerializer(read_only=True)
    media_url = serializers.CharField(source="vk_video_url", read_only=True)
    source_type = serializers.SerializerMethodField()

    class Meta:
        model = Room
        fields = (
            "id", "owner", "owner_name", "title", "description", "theme",
            "is_private", "invite_code", "max_members", "allow_guests_control",
            "vk_video_url", "media_url", "source_type", "members_count",
            "playback", "created_at",
        )
        read_only_fields = ("owner", "invite_code")

    def to_internal_value(self, data):
        mutable = data.copy()
        if mutable.get("media_url") and not mutable.get("vk_video_url"):
            mutable["vk_video_url"] = mutable["media_url"]
        return super().to_internal_value(mutable)

    def validate_vk_video_url(self, value):
        if not value:
            return value
        try:
            return validate_media_url(value)
        except ValueError as error:
            raise serializers.ValidationError(str(error)) from error

    def get_source_type(self, room):
        return detect_media_source(room.vk_video_url)

    def get_owner_name(self, room):
        return public_profile(room.owner)["nickname"]


class JoinSerializer(serializers.Serializer):
    invite_code = serializers.CharField(max_length=20)


class RoomMemberSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    nickname = serializers.SerializerMethodField()
    avatar_data_url = serializers.SerializerMethodField()
    is_owner = serializers.SerializerMethodField()
    is_online = serializers.SerializerMethodField()

    class Meta:
        model = RoomMember
        fields = (
            "user_id", "username", "nickname", "avatar_data_url",
            "is_owner", "is_online", "joined_at",
        )

    def get_nickname(self, member):
        return public_profile(member.user)["nickname"]

    def get_avatar_data_url(self, member):
        return public_profile(member.user)["avatar_data_url"]

    def get_is_owner(self, member):
        return member.room.owner_id == member.user_id

    def get_is_online(self, member):
        return member.active_connections > 0


class ChatMessageSerializer(serializers.ModelSerializer):
    author = serializers.CharField(source="user.username", read_only=True)
    author_id = serializers.IntegerField(source="user.id", read_only=True)
    nickname = serializers.SerializerMethodField()
    avatar_data_url = serializers.SerializerMethodField()
    reactions = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = (
            "id", "author_id", "author", "nickname", "avatar_data_url",
            "text", "image_data_url", "reactions", "created_at",
        )

    def get_nickname(self, message):
        return public_profile(message.user)["nickname"]

    def get_avatar_data_url(self, message):
        return public_profile(message.user)["avatar_data_url"]

    def get_reactions(self, message):
        grouped = {}
        request = self.context.get("request")
        current_id = request.user.id if request and request.user.is_authenticated else None
        for reaction in message.reactions.all():
            item = grouped.setdefault(
                reaction.emoji,
                {"emoji": reaction.emoji, "count": 0, "reacted": False},
            )
            item["count"] += 1
            item["reacted"] = item["reacted"] or reaction.user_id == current_id
        return list(grouped.values())
