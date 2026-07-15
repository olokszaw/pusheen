import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_watch_party/watch_party/vk_video.dart';

void main() {
  test('parses a canonical vkvideo.ru URL', () {
    final video = VkVideo.parse(
      'https://vkvideo.ru/video-185112119_456245562',
    );

    expect(video?.ownerId, '-185112119');
    expect(video?.videoId, '456245562');
    expect(
      video?.embedUrl,
      'https://vk.com/video_ext.php?oid=-185112119&id=456245562&hd=2&autoplay=0',
    );
  });

  test('parses canonical and z-style vk.com URLs', () {
    expect(
      VkVideo.parse('https://vk.com/video-185112119_456245562')?.videoId,
      '456245562',
    );
    expect(
      VkVideo.parse(
        'https://vk.com/video?z=video-185112119_456245562%2Fpl_cat_updates',
      )?.ownerId,
      '-185112119',
    );
  });

  test('does not treat an unrelated page as VK Video', () {
    expect(VkVideo.parse('https://example.com/movie/123'), isNull);
  });
}
