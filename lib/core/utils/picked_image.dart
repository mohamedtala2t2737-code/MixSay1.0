import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// A photo chosen by the user, ready for upload.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;
}

/// Returns null when the user cancels the picker.
///
/// Compression falls back to the original file because some devices fail the
/// native compressor on very large photos.
Future<PickedImage?> pickAndCompressImage({
  ImageSource source = ImageSource.gallery,
}) async {
  final file = await ImagePicker().pickImage(source: source);
  if (file == null) return null;
  final bytes =
      await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
        format: CompressFormat.jpeg,
      ) ??
      await file.readAsBytes();
  if (bytes.isEmpty) return null;
  return PickedImage(bytes: bytes, contentType: 'image/jpeg', extension: 'jpg');
}
