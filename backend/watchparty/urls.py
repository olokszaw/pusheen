from django.urls import path
from .views import RoomDetailView, RoomListCreateView, demo_login, join_room, profile, room_members, room_messages, room_stream

urlpatterns = [
    path("auth/demo-login/", demo_login),
    path("profile/", profile),
    path("rooms/", RoomListCreateView.as_view()),
    path("rooms/join/", join_room),
    path("rooms/<int:room_id>/members/", room_members),
    path("rooms/<int:room_id>/stream/", room_stream),
    path("rooms/<int:room_id>/messages/", room_messages),
    path("rooms/<int:pk>/", RoomDetailView.as_view()),
]
