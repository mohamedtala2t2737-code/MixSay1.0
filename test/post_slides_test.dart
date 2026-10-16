import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/utils/picked_media.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';

FeedPost _post({String? mediaUrl, List<String> mediaUrls = const []}) =>
    FeedPost(
      id: 'post-1',
      authorId: 'author-1',
      username: 'layla.hassan',
      fullName: 'Layla Hassan',
      caption: 'caption',
      likesCount: 0,
      commentsCount: 0,
      createdAt: null,
      artworkVariant: 0,
      isLiked: false,
      mediaUrl: mediaUrl,
      mediaUrls: mediaUrls,
      mediaType: mediaUrls.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)
          ? 'none'
          : 'image',
    );

void main() {
  group('slides', () {
    test('a post written before carousels reads as one slide', () {
      expect(_post(mediaUrl: 'https://cdn/a.jpg').slides, <String>[
        'https://cdn/a.jpg',
      ]);
    });

    test('a carousel uses its own list, not the mirrored first url', () {
      final post = _post(
        mediaUrl: 'https://cdn/a.jpg',
        mediaUrls: <String>['https://cdn/a.jpg', 'https://cdn/b.jpg'],
      );
      expect(post.slides, <String>['https://cdn/a.jpg', 'https://cdn/b.jpg']);
    });

    test('a text-only post has nothing to paint', () {
      expect(_post().slides, isEmpty);
      expect(_post(mediaUrl: '').slides, isEmpty);
    });
  });

  group('validatedSlides', () {
    test('accepts the whole allowed photo range', () {
      final urls = List<String>.generate(
        maxPostSlides,
        (index) => 'https://cdn/$index.jpg',
      );
      expect(FeedRepository.validatedSlides(urls, 'image'), urls);
      expect(
        FeedRepository.validatedSlides(const ['https://cdn/a.jpg'], 'image'),
        <String>['https://cdn/a.jpg'],
      );
    });

    test('drops blank urls so the rules never see an empty string', () {
      expect(
        FeedRepository.validatedSlides(const [
          ' https://cdn/a.jpg ',
          '',
          '   ',
        ], 'image'),
        <String>['https://cdn/a.jpg'],
      );
    });

    test('refuses more photos than the document rule allows', () {
      final urls = List<String>.generate(
        maxPostSlides + 1,
        (index) => 'https://cdn/$index.jpg',
      );
      expect(
        () => FeedRepository.validatedSlides(urls, 'image'),
        throwsArgumentError,
      );
    });

    test('a carousel cannot be empty once it is typed as images', () {
      expect(
        () => FeedRepository.validatedSlides(const <String>[], 'image'),
        throwsArgumentError,
      );
    });

    test('one clip only, never a clip plus photos', () {
      expect(
        FeedRepository.validatedSlides(const ['https://cdn/a.mp4'], 'video'),
        <String>['https://cdn/a.mp4'],
      );
      expect(
        () => FeedRepository.validatedSlides(const [
          'https://cdn/a.mp4',
          'https://cdn/b.jpg',
        ], 'video'),
        throwsArgumentError,
      );
      expect(
        () => FeedRepository.validatedSlides(const <String>[], 'video'),
        throwsArgumentError,
      );
    });

    test('a post without media cannot smuggle urls in', () {
      expect(FeedRepository.validatedSlides(const <String>[], 'none'), isEmpty);
      expect(
        () =>
            FeedRepository.validatedSlides(const ['https://cdn/a.jpg'], 'none'),
        throwsArgumentError,
      );
    });

    test('an unknown media type is rejected instead of written', () {
      expect(
        () =>
            FeedRepository.validatedSlides(const ['https://cdn/a.jpg'], 'gif'),
        throwsArgumentError,
      );
    });
  });
}
