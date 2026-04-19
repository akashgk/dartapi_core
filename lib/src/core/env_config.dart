import 'dart:io';

/// Base class for typed, environment-variable-backed configuration.
///
/// Extend this class and define getters using [env], [envInt], [envDouble],
/// and [envBool]. Required variables (no default) throw [MissingEnvException]
/// at startup if absent.
///
/// Pass a custom [environment] map in tests to avoid touching real env vars.
///
/// ```dart
/// class AppConfig extends EnvConfig {
///   AppConfig({super.environment});
///
///   String get dbHost    => env('DB_HOST', defaultValue: 'localhost');
///   int    get dbPort    => envInt('DB_PORT', defaultValue: 5432);
///   String get jwtSecret => env('JWT_SECRET');   // required — throws if missing
///   bool   get debug     => envBool('DEBUG', defaultValue: false);
/// }
///
/// // Production:
/// final config = AppConfig();
///
/// // Test:
/// final config = AppConfig(environment: {'DB_HOST': 'test-db', 'JWT_SECRET': 'x'});
/// ```
abstract class EnvConfig {
  final Map<String, String> _env;

  /// Creates a config that reads from [environment] (defaults to `Platform.environment`).
  EnvConfig({Map<String, String>? environment})
      : _env = environment ?? Platform.environment;

  /// Returns the value of [key] as a [String].
  ///
  /// Returns [defaultValue] when absent, or throws [MissingEnvException] if no default.
  String env(String key, {String? defaultValue}) {
    final value = _env[key];
    if (value != null) return value;
    if (defaultValue != null) return defaultValue;
    throw MissingEnvException(key);
  }

  /// Returns the value of [key] as an [int].
  ///
  /// Throws [InvalidEnvException] if the value cannot be parsed as an integer.
  int envInt(String key, {int? defaultValue}) {
    final raw = _env[key];
    if (raw == null) {
      if (defaultValue != null) return defaultValue;
      throw MissingEnvException(key);
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) throw InvalidEnvException(key, raw, 'integer');
    return parsed;
  }

  /// Returns the value of [key] as a [double].
  ///
  /// Throws [InvalidEnvException] if the value cannot be parsed as a number.
  double envDouble(String key, {double? defaultValue}) {
    final raw = _env[key];
    if (raw == null) {
      if (defaultValue != null) return defaultValue;
      throw MissingEnvException(key);
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) throw InvalidEnvException(key, raw, 'number');
    return parsed;
  }

  /// Returns the value of [key] as a [bool].
  ///
  /// `'true'` (case-insensitive) → `true`; anything else → `false`.
  bool envBool(String key, {bool defaultValue = false}) {
    final raw = _env[key];
    if (raw == null) return defaultValue;
    return raw.toLowerCase() == 'true';
  }
}

/// Thrown when a required environment variable is missing.
class MissingEnvException implements Exception {
  final String key;
  const MissingEnvException(this.key);

  @override
  String toString() => 'Missing required environment variable: $key';
}

/// Thrown when an environment variable cannot be parsed to the expected type.
class InvalidEnvException implements Exception {
  final String key;
  final String value;
  final String expectedType;
  const InvalidEnvException(this.key, this.value, this.expectedType);

  @override
  String toString() =>
      'Environment variable $key has invalid value "$value" — expected $expectedType';
}
