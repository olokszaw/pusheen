import mimetypes
import gzip
import os
import re
import json
import ssl
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from datetime import timedelta

import certifi

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.contrib.auth import authenticate, get_user_model
from django.core.cache import cache
from django.core.files.base import ContentFile
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import FileResponse, HttpResponse, StreamingHttpResponse
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
    RoomInvitation,
    RoomMember,
    RoomMute,
    UserProfile,
    ViewingActivity,
    TelegramSticker,
    TelegramStickerPack,
)
from .permissions import IsRoomOwner
from .presence import mark_presence_offline, touch_presence
from .playback import projected_playback_payload
from .serializers import (
    ChatMessageSerializer,
    JoinSerializer,
    RoomMemberSerializer,
    RoomSerializer,
    public_profile,
)


_TELEGRAM_SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def _telegram_open(request, timeout):
    last_error = None
    for attempt in range(3):
        try:
            return urlopen(request, timeout=timeout, context=_TELEGRAM_SSL_CONTEXT)
        except HTTPError as error:
            try:
                payload = json.loads(error.read().decode("utf-8", errors="replace"))
                description = payload.get("description")
            except (ValueError, AttributeError):
                description = None
            raise ValueError(f"Telegram API: {description or 'запрос отклонён'}") from error
        except (URLError, TimeoutError, OSError) as error:
            last_error = error
            if attempt < 2:
                time.sleep(0.35 * (attempt + 1))
    reason = getattr(last_error, "reason", None)
    detail = str(reason or "ошибка соединения")[:180]
    raise ValueError(f"Telegram API недоступен с сервера: {detail}") from last_error


def _telegram_api(method, token, **params):
    url = f"https://api.telegram.org/bot{token}/{method}"
    if params:
        url += "?" + urlencode(params)
    with _telegram_open(Request(url, headers={"User-Agent": "Pusheen/1.0"}), timeout=15) as response:
        payload = json.load(response)
    if not payload.get("ok"):
        raise ValueError(payload.get("description") or "Telegram отклонил набор")
    return payload["result"]


def _download_telegram_file(token, file_id):
    info = _telegram_api("getFile", token, file_id=file_id)
    path = info.get("file_path")
    if not path:
        raise ValueError("Telegram не вернул файл стикера")
    url = f"https://api.telegram.org/file/bot{token}/{path}"
    with _telegram_open(Request(url, headers={"User-Agent": "Pusheen/1.0"}), timeout=20) as response:
        data = response.read(3_000_001)
    if len(data) > 3_000_000:
        raise ValueError("Файл стикера слишком большой")
    return data, os.path.splitext(path)[1] or ".webp"


def _normalize_telegram_sticker_data(item, data, extension):
    if item.get("is_animated") and extension.lower() == ".tgs":
        # Telegram TGS files are gzip-compressed Lottie JSON. Store normalized
        # JSON so every iOS client can render the animation directly without
        # depending on platform-specific gzip support.
        try:
            data = gzip.decompress(data)
            json.loads(data.decode("utf-8"))
            extension = ".json"
        except (OSError, UnicodeDecodeError, ValueError) as error:
            raise ValueError("Telegram вернул повреждённый анимированный стикер") from error
    return data, extension


def _fetch_telegram_sticker(token, indexed_item):
    index, item = indexed_item
    data, extension = _download_telegram_file(token, item["file_id"])
    data, extension = _normalize_telegram_sticker_data(item, data, extension)
    preview_data = preview_extension = None
    thumbnail = item.get("thumbnail")
    if thumbnail and thumbnail.get("file_id"):
        preview_data, preview_extension = _download_telegram_file(token, thumbnail["file_id"])
        # Animated Telegram thumbnails can themselves be compressed .tgs.
        # Normalize them as well, so the iOS picker receives usable Lottie JSON.
        preview_data, preview_extension = _normalize_telegram_sticker_data(
            item, preview_data, preview_extension
        )
    return index, item, data, extension, preview_data, preview_extension


