/// Public web addresses the app can share. Empty until a real domain exists,
/// which is what hides "Copy link" rather than copying a broken url.
class AppLinks {
  const AppLinks._();

  static const String postBaseUrl = '';

  static String? postUrl(String postId) =>
      postBaseUrl.isEmpty ? null : '$postBaseUrl/posts/$postId';
}
