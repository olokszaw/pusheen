import re

from django.contrib.auth import authenticate, get_user_model
from django.core.cache import cache
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.http import HttpResponse
from django.utils.html import escape
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .media_sources import detect_media_source
from .models import (
    ChatMessage,
    ClientIdentity,
    FriendLink,
    PlaybackState,
    Room,
    RoomMember,
    UserProfile,
)
from .permissions import IsRoomOwner
from .serializers import (
    ChatMessageSerializer,
    JoinSerializer,
    RoomMemberSerializer,
    RoomSerializer,
    public_profile,
)
from .video_stream import resolve_media_stream


USERNAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]{2,29}$")


def valid_username(value):
    return bool(USERNAME_PATTERN.fullmatch(value))


def auth_payload(user):
    token, _ = Token.objects.get_or_create(user=user)
    return {"token": token.key, **public_profile(user)}


@api_view(["GET"])
@permission_classes([AllowAny])
def room_invite_page(request, invite_code):
    room = get_object_or_404(Room, invite_code=invite_code.upper())
    code = escape(room.invite_code)
    title = escape(room.title)
    return HttpResponse(
        f"""<!doctype html><html lang='ru'><meta name='viewport' content='width=device-width,initial-scale=1'>
        <title>{title} · Pusheen</title><style>
        body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#080816;color:#f6f0ff;font:16px system-ui}}
        main{{width:min(420px,82vw);padding:28px;border:1px solid #ffffff22;border-radius:26px;background:#ffffff12;backdrop-filter:blur(22px);text-align:center}}
        b{{font-size:24px}} code{{display:block;margin:18px;font-size:28px;letter-spacing:5px;color:#d1b5ff}}
        </style><main><b>{title}</b><code>{code}</code><p>Открой Pusheen и войди в комнату по этому коду.</p></main></html>"""
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def username_available(request):
    username = request.query_params.get("username", "").strip()[:150]
    valid = valid_username(username)
    matches = get_user_model().objects.filter(username__iexact=username)
    if request.user.is_authenticated:
        matches = matches.exclude(pk=request.user.pk)
    available = valid and not matches.exists()
    return Response({"username": username, "valid": valid, "available": available})


@api_view(["POST"])
@permission_classes([AllowAny])
def register(request):
    nickname = request.data.get("nickname", "").strip()[:50]
    username = request.data.get("username", "").strip()[:150]
    password = request.data.get("password", "")
    if len(nickname) < 2:
        return Response({"detail": "Nickname должен содержать минимум 2 символа"}, status=400)
    if not valid_username(username):
        return Response({"detail": "Username: минимум 3 символа, буквы, цифры и _"}, status=400)
    if len(password) < 6:
        return Response({"detail": "Пароль должен содержать минимум 6 символов"}, status=400)
    users = get_user_model()
    if users.objects.filter(username__iexact=username).exists():
        return Response({"detail": "Этот username уже занят"}, status=409)
    user = users.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, nickname=nickname)
    return Response(auth_payload(user), status=201)


@api_view(["POST"])
@permission_classes([AllowAny])
def account_login(request):
    user = authenticate(
        username=request.data.get("username", "").strip(),
        password=request.data.get("password", ""),
    )
    if not user:
        return Response({"detail": "Неверный username или пароль"}, status=401)
    UserProfile.objects.get_or_create(user=user, defaults={"nickname": user.username})
    return Response(auth_payload(user))


@api_view(["POST"])
@permission_classes([AllowAny])
def demo_login(request):
    """Compatibility endpoint for already installed old clients."""
    username = request.data.get("username", "guest").strip()[:150]
    client_id = request.data.get("client_id", "").strip()[:80]
    if not username or not client_id:
        return Response({"detail": "Не переданы имя или идентификатор устройства"}, status=400)
    users = get_user_model()
    identity = ClientIdentity.objects.select_related("user").filter(client_id=client_id).first()
    if identity:
        user = identity.user
    else:
        base = "".join(ch for ch in username.lower().replace(" ", "_") if ch.isalnum() or ch == "_") or "guest"
        candidate, suffix = base[:140], 1
        while users.objects.filter(username=candidate).exists():
            suffix += 1
            candidate = f"{base[:135]}_{suffix}"
        user = users.objects.create_user(username=candidate)
        ClientIdentity.objects.create(user=user, client_id=client_id)
    profile, _ = UserProfile.objects.get_or_create(user=user, defaults={"nickname": username})
    if profile.nickname != username:
        profile.nickname = username
        profile.save(update_fields=["nickname"])
    return Response(auth_payload(user))


@api_view(["GET", "PATCH"])
def profile(request):
    profile_obj, _ = UserProfile.objects.get_or_create(
        user=request.user, defaults={"nickname": request.user.username}
    )
    if request.method == "PATCH":
        nickname = request.data.get("nickname")
        username = request.data.get("username")
        avatar = request.data.get("avatar_data_url")
        if username is not None:
            username = username.strip()[:150]
            if not valid_username(username):
                return Response({"detail": "Start with A-Z · use 3-30 letters, numbers or _"}, status=400)
            users = get_user_model()
            if users.objects.filter(username__iexact=username).exclude(pk=request.user.pk).exists():
                return Response({"detail": "Username taken"}, status=409)
            request.user.username = username
            request.user.save(update_fields=["username"])
        if nickname is not None:
            nickname = nickname.strip()[:50]
            if len(nickname) < 2:
                return Response({"detail": "Nickname должен содержать минимум 2 символа"}, status=400)
            profile_obj.nickname = nickname
        if avatar is not None:
            if len(avatar) > 2_800_000:
                return Response({"detail": "Аватар слишком большой"}, status=413)
            profile_obj.avatar_data_url = avatar
        profile_obj.save()
    return Response(public_profile(request.user))


