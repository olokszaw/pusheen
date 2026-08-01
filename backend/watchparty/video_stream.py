from yt_dlp import YoutubeDL

from .media_sources import SOURCE_VK, SOURCE_WEB
from .genres import detect_genres


TRAILER_WORDS = ("trailer", "teaser", "preview", "трейлер", "тизер")


def _extract(page_url, *, format_selector=None, inspect_playlist=False):
    options = {
        "quiet": True,
        "no_warnings": True,
        # A generic page may expose a short trailer first and the actual movie
        # as another public entry. Web resolution opts in to inspect that list.
        "noplaylist": not inspect_playlist,
        "skip_download": True,
        "extract_flat": False,
        "socket_timeout": 20,
    }
    if format_selector:
        options["format"] = format_selector
    if inspect_playlist:
        # Enough entries to cover the usual trailer/full-feature pair while
        # keeping arbitrary giant collections bounded.
        options["playlistend"] = 20
    with YoutubeDL(options) as downloader:
        info = downloader.extract_info(page_url, download=False)
    if info.get("entries"):
        entries = [entry for entry in info["entries"] if entry]

        # A web page can expose a trailer alongside the full public video.
        # Prefer a non-trailer, longer entry. This never fabricates a source or
        # attempts to defeat DRM, sign-in walls, subscriptions or geo blocks.
        def entry_score(entry):
            text = " ".join(
                str(entry.get(key) or "") for key in ("title", "description")
            ).lower()
            trailer_penalty = 1 if any(word in text for word in TRAILER_WORDS) else 0
            return (-trailer_penalty, float(entry.get("duration") or 0), int(entry.get("view_count") or 0))

        info = max(entries, key=entry_score, default=info)
    return info


def _safe_headers(info, selected):
    headers = {}
    for source in (info.get("http_headers") or {}, selected.get("http_headers") or {}):
        for key, value in source.items():
            if key.lower() in {"user-agent", "referer", "origin", "cookie"} and value:
                headers[str(key)] = str(value)
    return headers


def _genres(info):
    return detect_genres(info.get("title"), info.get("description"), *(info.get("categories") or []), *(info.get("tags") or []))


def resolve_vk_stream(page_url):
    info = _extract(page_url)

    progressive = [
        item
        for item in info.get("formats", [])
        if item.get("format_id", "").startswith("url")
        and item.get("url")
        and item.get("ext") == "mp4"
    ]
    if not progressive:
        raise ValueError("VK не вернул совместимый MP4-поток")

    selected = max(progressive, key=lambda item: ((item.get("height") or 0), (item.get("tbr") or 0)))
    return {
        "url": selected["url"],
        "title": info.get("title") or "VK Видео",
        "duration_seconds": float(info.get("duration") or 0),
        "thumbnail": info.get("thumbnail") or "",
        "quality": selected.get("format_note") or selected.get("format_id") or "MP4",
        "headers": _safe_headers(info, selected),
        "source_type": SOURCE_VK,
        "genres": _genres(info),
    }


def resolve_web_stream(page_url):
    """Extract the main public video without rendering the surrounding site."""
    info = _extract(
        page_url,
        # AVPlayer requires a combined audio+video stream. Do not cap quality:
        # for YouTube and public sites choose the highest compatible stream.
        format_selector="best[vcodec!=none][acodec!=none]",
        inspect_playlist=True,
    )
    formats = [
        item
        for item in info.get("formats", [])
        if item.get("url")
        and item.get("vcodec") not in {None, "none"}
        and item.get("acodec") not in {None, "none"}
        and (
            str(item.get("protocol", "")).startswith("http")
            or "m3u8" in str(item.get("protocol", ""))
        )
    ]
    if info.get("url") and not formats:
        formats = [info]
    if not formats:
        raise ValueError("сайт не отдал совместимый прямой видеопоток")

    def score(item):
        protocol = str(item.get("protocol", ""))
        is_progressive_mp4 = item.get("ext") == "mp4" and protocol.startswith("http")
        height = int(item.get("height") or 0)
        return (1 if is_progressive_mp4 else 0, height, int(item.get("tbr") or 0))

    selected = max(formats, key=score)
    return {
        "url": selected["url"],
        "title": info.get("title") or "Видео с сайта",
        "duration_seconds": float(info.get("duration") or 0),
        "thumbnail": info.get("thumbnail") or "",
        "quality": selected.get("format_note") or selected.get("format_id") or "WEB",
        "headers": _safe_headers(info, selected),
        "source_type": SOURCE_WEB,
        "genres": _genres(info),
    }


def resolve_media_stream(page_url, source_type):
    if source_type == SOURCE_VK:
        return resolve_vk_stream(page_url)
    return resolve_web_stream(page_url)
