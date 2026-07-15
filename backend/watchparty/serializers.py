import ipaddress
from urllib.parse import urlparse
from rest_framework import serializers
from .models import ChatMessage, PlaybackState, Room, RoomMember


class PlaybackSerializer(serializers.ModelSerializer):
    server_updated_at = serializers.DateTimeField(source="updated_at", read_only=True)
    class Meta:
        model = PlaybackState
        fields = ("is_playing", "position_seconds", "server_updated_at")


class RoomSerializer(serializers.ModelSerializer):
    owner_name = serializers.CharField(source="owner.username", read_only=True)
    members_count = serializers.IntegerField(source="members.count", read_only=True)
    playback = PlaybackSerializer(read_only=True)
    class Meta:
        model = Room
        fields = ("id", "owner", "owner_name", "title", "description", "theme", "is_private", "invite_code", "max_members", "allow_guests_control", "vk_video_url", "members_count", "playback", "created_at")
        read_only_fields = ("owner", "invite_code")

    def validate_vk_video_url(self, value):
        if not value:
            return value
        parsed = urlparse(value)
        hostname = (parsed.hostname or "").lower()
        if parsed.scheme not in {"http", "https"} or not hostname:
            raise serializers.ValidationError("Нужна корректная HTTP(S)-ссылка на видео")
        if hostname == "localhost" or hostname.endswith(".local"):
            raise serializers.ValidationError("Локальные адреса не поддерживаются")
        try:
            address = ipaddress.ip_address(hostname)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise serializers.ValidationError("Локальные и служебные IP-адреса запрещены")
        return value


class JoinSerializer(serializers.Serializer):
    invite_code = serializers.CharField(max_length=20)


class RoomMemberSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    is_owner = serializers.SerializerMethodField()
    is_online = serializers.SerializerMethodField()
    avatar = serializers.SerializerMethodField()

    class Meta:
        model = RoomMember
        fields = ("user_id", "username", "avatar", "is_owner", "is_online", "joined_at")

    def get_is_owner(self, member):
        return member.room.owner_id == member.user_id

    def get_is_online(self, member):
        return member.active_connections > 0

    def get_avatar(self, member):
        identity = getattr(member.user, "client_identity", None)
        return identity.avatar_data_url if identity else ""


class ChatMessageSerializer(serializers.ModelSerializer):
    author = serializers.CharField(source="user.username", read_only=True)
    avatar = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = ("id", "author", "avatar", "text", "created_at")

    def get_avatar(self, message):
        identity = getattr(message.user, "client_identity", None)
        return identity.avatar_data_url if identity else ""
