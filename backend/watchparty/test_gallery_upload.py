"""Gallery upload regressions: proxy URLs, storage failures and validation."""

from pathlib import Path
import tempfile
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import OperationalError
from django.test import override_settings
from rest_framework.test import APITestCase

from .models import PlaybackState, Room, RoomMember


class GalleryUploadTests(APITestCase):
    def setUp(self):
        self.media_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.media_directory.cleanup)
        settings_override = override_settings(MEDIA_ROOT=self.media_directory.name)
        settings_override.enable()
        self.addCleanup(settings_override.disable)
        self.owner = get_user_model().objects.create_user(username="gallery-owner")
        self.guest = get_user_model().objects.create_user(username="gallery-guest")
        self.room = Room.objects.create(owner=self.owner, title="Original video")
        RoomMember.objects.create(room=self.room, user=self.owner)
        RoomMember.objects.create(room=self.room, user=self.guest)
        PlaybackState.objects.create(room=self.room)
        self.client.force_authenticate(user=self.owner)
        self.upload_url = f"/api/rooms/{self.room.pk}/upload/"

    @staticmethod
    def video(name="gallery.mov", content_type="video/quicktime", content=b"gallery-video-bytes"):
        return SimpleUploadedFile(name, content, content_type=content_type)

    def install_previous_video(self):
        self.room.uploaded_video.save("previous.mp4", self.video(content=b"previous-video"))
        return self.room.uploaded_video.name

    def stored_files(self):
        return sorted(
            str(path.relative_to(self.media_directory.name))
            for path in Path(self.media_directory.name).rglob("*") if path.is_file()
        )

    def test_forwarded_https_is_preserved_in_upload_and_stream_urls(self):
        headers = {"HTTP_HOST": "pulse.izanagi.online", "HTTP_X_FORWARDED_PROTO": "https"}
        response = self.client.post(self.upload_url, {"video": self.video()}, format="multipart", **headers)
        self.assertEqual(response.status_code, 201, response.data)
        expected = f"https://pulse.izanagi.online/api/rooms/{self.room.pk}/media/"
        self.assertEqual(response.data["media_url"], expected)
        self.client.force_authenticate(user=self.guest)
        stream = self.client.get(f"/api/rooms/{self.room.pk}/stream/", **headers)
        self.assertEqual(stream.status_code, 200, stream.data)
        self.assertEqual(stream.data["url"], expected)

    @override_settings(MAX_ROOM_VIDEO_UPLOAD_BYTES=123456)
    def test_upload_preflight_reports_configured_limit_without_creating_files(self):
        response = self.client.get(self.upload_url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["max_size_bytes"], 123456)
        self.assertEqual(set(response.data["extensions"]), {"mp4", "mov", "m4v"})
        self.assertEqual(self.stored_files(), [])
        self.client.force_authenticate(user=self.guest)
        self.assertEqual(self.client.get(self.upload_url).status_code, 403)

    def test_database_failure_preserves_previous_video_and_removes_new_file(self):
        previous_name = self.install_previous_video()
        previous_files = self.stored_files()
        self.client.raise_request_exception = False
        with patch.object(Room, "save", side_effect=OperationalError("simulated database failure")):
            response = self.client.post(self.upload_url, {"video": self.video()}, format="multipart")
        self.assertEqual(response.status_code, 500)
        self.room.refresh_from_db()
        self.assertEqual(self.room.uploaded_video.name, previous_name)
        self.assertEqual(self.stored_files(), previous_files)
        with self.room.uploaded_video.open("rb") as saved:
            self.assertEqual(saved.read(), b"previous-video")

    def test_locked_previous_file_does_not_turn_committed_upload_into_failure(self):
        previous_name = self.install_previous_video()
        storage = self.room.uploaded_video.storage
        with patch.object(storage, "delete", side_effect=PermissionError("file open in player")):
            response = self.client.post(self.upload_url, {"video": self.video()}, format="multipart")
        self.assertEqual(response.status_code, 201, response.data)
        self.room.refresh_from_db()
        self.assertNotEqual(self.room.uploaded_video.name, previous_name)
        self.assertTrue(storage.exists(previous_name))
        with self.room.uploaded_video.open("rb") as saved:
            self.assertEqual(saved.read(), b"gallery-video-bytes")

    def test_nonfinite_duration_is_rejected_before_any_file_is_written(self):
        for duration in ("nan", "inf", "-inf"):
            with self.subTest(duration=duration):
                response = self.client.post(
                    self.upload_url,
                    {"video": self.video(), "duration_seconds": duration},
                    format="multipart",
                )
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(self.stored_files(), [])
                self.room.refresh_from_db()
                self.assertFalse(self.room.uploaded_video)

    def test_guest_cannot_upload_or_replace_owner_video(self):
        previous_name = self.install_previous_video()
        previous_files = self.stored_files()
        self.client.force_authenticate(user=self.guest)
        response = self.client.post(self.upload_url, {"video": self.video()}, format="multipart")
        self.assertEqual(response.status_code, 403, response.data)
        self.room.refresh_from_db()
        self.assertEqual(self.room.uploaded_video.name, previous_name)
        self.assertEqual(self.stored_files(), previous_files)

    @override_settings(MAX_ROOM_VIDEO_UPLOAD_BYTES=4)
    def test_oversized_upload_is_rejected_without_storage_change(self):
        response = self.client.post(self.upload_url, {"video": self.video(content=b"12345")}, format="multipart")
        self.assertEqual(response.status_code, 413, response.data)
        self.assertEqual(self.stored_files(), [])

    def test_unsupported_container_or_mime_is_rejected_without_storage_change(self):
        for name, mime in (("movie.avi", "video/x-msvideo"), ("movie.mp4", "text/plain")):
            with self.subTest(name=name, mime=mime):
                response = self.client.post(
                    self.upload_url, {"video": self.video(name=name, content_type=mime)}, format="multipart"
                )
                self.assertEqual(response.status_code, 415, response.data)
                self.assertEqual(self.stored_files(), [])
