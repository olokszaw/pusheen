from datetime import datetime, timezone
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.db import transaction
from .models import ChatMessage, ClientIdentity, PlaybackState, Room, RoomMember


class RoomConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.room_id = int(self.scope["url_route"]["kwargs"]["room_id"])
        self.group_name = f"watch_room_{self.room_id}"
        if not self.scope["user"].is_authenticated or not await self.is_member():
            await self.close(code=4403)
            return
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send_json({"type": "playback_state", **await self.current_state()})
        presence = await self.mark_connected()
        await self.channel_layer.group_send(
            self.group_name,
            {"type": "room.presence", "payload": presence},
        )

    async def disconnect(self, _code):
        if hasattr(self, "room_id") and self.scope.get("user") and self.scope["user"].is_authenticated:
            presence = await self.mark_disconnected()
            if presence:
                await self.channel_layer.group_send(
                    self.group_name,
                    {"type": "room.presence", "payload": presence},
                )
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive_json(self, content, **_kwargs):
        event = content.get("type")
        if event == "request_state":
            await self.send_json({"type": "playback_state", **await self.current_state()})
        elif event == "playback_command":
            await self.apply_playback_command(content)
        elif event == "chat_message":
            await self.broadcast_chat(content.get("text", ""))

    async def apply_playback_command(self, content):
        # Client input is never trusted: only the creator can change global playback.
        if not await self.is_owner():
            await self.send_json({"type": "error", "code": "owner_only", "detail": "Только создатель управляет просмотром"})
            return
        action = content.get("action")
        if action not in {"play", "pause", "seek", "sync", "change_video"}:
            return
        state = await self.save_playback(
            action=action,
            is_playing=bool(content.get("is_playing", action == "play")),
            position=max(0.0, float(content.get("position_seconds", 0))),
            video_url=content.get("vk_video_url") if action == "change_video" else None,
        )
        await self.channel_layer.group_send(self.group_name, {"type": "room.playback", "payload": state})

    async def room_playback(self, event):
        # `is_owner` is connection-specific. Never broadcast the creator's
        # value to every participant in the group.
        await self.send_json(
            {
                "type": "playback_state",
                **event["payload"],
                "is_owner": await self.is_owner(),
            }
        )

    async def broadcast_chat(self, text):
        text = text.strip()[:500]
        if text:
            message = await self.save_chat(text)
            await self.channel_layer.group_send(self.group_name, {
                "type": "room.chat",
                "id": message["id"],
                "author": self.scope["user"].username,
                "avatar": message["avatar"],
                "text": text,
            })

    async def room_chat(self, event):
        await self.send_json({
            "type": "chat_message",
            "id": event["id"],
            "author": event["author"],
            "avatar": event.get("avatar", ""),
            "text": event["text"],
        })

    async def room_presence(self, event):
        await self.send_json({"type": "presence", **event["payload"]})

    @database_sync_to_async
    def is_member(self):
        return RoomMember.objects.filter(room_id=self.room_id, user=self.scope["user"]).exists()

    @database_sync_to_async
    def is_owner(self):
        return Room.objects.filter(id=self.room_id, owner=self.scope["user"]).exists()

    @database_sync_to_async
    def current_state(self):
        room = Room.objects.select_related("playback").get(id=self.room_id)
        state = room.playback
        return {"room_id": room.id, "command": "state", "is_owner": room.owner_id == self.scope["user"].id, "is_playing": state.is_playing, "position_seconds": state.position_seconds, "server_updated_at": state.updated_at.isoformat(), "server_sent_at": datetime.now(timezone.utc).isoformat(), "vk_video_url": room.vk_video_url}

    @database_sync_to_async
    def save_playback(self, action, is_playing, position, video_url):
        room = Room.objects.select_related("playback").get(id=self.room_id)
        if video_url is not None:
            room.vk_video_url = video_url
            room.save(update_fields=["vk_video_url"])
        state = room.playback
        state.is_playing = is_playing
        state.position_seconds = position
        state.save(update_fields=["is_playing", "position_seconds", "updated_at"])
        return {"room_id": room.id, "command": action, "is_playing": state.is_playing, "position_seconds": state.position_seconds, "server_updated_at": state.updated_at.isoformat(), "server_sent_at": datetime.now(timezone.utc).isoformat(), "vk_video_url": room.vk_video_url}

    @database_sync_to_async
    def save_chat(self, text):
        message = ChatMessage.objects.create(
            room_id=self.room_id,
            user=self.scope["user"],
            text=text,
        )
        identity = ClientIdentity.objects.filter(user=self.scope["user"]).first()
        return {
            "id": message.id,
            "avatar": identity.avatar_data_url if identity else "",
        }

    @database_sync_to_async
    def mark_connected(self):
        with transaction.atomic():
            member = RoomMember.objects.select_for_update().select_related("user", "user__client_identity", "room").get(
                room_id=self.room_id,
                user=self.scope["user"],
            )
            was_offline = member.active_connections == 0
            member.active_connections += 1
            member.save(update_fields=["active_connections"])
            return {
                "user_id": member.user_id,
                "username": member.user.username,
                "avatar": getattr(member.user, "client_identity", None).avatar_data_url if getattr(member.user, "client_identity", None) else "",
                "is_owner": member.room.owner_id == member.user_id,
                "is_online": True,
                "changed": was_offline,
            }

    @database_sync_to_async
    def mark_disconnected(self):
        with transaction.atomic():
            try:
                member = RoomMember.objects.select_for_update().select_related("user", "user__client_identity", "room").get(
                    room_id=self.room_id,
                    user=self.scope["user"],
                )
            except RoomMember.DoesNotExist:
                return None
            member.active_connections = max(0, member.active_connections - 1)
            member.save(update_fields=["active_connections"])
            return {
                "user_id": member.user_id,
                "username": member.user.username,
                "avatar": getattr(member.user, "client_identity", None).avatar_data_url if getattr(member.user, "client_identity", None) else "",
                "is_owner": member.room.owner_id == member.user_id,
                "is_online": member.active_connections > 0,
                "changed": member.active_connections == 0,
            }
