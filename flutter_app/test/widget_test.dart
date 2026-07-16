import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_watch_party/watch_party/media_source.dart';

void main() {
  group('MediaSourceType', () {
    test('keeps VK and WEB providers isolated', () {
      expect(
        MediaSourceType.detect(
          'https://vkvideo.ru/video-185112119_456245562',
        ),
        MediaSourceType.vk,
      );
      expect(
        MediaSourceType.detect('https://movies.example/watch/42'),
        MediaSourceType.web,
      );
    });

    test('uses API source type when it is present', () {
      expect(
        MediaSourceType.fromApi(
          'web',
          fallbackUrl: 'https://vkvideo.ru/video-1_2',
        ),
        MediaSourceType.web,
      );
    });
  });
}
