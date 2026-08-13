import asyncio
import math
import time
from datetime import timedelta
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.db import transaction
from django.utils import timezone as django_timezone
from .models import ChatMessage, MessageReaction, PlaybackState, Room, RoomBan, RoomMember, RoomMute
from .playback import projected_playback_payload

ROOM_DISCONNECT_GRACE_SECONDS = 5.0


class RoomConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.room_id = int(self.scope["url_route"]["kwargs"]["room_id"])
        self.group_name = f"watch_room_{self.room_id}"
        if (
            not self.scope["user"].is_authenticated
            or await self.is_banned()
            or not await self.is_member()
        ):
            await self.close(code=4403)
            return
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        # A cellular/Wi-Fi drop does not always close TCP immediately. The
        # heartbeat watchdog makes presence change within seconds instead of
        # waiting for an OS-level socket timeout.
        self.last_heartbeat = time.monotonic()
        self.heartbeat_watchdog = asyncio.create_task(self.watch_heartbeat())
        await self.send_json({"type": "playback_state", **await self.current_state()})
        presence = await self.mark_connected()
        await self.channel_layer.group_send(
            self.group_name, {"type": "room.presence", "payload": presence}
        )

    async def disconnect(self, _code):
        if hasattr(self, "heartbeat_watchdog"):
            self.heartbeat_watchdog.cancel()
        if hasattr(self, "room_id") and self.scope["user"].is_authenticated:
            await self.channel_layer.group_send(
                self.group_name,
                {
                    "type": "room.typing",
                    "payload": {
                        "user_id": self.scope["user"].id,
                        "is_typing": False,
                    },
                },
            )
            disconnected_at = await self.mark_disconnected_pending()
            if disconnected_at:
                # A socket can be replaced during a tunnel/VPN/network handoff
                # while the user never leaves the room. Give the replacement
                # connection a short window to arrive before announcing a real
                # leave. The token makes an older timer unable to close a newer
                # connection generation.
                asyncio.create_task(
                    self.finalize_disconnect_after_grace(disconnected_at)
                )
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def finalize_disconnect_after_grace(self, disconnected_at):
        try:
            await asyncio.sleep(ROOM_DISCONNECT_GRACE_SECONDS)
            presence = await self.finalize_disconnected(disconnected_at)
            if presence:
                await self.channel_layer.group_send(
                    self.group_name,
                    {"type": "room.presence", "payload": presence},
                )
        except asyncio.CancelledError:
            return

    async def receive_json(self, content, **_kwargs):
        self.last_heartbeat = time.monotonic()
        event = content.get("type")
        if event == "heartbeat":
            await self.mark_heartbeat()
            await self.send_json({"type": "heartbeat_ack"})
        elif event == "request_state":
            await self.send_json({"type": "playback_state", **await self.current_state()})
        elif event == "playback_command":
            await self.apply_playback_command(content)
        elif event == "playback_snapshot":
            await self.apply_playback_snapshot(content)
        elif event == "chat_message":
            await self.broadcast_chat(
                content.get("text", ""),
                content.get("image_data_url", ""),
                content.get("client_message_id", ""),
                content.get("reply_to_id"),
            )
        elif event == "message_reaction":
            await self.toggle_reaction(content.get("message_id"), content.get("emoji", ""))
        elif event == "typing":
            await self.channel_layer.group_send(
                self.group_name,
                {
                    "type": "room.typing",
                    "payload": {
                        "user_id": self.scope["user"].id,
                        "is_typing": bool(content.get("is_typing")),
                    },
                },
            )

    async def watch_heartbeat(self):
        try:
            while True:
                await asyncio.sleep(5)
                if time.monotonic() - self.last_heartbeat > 26:
                    await self.close(code=4001)
                    return
        except asyncio.CancelledError:
            return

    async def apply_playback_command(self, content):
        # Client input is never trusted: only the creator can change global playback.
        if not await self.is_owner():
            await self.send_json({"type": "error", "code": "owner_only", "detail": "Только создатель управляет просмотром"})
            return
        action = content.get("action")
        if action not in {"play", "pause", "seek", "sync", "change_video"}:
            return
        state, accepted = await self.save_playback(
            action=action,
            is_playing=bool(content.get("is_playing", action == "play")),
            position=max(0.0, float(content.get("position_seconds", 0))),
            video_url=content.get("vk_video_url") if action == "change_video" else None,
            base_sequence=content.get("sequence"),
        )
        if not accepted:
            # Optimistic-concurrency failure: correct only the stale sender.
            # Broadcasting it would make every healthy client process noise.
            await self.send_json({"type": "playback_state", **state, "is_owner": True})
            return
        await self.channel_layer.group_send(self.group_name, {"type": "room.playback", "payload": state})

    async def apply_playback_snapshot(self, content):
        """Persist this member's actual AVPlayer clock without disturbing viewers.

        Play/seek commands are sparse.  Extrapolating one old command forever
        made a public preview drift beyond the real duration and ask AVPlayer
        for a frame that does not exist. Every member reports the clock they are
        truly seeing so their own public profile can mirror it. Only the owner
        may also refresh the shared room timeline, and no snapshot is broadcast
        as another seek command.
        """
        try:
            position = max(0.0, float(content.get("position_seconds", 0)))
            duration = max(0.0, float(content.get("duration_seconds", 0)))
        except (TypeError, ValueError, OverflowError):
            return
        if not math.isfinite(position) or not math.isfinite(duration):
            return
        is_playing = bool(content.get("is_playing"))
        await self.save_member_playback_snapshot(
            is_playing=is_playing,
            position=position,
            duration=duration,
        )
        if not await self.is_owner():
            return
        state = await self.save_playback_snapshot(
            is_playing=is_playing,
            position=position,
            duration=duration,
            base_sequence=content.get("sequence"),
        )
        if state is not None:
            # A stale snapshot gets an authoritative correction, but must not
            # disturb other participants.
            await self.send_json({"type": "playback_state", **state, "is_owner": True})

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

    async def broadcast_chat(self, text, image_data_url, client_message_id="", reply_to_id=None):
        if await self.is_muted():
            await self.send_json({"type": "error", "code": "muted", "detail": "Вы не можете писать в этой комнате"})
            return
        text = text.strip()[:500]
        image_data_url = image_data_url.strip()
        if len(image_data_url) > 2_800_000:
            await self.send_json({"type": "error", "detail": "Изображение слишком большое"})
            return
        if text or image_data_url:
            message, created = await self.save_chat(text, image_data_url, client_message_id, reply_to_id)
            if created:
                await self.channel_layer.group_send(
                    self.group_name,
                    {"type": "room.chat", "payload": message},
                )

    async def room_chat(self, event):
        await self.send_json({"type": "chat_message", **event["payload"]})

    async def toggle_reaction(self, message_id, emoji):
        emoji = emoji.strip()[:32]
        if not emoji or not message_id:
            return
        payload = await self.save_reaction(int(message_id), emoji)
        if payload:
            await self.channel_layer.group_send(
                self.group_name,
                {"type": "room.reaction", "payload": payload},
            )

    async def room_reaction(self, event):
        payload = dict(event["payload"])
        payload["reacted"] = self.scope["user"].id in payload.pop("user_ids")
        await self.send_json({"type": "message_reaction", **payload})

    async def room_typing(self, event):
        # Typing is transient room state. It must never touch the database or
        # block chat delivery; clients also expire it locally as a safety net.
        await self.send_json({"type": "typing", **event["payload"]})

    async def room_presence(self, event):
        await self.send_json({"type": "presence", **event["payload"]})

    async def room_moderation(self, event):
        """Refresh membership in real time and close a removed participant."""
        payload = event["payload"]
        if payload["action"] in {"kick", "ban"} and payload["user_id"] == self.scope["user"].id:
            await self.send_json({"type": "room_removed", "reason": payload["action"]})
            await self.close(code=4403)
            return
        await self.send_json({"type": "members_changed", **payload})

    @database_sync_to_async
    def is_member(self):
        return RoomMember.objects.filter(room_id=self.room_id, user=self.scope["user"]).exists()

    @database_sync_to_async
    def is_banned(self):
        # Keep this independent from membership. A stale/recreated member row
        # must never let a banned authenticated account reopen the socket.
        return RoomBan.objects.filter(room_id=self.room_id, user=self.scope["user"]).exists()

    @database_sync_to_async
    def is_owner(self):
        return Room.objects.filter(id=self.room_id, owner=self.scope["user"]).exists()

    @database_sync_to_async
    def is_muted(self):
        # This is intentionally independent from RoomMember: rejoining creates
        # a new membership row, while a moderation decision must persist for
        # the same authenticated user ID.
        return RoomMute.objects.filter(room_id=self.room_id, user=self.scope["user"]).exists()

    @database_sync_to_async
    def current_state(self):
        room = Room.objects.select_related("playback").get(id=self.room_id)
        payload = projected_playback_payload(room, room.playback)
        payload.update({
            "is_owner": room.owner_id == self.scope["user"].id,
            "is_muted": RoomMute.objects.filter(room=room, user=self.scope["user"]).exists(),
        })
        return payload

    @database_sync_to_async
    def save_playback(self, action, is_playing, position, video_url, base_sequence):
        with transaction.atomic():
            room = Room.objects.select_for_update().get(id=self.room_id)
            state = PlaybackState.objects.select_for_update().get(room=room)
            try:
                incoming_sequence = int(base_sequence) if base_sequence is not None else None
            except (TypeError, ValueError, OverflowError):
                incoming_sequence = -1
            if incoming_sequence is not None and incoming_sequence != state.sequence:
                return projected_playback_payload(room, state, command="stale"), False
            if video_url is not None:
                room.vk_video_url = video_url
                room.save(update_fields=["vk_video_url"])
            state.is_playing = is_playing
            state.position_seconds = position
            state.sequence += 1
            state.save(update_fields=["is_playing", "position_seconds", "sequence", "updated_at"])
            # Commands carry the exact seek/play anchor. Clients compensate
            # transport time from state.updated_at; projecting here as well
            # would add the same elapsed time twice.
            return projected_playback_payload(
                room, state, command=action, project=False
            ), True

    @database_sync_to_async
    def save_member_playback_snapshot(self, is_playing, position, duration):
        if duration > 0:
            position = min(position, duration)
        RoomMember.objects.filter(
            room_id=self.room_id,
            user_id=self.scope["user"].id,
        ).update(
            viewer_is_playing=is_playing,
            viewer_position_seconds=position,
            viewer_duration_seconds=duration,
            viewer_playback_at=django_timezone.now(),
        )

    @database_sync_to_async
    def save_playback_snapshot(self, is_playing, position, duration, base_sequence):
        with transaction.atomic():
            room = Room.objects.select_for_update().get(id=self.room_id)
            state = PlaybackState.objects.select_for_update().get(room=room)
            if room.owner_id != self.scope["user"].id:
                return None
            try:
                incoming_sequence = int(base_sequence) if base_sequence is not None else None
            except (TypeError, ValueError, OverflowError):
                incoming_sequence = -1
            # Legacy clients without sequence remain functional. Sequence-aware
            # clients get strict protection from delayed pre-seek snapshots.
            if incoming_sequence is not None and incoming_sequence != state.sequence:
                return projected_playback_payload(room, state, command="stale")
            if duration > 0:
                position = min(position, duration)
                if abs(float(room.duration_seconds or 0) - duration) > 0.25:
                    room.duration_seconds = duration
                    room.save(update_fields=["duration_seconds"])
            state.is_playing = is_playing
            state.position_seconds = position
            # Snapshot refreshes the anchor inside the current generation; it
            # intentionally does not advance sequence.
            state.save(update_fields=["is_playing", "position_seconds", "updated_at"])
            return None

    @database_sync_to_async
    def save_chat(self, text, image_data_url, client_message_id, reply_to_id):
        client_message_id = str(client_message_id or "").strip()[:64]
        reply_to = None
        if reply_to_id:
            reply_to = ChatMessage.objects.filter(id=reply_to_id, room_id=self.room_id).first()
        if client_message_id:
            message, created = ChatMessage.objects.get_or_create(
                room_id=self.room_id,
                user=self.scope["user"],
                client_message_id=client_message_id,
                defaults={"text": text, "image_data_url": image_data_url, "reply_to": reply_to},
            )
        else:
            message = ChatMessage.objects.create(
                room_id=self.room_id,
                user=self.scope["user"],
                text=text,
                image_data_url=image_data_url,
                reply_to=reply_to,
            )
            created = True
        profile = getattr(self.scope["user"], "watch_profile", None)
        identity = getattr(self.scope["user"], "client_identity", None)
        return {
            "id": message.id,
            "author_id": self.scope["user"].id,
            "author": self.scope["user"].username,
            "nickname": profile.nickname if profile else self.scope["user"].username,
            "avatar_data_url": profile.avatar_data_url if profile and profile.avatar_data_url else getattr(identity, "avatar_data_url", ""),
            "text": text,
            "image_data_url": image_data_url,
            "client_message_id": client_message_id,
            "reactions": [],
            "reply_to": ({
                "id": reply_to.id,
                "author_id": reply_to.user_id,
                "nickname": getattr(getattr(reply_to.user, "watch_profile", None), "nickname", reply_to.user.username),
                "text": reply_to.text,
                "has_image": bool(reply_to.image_data_url),
            } if reply_to else None),
            "created_at": message.created_at.isoformat(),
            # The iPhone anchors this elapsed duration to its own clock.  Do
            # not make chat display depend on the Windows server wall clock.
            "created_at_age_seconds": max(
                0,
                int((django_timezone.now() - message.created_at).total_seconds()),
            ),
        }, created

    @database_sync_to_async
    def save_reaction(self, message_id, emoji):
        try:
            message = ChatMessage.objects.get(id=message_id, room_id=self.room_id)
        except ChatMessage.DoesNotExist:
            return None
        with transaction.atomic():
            existing = MessageReaction.objects.filter(
                message=message,
                user=self.scope["user"],
                emoji=emoji,
            ).first()
            if existing:
                existing.delete()
            else:
                reaction_types = MessageReaction.objects.filter(message=message).values("emoji").distinct().count()
                # Keep a reaction row compact and predictable on every client.
                # A third reaction type is ignored instead of overflowing the
                # message bubble or creating hidden server-side state.
                if reaction_types >= 2:
                    return None
                MessageReaction.objects.create(
                    message=message,
                    user=self.scope["user"],
                    emoji=emoji,
                )
        reactions = list(MessageReaction.objects.filter(message=message, emoji=emoji))
        return {
            "message_id": message.id,
            "emoji": emoji,
            "count": len(reactions),
            "user_ids": [item.user_id for item in reactions],
        }

    @database_sync_to_async
    def mark_connected(self):
        with transaction.atomic():
            member = RoomMember.objects.select_for_update(of=("self",)).select_related("user", "room").get(
                room_id=self.room_id, user=self.scope["user"]
            )
            now = django_timezone.now()
            heartbeat_was_stale = (
                not member.last_heartbeat_at
                or member.last_heartbeat_at < now - timedelta(seconds=24)
            )
            reconnecting_during_grace = bool(
                member.active_connections == 0
                and member.last_heartbeat_at
                and member.last_heartbeat_at
                >= now - timedelta(seconds=ROOM_DISCONNECT_GRACE_SECONDS)
            )
            was_offline = heartbeat_was_stale or (
                member.active_connections == 0 and not reconnecting_during_grace
            )
            if heartbeat_was_stale:
                # A dead process/socket can leave the diagnostic counter stale.
                # TTL is authoritative, so start a fresh generation here.
                member.active_connections = 0
            member.active_connections += 1
            member.last_heartbeat_at = now
            member.save(update_fields=["active_connections", "last_heartbeat_at"])
            profile = getattr(member.user, "watch_profile", None)
            identity = getattr(member.user, "client_identity", None)
            payload = {
                "user_id": member.user_id,
                "username": member.user.username,
                "nickname": profile.nickname if profile else member.user.username,
                "avatar_data_url": profile.avatar_data_url if profile and profile.avatar_data_url else getattr(identity, "avatar_data_url", ""),
                "is_owner": member.room.owner_id == member.user_id,
                "is_online": True,
                "changed": was_offline,
            }
        return payload

    @database_sync_to_async
    def mark_disconnected_pending(self):
        with transaction.atomic():
            try:
                member = RoomMember.objects.select_for_update(of=("self",)).get(
                    room_id=self.room_id, user=self.scope["user"]
                )
            except RoomMember.DoesNotExist:
                return None
            member.active_connections = max(0, member.active_connections - 1)
            disconnected_at = django_timezone.now()
            member.last_heartbeat_at = disconnected_at
            member.save(update_fields=["active_connections", "last_heartbeat_at"])
            return disconnected_at if member.active_connections == 0 else None

    @database_sync_to_async
    def finalize_disconnected(self, disconnected_at):
        with transaction.atomic():
            try:
                member = RoomMember.objects.select_for_update(of=("self",)).select_related("user", "room").get(
                    room_id=self.room_id, user=self.scope["user"]
                )
            except RoomMember.DoesNotExist:
                return None
            # Any reconnect or newer disconnect changes one of these values.
            # In that case this timer belongs to an obsolete socket generation.
            if (
                member.active_connections > 0
                or member.last_heartbeat_at != disconnected_at
            ):
                return None
            member.last_heartbeat_at = django_timezone.now() - timedelta(seconds=25)
            member.save(update_fields=["last_heartbeat_at"])
            profile = getattr(member.user, "watch_profile", None)
            identity = getattr(member.user, "client_identity", None)
            return {
                "user_id": member.user_id,
                "username": member.user.username,
                "nickname": profile.nickname if profile else member.user.username,
                "avatar_data_url": profile.avatar_data_url if profile and profile.avatar_data_url else getattr(identity, "avatar_data_url", ""),
                "is_owner": member.room.owner_id == member.user_id,
                "is_online": False,
                "changed": True,
            }

    @database_sync_to_async
    def mark_heartbeat(self):
        try:
            member = RoomMember.objects.select_related("user", "room").get(
                room_id=self.room_id, user=self.scope["user"]
            )
        except RoomMember.DoesNotExist:
            return None
        was_stale = not member.last_heartbeat_at or member.last_heartbeat_at < django_timezone.now() - timedelta(seconds=24)
        member.last_heartbeat_at = django_timezone.now()
        member.save(update_fields=["last_heartbeat_at"])
        profile = getattr(member.user, "watch_profile", None)
        identity = getattr(member.user, "client_identity", None)
        return {
            "user_id": member.user_id,
            "username": member.user.username,
            "nickname": profile.nickname if profile else member.user.username,
            "avatar_data_url": profile.avatar_data_url if profile and profile.avatar_data_url else getattr(identity, "avatar_data_url", ""),
            "is_owner": member.room.owner_id == member.user_id,
            "is_online": True,
            "changed": was_stale,
        }
