import 'validator.dart';

class EmailValidator extends Validators<String> {
  EmailValidator(super.validationErrorMessage);

  final _emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');

  @override
  bool validate(dynamic value) {
    return _emailRegex.hasMatch(value);
  }
}
