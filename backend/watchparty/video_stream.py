from yt_dlp import YoutubeDL
from yt_dlp.networking.impersonate import ImpersonateTarget


def resolve_vk_stream(page_url, preferred_quality=None):
    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        # VK may return 403 to generic HTTP clients. yt-dlp delegates these
        # requests to curl-cffi and presents the same TLS/browser fingerprint
        # as Chrome, while all playback authorization still stays on VK.
        "impersonate": ImpersonateTarget(client="chrome"),
        "nocheckcertificate": True,
    }
    with YoutubeDL(options) as downloader:
        info = downloader.extract_info(page_url, download=False)

    progressive = []
    for item in info.get("formats", []):
        if not item.get("url") or item.get("ext") != "mp4":
            continue
        has_audio_and_video = (
            item.get("vcodec") not in (None, "none")
            and item.get("acodec") not in (None, "none")
        )
        if has_audio_and_video or item.get("format_id", "").startswith("url"):
            progressive.append(item)

    if not progressive and info.get("url") and info.get("ext") == "mp4":
        progressive.append(info)
    if not progressive:
        raise ValueError(
            "Страница не предоставила совместимый MP4-поток. "
            "DRM и раздельные аудио/видеопотоки не поддерживаются."
        )

    # 1080p is enough for a watch party and avoids accidentally choosing
    # oversized variants when VK exposes higher resolutions.
    suitable = [item for item in progressive if (item.get("height") or 0) <= 1080]
    candidates = suitable or progressive
    requested_height = None
    if preferred_quality:
        try:
            requested_height = int(str(preferred_quality).lower().removesuffix("p"))
        except ValueError:
            requested_height = None
    if requested_height:
        matching = [
            item for item in candidates
            if (item.get("height") or 0) <= requested_height
        ]
        selected = max(matching or candidates, key=lambda item: item.get("height") or 0)
    else:
        selected = max(candidates, key=lambda item: item.get("height") or 0)
    available_qualities = sorted(
        {
            f"{int(item['height'])}p"
            for item in candidates
            if item.get("height")
        },
        key=lambda label: int(label[:-1]),
        reverse=True,
    )
    selected_quality = (
        f"{int(selected['height'])}p"
        if selected.get("height")
        else selected.get("format_note") or selected.get("format_id") or "MP4"
    )
    return {
        "url": selected["url"],
        "title": info.get("title") or "Видео",
        "duration_seconds": float(info.get("duration") or 0),
        "thumbnail": info.get("thumbnail") or "",
        "quality": selected_quality,
        "available_qualities": available_qualities,
    }
