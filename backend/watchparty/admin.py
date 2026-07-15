from django.contrib import admin

from .models import ChatMessage, ClientIdentity, PlaybackState, Room, RoomMember


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ("id", "title", "owner", "invite_code", "created_at")
    search_fields = ("title", "owner__username", "invite_code")


@admin.register(RoomMember)
class RoomMemberAdmin(admin.ModelAdmin):
    list_display = ("id", "room", "user", "active_connections", "joined_at")
    list_filter = ("room",)


@admin.register(PlaybackState)
class PlaybackStateAdmin(admin.ModelAdmin):
    list_display = ("room", "is_playing", "position_seconds", "updated_at")


@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
    list_display = ("id", "room", "user", "text", "created_at")
    search_fields = ("text", "user__username", "room__title")


@admin.register(ClientIdentity)
class ClientIdentityAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "client_id", "has_avatar", "created_at")
    readonly_fields = ("client_id",)

    @admin.display(boolean=True, description="Аватар")
    def has_avatar(self, identity):
        return bool(identity.avatar_data_url)
