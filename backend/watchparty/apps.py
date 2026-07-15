from django.apps import AppConfig
import sys

class WatchpartyConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "watchparty"

    def ready(self):
        # A killed development server cannot run WebSocket disconnect hooks.
        # Reset stale presence counters before accepting new connections.
        if "runserver" not in sys.argv:
            return
        try:
            from .models import RoomMember
            RoomMember.objects.update(active_connections=0)
        except Exception:
            # Database may not exist yet while running initial migrations.
            pass
