import '../core/api_exception.dart';
import 'field.dart';

/// A declarative set of typed, validated fields that derives both runtime
/// validation and an OpenAPI JSON Schema from a single declaration.
///
/// Define fields once; get validation and schema for free:
///
/// ```dart
/// class CreateUserDTO {
///   static final fields = FieldSet({
///     'name':  Field<String>(validators: [NotEmptyValidator(), MaxLengthValidator(100)], example: 'Alice'),
///     'email': Field<String>(validators: [EmailValidator()], example: 'alice@example.com'),
///     'age':   Field<int>(required: false, validators: [RangeValidator(min: 0, max: 150)]),
///   });
///
///   static Map<String, dynamic> get schema => fields.toJsonSchema();
///
///   factory CreateUserDTO.fromJson(Map<String, dynamic> json) {
///     fields.validate(json); // throws ValidationException with ALL errors
///     return CreateUserDTO(
///       name: json['name'] as String,
///       email: json['email'] as String,
///       age: json['age'] as int? ?? 0,
///     );
///   }
/// }
/// ```
class FieldSet {
  final Map<String, Field> _fields;

  const FieldSet(this._fields);

  /// Validates [json] against all declared fields.
  ///
  /// Collects every field error before throwing, so the caller receives the
  /// full list of problems in one [ValidationException] rather than stopping
  /// at the first failure.
  ///
  /// Throws [ValidationException] if one or more fields are invalid.
  void validate(Map<String, dynamic> json) {
    final errors = <Map<String, String>>[];

    for (final entry in _fields.entries) {
      final key = entry.key;
      final field = entry.value;

      if (!json.containsKey(key) || json[key] == null) {
        if (field.required) {
          errors.add({
            'field': key,
            'message': 'Missing required field "$key"',
          });
        }
        continue;
      }

      final value = json[key];
      for (final v in field.validators) {
        if (!v.validate(value)) {
          errors.add({'field': key, 'message': v.validationErrorMessage});
          break;
        }
      }
    }

    if (errors.isNotEmpty) throw ValidationException(errors);
  }

  /// Returns an OpenAPI 3.0-compatible JSON Schema for this field set.
  ///
  /// Each [Field]'s type maps to a JSON Schema `type`, and each validator
  /// contributes its own constraints via [Validators.toSchemaProperties].
  /// Optional fields (where [Field.required] is `false`) gain `nullable: true`.
  Map<String, dynamic> toJsonSchema() {
    final properties = <String, dynamic>{};
    final requiredFields = <String>[];

    for (final entry in _fields.entries) {
      final key = entry.key;
      final field = entry.value;

      final prop = <String, dynamic>{'type': field.jsonType};

      if (!field.required) prop['nullable'] = true;

      for (final v in field.validators) {
        prop.addAll(v.toSchemaProperties());
      }

      if (field.example != null) prop['example'] = field.example;
      if (field.description != null) prop['description'] = field.description;

      properties[key] = prop;
      if (field.required) requiredFields.add(key);
    }

    return {
      'type': 'object',
      'properties': properties,
      if (requiredFields.isNotEmpty) 'required': requiredFields,
    };
  }
}
