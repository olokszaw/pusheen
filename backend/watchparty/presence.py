from django.core.cache import cache
from django.db import IntegrityError, OperationalError
from django.utils import timezone

from .models import UserPresence


def touch_presence(user, minimum_interval=5):
    """Best-effort presence update that must never break the requested API.

    Presence is auxiliary state. Rewriting it on every poll created a write
    storm on SQLite and could turn a perfectly valid profile GET into HTTP 500.
    Throttle repeated writes per process, use a single UPDATE in the common
    path, and tolerate a temporarily unavailable database writer.
    """
    if not user or not user.is_authenticated:
        return False

    cache_key = f"presence-touch:{user.pk}"
    if minimum_interval > 0 and not cache.add(cache_key, True, timeout=minimum_interval):
        return True

    now = timezone.now()
    try:
        updated = UserPresence.objects.filter(user_id=user.pk).update(last_seen=now)
        if not updated:
            try:
                UserPresence.objects.create(user_id=user.pk, last_seen=now)
            except IntegrityError:
                UserPresence.objects.filter(user_id=user.pk).update(last_seen=now)
        return True
    except OperationalError:
        # A presence write is never important enough to fail profile/friends.
        # Clear the throttle so a later request can retry after the lock ends.
        cache.delete(cache_key)
        return False
