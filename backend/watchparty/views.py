import mimetypes
import os
import re
from datetime import timedelta

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.contrib.auth import authenticate, get_user_model
from django.core.cache import cache
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import HttpResponse, StreamingHttpResponse
from django.utils.html import escape
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .media_sources import detect_media_source
from .models import (
    ChatMessage,
    ClientIdentity,
    CompanionActivity,
    FriendLink,
    FriendRequest,
    PlaybackState,
    Room,
    RoomBan,
    RoomMember,
    RoomMute,
    UserProfile,
    ViewingActivity,
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


def month_increase_percent(daily_seconds, current_day=None):
    """Return the server-authoritative month-over-month increase.

    The source data remains the daily activity ledger. The derived percentage
    is refreshed and persisted with that ledger, rather than trusting each
    client to calculate a potentially different result.
    """
    today = current_day or timezone.localdate()
    current_start = today.replace(day=1)
    previous_end = current_start - timedelta(days=1)
    previous_start = previous_end.replace(day=1)
    daily = daily_seconds or {}

    def total_between(start, end):
        return sum(
            max(0, int(seconds or 0))
            for day, seconds in daily.items()
            if start.isoformat() <= str(day) <= end.isoformat()
        )

    current = total_between(current_start, today)
    previous = total_between(previous_start, previous_end)
    if previous <= 0:
        return 100 if current > 0 else 0
    return max(0, round((current - previous) / previous * 100))


def current_activity_streak(daily_seconds, current_day=None):
    """Count the active-day streak using the server calendar, not the device."""
    cursor = current_day or timezone.localdate()
    daily = daily_seconds or {}
    # A streak remains current until the end of the next calendar day, so a
    # user is not reset to zero just because they have not opened the app yet.
    if max(0, int(daily.get(cursor.isoformat(), 0) or 0)) <= 0:
        cursor -= timedelta(days=1)
    count = 0
    while max(0, int(daily.get(cursor.isoformat(), 0) or 0)) > 0:
        count += 1
        cursor -= timedelta(days=1)
    return count


def activity_payload(activity):
    genres = activity.genre_counts or {}
    total = sum(int(value or 0) for value in genres.values())
    genre_rows = [
        {"name": name, "seconds": int(seconds), "percent": round((int(seconds) / total * 100) if total else 0)}
        for name, seconds in sorted(genres.items(), key=lambda item: item[1], reverse=True)[:5]
    ]
    companion = (
        CompanionActivity.objects.filter(user=activity.user)
        .select_related("companion", "companion__watch_profile")
        .order_by("-seconds")
        .first()
    )
    top_companion = None
    if companion:
        top_companion = {**public_profile(companion.companion), "seconds": companion.seconds}
    return {
        "app_seconds": activity.app_seconds,
        "watched_seconds": activity.watched_seconds,
        "longest_movie_seconds": activity.longest_movie_seconds,
        "genres": genre_rows,
        "daily_seconds": activity.daily_seconds or {},
        "month_increase_percent": activity.month_increase_percent,
        "current_streak_days": current_activity_streak(activity.daily_seconds),
        "top_companion": top_companion,
    }


@api_view(["GET", "POST"])
def activity(request):
    activity_obj, _ = ViewingActivity.objects.get_or_create(user=request.user)
    if request.method == "GET":
        current_percent = month_increase_percent(activity_obj.daily_seconds)
        if activity_obj.month_increase_percent != current_percent:
            activity_obj.month_increase_percent = current_percent
            activity_obj.save(update_fields=["month_increase_percent", "updated_at"])
        return Response(activity_payload(activity_obj))

    # The client reports bounded foreground intervals. A single request can
    # never inflate a profile by hours, and no raw viewing history is stored.
    app_seconds = max(0, min(int(request.data.get("app_seconds") or 0), 90))
    watched_seconds = max(0, min(int(request.data.get("watched_seconds") or 0), 90))
    duration_seconds = max(0, min(int(request.data.get("duration_seconds") or 0), 86_400))
    genres = request.data.get("genres") or []
    room_id = request.data.get("room_id")
    if not isinstance(genres, list):
        genres = []
    day = timezone.localdate().isoformat()
    with transaction.atomic():
        activity_obj = ViewingActivity.objects.select_for_update().get(pk=activity_obj.pk)
        activity_obj.app_seconds += app_seconds
        activity_obj.watched_seconds += watched_seconds
        activity_obj.longest_movie_seconds = max(activity_obj.longest_movie_seconds, duration_seconds)
        daily = dict(activity_obj.daily_seconds or {})
        # App heartbeats already cover the time spent in a playing room.
        # Counting watched_seconds again inflated calendar totals and percent.
        daily[day] = min(86_400, int(daily.get(day, 0)) + app_seconds)
        # The activity card compares the current month with the previous one.
        # Keep enough history for two full months plus a safe margin.
        activity_obj.daily_seconds = dict(sorted(daily.items())[-100:])
        activity_obj.month_increase_percent = month_increase_percent(activity_obj.daily_seconds)
        counts = dict(activity_obj.genre_counts or {})
        for genre in genres[:5]:
            if isinstance(genre, str) and genre.strip():
                counts[genre.strip()[:32]] = int(counts.get(genre.strip()[:32], 0)) + watched_seconds
        activity_obj.genre_counts = counts
        activity_obj.save()
        if watched_seconds and room_id:
            room = Room.objects.filter(pk=room_id).first()
            if room:
                active_friend_ids = RoomMember.objects.filter(
                    room=room,
                    active_connections__gt=0,
                ).exclude(user=request.user).values_list("user_id", flat=True)
                friend_ids = FriendLink.objects.filter(
                    user=request.user,
                    friend_id__in=active_friend_ids,
                ).values_list("friend_id", flat=True)
                for friend_id in friend_ids:
                    pair, _ = CompanionActivity.objects.get_or_create(
                        user=request.user,
                        companion_id=friend_id,
                    )
                    pair.seconds += watched_seconds
                    pair.save(update_fields=["seconds", "updated_at"])
    return Response(activity_payload(activity_obj))


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


def request_profile(friend_request, user):
    return {"id": friend_request.id, **public_profile(user)}


@api_view(["GET", "POST", "DELETE"])
def friends(request):
    """Search confirmed friends. POST sends a request; DELETE removes a friend."""
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

    # DELETE bodies are not consistently forwarded by reverse proxies and
    # temporary tunnels. Accept the username in either place.
    username = (request.data.get("username") or request.query_params.get("username") or "").strip()
    friend = users.objects.filter(username__iexact=username).first()
    if not friend:
        return Response({"detail": "Пользователь не найден"}, status=status.HTTP_404_NOT_FOUND)
    if friend.pk == request.user.pk:
        return Response({"detail": "Нельзя добавить самого себя"}, status=status.HTTP_400_BAD_REQUEST)
    if request.method == "POST":
        if FriendLink.objects.filter(user=request.user, friend=friend).exists():
            return Response({**public_profile(friend), "is_friend": True, "status": "already_friends"})
        if FriendRequest.objects.filter(sender=request.user, recipient=friend).exists():
            return Response({"detail": "Request already sent", "status": "pending"}, status=status.HTTP_200_OK)
        # If both people pressed add, accepting immediately is friendlier than two requests.
        reverse = FriendRequest.objects.filter(sender=friend, recipient=request.user).first()
        with transaction.atomic():
            if reverse:
                reverse.delete()
                FriendLink.objects.get_or_create(user=request.user, friend=friend)
                FriendLink.objects.get_or_create(user=friend, friend=request.user)
                return Response({**public_profile(friend), "is_friend": True, "status": "accepted"}, status=status.HTTP_201_CREATED)
            FriendRequest.objects.create(sender=request.user, recipient=friend)
        return Response({**public_profile(friend), "is_friend": False, "status": "pending"}, status=status.HTTP_201_CREATED)

    FriendLink.objects.filter(user=request.user, friend=friend).delete()
    FriendLink.objects.filter(user=friend, friend=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["GET", "POST"])
def friend_requests(request):
    if request.method == "GET":
        incoming = FriendRequest.objects.filter(recipient=request.user).select_related("sender", "sender__watch_profile")
        outgoing = FriendRequest.objects.filter(sender=request.user).select_related("recipient", "recipient__watch_profile")
        return Response({
            "incoming": [request_profile(item, item.sender) for item in incoming],
            "outgoing": [request_profile(item, item.recipient) for item in outgoing],
        })

    request_id = request.data.get("request_id")
    action = request.data.get("action")
    invite = get_object_or_404(FriendRequest, pk=request_id, recipient=request.user)
    if action == "accept":
        with transaction.atomic():
            FriendLink.objects.get_or_create(user=request.user, friend=invite.sender)
            FriendLink.objects.get_or_create(user=invite.sender, friend=request.user)
            invite.delete()
        return Response({"status": "accepted"})
    if action == "decline":
        invite.delete()
        return Response({"status": "declined"})
    return Response({"detail": "Unknown action"}, status=status.HTTP_400_BAD_REQUEST)


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
                duration = float(metadata.get("duration_seconds") or 0)
                genres = metadata.get("genres") or []
                changed = []
                if resolved_title:
                    room.title = resolved_title
                    changed.append("title")
                if thumbnail:
                    room.thumbnail_url = thumbnail
                    changed.append("thumbnail_url")
                if duration:
                    room.duration_seconds = duration
                    changed.append("duration_seconds")
                if genres:
                    room.genres = genres
                    changed.append("genres")
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
    if RoomBan.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы заблокированы в этой комнате"}, status=403)
    if room.members.count() >= room.max_members and not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Комната заполнена"}, status=409)
    member, _ = RoomMember.objects.get_or_create(room=room, user=request.user)
    # Do not let a newly-created participation row silently clear a prior
    # moderation decision. `RoomMute` is keyed by the persistent user ID.
    durable_mute = RoomMute.objects.filter(room=room, user=request.user).exists()
    if member.is_muted != durable_mute:
        member.is_muted = durable_mute
        member.save(update_fields=["is_muted"])
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


@api_view(["POST"])
def moderate_member(request, room_id, user_id):
    """Room owner can mute, kick, ban, or transfer ownership in one atomic endpoint."""
    with transaction.atomic():
        room = get_object_or_404(Room.objects.select_for_update(), id=room_id)
        if room.owner_id != request.user.id:
            return Response({"detail": "Только создатель управляет участниками"}, status=403)
        if user_id == request.user.id:
            return Response({"detail": "Нельзя применить это действие к себе"}, status=400)
        member = get_object_or_404(
            RoomMember.objects.select_for_update().select_related(
                "user", "user__watch_profile", "user__client_identity"
            ),
            room=room,
            user_id=user_id,
        )
        actor_name = public_profile(request.user)["nickname"]
        target_name = public_profile(member.user)["nickname"]
        action = str(request.data.get("action") or "")
        muted = RoomMute.objects.filter(room=room, user_id=user_id).exists()
        if action == "mute":
            mute, created = RoomMute.objects.get_or_create(
                room=room,
                user_id=user_id,
                defaults={"muted_by": request.user},
            )
            if not created:
                mute.delete()
            muted = created
            # Keep the old member flag in sync for old clients/admin views,
            # but never use it as the authoritative moderation state.
            member.is_muted = muted
            member.save(update_fields=["is_muted"])
            system_text = (
                f"{actor_name} заглушил(а) {target_name}"
                if muted
                else f"{actor_name} разрешил(а) писать {target_name}"
            )
        elif action == "kick":
            # A removal is final for this room.  Persist it against the
            # account before deleting the visit, otherwise the same user can
            # immediately recreate RoomMember through the invite code.
            RoomBan.objects.get_or_create(room=room, user_id=user_id)
            member.delete()
            system_text = f"{actor_name} выгнал(а) {target_name}"
        elif action == "ban":
            RoomBan.objects.get_or_create(room=room, user_id=user_id)
            member.delete()
            system_text = f"{actor_name} заблокировал(а) {target_name}"
        elif action == "transfer":
            room.owner_id = user_id
            room.save(update_fields=["owner"])
            system_text = f"{actor_name} передал(а) управление {target_name}"
        else:
            return Response({"detail": "Неизвестное действие"}, status=400)
    # REST changes also need to reach people who are already in the room.  Do
    # not make them leave and re-enter just to see a mute, kick or new owner.
    async_to_sync(get_channel_layer().group_send)(
        f"watch_room_{room_id}",
        {
            "type": "room.moderation",
            "payload": {
                "action": action,
                "user_id": user_id,
                "owner_id": room.owner_id,
                "muted": muted,
                "actor_name": actor_name,
                "target_name": target_name,
                "system_text": system_text,
            },
        },
    )
    return Response(
        {"ok": True, "action": action, "muted": muted, "system_text": system_text}
    )


@api_view(["GET"])
def room_stream(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    if RoomBan.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы заблокированы в этой комнате"}, status=403)
    # Uploads deliberately bypass the external-source resolver. This keeps the
    # VK/site flow untouched and lets AVPlayer request the file through the
    # authenticated media endpoint below.
    if room.uploaded_video:
        if not room.uploaded_video.storage.exists(room.uploaded_video.name):
            return Response({"detail": "Загруженный файл больше недоступен"}, status=404)
        return Response({
            "url": request.build_absolute_uri(f"/api/rooms/{room.id}/media/"),
            "title": room.title,
            "duration_seconds": room.duration_seconds,
            "quality": "Original",
            "headers": {"Authorization": request.headers.get("Authorization", "")},
            "source_type": "upload",
            "thumbnail": room.thumbnail_url,
            "genres": room.genres,
        })
    if not room.vk_video_url:
        return Response({"detail": "В комнате не выбрано видео"}, status=400)
    source_type = detect_media_source(room.vk_video_url)
    # v3 invalidates streams resolved before trailer-aware selection existed.
    cache_key = f"room-stream:v3:{source_type}:{room.id}:{room.vk_video_url}"
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
    duration = float(stream.get("duration_seconds") or 0)
    genres = stream.get("genres") or []
    if resolved_title and room.title != resolved_title:
        room.title = resolved_title
        changed.append("title")
    if thumbnail and room.thumbnail_url != thumbnail:
        room.thumbnail_url = thumbnail
        changed.append("thumbnail_url")
    if duration and room.duration_seconds != duration:
        room.duration_seconds = duration
        changed.append("duration_seconds")
    if genres and room.genres != genres:
        room.genres = genres
        changed.append("genres")
    if changed:
        room.save(update_fields=changed)
    return Response(stream)


def _video_file_chunks(file_path, start, length):
    with open(file_path, "rb") as source:
        source.seek(start)
        remaining = length
        while remaining > 0:
            chunk = source.read(min(128 * 1024, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk


@api_view(["POST"])
def room_upload_video(request, room_id):
    """Attach an owner-selected local movie without touching URL providers."""
    room = get_object_or_404(Room, id=room_id)
    if room.owner_id != request.user.id:
        return Response({"detail": "Только создатель комнаты может загрузить видео"}, status=403)
    video = request.FILES.get("video")
    if video is None:
        return Response({"detail": "Выберите файл видео"}, status=400)
    extension = os.path.splitext(video.name or "")[1].lower()
    # iOS AVPlayer supports these containers reliably. No video is transcoded
    # or altered by the server, so the exact downloaded film is preserved.
    if extension not in {".mp4", ".mov", ".m4v"} or not str(video.content_type or "").startswith("video/"):
        return Response({"detail": "Поддерживаются видео MP4, MOV и M4V"}, status=415)
    if video.size <= 0:
        return Response({"detail": "Файл видео пустой"}, status=400)
    if video.size > settings.MAX_ROOM_VIDEO_UPLOAD_BYTES:
        return Response({"detail": "Видео превышает допустимый размер"}, status=413)

    old_file_name = room.uploaded_video.name if room.uploaded_video else ""
    # Saving through FileField uses Django's streaming upload handler; it does
    # not read a multi-gigabyte gallery file into Python memory.
    room.uploaded_video.save(os.path.basename(video.name), video, save=False)
    room.vk_video_url = ""
    requested_title = str(request.data.get("title") or "").strip()[:80]
    room.title = requested_title or os.path.splitext(os.path.basename(video.name))[0][:80] or "Видео"
    try:
        room.duration_seconds = max(0.0, float(request.data.get("duration_seconds") or 0))
    except (TypeError, ValueError):
        room.duration_seconds = 0
    room.thumbnail_url = ""
    room.genres = []
    room.save(update_fields=[
        "uploaded_video", "vk_video_url", "title", "duration_seconds", "thumbnail_url", "genres",
    ])
    if old_file_name and old_file_name != room.uploaded_video.name:
        room.uploaded_video.storage.delete(old_file_name)
    return Response(RoomSerializer(room, context={"request": request}).data, status=201)


@api_view(["GET"])
def room_uploaded_media(request, room_id):
    """Authenticated byte-range media stream for AVPlayer/local room movies."""
    room = get_object_or_404(Room, id=room_id)
    if (
        not RoomMember.objects.filter(room=room, user=request.user).exists()
        or RoomBan.objects.filter(room=room, user=request.user).exists()
    ):
        return Response({"detail": "Нет доступа к видео этой комнаты"}, status=403)
    if not room.uploaded_video or not room.uploaded_video.storage.exists(room.uploaded_video.name):
        return Response({"detail": "Загруженное видео не найдено"}, status=404)
    try:
        file_path = room.uploaded_video.path
        file_size = os.path.getsize(file_path)
    except (NotImplementedError, OSError):
        return Response({"detail": "Файл временно недоступен"}, status=503)

    start, end = 0, max(0, file_size - 1)
    range_header = request.headers.get("Range", "")
    if range_header:
        match = re.match(r"^bytes=(\d*)-(\d*)$", range_header.strip())
        if not match:
            return HttpResponse(status=416, headers={"Content-Range": f"bytes */{file_size}"})
        first, last = match.groups()
        if first:
            start = int(first)
            end = int(last) if last else end
        elif last:
            suffix = min(int(last), file_size)
            start = max(0, file_size - suffix)
        if start >= file_size or start > end:
            return HttpResponse(status=416, headers={"Content-Range": f"bytes */{file_size}"})
        end = min(end, file_size - 1)
    length = end - start + 1
    content_type = mimetypes.guess_type(room.uploaded_video.name)[0] or "video/mp4"
    response = StreamingHttpResponse(
        _video_file_chunks(file_path, start, length),
        status=206 if range_header else 200,
        content_type=content_type,
    )
    response["Accept-Ranges"] = "bytes"
    response["Content-Length"] = str(length)
    if range_header:
        response["Content-Range"] = f"bytes {start}-{end}/{file_size}"
    return response


@api_view(["GET", "POST"])
def room_messages(request, room_id):
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    if request.method == "POST":
        if RoomMute.objects.filter(room=room, user=request.user).exists():
            return Response({"detail": "You are muted in this room"}, status=403)
        text = str(request.data.get("text") or "").strip()[:500]
        image_data_url = str(request.data.get("image_data_url") or "").strip()
        if len(image_data_url) > 2_800_000:
            return Response({"detail": "Image is too large"}, status=413)
        if not text and not image_data_url:
            return Response({"detail": "Message is empty"}, status=400)
        client_message_id = str(request.data.get("client_message_id") or "").strip()[:64]
        # Persist before fan-out: a socket reconnect must never lose chat.
        if client_message_id:
            message, created = ChatMessage.objects.get_or_create(
                room=room, user=request.user, client_message_id=client_message_id,
                defaults={"text": text, "image_data_url": image_data_url},
            )
        else:
            message = ChatMessage.objects.create(
                room=room, user=request.user, text=text, image_data_url=image_data_url
            )
            created = True
        payload = ChatMessageSerializer(message, context={"request": request}).data
        if created:
            async_to_sync(get_channel_layer().group_send)(
                f"watch_room_{room.id}", {"type": "room.chat", "payload": dict(payload)}
            )
        return Response(payload, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
    messages = list(
        ChatMessage.objects.filter(room=room)
        .select_related("user", "user__watch_profile", "user__client_identity")
        .prefetch_related("reactions")
        .order_by("-created_at")[:100]
    )
    messages.reverse()
    return Response(ChatMessageSerializer(messages, many=True, context={"request": request}).data)
