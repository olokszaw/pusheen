from django.urls import path
from .views import RoomDetailView, RoomListCreateView, account_login, demo_login, friends, join_room, profile, register, room_members, room_messages, room_stream, username_available

urlpatterns = [
    path("auth/demo-login/", demo_login),
    path("auth/register/", register),
    path("auth/login/", account_login),
    path("auth/username-available/", username_available),
    path("profile/", profile),
    path("friends/", friends),
    path("rooms/", RoomListCreateView.as_view()),
    path("rooms/join/", join_room),
    path("rooms/<int:room_id>/members/", room_members),
    path("rooms/<int:room_id>/stream/", room_stream),
    path("rooms/<int:room_id>/messages/", room_messages),
    path("rooms/<int:pk>/", RoomDetailView.as_view()),
]
