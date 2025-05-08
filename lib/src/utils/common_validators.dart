import 'validator.dart';

/// A validator that checks whether a given string is a valid email address.
///
/// Uses a simple regular expression to check the format of the email.
/// This validator can be used to validate user input in DTOs or forms.
class EmailValidator extends Validators<String> {
  /// Creates an [EmailValidator] with an optional custom error message.
  EmailValidator(super.validationErrorMessage);

  /// A regular expression that matches basic email address formats.
  final _emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');

  @override
  bool validate(dynamic value) {
    return _emailRegex.hasMatch(value);
  }
}
