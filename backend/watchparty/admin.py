from django.contrib import admin

from .models import (
    ChatMessage,
    ClientIdentity,
    MessageReaction,
    PlaybackState,
    Room,
    RoomMember,
    UserProfile,
)


admin.site.register(Room)
admin.site.register(RoomMember)
admin.site.register(PlaybackState)
admin.site.register(ClientIdentity)
admin.site.register(UserProfile)
admin.site.register(ChatMessage)
admin.site.register(MessageReaction)
