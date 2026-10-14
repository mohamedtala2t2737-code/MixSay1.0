import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/picked_media.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/home/presentation/create_post_sheet.dart';

/// A real 1x1 PNG so `Image.memory` can decode the composer preview.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakePicker extends ImagePickerPlatform {
  _FakePicker({this.images = const <XFile>[], this.video});

  final List<XFile> images;
  final XFile? video;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => images.isEmpty ? null : images.first;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => images;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => video;
}

class _CreatedPost {
  const _CreatedPost(this.caption, this.mediaUrls, this.mediaType);

  final String caption;
  final List<String> mediaUrls;
  final String mediaType;
}

/// Stands in for Firebase: it records what the composer tried to store and lets
/// the test hold the upload open to observe progress.
class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository({this.createError});

  final String? createError;
  final Completer<void> uploadGate = Completer<void>();
  final List<PickedPostMedia> uploads = <PickedPostMedia>[];
  final List<int> uploadedSlides = <int>[];
  final List<_CreatedPost> created = <_CreatedPost>[];
  final List<String> deleted = <String>[];

  @override
  String newPostId() => 'post-1';

  @override
  Future<String> uploadPostMedia({
    required String postId,
    required PickedPostMedia media,
    int slide = 0,
    void Function(double fraction)? onProgress,
  }) async {
    uploads.add(media);
    uploadedSlides.add(slide);
    onProgress?.call(0.4);
    await uploadGate.future;
    // Mirrors the real naming: slide 0 keeps the bare post id.
    final name = slide == 0 ? postId : '$postId-$slide';
    return 'https://cdn.test/$name.${media.extension}';
  }

  @override
  Future<void> createPost({
    required String postId,
    required String caption,
    List<String> mediaUrls = const <String>[],
    String mediaType = 'none',
  }) async {
    if (createError != null) throw Exception(createError);
    created.add(_CreatedPost(caption, mediaUrls, mediaType));
  }

  @override
  Future<void> deleteUnpublishedMedia(String url) async => deleted.add(url);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Future<_FakeFeedRepository> _openSheet(
  WidgetTester tester, {
  List<XFile> images = const <XFile>[],
  XFile? video,
  _FakeFeedRepository? repository,
}) async {
  final repo = repository ?? _FakeFeedRepository();
  ImagePickerPlatform.instance = _FakePicker(images: images, video: video);
  final container = ProviderContainer(
    overrides: [
      feedRepositoryProvider.overrideWith((ref) => repo),
      currentUserIdProvider.overrideWithValue('user-me'),
      currentProfileProvider.overrideWith(
        (ref) async => const AppUser(
          id: 'user-me',
          username: 'mixsay.user',
          fullName: 'MixSay User',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCreatePostSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a picked clip uploads as a video and stores mediaType video', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      video: XFile.fromData(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
        mimeType: 'video/mp4',
      ),
    );

    await tester.tap(find.byTooltip('Add video'));
    await tester.pumpAndSettle();
    // The tile shows what the user picked, not a generic "video" label.
    expect(find.textContaining('clip.mp4'), findsOneWidget);

    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.text('Uploading… 40%'), findsOneWidget);
    repo.uploadGate.complete();
    await tester.pumpAndSettle();

    final media = repo.uploads.single;
    expect(media.kind, PostMediaKind.video);
    expect(media.contentType, 'video/mp4');
    expect(media.extension, 'mp4');
    // Clips stream from disk, so the bytes never land in the Dart heap.
    expect(media.bytes, isNull);
    expect(media.filePath, '/tmp/clip.mp4');
    expect(repo.created.single.mediaType, 'video');
    expect(repo.created.single.mediaUrls, <String>[
      'https://cdn.test/post-1.mp4',
    ]);
    expect(find.text('Posted'), findsOneWidget);
  });

  testWidgets('a picked photo uploads as an image post', (tester) async {
    final repo = await _openSheet(
      tester,
      images: <XFile>[
        XFile.fromData(
          _pngBytes,
          name: 'photo.png',
          path: '/tmp/photo.png',
          mimeType: 'image/png',
        ),
      ],
    );

    await tester.tap(find.byTooltip('Add photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);

    await tester.tap(find.text('Post'));
    repo.uploadGate.complete();
    await tester.pumpAndSettle();

    final media = repo.uploads.single;
    expect(media.kind, PostMediaKind.image);
    expect(media.contentType, 'image/png');
    expect(media.extension, 'png');
    expect(media.bytes, isNotNull);
    expect(repo.created.single.mediaType, 'image');
    expect(repo.created.single.mediaUrls, <String>[
      'https://cdn.test/post-1.png',
    ]);
  });

  testWidgets('several photos upload as numbered slides in order', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      images: <XFile>[
        XFile.fromData(_pngBytes, path: '/tmp/one.png', mimeType: 'image/png'),
        XFile.fromData(_pngBytes, path: '/tmp/two.jpg', mimeType: 'image/jpeg'),
        XFile.fromData(
          _pngBytes,
          path: '/tmp/three.webp',
          mimeType: 'image/webp',
        ),
      ],
    );

    await tester.tap(find.byTooltip('Add photo'));
    await tester.pumpAndSettle();
    // The strip shows one thumb per pick, so the order is visible before post.
    expect(find.byType(Image), findsNWidgets(3));

    await tester.tap(find.text('Post'));
    repo.uploadGate.complete();
    await tester.pumpAndSettle();

    // One upload per photo, in the order they were picked.
    expect(repo.uploads.map((media) => media.extension).toList(), <String>[
      'png',
      'jpg',
      'webp',
    ]);
    expect(repo.uploadedSlides, <int>[0, 1, 2]);
    expect(repo.created.single.mediaType, 'image');
    expect(repo.created.single.mediaUrls, <String>[
      'https://cdn.test/post-1.png',
      'https://cdn.test/post-1-1.jpg',
      'https://cdn.test/post-1-2.webp',
    ]);
  });

  testWidgets('a removed slide is never uploaded', (tester) async {
    final repo = await _openSheet(
      tester,
      images: <XFile>[
        XFile.fromData(_pngBytes, path: '/tmp/keep.png', mimeType: 'image/png'),
        XFile.fromData(
          _pngBytes,
          path: '/tmp/drop.jpg',
          mimeType: 'image/jpeg',
        ),
      ],
    );

    await tester.tap(find.byTooltip('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Post'));
    repo.uploadGate.complete();
    await tester.pumpAndSettle();

    expect(repo.uploads.single.extension, 'png');
    expect(repo.created.single.mediaUrls, <String>[
      'https://cdn.test/post-1.png',
    ]);
  });

  testWidgets('clearing the clip lets a caption-only post publish', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      video: XFile.fromData(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
        mimeType: 'video/mp4',
      ),
    );

    await tester.tap(find.byTooltip('Add video'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('clip.mp4'), findsNothing);

    await tester.enterText(find.byType(TextField), 'just words');
    // The sheet only re-enables Post on the frame the typed text triggers.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(repo.uploads, isEmpty);
    expect(repo.created.single.mediaType, 'none');
    expect(repo.created.single.mediaUrls, isEmpty);
  });

  testWidgets('an unsupported pick says so instead of failing silently', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      video: XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3]),
        name: 'notes.txt',
        path: '/tmp/notes.txt',
        mimeType: 'text/plain',
      ),
    );

    await tester.tap(find.byTooltip('Add video'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unsupported type'), findsOneWidget);
    expect(repo.uploads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a media upload that breaks cleans up and names the failure', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      repository: _FakeFeedRepository(
        createError: 'firestore/permission-denied',
      ),
      video: XFile.fromData(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
        mimeType: 'video/mp4',
      ),
    );

    await tester.tap(find.byTooltip('Add video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    repo.uploadGate.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Upload failed'), findsOneWidget);
    // The clip is already in Storage but has no post document, so the composer
    // removes it instead of leaving an orphan file behind.
    expect(repo.deleted, <String>['https://cdn.test/post-1.mp4']);
    expect(repo.created, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
