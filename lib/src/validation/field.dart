import '../utils/validator.dart';

/// Describes a single field in a [FieldSet]: its expected Dart type, whether
/// it is required, and any validators that should run against its value.
///
/// The generic parameter [T] determines the JSON Schema `type` emitted by
/// [FieldSet.toJsonSchema]. Supported scalar types: [String], [int], [double],
/// [num], [bool]. List types (e.g. `Field<List<String>>`) produce
/// `type: array` with the correct `items` type.
///
/// ```dart
/// Field<String>(validators: [NotEmptyValidator(), MaxLengthValidator(100)])
/// Field<int>(required: false, validators: [RangeValidator(min: 0, max: 150)])
/// Field<List<String>>(description: 'Tag list')
/// Field<String>(validators: [EnumValidator(['draft', 'published'])])
/// ```
class Field<T> {
  final bool required;
  final List<Validators<T>> validators;
  final dynamic example;
  final String? description;

  /// The JSON Schema `type` string derived from [T] at construction time.
  final String jsonType;

  /// For `type: array` fields, the JSON Schema type of each item element.
  /// `null` for non-array fields.
  final String? arrayItemType;

  Field({
    this.required = true,
    this.validators = const [],
    this.example,
    this.description,
  }) : jsonType = _dartTypeToJsonType<T>(),
       arrayItemType = _extractArrayItemType<T>();
}

String _dartTypeToJsonType<T>() {
  if (T.toString().startsWith('List<')) return 'array';
  return switch (T) {
    const (String) => 'string',
    const (int) => 'integer',
    const (double) => 'number',
    const (num) => 'number',
    const (bool) => 'boolean',
    _ => 'string',
  };
}

String? _extractArrayItemType<T>() {
  final name = T.toString();
  if (!name.startsWith('List<') || !name.endsWith('>')) return null;
  final inner = name.substring(5, name.length - 1);
  return switch (inner) {
    'String' => 'string',
    'int' => 'integer',
    'double' || 'num' => 'number',
    'bool' => 'boolean',
    _ => 'string',
  };
}
