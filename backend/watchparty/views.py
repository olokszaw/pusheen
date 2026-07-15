from django.db import transaction
import base64
import binascii
import logging
import re

from django.core.cache import cache
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from .models import ChatMessage, ClientIdentity, PlaybackState, Room, RoomMember
from .permissions import IsRoomOwner
from .serializers import ChatMessageSerializer, JoinSerializer, RoomMemberSerializer, RoomSerializer
from .video_stream import resolve_vk_stream


logger = logging.getLogger(__name__)
AVATAR_PATTERN = re.compile(r"^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/=\r\n]+)$")


def user_avatar(user):
    identity = getattr(user, "client_identity", None)
    return identity.avatar_data_url if identity else ""


def validate_avatar(value):
    if value == "":
        return ""
    if not isinstance(value, str):
        raise ValueError("Некорректный формат аватара")
    match = AVATAR_PATTERN.fullmatch(value)
    if not match:
        raise ValueError("Поддерживаются PNG, JPEG и WebP")
    try:
        payload = base64.b64decode(match.group(2), validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("Повреждённое изображение") from error
    if len(payload) > 600_000:
        raise ValueError("Аватар должен быть меньше 600 КБ")
    return value


@api_view(["POST"])
@permission_classes([AllowAny])
def demo_login(request):
    from django.contrib.auth import get_user_model
    username = request.data.get("username", "guest").strip()[:150]
    client_id = request.data.get("client_id", "").strip()[:80]
    if not client_id:
        return Response({"detail": "Не передан идентификатор устройства"}, status=status.HTTP_400_BAD_REQUEST)

    identity = ClientIdentity.objects.select_related("user").filter(client_id=client_id).first()
    if identity:
        user = identity.user
        if username and username != user.username:
            if get_user_model().objects.exclude(id=user.id).filter(username=username).exists():
                return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
            user.username = username
            user.save(update_fields=["username"])
    else:
        user = get_user_model().objects.filter(username=username).first()
        if user and ClientIdentity.objects.filter(user=user).exists():
            return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
        if user is None:
            user = get_user_model().objects.create_user(username=username)
        ClientIdentity.objects.create(user=user, client_id=client_id)
    token, _ = Token.objects.get_or_create(user=user)
    return Response({
        "token": token.key,
        "user_id": user.id,
        "username": user.username,
        "avatar": user_avatar(user),
    })


@api_view(["GET", "PATCH"])
def profile(request):
    if request.method == "PATCH":
        if "username" in request.data:
            username = request.data.get("username", "").strip()[:150]
            if len(username) < 2:
                return Response({"detail": "Ник должен содержать минимум 2 символа"}, status=status.HTTP_400_BAD_REQUEST)
            from django.contrib.auth import get_user_model
            if get_user_model().objects.exclude(id=request.user.id).filter(username=username).exists():
                return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
            request.user.username = username
            request.user.save(update_fields=["username"])
        if "avatar" in request.data:
            try:
                avatar = validate_avatar(request.data.get("avatar"))
            except ValueError as error:
                return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)
            identity, _ = ClientIdentity.objects.get_or_create(
                user=request.user,
                defaults={"client_id": f"legacy-{request.user.id}"},
            )
            identity.avatar_data_url = avatar
            identity.save(update_fields=["avatar_data_url"])
    return Response({
        "user_id": request.user.id,
        "username": request.user.username,
        "avatar": user_avatar(request.user),
    })


class RoomListCreateView(generics.ListCreateAPIView):
    serializer_class = RoomSerializer
    def get_queryset(self):
        return Room.objects.filter(members__user=self.request.user).select_related("owner", "playback").distinct()
    @transaction.atomic
    def perform_create(self, serializer):
        room = serializer.save(owner=self.request.user)
        RoomMember.objects.create(room=room, user=self.request.user)
        PlaybackState.objects.create(room=room)


class RoomDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = RoomSerializer
    queryset = Room.objects.select_related("owner", "playback")
    permission_classes = [IsAuthenticated, IsRoomOwner]


@api_view(["POST"])
def join_room(request):
    data = JoinSerializer(data=request.data)
    data.is_valid(raise_exception=True)
    room = get_object_or_404(Room, invite_code=data.validated_data["invite_code"])
    if room.members.count() >= room.max_members and not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Комната заполнена"}, status=status.HTTP_409_CONFLICT)
    RoomMember.objects.get_or_create(room=room, user=request.user)
    return Response(RoomSerializer(room, context={"request": request}).data)


@api_view(["GET"])
def room_members(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=status.HTTP_403_FORBIDDEN)
    members = room.members.select_related("user", "user__client_identity", "room__owner").order_by("joined_at")
    return Response(RoomMemberSerializer(members, many=True).data)


@api_view(["GET"])
def room_stream(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=status.HTTP_403_FORBIDDEN)
    if not room.vk_video_url:
        return Response({"detail": "В комнате не выбрано видео"}, status=status.HTTP_400_BAD_REQUEST)

    quality = request.query_params.get("quality", "").strip().lower()
    if quality and not re.fullmatch(r"\d{3,4}p?", quality):
        return Response({"detail": "Некорректное качество"}, status=status.HTTP_400_BAD_REQUEST)
    cache_key = f"room-stream:{room.id}:{quality or 'auto'}:{room.vk_video_url}"
    stream = cache.get(cache_key)
    if stream is None:
        try:
            stream = resolve_vk_stream(room.vk_video_url, preferred_quality=quality)
        except Exception:
            logger.exception("Could not resolve video source for room %s", room.id)
            return Response(
                {
                    "detail": (
                        "Этот сайт не разрешает открыть видео во внешнем плеере. "
                        "Попробуйте ссылку VK Видео или прямую публичную ссылку на MP4."
                    )
                },
                status=status.HTTP_502_BAD_GATEWAY,
            )
        cache.set(cache_key, stream, timeout=20 * 60)
    return Response(stream)


@api_view(["GET"])
def room_messages(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=status.HTTP_403_FORBIDDEN)
    messages = list(
        ChatMessage.objects.filter(room=room)
        .select_related("user", "user__client_identity")
        .order_by("-created_at")[:100]
    )
    messages.reverse()
    return Response(ChatMessageSerializer(messages, many=True).data)
