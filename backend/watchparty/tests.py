from django.contrib.auth import get_user_model
import base64
from django.test import TransactionTestCase
from asgiref.sync import async_to_sync
from channels.testing import WebsocketCommunicator
from unittest.mock import patch
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from config.asgi import application
from .models import ClientIdentity, PlaybackState, Room, RoomMember


class RoomApiTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.owner = users.objects.create_user(username="owner")
        self.guest = users.objects.create_user(username="guest")
        self.owner_token = Token.objects.create(user=self.owner)
        self.guest_token = Token.objects.create(user=self.guest)

    def authenticate(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_device_identity_and_rename_keep_numeric_user_id(self):
        response = self.client.post(
            "/api/auth/demo-login/",
            {"username": "Луна", "client_id": "device-test-123"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        user_id = response.data["user_id"]
        self.assertTrue(ClientIdentity.objects.filter(client_id="device-test-123", user_id=user_id).exists())

        self.client.credentials(HTTP_AUTHORIZATION=f"Token {response.data['token']}")
        rename = self.client.patch(
            "/api/profile/", {"username": "Новая Луна"}, format="json"
        )
        self.assertEqual(rename.status_code, 200)
        self.assertEqual(rename.data["user_id"], user_id)

        self.client.credentials()
        login_again = self.client.post(
            "/api/auth/demo-login/",
            {"username": "Любое имя", "client_id": "device-test-123"},
            format="json",
        )
        self.assertEqual(login_again.data["user_id"], user_id)
        self.assertEqual(login_again.data["username"], "Любое имя")

    def test_profile_avatar_is_returned_to_chat_and_members(self):
        login = self.client.post(
            "/api/auth/demo-login/",
            {"username": "Аватар", "client_id": "avatar-device"},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")
        avatar = "data:image/png;base64," + base64.b64encode(b"small-image").decode()
        profile = self.client.patch(
            "/api/profile/", {"avatar": avatar}, format="json"
        )
        self.assertEqual(profile.status_code, 200)
        self.assertEqual(profile.data["avatar"], avatar)

        user = get_user_model().objects.get(id=login.data["user_id"])
        room = Room.objects.create(owner=user, title="С аватаром")
        RoomMember.objects.create(room=room, user=user)
        PlaybackState.objects.create(room=room)
        members = self.client.get(f"/api/rooms/{room.id}/members/")
        self.assertEqual(members.data[0]["avatar"], avatar)

    def test_legacy_user_can_be_claimed_by_first_device_id(self):
        legacy = get_user_model().objects.create_user(username="Старый пользователь")
        response = self.client.post(
            "/api/auth/demo-login/",
            {"username": legacy.username, "client_id": "legacy-device"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["user_id"], legacy.id)

    def test_create_room_keeps_one_invite_code(self):
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

    def test_private_video_url_is_rejected(self):
        self.authenticate(self.owner_token)
        response = self.client.post(
            "/api/rooms/",
            {"title": "Комната", "vk_video_url": "http://127.0.0.1/video"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    @patch("watchparty.views.resolve_vk_stream")
    def test_member_can_resolve_managed_stream(self, resolver):
        resolver.return_value = {
            "url": "https://cdn.example/video.mp4",
            "title": "Видео",
            "duration_seconds": 120.0,
            "thumbnail": "",
            "quality": "720p",
        }
        room = Room.objects.create(
            owner=self.owner,
            title="Плеер",
            vk_video_url="https://vkvideo.ru/video-185112119_456245562",
        )
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        self.authenticate(self.owner_token)

        response = self.client.get(f"/api/rooms/{room.id}/stream/?quality=720p")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["url"], "https://cdn.example/video.mp4")
        resolver.assert_called_once_with(
            room.vk_video_url,
            preferred_quality="720p",
        )

    @patch("watchparty.views.resolve_vk_stream")
    def test_stream_error_does_not_expose_extractor_details(self, resolver):
        resolver.side_effect = RuntimeError("Cloudflare secret extractor output")
        room = Room.objects.create(
            owner=self.owner,
            title="Закрытый плеер",
            vk_video_url="https://example.com/protected-video",
        )
        RoomMember.objects.create(room=room, user=self.owner)
        PlaybackState.objects.create(room=room)
        self.authenticate(self.owner_token)

        response = self.client.get(f"/api/rooms/{room.id}/stream/")
        self.assertEqual(response.status_code, 502)
        self.assertIn("не разрешает открыть видео", response.data["detail"])
        self.assertNotIn("Cloudflare", response.data["detail"])


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
        await self.receive_type(owner_socket, "playback_state")
        await self.receive_type(guest_socket, "playback_state")

        await guest_socket.send_json_to(
            {
                "type": "playback_command",
                "action": "seek",
                "position_seconds": 99,
            }
        )
        error = await self.receive_type(guest_socket, "error")
        self.assertEqual(error["code"], "owner_only")

        await owner_socket.send_json_to(
            {
                "type": "playback_command",
                "action": "play",
                "position_seconds": 42.5,
                "is_playing": True,
            }
        )
        owner_state = await self.receive_type(owner_socket, "playback_state")
        guest_state = await self.receive_type(guest_socket, "playback_state")
        self.assertEqual(owner_state["type"], "playback_state")
        self.assertEqual(guest_state["type"], "playback_state")
        self.assertEqual(owner_state["position_seconds"], 42.5)
        self.assertEqual(guest_state["position_seconds"], 42.5)
        self.assertEqual(owner_state["command"], "play")
        self.assertIn("server_sent_at", guest_state)
        self.assertTrue(owner_state["is_owner"])
        self.assertFalse(guest_state["is_owner"])
        self.assertTrue(guest_state["is_playing"])

        await guest_socket.disconnect()
        left = await self.receive_type(owner_socket, "presence")
        self.assertEqual(left["user_id"], self.guest.id)
        self.assertFalse(left["is_online"])
        await owner_socket.disconnect()

    async def receive_type(self, socket, event_type):
        for _ in range(10):
            event = await socket.receive_json_from()
            if event.get("type") == event_type:
                return event
        self.fail(f"WebSocket event {event_type} was not received")
