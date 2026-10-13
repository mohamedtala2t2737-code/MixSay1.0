class UsernamePolicy {
  UsernamePolicy._();

  static const minLength = 4;
  static const maxLength = 24;

  static final _pattern = RegExp('^[a-z0-9.]{$minLength,$maxLength}\$');

  static bool isValid(String username) => _pattern.hasMatch(username.trim());

  static String normalize(String username) => username.trim().toLowerCase();
}
