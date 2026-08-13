import math

from django.utils import timezone

from .media_sources import detect_media_source


def projected_playback_payload(room, state, *, now=None, command="state", project=True):
    """Return the authoritative room clock projected to one server instant.

    `position_seconds` is an anchor at `PlaybackState.updated_at`.  Projecting
    on the server makes reconnect/rejoin deterministic and avoids briefly
    constructing a client player at 00:00.
    """
    now = now or timezone.now()
    position = max(0.0, float(state.position_seconds or 0))
    if project and state.is_playing:
        position += max(0.0, (now - state.updated_at).total_seconds())
    duration = max(0.0, float(room.duration_seconds or 0))
    if duration > 0:
        position = min(position, duration)
    if not math.isfinite(position):
        position = 0.0
    sent_timestamp = now.isoformat()
    anchor_timestamp = (now if project else state.updated_at).isoformat()
    return {
        "room_id": room.id,
        "command": command,
        "is_playing": bool(state.is_playing),
        "position_seconds": position,
        "sequence": int(state.sequence),
        # The returned position is already projected to `now`, therefore both
        # timestamps intentionally describe that same authoritative instant.
        "server_updated_at": anchor_timestamp,
        "server_sent_at": sent_timestamp,
        "vk_video_url": room.vk_video_url,
        "source_type": "upload" if room.uploaded_video else detect_media_source(room.vk_video_url),
    }
