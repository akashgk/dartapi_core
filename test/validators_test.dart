import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

void main() {
  group('MinLengthValidator', () {
    test('passes when length >= min', () {
      expect(MinLengthValidator(3).validate('abc'), isTrue);
      expect(MinLengthValidator(3).validate('abcd'), isTrue);
    });

    test('fails when length < min', () {
      expect(MinLengthValidator(3).validate('ab'), isFalse);
    });

    test('uses default message', () {
      expect(
        MinLengthValidator(5).validationErrorMessage,
        equals('Must be at least 5 characters'),
      );
    });

    test('accepts custom message', () {
      expect(
        MinLengthValidator(5, 'Too short').validationErrorMessage,
        equals('Too short'),
      );
    });
  });

  group('MaxLengthValidator', () {
    test('passes when length <= max', () {
      expect(MaxLengthValidator(5).validate('abc'), isTrue);
      expect(MaxLengthValidator(5).validate('abcde'), isTrue);
    });

    test('fails when length > max', () {
      expect(MaxLengthValidator(5).validate('abcdef'), isFalse);
    });
  });

  group('NotEmptyValidator', () {
    test('passes for non-blank string', () {
      expect(NotEmptyValidator().validate('hi'), isTrue);
    });

    test('fails for empty string', () {
      expect(NotEmptyValidator().validate(''), isFalse);
    });

    test('fails for whitespace-only string', () {
      expect(NotEmptyValidator().validate('   '), isFalse);
    });
  });

  group('RangeValidator', () {
    test('passes when within range', () {
      expect(RangeValidator(min: 1, max: 10).validate(5), isTrue);
    });

    test('passes at boundary values', () {
      expect(RangeValidator(min: 1, max: 10).validate(1), isTrue);
      expect(RangeValidator(min: 1, max: 10).validate(10), isTrue);
    });

    test('fails below min', () {
      expect(RangeValidator(min: 1, max: 10).validate(0), isFalse);
    });

    test('fails above max', () {
      expect(RangeValidator(min: 1, max: 10).validate(11), isFalse);
    });

    test('works with only min', () {
      final v = RangeValidator(min: 5);
      expect(v.validate(5), isTrue);
      expect(v.validate(4), isFalse);
    });

    test('works with only max', () {
      final v = RangeValidator(max: 5);
      expect(v.validate(5), isTrue);
      expect(v.validate(6), isFalse);
    });

    test('default message includes both bounds', () {
      expect(
        RangeValidator(min: 1, max: 100).validationErrorMessage,
        equals('Must be between 1 and 100'),
      );
    });
  });

  group('PatternValidator', () {
    test('passes when pattern matches', () {
      final v = PatternValidator(RegExp(r'^\d{4}$'), 'Must be 4 digits');
      expect(v.validate('1234'), isTrue);
    });

    test('fails when pattern does not match', () {
      final v = PatternValidator(RegExp(r'^\d{4}$'), 'Must be 4 digits');
      expect(v.validate('abc'), isFalse);
    });
  });

  group('UrlValidator', () {
    test('passes for valid http URL', () {
      expect(UrlValidator().validate('http://example.com'), isTrue);
    });

    test('passes for valid https URL', () {
      expect(UrlValidator().validate('https://example.com/path'), isTrue);
    });

    test('fails for missing scheme', () {
      expect(UrlValidator().validate('example.com'), isFalse);
    });

    test('fails for ftp scheme', () {
      expect(UrlValidator().validate('ftp://example.com'), isFalse);
    });

    test('fails for empty string', () {
      expect(UrlValidator().validate(''), isFalse);
    });
  });

  group('Validators integration with verifyKey', () {
    test('MinLengthValidator applied via verifyKey', () {
      final json = <String, dynamic>{'name': 'ab'};
      expect(
        () =>
            json.verifyKey<String>('name', validators: [MinLengthValidator(3)]),
        throwsA(isA<ApiException>()),
      );
    });

    test('RangeValidator applied via verifyKey', () {
      final json = <String, dynamic>{'age': 200};
      expect(
        () => json.verifyKey<int>(
          'age',
          validators: [RangeValidator(min: 0, max: 150)],
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
