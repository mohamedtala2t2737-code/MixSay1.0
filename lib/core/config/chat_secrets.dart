/// Build-time third-party keys, read with `--dart-define-from-file`.
///
/// The real values live in `chat.secrets.json` at the project root, which is
/// git-ignored; `chat.secrets.example.json` is the committed template. Nothing
/// here is a secret: an absent key simply reports itself as absent, and the
/// feature that needs it stays hidden.
///
/// Because the values are compiled in, every build that should have them must
/// pass the file:
///
/// ```powershell
/// flutter run --dart-define-from-file=chat.secrets.json
/// flutter build apk --release --split-per-abi --dart-define-from-file=chat.secrets.json
/// ```
class ChatSecrets {
  const ChatSecrets._();

  /// Tenor search key. Empty until `chat.secrets.json` provides one.
  static const String tenorApiKey = String.fromEnvironment('TENOR_API_KEY');

  /// GIF search needs both the flag and a key; without either the tab is
  /// simply not there.
  static bool get hasTenorKey => tenorApiKey.isNotEmpty;
}
