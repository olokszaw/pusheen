from datetime import date, datetime, timedelta, timezone as datetime_timezone
import gzip
import json

from django.contrib.auth import get_user_model
from django.db import OperationalError
from django.test import TransactionTestCase
from django.utils import timezone
from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator
from unittest.mock import patch
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from config.asgi import application
from .models import ChatMessage, FriendLink, FriendRequest, MessageReaction, PlaybackState, Room, RoomBan, RoomInvitation, RoomMember, RoomMute, UserPresence, UserProfile, ViewingActivity
from .views import _normalize_telegram_sticker_data
from .presence import touch_presence


class RoomApiTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.owner = users.objects.create_user(username="owner")
        self.guest = users.objects.create_user(username="guest")
        self.owner_token = Token.objects.create(user=self.owner)
        self.guest_token = Token.objects.create(user=self.guest)

    def authenticate(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_animated_telegram_sticker_is_normalized_to_lottie_json(self):
        source = {"v": "5.7.4", "fr": 30, "ip": 0, "op": 60, "layers": []}
        compressed = gzip.compress(json.dumps(source).encode("utf-8"))
        payload, extension = _normalize_telegram_sticker_data(
            {"is_animated": True}, compressed, ".tgs"
        )
        self.assertEqual(extension, ".json")
        self.assertEqual(json.loads(payload), source)

    def test_locked_presence_write_never_breaks_api_request(self):
        with patch("watchparty.presence.cache.add", return_value=True), patch(
            "watchparty.presence.UserPresence.objects.filter"
        ) as filtered:
            filtered.return_value.update.side_effect = OperationalError("database is locked")
            self.assertFalse(touch_presence(self.owner))

    def test_message_post_is_persisted_and_visible_to_another_member(self):
        room = Room.objects.create(owner=self.owner, title="Durable chat")
        RoomMember.objects.create(room=room, user=self.owner)
        RoomMember.objects.create(room=room, user=self.guest)
        self.authenticate(self.owner_token)
        posted = self.client.post(
            f"/api/rooms/{room.id}/messages/", {"text": "Visible message"}, format="json"
        )
        self.assertEqual(posted.status_code, 201, posted.data)
        self.authenticate(self.guest_token)
        history = self.client.get(f"/api/rooms/{room.id}/messages/")
        self.assertEqual(history.status_code, 200)
        self.assertEqual([item["text"] for item in history.data], ["Visible message"])

    def test_retrying_client_message_id_does_not_duplicate_chat(self):
        room = Room.objects.create(owner=self.owner, title="Retry chat")
        RoomMember.objects.create(room=room, user=self.owner)
        self.authenticate(self.owner_token)
        payload = {"text": "Retry once", "client_message_id": "offline-retry-1"}
        first = self.client.post(f"/api/rooms/{room.id}/messages/", payload, format="json")
        retry = self.client.post(f"/api/rooms/{room.id}/messages/", payload, format="json")
        self.assertEqual(first.status_code, 201)
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(first.data["id"], retry.data["id"])
        self.assertEqual(ChatMessage.objects.filter(room=room).count(), 1)

    def test_batch_fallback_persists_a_spam_burst_in_client_order(self):
        room = Room.objects.create(owner=self.owner, title="Burst chat")
        RoomMember.objects.create(room=room, user=self.owner)
        self.authenticate(self.owner_token)
        burst = [
            {"text": "a", "client_message_id": f"burst-{index}"}
            for index in range(12)
        ]
        response = self.client.post(
            f"/api/rooms/{room.id}/messages/batch/", {"messages": burst}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual([item["text"] for item in response.data], [item["text"] for item in burst])
        self.assertEqual(
            [item["client_message_id"] for item in response.data],
            [item["client_message_id"] for item in burst],
        )
        self.assertEqual(
            list(ChatMessage.objects.filter(room=room).order_by("id").values_list("text", flat=True)),
            [item["text"] for item in burst],
        )
        # Retrying the entire network burst remains idempotent.
        retry = self.client.post(
            f"/api/rooms/{room.id}/messages/batch/", {"messages": burst}, format="json"
        )
        self.assertEqual(retry.status_code, 201, retry.data)
        self.assertEqual(ChatMessage.objects.filter(room=room).count(), len(burst))

    def test_reply_is_persisted_and_visible_to_every_member(self):
        room = Room.objects.create(owner=self.owner, title="Reply chat")
        RoomMember.objects.create(room=room, user=self.owner)
        RoomMember.objects.create(room=room, user=self.guest)
        original = ChatMessage.objects.create(room=room, user=self.guest, text="original")
        self.authenticate(self.owner_token)
        posted = self.client.post(
            f"/api/rooms/{room.id}/messages/",
            {"text": "answer", "reply_to_id": original.id}, format="json",
        )
        self.assertEqual(posted.status_code, 201, posted.data)
        self.assertEqual(posted.data["reply_to"]["id"], original.id)
        self.authenticate(self.guest_token)
        history = self.client.get(f"/api/rooms/{room.id}/messages/")
        self.assertEqual(history.data[-1]["reply_to"]["text"], "original")

    def test_reply_cannot_reference_another_room(self):
        room = Room.objects.create(owner=self.owner, title="Current")
        other = Room.objects.create(owner=self.owner, title="Other")
        RoomMember.objects.create(room=room, user=self.owner)
        foreign = ChatMessage.objects.create(room=other, user=self.owner, text="private")
        self.authenticate(self.owner_token)
        response = self.client.post(
            f"/api/rooms/{room.id}/messages/",
            {"text": "bad", "reply_to_id": foreign.id}, format="json",
        )
        self.assertEqual(response.status_code, 404)

    def test_room_presence_expires_even_if_connection_counter_is_stale(self):
        room = Room.objects.create(owner=self.owner, title="Presence")
        member = RoomMember.objects.create(
            room=room, user=self.owner, active_connections=9,
            last_heartbeat_at=timezone.now() - timedelta(seconds=25),
        )
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/rooms/{room.id}/members/")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data[0]["is_online"])

    def test_message_history_is_ordered_by_server_timestamp(self):
        room = Room.objects.create(owner=self.owner, title="Ordered chat")
        RoomMember.objects.create(room=room, user=self.owner)
        older = ChatMessage.objects.create(room=room, user=self.owner, text="21:06")
        newer = ChatMessage.objects.create(room=room, user=self.owner, text="21:08")
        base = datetime(2026, 8, 2, 21, 6, tzinfo=datetime_timezone.utc)
        ChatMessage.objects.filter(pk=older.pk).update(created_at=base)
        ChatMessage.objects.filter(pk=newer.pk).update(created_at=base + timedelta(minutes=2))
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/rooms/{room.id}/messages/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual([item["text"] for item in response.data], ["21:06", "21:08"])

    @patch("watchparty.views.timezone.localdate", return_value=date(2026, 8, 2))
    def test_activity_persists_server_calculated_month_increase(self, _localdate):
        ViewingActivity.objects.create(
            user=self.owner,
            daily_seconds={"2026-07-01": 100, "2026-08-01": 150},
        )
        self.authenticate(self.owner_token)
        response = self.client.get("/api/activity/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["month_increase_percent"], 50)
        activity = ViewingActivity.objects.get(user=self.owner)
        self.assertEqual(activity.month_increase_percent, 50)

    @patch("watchparty.views.timezone.localdate", return_value=date(2026, 8, 2))
    def test_activity_streak_is_server_calculated_as_seven_days(self, _localdate):
        activity_days = {
            f"2026-07-{day:02d}": 60 for day in range(27, 32)
        }
        activity_days.update({"2026-08-01": 60, "2026-08-02": 60})
        ViewingActivity.objects.create(user=self.owner, daily_seconds=activity_days)
        self.authenticate(self.owner_token)
        response = self.client.get("/api/activity/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["current_streak_days"], 7)

    @patch("watchparty.views.timezone.localdate", return_value=date(2026, 8, 2))
    def test_watched_heartbeat_does_not_double_calendar_activity(self, _localdate):
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/activity/",
            {"app_seconds": 30, "watched_seconds": 30},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["daily_seconds"]["2026-08-02"], 30)

    def test_moderation_returns_realtime_system_event_and_muted_state(self):
        UserProfile.objects.create(user=self.owner, nickname="Создатель")
        UserProfile.objects.create(user=self.guest, nickname="Гость")
        room = Room.objects.create(owner=self.owner, title="Модерация")
        RoomMember.objects.create(room=room, user=self.owner)
        member = RoomMember.objects.create(room=room, user=self.guest)
        self.authenticate(self.owner_token)

        muted = self.client.post(
            f"/api/rooms/{room.id}/members/{self.guest.id}/moderate/",
            {"action": "mute"},
            format="json",
        )
        self.assertEqual(muted.status_code, 200)
        self.assertTrue(muted.data["muted"])
        self.assertEqual(muted.data["system_text"], "Создатель заглушил(а) Гость")
        member.refresh_from_db()
        self.assertTrue(member.is_muted)
        self.assertTrue(RoomMute.objects.filter(room=room, user=self.guest).exists())

        unmuted = self.client.post(
            f"/api/rooms/{room.id}/members/{self.guest.id}/moderate/",
            {"action": "mute"},
            format="json",
        )
        self.assertEqual(unmuted.status_code, 200)
        self.assertFalse(unmuted.data["muted"])
        self.assertFalse(RoomMute.objects.filter(room=room, user=self.guest).exists())
        self.assertEqual(
            unmuted.data["system_text"],
            "Создатель разрешил(а) писать Гость",
        )

    def test_muting_is_bound_to_user_id_and_survives_rejoining_room(self):
        room = Room.objects.create(owner=self.owner, title="Persistent mute")
        RoomMember.objects.create(room=room, user=self.owner)
        RoomMember.objects.create(room=room, user=self.guest)
        self.authenticate(self.owner_token)
        muted = self.client.post(
            f"/api/rooms/{room.id}/members/{self.guest.id}/moderate/",
            {"action": "mute"},
            format="json",
        )
        self.assertEqual(muted.status_code, 200)
        self.assertTrue(RoomMute.objects.filter(room=room, user_id=self.guest.id).exists())

        # Simulates a row being recreated after the client leaves/rejoins. A
        # new `RoomMember` must inherit the durable mute for the same account.
        RoomMember.objects.filter(room=room, user=self.guest).delete()
        self.authenticate(self.guest_token)
        joined = self.client.post(
            "/api/rooms/join/", {"invite_code": room.invite_code}, format="json"
        )
        self.assertEqual(joined.status_code, 200)
        recreated = RoomMember.objects.get(room=room, user=self.guest)
        self.assertTrue(recreated.is_muted)
        members = self.client.get(f"/api/rooms/{room.id}/members/")
        current = next(item for item in members.data if item["user_id"] == self.guest.id)
        self.assertTrue(current["is_muted"])

    def test_removed_member_is_banned_from_rejoining_with_the_same_account(self):
        room = Room.objects.create(owner=self.owner, title="No re-entry")
        RoomMember.objects.create(room=room, user=self.owner)
        RoomMember.objects.create(room=room, user=self.guest)
        self.authenticate(self.owner_token)

        removed = self.client.post(
            f"/api/rooms/{room.id}/members/{self.guest.id}/moderate/",
            {"action": "kick"},
            format="json",
        )
        self.assertEqual(removed.status_code, 200)
        self.assertTrue(RoomBan.objects.filter(room=room, user=self.guest).exists())
        self.assertFalse(RoomMember.objects.filter(room=room, user=self.guest).exists())

        self.authenticate(self.guest_token)
        retry = self.client.post(
            "/api/rooms/join/", {"invite_code": room.invite_code}, format="json"
        )
        self.assertEqual(retry.status_code, 403)
        self.assertFalse(RoomMember.objects.filter(room=room, user=self.guest).exists())

    def test_registration_separates_unique_username_and_repeatable_nickname(self):
        first = self.client.post(
            "/api/auth/register/",
            {"nickname": "Луна", "username": "moon_one", "password": "secret12"},
            format="json",
        )
        second = self.client.post(
            "/api/auth/register/",
            {"nickname": "Луна", "username": "moon_two", "password": "secret12"},
            format="json",
        )
        duplicate = self.client.post(
            "/api/auth/register/",
            {"nickname": "Другая", "username": "moon_one", "password": "secret12"},
            format="json",
        )
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 201)
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(UserProfile.objects.filter(nickname="Луна").count(), 2)

    def test_username_must_start_with_english_letter(self):
        invalid_usernames = ["1mpala", "_impala", "импала", "a-b"]
        for username in invalid_usernames:
            response = self.client.post(
                "/api/auth/register/",
                {
                    "nickname": "Impala",
                    "username": username,
                    "password": "secret12",
                },
                format="json",
            )
            self.assertEqual(response.status_code, 400, username)

        response = self.client.post(
            "/api/auth/register/",
            {
                "nickname": "Impala",
                "username": "imp4la_one",
                "password": "secret12",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)

    def test_authenticated_user_can_change_unique_username(self):
        self.authenticate(self.owner_token)
        own_name = self.client.get(
            "/api/auth/username-available/?username=owner"
        )
        changed = self.client.patch(
            "/api/profile/", {"username": "owner_new"}, format="json"
        )
        duplicate = self.client.patch(
            "/api/profile/", {"username": "guest"}, format="json"
        )
        invalid = self.client.patch(
            "/api/profile/", {"username": "1owner"}, format="json"
        )
        self.assertTrue(own_name.data["available"])
        self.assertEqual(changed.status_code, 200)
        self.assertEqual(changed.data["username"], "owner_new")
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(invalid.status_code, 400)

    def test_user_can_find_request_and_confirm_friend_by_username(self):
        UserProfile.objects.create(user=self.owner, nickname="Создатель")
        UserProfile.objects.create(user=self.guest, nickname="Гость")
        self.authenticate(self.owner_token)
        search = self.client.get("/api/friends/?username=gue")
        added = self.client.post(
            "/api/friends/", {"username": "guest"}, format="json"
        )
        friends = self.client.get("/api/friends/")
        self.assertEqual(search.status_code, 200)
        self.assertEqual(search.data[0]["username"], "guest")
        self.assertFalse(search.data[0]["is_friend"])
        self.assertEqual(added.status_code, 201)
        self.assertFalse(added.data["is_friend"])
        self.assertEqual(added.data["status"], "pending")
        self.assertEqual(friends.data, [])

        self.authenticate(self.guest_token)
        requests = self.client.get("/api/friends/requests/")
        accepted = self.client.post(
            "/api/friends/requests/",
            {"request_id": requests.data["incoming"][0]["id"], "action": "accept"},
            format="json",
        )
        self.assertEqual(accepted.status_code, 200)

        self.authenticate(self.owner_token)
        confirmed = self.client.get("/api/friends/")
        self.assertEqual(confirmed.data[0]["username"], "guest")
        self.assertTrue(confirmed.data[0]["is_friend"])

    def test_sender_can_cancel_outgoing_friend_request(self):
        invite = FriendRequest.objects.create(sender=self.owner, recipient=self.guest)
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/friends/requests/",
            {"request_id": invite.id, "action": "cancel"}, format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(FriendRequest.objects.filter(pk=invite.id).exists())
        self.authenticate(self.guest_token)
        self.assertEqual(self.client.get("/api/friends/requests/").data["incoming"], [])

    def test_public_profile_hides_analytics_from_non_friend(self):
        UserProfile.objects.create(user=self.guest, nickname="Guest profile")
        ViewingActivity.objects.create(user=self.guest, watched_seconds=7200, genre_counts={"Drama": 7200})
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "guest")
        self.assertFalse(response.data["analytics_visible"])
        self.assertIsNone(response.data["stats"])

    def test_confirmed_friend_can_see_aggregate_profile_analytics(self):
        UserProfile.objects.create(user=self.guest, nickname="Guest profile")
        ViewingActivity.objects.create(user=self.guest, watched_seconds=7200, genre_counts={"Drama": 7200})
        FriendLink.objects.create(user=self.owner, friend=self.guest)
        FriendLink.objects.create(user=self.guest, friend=self.owner)
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["is_friend"])
        self.assertTrue(response.data["analytics_visible"])
        self.assertEqual(response.data["stats"]["watched_seconds"], 7200)
        self.assertEqual(response.data["stats"]["genres"][0]["name"], "Drama")

    def test_legacy_one_way_friend_link_can_see_aggregate_profile_analytics(self):
        UserProfile.objects.create(user=self.guest, nickname="Guest profile")
        ViewingActivity.objects.create(user=self.guest, watched_seconds=7200, genre_counts={"Drama": 7200})
        # Databases created by an older app version may contain only this row.
        FriendLink.objects.create(user=self.guest, friend=self.owner)
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["is_friend"])
        self.assertTrue(response.data["analytics_visible"])
        self.assertEqual(response.data["stats"]["genres"][0]["name"], "Drama")

    def test_presence_is_real_and_privacy_aware(self):
        UserProfile.objects.create(user=self.guest, nickname="Guest profile")
        FriendLink.objects.create(user=self.owner, friend=self.guest)
        self.authenticate(self.guest_token)
        heartbeat = self.client.get("/api/friends/requests/")
        self.assertEqual(heartbeat.status_code, 200)
        self.authenticate(self.owner_token)
        visible = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertTrue(visible.data["activity_visible"])
        self.assertTrue(visible.data["is_online"])
        presence = UserPresence.objects.get(user=self.guest)
        presence.show_activity = False
        presence.save(update_fields=["show_activity"])
        hidden = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertFalse(hidden.data["activity_visible"])
        self.assertFalse(hidden.data["is_online"])
        self.assertIsNone(hidden.data["last_seen"])

    def test_room_invitation_full_flow_and_duplicate_protection(self):
        room = Room.objects.create(owner=self.owner, title="Invite room", thumbnail_url="https://example.com/cover.jpg")
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        FriendLink.objects.create(user=self.owner, friend=self.guest)
        FriendLink.objects.create(user=self.guest, friend=self.owner)
        self.authenticate(self.owner_token)
        first = self.client.post(f"/api/rooms/{room.id}/invites/", {"user_ids": [self.guest.id]}, format="json")
        second = self.client.post(f"/api/rooms/{room.id}/invites/", {"user_ids": [self.guest.id]}, format="json")
        self.assertEqual(first.status_code, 201)
        self.assertEqual(first.data["results"][0]["state"], "sent")
        self.assertEqual(second.data["results"][0]["state"], "pending")
        self.assertEqual(RoomInvitation.objects.filter(room=room, recipient=self.guest).count(), 1)
        invitation_id = first.data["results"][0]["invitation_id"]
        self.authenticate(self.guest_token)
        incoming = self.client.get("/api/room-invitations/")
        self.assertEqual(incoming.status_code, 200)
        self.assertEqual(incoming.data[0]["room"]["title"], "Invite room")
        accepted = self.client.post(f"/api/room-invitations/{invitation_id}/", {"action": "accept"}, format="json")
        self.assertEqual(accepted.status_code, 200, accepted.data)
        self.assertEqual(accepted.data["room"]["id"], room.id)
        self.assertTrue(RoomMember.objects.filter(room=room, user=self.guest).exists())
        self.assertEqual(self.client.get("/api/room-invitations/").data, [])

    def test_public_profile_tolerates_legacy_malformed_activity_json(self):
        UserProfile.objects.create(user=self.guest, nickname="Guest profile")
        ViewingActivity.objects.create(user=self.guest, genre_counts=["old"], daily_seconds=["old"])
        FriendLink.objects.create(user=self.owner, friend=self.guest)
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/users/{self.guest.id}/profile/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["analytics_visible"])
        self.assertEqual(response.data["stats"]["genres"], [])
        self.assertEqual(response.data["stats"]["daily_seconds"], {})

    def test_message_history_contains_photo_profile_and_reactions(self):
        profile = UserProfile.objects.create(user=self.owner, nickname="Создатель")
        profile.avatar_data_url = "data:image/png;base64,AA=="
        profile.save()
        room = Room.objects.create(owner=self.owner, title="Чат")
        RoomMember.objects.create(room=room, user=self.owner)
        message = ChatMessage.objects.create(
            room=room,
            user=self.owner,
            image_data_url="data:image/png;base64,AA==",
        )
        MessageReaction.objects.create(message=message, user=self.owner, emoji="🔥")
        self.authenticate(self.owner_token)
        response = self.client.get(f"/api/rooms/{room.id}/messages/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data[0]["nickname"], "Создатель")
        self.assertTrue(response.data[0]["image_data_url"])
        self.assertEqual(response.data[0]["reactions"][0]["count"], 1)
        self.assertTrue(response.data[0]["reactions"][0]["reacted"])

    @patch("watchparty.views.resolve_media_stream")
    def test_create_room_keeps_one_invite_code(self, resolver):
        resolver.return_value = {
            "title": "Название из VK",
            "thumbnail": "https://cdn.example/cover.jpg",
        }
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/rooms/",
            {
                "title": "Кино вечером",
                "description": "Тестовая комната",
                "theme": "movie",
                "vk_video_url": "https://vkvideo.ru/video-185112119_456245562",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        room = Room.objects.get(pk=response.data["id"])
        self.assertEqual(response.data["invite_code"], room.invite_code)
        self.assertEqual(response.data["title"], "Название из VK")
        self.assertEqual(response.data["thumbnail_url"], "https://cdn.example/cover.jpg")
        self.assertTrue(RoomMember.objects.filter(room=room, user=self.owner).exists())
        self.assertTrue(PlaybackState.objects.filter(room=room).exists())

        list_response = self.client.get("/api/rooms/")
        self.assertEqual(list_response.status_code, 200)
        self.assertEqual(list_response.data[0]["invite_code"], room.invite_code)

    def test_guest_joins_existing_room_without_new_code(self):
        room = Room.objects.create(owner=self.owner, title="Общая комната")
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        original_code = room.invite_code

        self.authenticate(self.guest_token)
        response = self.client.post(
            "/api/rooms/join/", {"invite_code": original_code}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["invite_code"], original_code)
        self.assertTrue(RoomMember.objects.filter(room=room, user=self.guest).exists())
        room.refresh_from_db()
        self.assertEqual(room.invite_code, original_code)

        members_response = self.client.get(f"/api/rooms/{room.id}/members/")
        self.assertEqual(members_response.status_code, 200)
        self.assertEqual(len(members_response.data), 2)
        roles = {item["username"]: item["is_owner"] for item in members_response.data}
        self.assertTrue(roles["owner"])
        self.assertFalse(roles["guest"])

    def test_guest_cannot_edit_room(self):
        room = Room.objects.create(owner=self.owner, title="Комната владельца")
        RoomMember.objects.create(room=room, user=self.guest)
        PlaybackState.objects.create(room=room)

        self.authenticate(self.guest_token)
        response = self.client.patch(
            f"/api/rooms/{room.id}/", {"title": "Взлом"}, format="json"
        )
        self.assertEqual(response.status_code, 403)
        room.refresh_from_db()
        self.assertEqual(room.title, "Комната владельца")

    def test_private_media_url_is_rejected(self):
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/rooms/",
            {"title": "Комната", "media_url": "http://127.0.0.1/video"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    @patch("watchparty.views.resolve_media_stream")
    def test_web_media_url_uses_separate_source(self, resolver):
        resolver.return_value = {"title": "Фильм 42", "thumbnail": ""}
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/rooms/",
            {
                "title": "Фильм с сайта",
                "media_url": "https://movies.example/watch/42",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["source_type"], "web")
        self.assertEqual(response.data["media_url"], "https://movies.example/watch/42")

    @patch("watchparty.views.resolve_media_stream")
    def test_member_can_resolve_managed_stream(self, resolver):
        resolver.return_value = {
            "url": "https://cdn.example/video.mp4",
            "title": "Видео",
            "duration_seconds": 120.0,
            "thumbnail": "",
            "quality": "720p",
            "headers": {},
            "source_type": "vk",
        }
        room = Room.objects.create(
            owner=self.owner,
            title="Плеер",
            vk_video_url="https://vkvideo.ru/video-185112119_456245562",
        )
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        self.authenticate(self.owner_token)

        response = self.client.get(f"/api/rooms/{room.id}/stream/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["url"], "https://cdn.example/video.mp4")
        resolver.assert_called_once_with(room.vk_video_url, "vk")

    @patch("watchparty.views.resolve_media_stream")
    def test_web_room_dispatches_to_web_resolver(self, resolver):
        resolver.return_value = {
            "url": "https://cdn.example/movie.m3u8",
            "title": "Фильм",
            "duration_seconds": 3600.0,
            "thumbnail": "",
            "quality": "WEB",
            "headers": {"Referer": "https://movies.example/"},
            "source_type": "web",
        }
        room = Room.objects.create(
            owner=self.owner,
            title="WEB",
            vk_video_url="https://movies.example/watch/42",
        )
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        self.authenticate(self.owner_token)

        response = self.client.get(f"/api/rooms/{room.id}/stream/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["source_type"], "web")
        resolver.assert_called_once_with(room.vk_video_url, "web")


class RoomSocketTests(TransactionTestCase):
    reset_sequences = True

    def setUp(self):
        users = get_user_model()
        self.owner = users.objects.create_user(username="socket-owner")
        self.guest = users.objects.create_user(username="socket-guest")
        self.owner_token = Token.objects.create(user=self.owner)
        self.guest_token = Token.objects.create(user=self.guest)
        self.room = Room.objects.create(owner=self.owner, title="Синхронизация")
        RoomMember.objects.create(room=self.room, user=self.owner)
        RoomMember.objects.create(room=self.room, user=self.guest)
        PlaybackState.objects.create(room=self.room)

    def test_only_owner_can_change_shared_timeline(self):
        async_to_sync(self._assert_owner_control)()

    def test_guest_recovers_history_and_live_chat_after_reconnect(self):
        async_to_sync(self._assert_chat_recovery)()

    def test_guest_receives_every_identical_message_from_rapid_socket_burst(self):
        async_to_sync(self._assert_identical_chat_burst)()

    async def _assert_identical_chat_burst(self):
        owner_socket = WebsocketCommunicator(
            application, f"/ws/rooms/{self.room.id}/?token={self.owner_token.key}"
        )
        guest_socket = WebsocketCommunicator(
            application, f"/ws/rooms/{self.room.id}/?token={self.guest_token.key}"
        )
        self.assertTrue((await owner_socket.connect())[0])
        self.assertTrue((await guest_socket.connect())[0])
        await self._next_event(owner_socket, "playback_state")
        await self._next_event(guest_socket, "playback_state")

        expected_client_ids = [f"socket-burst-{index}" for index in range(12)]
        for client_id in expected_client_ids:
            await owner_socket.send_json_to(
                {"type": "chat_message", "text": "a", "client_message_id": client_id}
            )

        received = [await self._next_event(guest_socket, "chat_message") for _ in expected_client_ids]
        self.assertEqual([item["text"] for item in received], ["a"] * 12)
        self.assertEqual([item["client_message_id"] for item in received], expected_client_ids)
        self.assertEqual(len({item["id"] for item in received}), 12)
        self.assertEqual(await self._room_message_texts(), ["a"] * 12)

        await owner_socket.disconnect()
        await guest_socket.disconnect()

    async def _assert_chat_recovery(self):
        owner_socket = WebsocketCommunicator(
            application, f"/ws/rooms/{self.room.id}/?token={self.owner_token.key}"
        )
        guest_socket = WebsocketCommunicator(
            application, f"/ws/rooms/{self.room.id}/?token={self.guest_token.key}"
        )
        self.assertTrue((await owner_socket.connect())[0])
        self.assertTrue((await guest_socket.connect())[0])
        await self._next_event(owner_socket, "playback_state")
        await self._next_event(guest_socket, "playback_state")

        # The guest loses internet and is not present when this is sent.
        await guest_socket.disconnect()
        retry_id = "socket-offline-retry"
        await owner_socket.send_json_to({"type": "chat_message", "text": "while-offline", "client_message_id": retry_id})
        owner_message = await self._next_event(owner_socket, "chat_message")
        self.assertEqual(owner_message["text"], "while-offline")
        # The same interaction may be sent through both the socket and HTTP.
        # Retrying its id must not create another row or another broadcast.
        await owner_socket.send_json_to({"type": "chat_message", "text": "while-offline", "client_message_id": retry_id})
        self.assertTrue(await owner_socket.receive_nothing(timeout=0.1))
        self.assertEqual(await self._room_message_texts(), ["while-offline"])

        # After reconnect, the client loads this persisted history, then
        # receives subsequent messages through its fresh WebSocket.
        recovered_guest = WebsocketCommunicator(
            application, f"/ws/rooms/{self.room.id}/?token={self.guest_token.key}"
        )
        self.assertTrue((await recovered_guest.connect())[0])
        await self._next_event(recovered_guest, "playback_state")
        self.assertEqual(await self._room_message_texts(), ["while-offline"])

        await owner_socket.send_json_to({"type": "chat_message", "text": "after-reconnect"})
        guest_message = await self._next_event(recovered_guest, "chat_message")
        self.assertEqual(guest_message["text"], "after-reconnect")
        await owner_socket.disconnect()
        await recovered_guest.disconnect()

    @database_sync_to_async
    def _room_message_texts(self):
        return list(ChatMessage.objects.filter(room=self.room).values_list("text", flat=True))

    async def _assert_owner_control(self):
        owner_socket = WebsocketCommunicator(
            application,
            f"/ws/rooms/{self.room.id}/?token={self.owner_token.key}",
        )
        guest_socket = WebsocketCommunicator(
            application,
            f"/ws/rooms/{self.room.id}/?token={self.guest_token.key}",
        )
        self.assertTrue((await owner_socket.connect())[0])
        self.assertTrue((await guest_socket.connect())[0])
        await self._next_event(owner_socket, "playback_state")
        await self._next_event(guest_socket, "playback_state")

        await guest_socket.send_json_to(
            {
                "type": "playback_command",
                "action": "seek",
                "position_seconds": 99,
            }
        )
        error = await self._next_event(guest_socket, "error")
        self.assertEqual(error["code"], "owner_only")

        await owner_socket.send_json_to(
            {
                "type": "playback_command",
                "action": "play",
                "position_seconds": 42.5,
                "is_playing": True,
            }
        )
        owner_state = await self._next_event(owner_socket, "playback_state")
        guest_state = await self._next_event(guest_socket, "playback_state")
        self.assertEqual(owner_state["type"], "playback_state")
        self.assertEqual(guest_state["type"], "playback_state")
        self.assertEqual(owner_state["position_seconds"], 42.5)
        self.assertEqual(guest_state["position_seconds"], 42.5)
        self.assertEqual(owner_state["command"], "play")
        self.assertIn("server_sent_at", guest_state)
        self.assertTrue(owner_state["is_owner"])
        self.assertFalse(guest_state["is_owner"])
        self.assertTrue(guest_state["is_playing"])

        await owner_socket.disconnect()
        await guest_socket.disconnect()

    async def _next_event(self, socket, event_type):
        for _ in range(8):
            event = await socket.receive_json_from()
            if event.get("type") == event_type:
                return event
        self.fail(f"Did not receive {event_type}")
