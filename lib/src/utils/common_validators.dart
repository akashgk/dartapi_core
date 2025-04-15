import 'validator.dart';

class EmailValidator extends Validators<String> {
  EmailValidator() : super('Invalid email format');

  @override
  bool validate(
    dynamic value, {
    List<Validators<String>> validators = const [],
  }) {
    if (value is! String || !value.contains('@')) {
      return false;
    }

    for (var validator in validators) {
      if (!validator.validate(value)) {
        return false;
      }
    }

    return true;
  }
}
