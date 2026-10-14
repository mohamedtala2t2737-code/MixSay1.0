import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

enum PostMediaKind { image, video }

/// Everything the composer needs to know about an attached photo or clip.
///
/// Images are compressed and held in memory; videos keep only the file path so
/// a 40 MB clip is never copied into the Dart heap before upload.
class PickedPostMedia {
  const PickedPostMedia({
    required this.kind,
    required this.name,
    required this.contentType,
    required this.extension,
    required this.sizeBytes,
    this.bytes,
    this.filePath,
  });

  final PostMediaKind kind;
  final String name;
  final String contentType;
  final String extension;
  final int sizeBytes;
  final Uint8List? bytes;
  final String? filePath;

  bool get isVideo => kind == PostMediaKind.video;

  /// Firestore stores this verbatim in `mediaType`, and the card branches on it.
  String get mediaType => isVideo ? 'video' : 'image';
}

enum PostMediaFailure { tooLarge, unsupported }

class PostMediaException implements Exception {
  const PostMediaException(this.reason);

  final PostMediaFailure reason;

  @override
  String toString() => 'PostMediaException(${reason.name})';
}

/// `storage.rules` caps a post object at 50 MiB. Stopping at 48 leaves room for
/// the request overhead instead of a confusing server-side rejection.
const maxPostMediaBytes = 48 * 1024 * 1024;

/// How many photos one carousel may hold — the same ceiling the
/// `mediaUrls.size() <= 10` rule puts on the document.
const maxPostSlides = 10;

const _imageContentTypes = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

const _videoContentTypes = <String, String>{
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
};

/// Returns null when the user cancels. Throws [PostMediaException] when the
/// choice cannot be uploaded, so the sheet can say why instead of failing
/// silently.
Future<PickedPostMedia?> pickPostImage({
  ImageSource source = ImageSource.gallery,
}) async {
  final file = await ImagePicker().pickImage(source: source);
  if (file == null) return null;
  return _imageMedia(file);
}

/// Several photos for one carousel. The picker itself is capped at
/// [maxPostSlides], which is the same ceiling `firestore.rules` puts on
/// `mediaUrls`, and every file goes through the same compress-and-check path as
/// a single photo.
Future<List<PickedPostMedia>> pickPostImages() async {
  final files = await ImagePicker().pickMultiImage(limit: maxPostSlides);
  final slides = <PickedPostMedia>[];
  for (final file in files) {
    slides.add(await _imageMedia(file));
  }
  return slides;
}

Future<PickedPostMedia> _imageMedia(XFile file) async {
  final extension = _extensionOf(file.name, file.path);
  final compressed = await _compress(file);
  // Some devices fail the native compressor on very large photos, so the
  // original bytes are a supported fallback, not a shortcut.
  final bytes = compressed ?? await file.readAsBytes();
  if (bytes.isEmpty) {
    throw const PostMediaException(PostMediaFailure.unsupported);
  }
  if (bytes.lengthInBytes > maxPostMediaBytes) {
    throw const PostMediaException(PostMediaFailure.tooLarge);
  }

  if (compressed == null) {
    final contentType =
        _contentTypeOf(extension, _imageContentTypes) ??
        _fromMimeType(file.mimeType, 'image/');
    if (contentType == null) {
      throw const PostMediaException(PostMediaFailure.unsupported);
    }
    return PickedPostMedia(
      kind: PostMediaKind.image,
      name: file.name,
      contentType: contentType,
      extension: extension,
      sizeBytes: bytes.lengthInBytes,
      bytes: bytes,
    );
  }
  return PickedPostMedia(
    kind: PostMediaKind.image,
    name: file.name,
    contentType: 'image/jpeg',
    extension: 'jpg',
    sizeBytes: bytes.lengthInBytes,
    bytes: bytes,
    filePath: file.path,
  );
}

Future<Uint8List?> _compress(XFile file) async {
  try {
    return await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
      format: CompressFormat.jpeg,
    );
  } catch (error) {
    debugPrint('Photo compression is unavailable, using the original: $error');
    return null;
  }
}

/// Picks a clip. `image_picker` hands back the file the system photo picker
/// chose, so no storage permission is needed on Android 13+.
Future<PickedPostMedia?> pickPostVideo({
  ImageSource source = ImageSource.gallery,
}) async {
  final file = await ImagePicker().pickVideo(source: source);
  if (file == null) return null;

  final extension = _extensionOf(file.name, file.path);
  final contentType =
      _contentTypeOf(extension, _videoContentTypes) ??
      _fromMimeType(file.mimeType, 'video/');
  if (contentType == null) {
    throw const PostMediaException(PostMediaFailure.unsupported);
  }
  final sizeBytes = await file.length();
  if (sizeBytes > maxPostMediaBytes) {
    throw const PostMediaException(PostMediaFailure.tooLarge);
  }
  return PickedPostMedia(
    kind: PostMediaKind.video,
    name: file.name,
    contentType: contentType,
    extension: extension,
    sizeBytes: sizeBytes,
    filePath: file.path,
  );
}

String _extensionOf(String name, String path) {
  for (final candidate in [name, path]) {
    final dot = candidate.lastIndexOf('.');
    if (dot >= 0 && dot < candidate.length - 1) {
      return candidate.substring(dot + 1).toLowerCase();
    }
  }
  return '';
}

String? _contentTypeOf(String extension, Map<String, String> table) =>
    table[extension];

String? _fromMimeType(String? mimeType, String prefix) =>
    mimeType != null && mimeType.toLowerCase().startsWith(prefix)
    ? mimeType.toLowerCase()
    : null;
