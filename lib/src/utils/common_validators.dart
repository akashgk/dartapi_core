import 'validator.dart';

/// Validates that a string matches a valid email format.
class EmailValidator extends Validators<String> {
  EmailValidator([super.validationErrorMessage = 'Invalid email address']);
  final _emailRegex = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

  @override
  bool validate(dynamic value) => _emailRegex.hasMatch(value as String);

  @override
  Map<String, dynamic> toSchemaProperties() => const {'format': 'email'};
}

/// Validates that a string has at least [min] characters.
class MinLengthValidator extends Validators<String> {
  final int min;
  MinLengthValidator(this.min, [String? message])
    : super(message ?? 'Must be at least $min characters');

  @override
  bool validate(dynamic value) => (value as String).length >= min;

  @override
  Map<String, dynamic> toSchemaProperties() => {'minLength': min};
}

/// Validates that a string has at most [max] characters.
class MaxLengthValidator extends Validators<String> {
  final int max;
  MaxLengthValidator(this.max, [String? message])
    : super(message ?? 'Must be at most $max characters');

  @override
  bool validate(dynamic value) => (value as String).length <= max;

  @override
  Map<String, dynamic> toSchemaProperties() => {'maxLength': max};
}

/// Validates that a string is not blank (empty or whitespace-only).
class NotEmptyValidator extends Validators<String> {
  NotEmptyValidator([super.message = 'Must not be empty']);

  @override
  bool validate(dynamic value) => (value as String).trim().isNotEmpty;

  @override
  Map<String, dynamic> toSchemaProperties() => const {'minLength': 1};
}

/// Validates that a number falls within an optional [min] and [max] range (inclusive).
class RangeValidator<T extends num> extends Validators<T> {
  final T? min;
  final T? max;

  RangeValidator({this.min, this.max, String? message})
    : super(message ?? _buildMessage(min, max));

  static String _buildMessage(num? min, num? max) {
    if (min != null && max != null) return 'Must be between $min and $max';
    if (min != null) return 'Must be at least $min';
    return 'Must be at most $max';
  }

  @override
  bool validate(dynamic value) {
    final n = value as T;
    return (min == null || n >= min!) && (max == null || n <= max!);
  }

  @override
  Map<String, dynamic> toSchemaProperties() => {
    if (min != null) 'minimum': min,
    if (max != null) 'maximum': max,
  };
}

/// Validates that a string matches the given [pattern].
class PatternValidator extends Validators<String> {
  final RegExp pattern;
  PatternValidator(this.pattern, String message) : super(message);

  @override
  bool validate(dynamic value) => pattern.hasMatch(value as String);

  @override
  Map<String, dynamic> toSchemaProperties() => {'pattern': pattern.pattern};
}

/// Validates that a string is a well-formed absolute URL (http or https).
class UrlValidator extends Validators<String> {
  UrlValidator([super.message = 'Invalid URL']);

  @override
  bool validate(dynamic value) {
    try {
      final uri = Uri.parse(value as String);
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, dynamic> toSchemaProperties() => const {'format': 'uri'};
}

/// Validates that a value is one of the allowed [values].
///
/// Also contributes `enum: [...]` to the OpenAPI schema via [toSchemaProperties].
///
/// ```dart
/// Field<String>(validators: [EnumValidator(['draft', 'published', 'archived'])])
/// Field<int>(validators: [EnumValidator([1, 2, 3])])
/// ```
class EnumValidator<T> extends Validators<T> {
  final List<T> values;

  EnumValidator(this.values, [String? message])
    : super(message ?? 'Must be one of: ${values.join(', ')}');

  @override
  bool validate(dynamic value) => values.contains(value);

  @override
  Map<String, dynamic> toSchemaProperties() => {'enum': values};
}