def sticker_payload(sticker):
    return {
        "id": sticker.id,
        "emoji": sticker.emoji,
        "format": sticker.format,
        "file_url": f"/api/stickers/{sticker.id}/file/",
        "preview_url": f"/api/stickers/{sticker.id}/preview/" if sticker.preview else f"/api/stickers/{sticker.id}/file/",
    }
from .video_stream import resolve_media_stream


USERNAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]{2,29}$")


def safe_seconds(value):
    """Coerce legacy JSON values without allowing a bad profile to break API."""
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError, OverflowError):
        return 0


def safe_activity_map(value):
    """Return a Swift-decodable day/genre map from potentially old JSON."""
    if not isinstance(value, dict):
        return {}
    return {str(key): safe_seconds(seconds) for key, seconds in value.items()}


def presence_payload(user):
    presence = getattr(user, "watch_presence", None)
    if not presence or not presence.show_activity:
        return {
            "activity_visible": False,
            "is_online": False,
            "last_seen": None,
            "last_seen_age_seconds": None,
        }

    now = timezone.now()
    app_online = presence.is_active and presence.last_seen >= now - timedelta(seconds=15)

    # A live room WebSocket is also authoritative proof that the application
    # is open.  Keeping app presence and room presence completely separate made
    # the friends list say "last seen" while the very same profile exposed an
    # active watch session.  The room heartbeat expires independently, so a
    # dead socket can keep this true for at most the normal 24-second TTL.
    room_last_seen = (
        RoomMember.objects.filter(
            user_id=user.pk,
            active_connections__gt=0,
            last_heartbeat_at__gte=now - timedelta(seconds=24),
        )
        .order_by("-last_heartbeat_at")
        .values_list("last_heartbeat_at", flat=True)
        .first()
    )
    online = app_online or room_last_seen is not None
    last_seen = max(
        value for value in (presence.last_seen, room_last_seen) if value is not None
    )
    return {
        "activity_visible": True,
        "is_online": online,
        "last_seen": last_seen.isoformat(),
        # Clients anchor this elapsed value to their own clock/time zone. A
        # fixed offset configured on the Windows server cannot leak into the
        # hour displayed by an iPhone.
        "last_seen_age_seconds": max(
            0, int((now - last_seen).total_seconds())
        ),
    }


def social_profile(user):
    return {**public_profile(user), **presence_payload(user)}


def _active_room_member(user):
    """Return the user's newest live room connection, never a stale membership."""
    cutoff = timezone.now() - timedelta(seconds=24)
    return (
        RoomMember.objects.filter(
            user=user,
            active_connections__gt=0,
            last_heartbeat_at__gte=cutoff,
        )
        .select_related("room", "room__playback")
        .order_by("-last_heartbeat_at")
        .first()
    )


