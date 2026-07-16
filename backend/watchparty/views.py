from django.db import transaction
from django.core.cache import cache
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from .models import ChatMessage, ClientIdentity, PlaybackState, Room, RoomMember
from .media_sources import detect_media_source
from .permissions import IsRoomOwner
from .serializers import ChatMessageSerializer, JoinSerializer, RoomMemberSerializer, RoomSerializer
from .video_stream import resolve_media_stream


@api_view(["POST"])
@permission_classes([AllowAny])
def demo_login(request):
    from django.contrib.auth import get_user_model
    username = request.data.get("username", "guest").strip()[:150]
    client_id = request.data.get("client_id", "").strip()[:80]
    if not username:
        return Response({"detail": "Введите ник"}, status=status.HTTP_400_BAD_REQUEST)
    if not client_id:
        return Response({"detail": "Не передан идентификатор устройства"}, status=status.HTTP_400_BAD_REQUEST)

    users = get_user_model()
    identity = ClientIdentity.objects.select_related("user").filter(client_id=client_id).first()
    if identity:
        user = identity.user
        if username != user.username:
            if users.objects.exclude(id=user.id).filter(username=username).exists():
                return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
            user.username = username
            user.save(update_fields=["username"])
    else:
        existing = users.objects.filter(username=username).first()
        if existing and ClientIdentity.objects.filter(user=existing).exists():
            return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
        user = existing or users.objects.create_user(username=username)
        ClientIdentity.objects.create(user=user, client_id=client_id)
    token, _ = Token.objects.get_or_create(user=user)
    return Response({"token": token.key, "user_id": user.id, "username": user.username})


@api_view(["GET", "PATCH"])
def profile(request):
    if request.method == "PATCH":
        username = request.data.get("username", "").strip()[:150]
        if len(username) < 2:
            return Response({"detail": "Ник должен содержать минимум 2 символа"}, status=status.HTTP_400_BAD_REQUEST)
        from django.contrib.auth import get_user_model
        if get_user_model().objects.exclude(id=request.user.id).filter(username=username).exists():
            return Response({"detail": "Этот ник уже занят"}, status=status.HTTP_409_CONFLICT)
        request.user.username = username
        request.user.save(update_fields=["username"])
    return Response({"user_id": request.user.id, "username": request.user.username})


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
    members = room.members.select_related("user", "room__owner").order_by("joined_at")
    return Response(RoomMemberSerializer(members, many=True).data)


@api_view(["GET"])
def room_stream(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=status.HTTP_403_FORBIDDEN)
    if not room.vk_video_url:
        return Response({"detail": "В комнате не выбрано видео"}, status=status.HTTP_400_BAD_REQUEST)

    source_type = detect_media_source(room.vk_video_url)
    cache_key = f"room-stream:v2:{source_type}:{room.id}:{room.vk_video_url}"
    stream = cache.get(cache_key)
    if stream is None:
        try:
            stream = resolve_media_stream(room.vk_video_url, source_type)
        except Exception as error:
            return Response(
                {
                    "detail": (
                        f"Не удалось получить основной поток {source_type.upper()}: {error}"
                    ),
                    "source_type": source_type,
                    "fallback": "embedded_page" if source_type == "web" else None,
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
    messages = list(ChatMessage.objects.filter(room=room).select_related("user").order_by("-created_at")[:100])
    messages.reverse()
    return Response(ChatMessageSerializer(messages, many=True).data)
