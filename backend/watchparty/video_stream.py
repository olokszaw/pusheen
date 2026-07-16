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
        # The Windows VPS has TLS inspection with a private root certificate.
        # yt-dlp otherwise cannot read public VK metadata and the room returns
        # 502. This affects only the server-to-VK metadata request.
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

    # AVPlayer can accept an MP4 container whose audio codec is supported while
    # silently failing to render an AV1/VP9 video track.  That looks exactly
    # like "sound but no picture" on an iPhone.  Prefer the cross-platform
    # H.264 + AAC progressive variants before comparing their resolutions.
    def is_apple_compatible(item):
        video_codec = str(item.get("vcodec") or "").lower()
        audio_codec = str(item.get("acodec") or "").lower()
        h264 = video_codec.startswith(("avc1", "avc3", "h264"))
        aac = not audio_codec or audio_codec.startswith(("mp4a", "aac"))
        return h264 and aac

    compatible = [item for item in progressive if is_apple_compatible(item)]
    codec_candidates = compatible or progressive

    # 1080p is enough for a watch party and avoids accidentally choosing
    # oversized variants when VK exposes higher resolutions.
    suitable = [
        item for item in codec_candidates if (item.get("height") or 0) <= 1080
    ]
    candidates = suitable or codec_candidates
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