def _current_watching_payload(request, target):
    """Build a friend-safe, read-only live preview without room credentials."""
    member = _active_room_member(target)
    if not member:
        return None
    room = member.room
    try:
        playback = room.playback
    except PlaybackState.DoesNotExist:
        playback = None

    snapshot_at = timezone.now()
    viewer_snapshot_is_fresh = bool(
        member.viewer_playback_at
        and member.viewer_playback_at >= snapshot_at - timedelta(seconds=8)
    )
    if viewer_snapshot_is_fresh:
        position = max(0.0, float(member.viewer_position_seconds or 0))
        is_playing = bool(member.viewer_is_playing)
        playback_updated_at = member.viewer_playback_at
    else:
        position = max(0.0, float(playback.position_seconds if playback else 0))
        is_playing = bool(playback and playback.is_playing)
        playback_updated_at = playback.updated_at if playback else snapshot_at

    elapsed = max(0.0, (snapshot_at - playback_updated_at).total_seconds())
    if is_playing:
        if viewer_snapshot_is_fresh or elapsed <= 8:
            position += elapsed
        else:
            # A room heartbeat can remain live while an old shared play command
            # has no reporting AVPlayer behind it. Never extrapolate that stale
            # command all the way to the last frame of the movie.
            is_playing = False

    title = room.title
    thumbnail = room.thumbnail_url
    duration = max(
        0.0,
        float(room.duration_seconds or 0),
        float(member.viewer_duration_seconds or 0) if viewer_snapshot_is_fresh else 0.0,
    )
    preview_url = ""
    preview_headers = {}
    source_type = "upload" if room.uploaded_video else detect_media_source(room.vk_video_url)

    if room.uploaded_video:
        if title.startswith(("pusheen-movie-", "pusheen-file-")):
            title = "Видео из галереи"
        if room.uploaded_video.storage.exists(room.uploaded_video.name):
            preview_url = request.build_absolute_uri(
                f"/api/users/{target.id}/watch-preview/?room_id={room.id}"
            )
            authorization = request.headers.get("Authorization", "")
            if authorization:
                preview_headers["Authorization"] = authorization
    elif room.vk_video_url:
        cache_key = f"room-stream:v4:{source_type}:{room.id}:{room.vk_video_url}"
        stream = cache.get(cache_key)
        if stream is None:
            try:
                stream = resolve_media_stream(room.vk_video_url, source_type)
            except Exception:
                stream = {}
            else:
                cache.set(cache_key, stream, timeout=90)
        preview_url = str(stream.get("url") or "")
        preview_headers = dict(stream.get("headers") or {})
        title = str(stream.get("title") or title)
        thumbnail = str(stream.get("thumbnail") or thumbnail)
        duration = max(duration, float(stream.get("duration_seconds") or 0))

    if duration > 0:
        position = min(position, duration)
    return {
        "title": title,
        "thumbnail_url": thumbnail,
        "duration_seconds": duration,
        "position_seconds": position,
        "is_playing": is_playing,
        # `position` above is already projected to snapshot_at. Returning the
        # old database timestamp made iOS add the same elapsed interval a
        # second time, which is how a short movie displayed a 7-hour position.
        "server_updated_at": snapshot_at.isoformat(),
        "preview_url": preview_url,
        "headers": preview_headers,
        "source_type": source_type,
    }


@api_view(["POST"])
def app_presence(request):
    """Explicit app-lifecycle presence; ordinary API polling never counts."""
    active = request.data.get("active") is True
    if active:
        touch_presence(request.user, minimum_interval=0)
    else:
        mark_presence_offline(request.user)
    current = get_user_model().objects.select_related("watch_presence").get(pk=request.user.pk)
    return Response(presence_payload(current))


def valid_username(value):
    return bool(USERNAME_PATTERN.fullmatch(value))


def auth_payload(user):
    token, _ = Token.objects.get_or_create(user=user)
    return {"token": token.key, **public_profile(user)}


def month_increase_percent(daily_seconds, current_day=None):
    """Compare this month with the same elapsed period of last month."""
    today = current_day or timezone.localdate()
    current_start = today.replace(day=1)
    previous_end = current_start - timedelta(days=1)
    previous_start = previous_end.replace(day=1)
    daily = safe_activity_map(daily_seconds)

    def total_between(start, end):
        return sum(
            safe_seconds(seconds)
            for day, seconds in daily.items()
            if start.isoformat() <= str(day) <= end.isoformat()
        )

    current = total_between(current_start, today)
    elapsed_days = (today - current_start).days
    previous_comparison_end = min(
        previous_start + timedelta(days=elapsed_days),
        previous_end,
    )
    previous = total_between(previous_start, previous_comparison_end)
    if previous <= 0:
        return 100 if current > 0 else 0
    return max(0, round((current - previous) / previous * 100))


