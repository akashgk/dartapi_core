import 'package:dartapi_core/dartapi_core.dart';

/// Extension methods on `Map<String, dynamic>` to support typed and validated key extraction.
extension MapExtensions on Map<String, dynamic> {
  /// Verifies that a key exists, is of the correct type, and passes all provided validators.
  ///
  /// Throws an [Exception] if:
  /// - The key is missing
  /// - The value is not of the expected type `T`
  /// - Any validator fails
  ///
  /// Example usage:
  /// ```dart
  /// final name = json.verifyKey<String>('name');
  /// final age = json.verifyKey<int>('age', validators: [MinValidator(18)]);
  /// ```
  ///
  /// - [key]: The key to look up in the map.
  /// - [validators]: A list of [Validators] to apply to the extracted value.
  T verifyKey<T>(String key, {List<Validators<T>> validators = const []}) {
    if (!containsKey(key)) {
      throw Exception('Missing key "$key"');
    }

    final value = this[key];

    if (value is! T) {
      throw Exception('Invalid type for key "$key"');
    }

    for (final validator in validators) {
      if (!validator.validate(value)) {
        throw Exception(validator.validationErrorMessage);
      }
    }

    return value;
  }
}
