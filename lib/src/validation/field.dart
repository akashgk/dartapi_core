import '../utils/validator.dart';

/// Describes a single field in a [FieldSet]: its expected Dart type, whether
/// it is required, and any validators that should run against its value.
///
/// The generic parameter [T] determines the JSON Schema `type` emitted by
/// [FieldSet.toJsonSchema]. Supported types: [String], [int], [double], [num],
/// [bool].
///
/// ```dart
/// Field<String>(validators: [NotEmptyValidator(), MaxLengthValidator(100)])
/// Field<int>(required: false, validators: [RangeValidator(min: 0, max: 150)])
/// ```
class Field<T> {
  final bool required;
  final List<Validators<T>> validators;
  final dynamic example;
  final String? description;

  /// The JSON Schema type string derived from [T] at construction time.
  final String jsonType;

  Field({
    this.required = true,
    this.validators = const [],
    this.example,
    this.description,
  }) : jsonType = _dartTypeToJsonType<T>();
}

String _dartTypeToJsonType<T>() => switch (T) {
  const (String) => 'string',
  const (int) => 'integer',
  const (double) => 'number',
  const (num) => 'number',
  const (bool) => 'boolean',
  _ => 'string',
};