def current_activity_streak(daily_seconds, current_day=None):
    """Count the active-day streak using the server calendar, not the device."""
    cursor = current_day or timezone.localdate()
    daily = safe_activity_map(daily_seconds)
    # A streak remains current until the end of the next calendar day, so a
    # user is not reset to zero just because they have not opened the app yet.
    if safe_seconds(daily.get(cursor.isoformat(), 0)) <= 0:
        cursor -= timedelta(days=1)
    count = 0
    while safe_seconds(daily.get(cursor.isoformat(), 0)) > 0:
        count += 1
        cursor -= timedelta(days=1)
    return count


def activity_payload(activity):
    genres = safe_activity_map(activity.genre_counts)
    total = sum(genres.values())
    genre_rows = [
        {"name": name, "seconds": seconds, "percent": round((seconds / total * 100) if total else 0)}
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
        "daily_seconds": safe_activity_map(activity.daily_seconds),
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
    submitted_username = request.data.get("username", "").strip()
    # Registration and availability checks are case-insensitive, so login must
    # resolve the same canonical account instead of rejecting @Alice as @alice.
    canonical_username = (
        get_user_model().objects.filter(username__iexact=submitted_username)
        .values_list("username", flat=True)
        .first()
    )
    user = authenticate(
        username=canonical_username or submitted_username,
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


@api_view(["GET"])
def public_user_profile(request, user_id):
    """Return a safe public profile and friend-only aggregate analytics.

    Basic identity is visible to authenticated users because it is already
    shown in rooms and friend search. Viewing analytics never expose raw room
    history and are available only to the owner or a confirmed friend.
    """
    target = get_object_or_404(
        get_user_model().objects.select_related("watch_profile", "client_identity", "watch_presence"),
        pk=user_id,
    )
    is_self = target.pk == request.user.pk
    # New friendships create two directional rows.  Earlier builds could
    # leave only one row behind, though, so treat either direction as the same
    # confirmed relationship when deciding whether aggregated insights may be
    # shown.  This keeps existing friends from seeing an empty profile.
    is_friend = FriendLink.objects.filter(
        Q(user=request.user, friend=target) | Q(user=target, friend=request.user)
    ).exists()
    analytics_visible = is_self or is_friend
    payload = {
        **social_profile(target),
        "is_friend": is_friend,
        "analytics_visible": analytics_visible,
        "stats": None,
        "now_watching": None,
    }
    if analytics_visible:
        activity_obj, _ = ViewingActivity.objects.get_or_create(user=target)
        current_percent = month_increase_percent(activity_obj.daily_seconds)
        if activity_obj.month_increase_percent != current_percent:
            activity_obj.month_increase_percent = current_percent
            activity_obj.save(update_fields=["month_increase_percent", "updated_at"])
        payload["stats"] = activity_payload(activity_obj)
        presence = presence_payload(target)
        if presence["activity_visible"]:
            # A provider/storage outage must never make the whole public
            # profile fail. The live tile can safely disappear until retry.
            try:
                payload["now_watching"] = _current_watching_payload(request, target)
            except Exception:
                payload["now_watching"] = None
    return Response(payload)


def request_profile(friend_request, user):
    return {"id": friend_request.id, **social_profile(user)}


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
                .select_related("watch_profile", "client_identity", "watch_presence")[:20]
            )
            existing = set(
                FriendLink.objects.filter(user=request.user).values_list("friend_id", flat=True)
            )
            return Response([
                {**social_profile(candidate), "is_friend": candidate.id in existing}
                for candidate in candidates
            ])
        friend_ids = FriendLink.objects.filter(user=request.user).values_list("friend_id", flat=True)
        result = users.objects.filter(pk__in=friend_ids).select_related("watch_profile", "client_identity", "watch_presence")
        return Response([{**social_profile(user), "is_friend": True} for user in result])

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
    if action == "cancel":
        invite = get_object_or_404(FriendRequest, pk=request_id, sender=request.user)
        invite.delete()
        return Response({"status": "cancelled"})
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


@api_view(["GET", "POST"])
def telegram_sticker_packs(request):
    if request.method == "GET":
        packs = TelegramStickerPack.objects.filter(user=request.user).prefetch_related("stickers")
        return Response([
            {"id": pack.id, "short_name": pack.short_name, "title": pack.title,
             "stickers": [sticker_payload(item) for item in pack.stickers.all()]}
            for pack in packs
        ])
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    if not token:
        return Response({"detail": "На сервере не настроен TELEGRAM_BOT_TOKEN"}, status=503)
    link = str(request.data.get("url") or "").strip()
    match = re.fullmatch(r"https?://(?:t\.me|telegram\.me)/addstickers/([A-Za-z0-9_]{1,80})/?", link)
    if not match:
        return Response({"detail": "Нужна ссылка вида https://t.me/addstickers/name"}, status=400)
    short_name = match.group(1)
    try:
        source = _telegram_api("getStickerSet", token, name=short_name)
        source_stickers = list(enumerate(source.get("stickers", [])[:120]))
        worker_count = min(6, max(1, len(source_stickers)))
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            downloaded = list(executor.map(lambda item: _fetch_telegram_sticker(token, item), source_stickers))
        with transaction.atomic():
            pack, _ = TelegramStickerPack.objects.get_or_create(
                user=request.user, short_name=short_name,
                defaults={"title": source.get("title") or short_name},
            )
            pack.title = source.get("title") or short_name
            pack.save(update_fields=["title"])
            pack.stickers.all().delete()
            for index, item, data, extension, preview_data, preview_extension in downloaded:
                format_name = "video" if item.get("is_video") else "animated" if item.get("is_animated") else "static"
                sticker = TelegramSticker(
                    pack=pack, telegram_file_id=item["file_id"], emoji=item.get("emoji", ""),
                    format=format_name, order=index,
                )
                sticker.file.save(f"{item.get('file_unique_id', index)}{extension}", ContentFile(data), save=False)
                if preview_data is not None:
                    sticker.preview.save(f"{item.get('file_unique_id', index)}-preview{preview_extension}", ContentFile(preview_data), save=False)
                sticker.save()
    except ValueError as error:
        return Response({"detail": str(error)}, status=502)
    pack = TelegramStickerPack.objects.prefetch_related("stickers").get(pk=pack.pk)
    return Response({"id": pack.id, "short_name": pack.short_name, "title": pack.title, "stickers": [sticker_payload(item) for item in pack.stickers.all()]}, status=201)


@api_view(["GET"])
def telegram_sticker_file(request, sticker_id, preview=False):
    sticker = get_object_or_404(TelegramSticker, pk=sticker_id)
    stored = sticker.preview if preview and sticker.preview else sticker.file
    # Packs imported by an older backend may still contain compressed .tgs.
    # Normalize those lazily as well, so an existing pack starts animating
    # without forcing the user to import it again.
    if sticker.format == TelegramSticker.ANIMATED and stored.name.lower().endswith(".tgs"):
        try:
            payload = gzip.decompress(stored.read())
            json.loads(payload.decode("utf-8"))
        except (OSError, UnicodeDecodeError, ValueError):
            return Response({"detail": "Повреждённый анимированный стикер"}, status=422)
        response = HttpResponse(payload, content_type="application/json")
    else:
        response = FileResponse(stored.open("rb"), content_type=mimetypes.guess_type(stored.name)[0] or "application/octet-stream")
    response["Cache-Control"] = "private, max-age=86400"
    return response


def room_invitation_payload(invitation):
    sender = social_profile(invitation.sender)
    room = invitation.room
    return {
        "id": invitation.id,
        "status": invitation.status,
        "created_at": invitation.created_at.isoformat(),
        "sender": sender,
        "room": {
            "id": room.id,
            "title": room.title,
            "thumbnail_url": room.thumbnail_url,
            "invite_code": room.invite_code,
        },
    }


@api_view(["GET"])
def room_invitations(request):
    invitations = (
        RoomInvitation.objects.filter(recipient=request.user, status=RoomInvitation.PENDING)
        .exclude(room__members__user=request.user)
        .select_related(
            "room", "sender", "sender__watch_profile", "sender__client_identity", "sender__watch_presence"
        )
        .order_by("-created_at")
    )
    return Response([room_invitation_payload(item) for item in invitations])


@api_view(["POST"])
def invite_room_friends(request, room_id):
    room = get_object_or_404(Room, pk=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не состоите в этой комнате"}, status=403)
    raw_ids = request.data.get("user_ids")
    if raw_ids is None:
        raw_ids = [request.data.get("user_id")]
    if not isinstance(raw_ids, list):
        return Response({"detail": "Некорректный список друзей"}, status=400)
    recipient_ids = []
    for raw_id in raw_ids[:20]:
        try:
            user_id = int(raw_id)
        except (TypeError, ValueError):
            continue
        if user_id != request.user.id and user_id not in recipient_ids:
            recipient_ids.append(user_id)
    users = get_user_model().objects.filter(pk__in=recipient_ids).select_related(
        "watch_profile", "client_identity", "watch_presence"
    )
    results = []
    for recipient in users:
        confirmed_friend = FriendLink.objects.filter(
            Q(user=request.user, friend=recipient) | Q(user=recipient, friend=request.user)
        ).exists()
        if not confirmed_friend:
            results.append({"user_id": recipient.id, "state": "not_friend"})
            continue
        if RoomMember.objects.filter(room=room, user=recipient).exists():
            results.append({"user_id": recipient.id, "state": "already_member"})
            continue
        if RoomBan.objects.filter(room=room, user=recipient).exists():
            results.append({"user_id": recipient.id, "state": "unavailable"})
            continue
        invitation, created = RoomInvitation.objects.get_or_create(
            room=room,
            recipient=recipient,
            defaults={"sender": request.user},
        )
        results.append({
            "user_id": recipient.id,
            "invitation_id": invitation.id,
            "state": "sent" if created else invitation.status,
        })
    return Response({"results": results}, status=status.HTTP_201_CREATED)


@api_view(["POST"])
def respond_room_invitation(request, invitation_id):
    invitation = get_object_or_404(
        RoomInvitation.objects.select_related("room", "room__owner", "room__playback"),
        pk=invitation_id,
        recipient=request.user,
        status=RoomInvitation.PENDING,
    )
    action = request.data.get("action")
    if action == "decline":
        invitation.status = RoomInvitation.DECLINED
        invitation.save(update_fields=["status", "updated_at"])
        return Response({"status": "declined"})
    if action != "accept":
        return Response({"detail": "Неизвестное действие"}, status=400)
    room = invitation.room
    if RoomBan.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Приглашение больше недействительно"}, status=410)
    with transaction.atomic():
        if not RoomMember.objects.filter(room=room, user=request.user).exists():
            if room.members.count() >= room.max_members:
                return Response({"detail": "В комнате больше нет свободных мест"}, status=409)
            RoomMember.objects.create(room=room, user=request.user)
        invitation.status = RoomInvitation.ACCEPTED
        invitation.save(update_fields=["status", "updated_at"])
    serializer = RoomSerializer(room, context={"request": request})
    return Response({"status": "accepted", "room": serializer.data})


class RoomListCreateView(generics.ListCreateAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        return Room.objects.filter(members__user=self.request.user).select_related(
            "owner", "owner__watch_profile", "playback"
        ).distinct()

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_id = serializer.validated_data.get("creation_request_id")
        if request_id:
            existing = Room.objects.filter(
                owner=request.user, creation_request_id=request_id
            ).select_related("owner", "owner__watch_profile", "playback").first()
            if existing:
                return Response(self.get_serializer(existing).data, status=status.HTTP_200_OK)
        return self._create_room_once(serializer, request, request_id)

    def _create_room_once(self, serializer, request, request_id):
        media_url = serializer.validated_data.get("vk_video_url", "")
        metadata = None
        if media_url:
            try:
                # External extraction must not hold an owner/room database lock.
                metadata = resolve_media_stream(media_url, detect_media_source(media_url))
            except Exception:
                metadata = None
        created = True
        try:
            with transaction.atomic():
                get_user_model().objects.select_for_update().get(pk=request.user.pk)
                room = (
                    Room.objects.filter(owner=request.user, creation_request_id=request_id).first()
                    if request_id else None
                )
                if room is None:
                    room = serializer.save(
                        owner=request.user,
                        title=serializer.validated_data.get("title") or "Watch together",
                        description="",
                        theme="movie",
                        allow_guests_control=False,
                    )
                else:
                    serializer.instance = room
                    created = False
                RoomMember.objects.get_or_create(room=room, user=request.user)
                PlaybackState.objects.get_or_create(room=room)
        except IntegrityError:
            if not request_id:
                raise
            room = Room.objects.select_related("playback").get(
                owner=request.user, creation_request_id=request_id
            )
            serializer.instance = room
            created = False
        if metadata and created:
            changed = []
            resolved_title = str(metadata.get("title") or "").strip()[:80]
            thumbnail = str(metadata.get("thumbnail") or "").strip()
            duration = float(metadata.get("duration_seconds") or 0)
            genres = metadata.get("genres") or []
            for field, value in (
                ("title", resolved_title),
                ("thumbnail_url", thumbnail),
                ("duration_seconds", duration),
                ("genres", genres),
            ):
                if value:
                    setattr(room, field, value)
                    changed.append(field)
            if changed:
                room.save(update_fields=changed)
        output = self.get_serializer(room)
        return Response(
            output.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
            headers=self.get_success_headers(output.data),
        )

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


@api_view(["GET"])
def room_snapshot(request, room_id):
    """Atomic-shaped authoritative bootstrap for entry and reconnect."""
    now = timezone.now()
    room = get_object_or_404(
        Room.objects.select_related("owner", "owner__watch_profile", "playback"),
        id=room_id,
    )
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Not a room member"}, status=403)
    members = list(room.members.select_related(
        "user", "user__watch_profile", "user__client_identity", "room__owner"
    ).order_by("joined_at"))
    playback = projected_playback_payload(room, room.playback, now=now)
    playback.update({
        "is_owner": room.owner_id == request.user.id,
        "is_muted": RoomMute.objects.filter(room=room, user=request.user).exists(),
    })
    context = {"request": request, "snapshot_now": now}
    return Response({
        "snapshot_at": now.isoformat(),
        "room": RoomSerializer(room, context=context).data,
        "playback": playback,
        "members": RoomMemberSerializer(members, many=True, context=context).data,
    })


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
            RoomMember.objects.select_for_update(of=("self",)).select_related(
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
    # v4 invalidates streams resolved before AVPlayer codec-aware selection.
    cache_key = f"room-stream:v4:{source_type}:{room.id}:{room.vk_video_url}"
    if request.query_params.get("refresh") == "1":
        cache.delete(cache_key)
    stream = cache.get(cache_key)
    if stream is None:
        try:
            stream = resolve_media_stream(room.vk_video_url, source_type)
        except Exception as error:
            return Response(
                {"detail": f"Не удалось получить поток {source_type.upper()}: {error}", "source_type": source_type, "fallback": "embedded_page" if source_type == "web" else None},
                status=502,
            )
        # Extracted CDN URLs are often signed and short-lived. Keeping one for
        # twenty minutes made re-entering a room reuse an already expired URL.
        cache.set(cache_key, stream, timeout=90)
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


def _uploaded_video_response(request, room):
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
    return _uploaded_video_response(request, room)


@api_view(["GET"])
def public_user_watch_preview(request, user_id):
    """Stream a friend's active local video without joining or exposing its room."""
    target = get_object_or_404(get_user_model(), pk=user_id)
    is_self = target.pk == request.user.pk
    is_friend = FriendLink.objects.filter(
        Q(user=request.user, friend=target) | Q(user=target, friend=request.user)
    ).exists()
    if not (is_self or is_friend):
        return Response({"detail": "Просмотр недоступен"}, status=403)
    presence = presence_payload(target)
    if not presence["activity_visible"]:
        return Response({"detail": "Активность скрыта"}, status=403)
    member = _active_room_member(target)
    requested_room_id = request.query_params.get("room_id")
    if requested_room_id and (
        not member or str(member.room_id) != str(requested_room_id)
    ):
        return Response({"detail": "Превью комнаты устарело"}, status=404)
    if not member or not member.room.uploaded_video:
        return Response({"detail": "Активное видео не найдено"}, status=404)
    return _uploaded_video_response(request, member.room)


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
        reply_to = None
        if request.data.get("reply_to_id"):
            reply_to = get_object_or_404(
                ChatMessage, id=request.data.get("reply_to_id"), room=room
            )
        # Persist before fan-out: a socket reconnect must never lose chat.
        if client_message_id:
            message, created = ChatMessage.objects.get_or_create(
                room=room, user=request.user, client_message_id=client_message_id,
                defaults={"text": text, "image_data_url": image_data_url, "reply_to": reply_to},
            )
        else:
            message = ChatMessage.objects.create(
                room=room, user=request.user, text=text, image_data_url=image_data_url,
                reply_to=reply_to,
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
        .select_related(
            "user", "user__watch_profile", "user__client_identity",
            "reply_to", "reply_to__user", "reply_to__user__watch_profile",
        )
        .prefetch_related("reactions")
        .order_by("-created_at")[:100]
    )
    messages.reverse()
    return Response(ChatMessageSerializer(messages, many=True, context={"request": request}).data)


@api_view(["POST"])
def room_messages_batch(request, room_id):
    """Persist a short offline/reconnect burst in one ordered transaction.

    The socket remains the real-time path. This endpoint exists only as its
    reliable fallback, so ten quick taps never become ten serial HTTP waits.
    """
    room = get_object_or_404(Room, id=room_id)
    if not RoomMember.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "Вы не участник комнаты"}, status=403)
    if RoomMute.objects.filter(room=room, user=request.user).exists():
        return Response({"detail": "You are muted in this room"}, status=403)
    items = request.data.get("messages")
    if not isinstance(items, list) or not items:
        return Response({"detail": "Messages are required"}, status=400)
    if len(items) > 40:
        return Response({"detail": "Too many messages"}, status=400)

    persisted = []
    created_payloads = []
    with transaction.atomic():
        for item in items:
            if not isinstance(item, dict):
                return Response({"detail": "Invalid message"}, status=400)
            text = str(item.get("text") or "").strip()[:500]
            image_data_url = str(item.get("image_data_url") or "").strip()
            if len(image_data_url) > 2_800_000:
                return Response({"detail": "Image is too large"}, status=413)
            if not text and not image_data_url:
                return Response({"detail": "Message is empty"}, status=400)
            client_message_id = str(item.get("client_message_id") or "").strip()[:64]
            if not client_message_id:
                return Response({"detail": "client_message_id is required"}, status=400)
            reply_to = None
            if item.get("reply_to_id"):
                reply_to = ChatMessage.objects.filter(id=item["reply_to_id"], room=room).first()
                if not reply_to:
                    return Response({"detail": "Reply message not found"}, status=404)
            message, created = ChatMessage.objects.get_or_create(
                room=room, user=request.user, client_message_id=client_message_id,
                defaults={"text": text, "image_data_url": image_data_url, "reply_to": reply_to},
            )
            payload = ChatMessageSerializer(message, context={"request": request}).data
            persisted.append(payload)
            if created:
                created_payloads.append(dict(payload))

    # Fan out only after the transaction commits, preserving burst order for
    # every connected participant.
    channel_layer = get_channel_layer()
    for payload in created_payloads:
        async_to_sync(channel_layer.group_send)(
            f"watch_room_{room.id}", {"type": "room.chat", "payload": payload}
        )
    return Response(persisted, status=status.HTTP_201_CREATED)
