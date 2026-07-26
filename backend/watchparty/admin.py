from django.contrib import admin

from .models import (
    ChatMessage,
    ClientIdentity,
    FriendLink,
    FriendRequest,
    MessageReaction,
    PlaybackState,
    Room,
    RoomMember,
    UserProfile,
    ViewingActivity,
)


admin.site.register(Room)
admin.site.register(RoomMember)
admin.site.register(PlaybackState)
admin.site.register(ClientIdentity)
admin.site.register(UserProfile)
admin.site.register(FriendLink)
admin.site.register(FriendRequest)
admin.site.register(ChatMessage)
admin.site.register(MessageReaction)
admin.site.register(ViewingActivity)
