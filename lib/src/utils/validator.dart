/// An abstract class for validating values of type [T].
///
/// Subclasses must implement the [validate] method to define
/// how the value should be checked. If validation fails, the
/// provided [validationErrorMessage] should explain the reason.
///
/// Used in combination with `verifyKey` to perform runtime validation
/// of request payloads or other dynamic data.
abstract class Validators<T> {
  /// The error message to show if validation fails.
  final String validationErrorMessage;

  /// Creates a validator with a custom error message.
  Validators(this.validationErrorMessage);

  /// Validates the provided [value].
  ///
  /// Returns `true` if the value is valid, otherwise `false`.
  bool validate(dynamic value);

  /// Returns OpenAPI-compatible JSON Schema constraints contributed by this
  /// validator (e.g. `{'minLength': 8}`, `{'format': 'email'}`).
  ///
  /// Used by [FieldSet.toJsonSchema] to derive a schema from validation rules.
  /// Override in subclasses that add schema constraints. Defaults to empty.
  Map<String, dynamic> toSchemaProperties() => const {};
}
