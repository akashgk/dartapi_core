import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

// Low iteration count keeps the suite fast; production uses
// PasswordHasher.defaultIterations.
const _fast = 1000;

void main() {
  group('PasswordHasher', () {
    test('hash/verify round-trip', () {
      final encoded = PasswordHasher.hash('s3cret', iterations: _fast);
      expect(PasswordHasher.verify('s3cret', encoded), isTrue);
    });

    test('wrong password is rejected', () {
      final encoded = PasswordHasher.hash('s3cret', iterations: _fast);
      expect(PasswordHasher.verify('nope', encoded), isFalse);
    });

    test('same password hashes differently (random salt)', () {
      final a = PasswordHasher.hash('s3cret', iterations: _fast);
      final b = PasswordHasher.hash('s3cret', iterations: _fast);
      expect(a, isNot(equals(b)));
      expect(PasswordHasher.verify('s3cret', a), isTrue);
      expect(PasswordHasher.verify('s3cret', b), isTrue);
    });

    test('encoded format is self-describing', () {
      final encoded = PasswordHasher.hash('pw', iterations: _fast);
      expect(encoded, startsWith('pbkdf2-sha256\$$_fast\$'));
      expect(encoded.split(r'$'), hasLength(4));
    });

    test('verify honours the iteration count stored in the hash', () {
      // A hash created with N iterations verifies even if the default
      // changes — parameters travel with the hash.
      final encoded = PasswordHasher.hash('pw', iterations: 500);
      expect(PasswordHasher.verify('pw', encoded), isTrue);
    });

    test('malformed input returns false instead of throwing', () {
      expect(PasswordHasher.verify('pw', ''), isFalse);
      expect(PasswordHasher.verify('pw', 'not-a-hash'), isFalse);
      expect(PasswordHasher.verify('pw', r'pbkdf2-sha256$abc$x$y'), isFalse);
      expect(PasswordHasher.verify('pw', r'md5$1$AA$AA'), isFalse);
      expect(PasswordHasher.verify('pw', r'pbkdf2-sha256$1000$!!$!!'), isFalse);
    });

    test('unicode passwords round-trip', () {
      final encoded = PasswordHasher.hash('pässwörd🔑', iterations: _fast);
      expect(PasswordHasher.verify('pässwörd🔑', encoded), isTrue);
      expect(PasswordHasher.verify('passwörd🔑', encoded), isFalse);
    });

    test('iterations < 1 throws', () {
      expect(
        () => PasswordHasher.hash('pw', iterations: 0),
        throwsArgumentError,
      );
    });

    test('known-answer test: standard PBKDF2-HMAC-SHA256 vector', () {
      // P="password", S="salt", c=1, dkLen=32 →
      // 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
      const expectedHex =
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b';
      final expectedBytes = [
        for (var i = 0; i < expectedHex.length; i += 2)
          int.parse(expectedHex.substring(i, i + 2), radix: 16),
      ];
      final encoded =
          'pbkdf2-sha256\$1'
          '\$${base64.encode(utf8.encode('salt'))}'
          '\$${base64.encode(expectedBytes)}';
      expect(PasswordHasher.verify('password', encoded), isTrue);
    });
  });
}