@api_view(["GET", "POST", "DELETE"])
def friends(request):
    """Search profiles and add/remove confirmed friends by @username."""
    users = get_user_model()
    if request.method == "GET":
        query = request.query_params.get("username", "").strip()
        if query:
            candidates = (
                users.objects.filter(username__istartswith=query)
                .exclude(pk=request.user.pk)
                .select_related("watch_profile")[:20]
            )
            existing = set(
                FriendLink.objects.filter(user=request.user).values_list("friend_id", flat=True)
            )
            return Response([
                {**public_profile(candidate), "is_friend": candidate.id in existing}
                for candidate in candidates
            ])
        friend_ids = FriendLink.objects.filter(user=request.user).values_list("friend_id", flat=True)
        result = users.objects.filter(pk__in=friend_ids).select_related("watch_profile")
        return Response([{**public_profile(user), "is_friend": True} for user in result])

    username = request.data.get("username", "").strip()
    friend = users.objects.filter(username__iexact=username).first()
    if not friend:
        return Response({"detail": "Пользователь не найден"}, status=status.HTTP_404_NOT_FOUND)
    if friend.pk == request.user.pk:
        return Response({"detail": "Нельзя добавить самого себя"}, status=status.HTTP_400_BAD_REQUEST)
    if request.method == "POST":
        with transaction.atomic():
            FriendLink.objects.get_or_create(user=request.user, friend=friend)
            FriendLink.objects.get_or_create(user=friend, friend=request.user)
        return Response({**public_profile(friend), "is_friend": True}, status=status.HTTP_201_CREATED)

    FriendLink.objects.filter(user=request.user, friend=friend).delete()
    FriendLink.objects.filter(user=friend, friend=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


class RoomListCreateView(generics.ListCreateAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        return Room.objects.filter(members__user=self.request.user).select_related(
            "owner", "owner__watch_profile", "playback"
        ).distinct()

    @transaction.atomic
    def perform_create(self, serializer):
        media_url = serializer.validated_data.get("vk_video_url", "")
        fallback_title = "Совместный просмотр"
        room = serializer.save(
            owner=self.request.user,
            title=serializer.validated_data.get("title") or fallback_title,
            description="",
            theme="movie",
            allow_guests_control=False,
        )
        RoomMember.objects.create(room=room, user=self.request.user)
        PlaybackState.objects.create(room=room)
        if media_url:
            try:
                metadata = resolve_media_stream(
                    media_url, detect_media_source(media_url)
                )
                resolved_title = str(metadata.get("title") or "").strip()[:80]
                thumbnail = str(metadata.get("thumbnail") or "").strip()
                changed = []
                if resolved_title:
                    room.title = resolved_title
                    changed.append("title")
                if thumbnail:
                    room.thumbnail_url = thumbnail
                    changed.append("thumbnail_url")
                if changed:
                    room.save(update_fields=changed)
            except Exception:
                # Room creation must still succeed if a provider temporarily
                # refuses metadata; room_stream will retry later.
                pass


class RoomDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = RoomSerializer
    queryset = Room.objects.select_related("owner", "owner__watch_profile", "playback")
    permission_classes = [IsAuthenticated, IsRoomOwner]


@api_view(["POST"])
def join_room(request):
    data = JoinSerializer(data=request.data)
    data.is_valid(raise_exception=True)
    room = get_object_or_404(Room, invite_code=data.validated_data["invite_code"])
    if room.members.count() >= room.max_members and not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Комната заполнена"}, status=409)
    RoomMember.objects.get_or_create(room=room, user=request.user)
    return Response(RoomSerializer(room, context={"request": request}).data)


@api_view(["GET"])
def room_members(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    members = room.members.select_related(
        "user", "user__watch_profile", "user__client_identity", "room__owner"
    ).order_by("joined_at")
    return Response(RoomMemberSerializer(members, many=True).data)


@api_view(["GET"])
def room_stream(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    if not room.vk_video_url:
        return Response({"detail": "В комнате не выбрано видео"}, status=400)
    source_type = detect_media_source(room.vk_video_url)
    cache_key = f"room-stream:v2:{source_type}:{room.id}:{room.vk_video_url}"
    stream = cache.get(cache_key)
    if stream is None:
        try:
            stream = resolve_media_stream(room.vk_video_url, source_type)
        except Exception as error:
            return Response(
                {"detail": f"Не удалось получить поток {source_type.upper()}: {error}", "source_type": source_type, "fallback": "embedded_page" if source_type == "web" else None},
                status=502,
            )
        cache.set(cache_key, stream, timeout=20 * 60)
    changed = []
    resolved_title = str(stream.get("title") or "").strip()[:80]
    thumbnail = str(stream.get("thumbnail") or "").strip()
    if resolved_title and room.title != resolved_title:
        room.title = resolved_title
        changed.append("title")
    if thumbnail and room.thumbnail_url != thumbnail:
        room.thumbnail_url = thumbnail
        changed.append("thumbnail_url")
    if changed:
        room.save(update_fields=changed)
    return Response(stream)


@api_view(["GET"])
def room_messages(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    messages = list(
        ChatMessage.objects.filter(room=room)
        .select_related("user", "user__watch_profile", "user__client_identity")
        .prefetch_related("reactions")
        .order_by("-created_at")[:100]
    )
    messages.reverse()
    return Response(ChatMessageSerializer(messages, many=True, context={"request": request}).data)
