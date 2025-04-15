import 'package:dartapi_core/dartapi_core.dart';

extension MapExtensions on Map<String, dynamic> {
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
