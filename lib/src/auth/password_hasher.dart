import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted password hashing with PBKDF2-HMAC-SHA256.
///
/// ```dart
/// // At registration:
/// final hash = PasswordHasher.hash('s3cret');   // store this string
///
/// // At login:
/// if (!PasswordHasher.verify(dto.password, user.passwordHash)) {
///   throw const ApiException(401, 'Invalid credentials');
/// }
/// ```
///
/// The encoded string is self-describing
/// (`pbkdf2-sha256$<iterations>$<salt>$<hash>`), so [iterations] can be
/// raised later without breaking existing hashes — old hashes verify with
/// their stored parameters, and you can re-hash on successful login.
///
/// Hashing is CPU-bound **by design** (~100–300 ms at the default
/// [defaultIterations]) — that cost is what slows down brute-forcing.
/// On a busy server run it off the request isolate:
/// `await Isolate.run(() => PasswordHasher.verify(password, hash))`.
class PasswordHasher {
  PasswordHasher._();

  /// PBKDF2 iteration count used by [hash]. Tune upward as hardware allows.
  static const int defaultIterations = 100000;

  static const int _saltLength = 16;
  static const int _keyLength = 32;
  static const String _algorithm = 'pbkdf2-sha256';

  static final Random _random = Random.secure();

  /// Hashes [password] with a fresh random salt.
  ///
  /// Returns `pbkdf2-sha256$<iterations>$<base64 salt>$<base64 hash>`.
  static String hash(String password, {int iterations = defaultIterations}) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
    }
    final salt = List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    final derived = _pbkdf2(utf8.encode(password), salt, iterations);
    return '$_algorithm\$$iterations\$${base64.encode(salt)}\$${base64.encode(derived)}';
  }

  /// Returns `true` when [password] matches [encoded] (a string produced by
  /// [hash]). Comparison is constant-time; malformed input returns `false`
  /// instead of throwing.
  static bool verify(String password, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) return false;
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } on FormatException {
      return false;
    }
    final derived = _pbkdf2(
      utf8.encode(password),
      salt,
      iterations,
      keyLength: expected.length,
    );
    return _constantTimeEquals(derived, expected);
  }

  /// RFC 2898 PBKDF2 with HMAC-SHA256 as the PRF.
  static List<int> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations, {
    int keyLength = _keyLength,
  }) {
    final prf = Hmac(sha256, password);
    final blockCount = (keyLength + 31) ~/ 32;
    final output = <int>[];
    for (var block = 1; block <= blockCount; block++) {
      var u =
          prf.convert([
            ...salt,
            (block >> 24) & 0xff,
            (block >> 16) & 0xff,
            (block >> 8) & 0xff,
            block & 0xff,
          ]).bytes;
      final t = List<int>.of(u);
      for (var i = 1; i < iterations; i++) {
        u = prf.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      output.addAll(t);
    }
    return output.sublist(0, keyLength);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
