import ipaddress
import re
from urllib.parse import urlsplit


SOURCE_VK = "vk"
SOURCE_WEB = "web"

VK_VIDEO_PATTERN = re.compile(
    r"^https://(?:m\.)?(?:vkvideo\.ru|vk\.com)/video-?\d+_\d+(?:\?.*)?$",
    re.IGNORECASE,
)
VK_Z_VIDEO_PATTERN = re.compile(
    r"^https://(?:m\.)?vk\.com/video\?[^#]*\bz=video-?\d+_\d+",
    re.IGNORECASE,
)


def detect_media_source(value):
    """Return the provider pipeline used for a room URL."""
    value = (value or "").strip()
    if VK_VIDEO_PATTERN.match(value) or VK_Z_VIDEO_PATTERN.match(value):
        return SOURCE_VK
    return SOURCE_WEB


def validate_media_url(value):
    """Accept public HTTP(S) media pages and reject local/private targets."""
    value = (value or "").strip()
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Нужна корректная HTTP(S)-ссылка на видео или страницу фильма")

    hostname = parsed.hostname.lower().rstrip(".")
    if hostname == "localhost" or hostname.endswith(".localhost") or hostname.endswith(".local"):
        raise ValueError("Локальные адреса использовать нельзя")

    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise ValueError("Приватные и локальные IP-адреса использовать нельзя")

    if "vkvideo.ru" in hostname and not VK_VIDEO_PATTERN.match(value):
        raise ValueError("Нужна ссылка VK Видео вида https://vkvideo.ru/video-123_456")
    return value
