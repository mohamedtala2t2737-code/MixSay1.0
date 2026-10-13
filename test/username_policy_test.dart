import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/features/auth/domain/username_policy.dart';

void main() {
  group('UsernamePolicy', () {
    test('accepts lowercase letters, digits, and periods', () {
      expect(UsernamePolicy.isValid('alex.123'), isTrue);
      expect(UsernamePolicy.isValid('mixsay24'), isTrue);
      expect(UsernamePolicy.isValid('a.1x'), isTrue);
    });

    test('trims surrounding whitespace and enforces length limits', () {
      expect(UsernamePolicy.isValid('  alex  '), isTrue);
      expect(UsernamePolicy.isValid('abc'), isFalse);
      expect(UsernamePolicy.isValid('a' * 25), isFalse);
      expect(UsernamePolicy.isValid('a' * 24), isTrue);
    });

    test('rejects characters outside the Firestore username rule', () {
      expect(UsernamePolicy.isValid('has space'), isFalse);
      expect(UsernamePolicy.isValid('name-tag'), isFalse);
      expect(UsernamePolicy.isValid('mix_say'), isFalse);
      expect(UsernamePolicy.isValid('Alex123'), isFalse);
      expect(UsernamePolicy.isValid('عربي'), isFalse);
    });

    test('normalizes case after trimming', () {
      expect(UsernamePolicy.normalize('  Alex.123 '), 'alex.123');
    });
  });
}
