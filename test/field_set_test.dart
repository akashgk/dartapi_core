import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

void main() {
  // ── Validator.toSchemaProperties ──────────────────────────────────────────

  group('EmailValidator.toSchemaProperties', () {
    test('default message works', () {
      final v = EmailValidator();
      expect(v.validationErrorMessage, 'Invalid email address');
      expect(v.validate('a@b.com'), isTrue);
    });

    test('custom message still works', () {
      final v = EmailValidator('Bad email');
      expect(v.validationErrorMessage, 'Bad email');
    });

    test('returns format: email', () {
      expect(EmailValidator().toSchemaProperties(), {'format': 'email'});
    });
  });

  group('MinLengthValidator.toSchemaProperties', () {
    test('returns minLength', () {
      expect(MinLengthValidator(5).toSchemaProperties(), {'minLength': 5});
    });
  });

  group('MaxLengthValidator.toSchemaProperties', () {
    test('returns maxLength', () {
      expect(MaxLengthValidator(100).toSchemaProperties(), {'maxLength': 100});
    });
  });

  group('NotEmptyValidator.toSchemaProperties', () {
    test('returns minLength: 1', () {
      expect(NotEmptyValidator().toSchemaProperties(), {'minLength': 1});
    });
  });

  group('RangeValidator.toSchemaProperties', () {
    test('both min and max', () {
      expect(RangeValidator<int>(min: 0, max: 150).toSchemaProperties(), {
        'minimum': 0,
        'maximum': 150,
      });
    });

    test('min only', () {
      expect(RangeValidator<double>(min: 0.0).toSchemaProperties(), {
        'minimum': 0.0,
      });
    });

    test('max only', () {
      expect(RangeValidator<int>(max: 99).toSchemaProperties(), {
        'maximum': 99,
      });
    });
  });

  group('PatternValidator.toSchemaProperties', () {
    test('returns pattern string', () {
      final v = PatternValidator(RegExp(r'^\d{4}$'), 'Must be 4 digits');
      expect(v.toSchemaProperties(), {'pattern': r'^\d{4}$'});
    });
  });

  group('UrlValidator.toSchemaProperties', () {
    test('returns format: uri', () {
      expect(UrlValidator().toSchemaProperties(), {'format': 'uri'});
    });
  });

  // ── Field<T> ──────────────────────────────────────────────────────────────

  group('Field jsonType', () {
    test('String → string', () => expect(Field<String>().jsonType, 'string'));
    test('int → integer', () => expect(Field<int>().jsonType, 'integer'));
    test('double → number', () => expect(Field<double>().jsonType, 'number'));
    test('num → number', () => expect(Field<num>().jsonType, 'number'));
    test('bool → boolean', () => expect(Field<bool>().jsonType, 'boolean'));
  });

  group('Field defaults', () {
    test('required defaults to true', () {
      expect(Field<String>().required, isTrue);
    });

    test('validators defaults to empty', () {
      expect(Field<String>().validators, isEmpty);
    });

    test('example and description default to null', () {
      final f = Field<String>();
      expect(f.example, isNull);
      expect(f.description, isNull);
    });
  });

  group('Field optional', () {
    test('required: false', () {
      expect(Field<int>(required: false).required, isFalse);
    });
  });

  // ── FieldSet.validate ─────────────────────────────────────────────────────

  group('FieldSet.validate', () {
    final fields = FieldSet({
      'name': Field<String>(
        validators: [NotEmptyValidator(), MaxLengthValidator(10)],
      ),
      'email': Field<String>(validators: [EmailValidator()]),
      'age': Field<int>(
        required: false,
        validators: [RangeValidator<int>(min: 0)],
      ),
    });

    test('passes valid input with all fields present', () {
      expect(
        () => fields.validate({'name': 'Alice', 'email': 'a@b.com', 'age': 25}),
        returnsNormally,
      );
    });

    test('passes when optional field is absent', () {
      expect(
        () => fields.validate({'name': 'Alice', 'email': 'a@b.com'}),
        returnsNormally,
      );
    });

    test('throws ValidationException for missing required field', () {
      final e = _catchValidation(() => fields.validate({'email': 'a@b.com'}));
      expect(e.errors.any((e) => e['field'] == 'name'), isTrue);
    });

    test('collects ALL errors instead of stopping at first', () {
      final e = _catchValidation(
        () => fields.validate({'name': '', 'email': 'bad-email'}),
      );
      expect(e.errors.length, greaterThanOrEqualTo(2));
      final fields_ = e.errors.map((e) => e['field']).toSet();
      expect(fields_, containsAll(['name', 'email']));
    });

    test('reports correct validator message', () {
      final e = _catchValidation(
        () => fields.validate({'name': 'Alice', 'email': 'not-an-email'}),
      );
      expect(e.errors.any((e) => e['field'] == 'email'), isTrue);
    });

    test('stops at first failing validator per field', () {
      // name fails NotEmpty — MaxLength should not also fire
      final e = _catchValidation(
        () => fields.validate({'name': '', 'email': 'a@b.com'}),
      );
      final nameErrors = e.errors.where((e) => e['field'] == 'name').toList();
      expect(nameErrors.length, 1);
    });

    test('throws for missing required field with null value', () {
      final e = _catchValidation(
        () => fields.validate({'name': null, 'email': 'a@b.com'}),
      );
      expect(e.errors.any((e) => e['field'] == 'name'), isTrue);
    });
  });

  // ── FieldSet.toJsonSchema ─────────────────────────────────────────────────

  group('FieldSet.toJsonSchema', () {
    test('top-level type is object', () {
      final schema = FieldSet({'x': Field<String>()}).toJsonSchema();
      expect(schema['type'], 'object');
    });

    test('required array contains required fields only', () {
      final schema =
          FieldSet({
            'name': Field<String>(),
            'bio': Field<String>(required: false),
          }).toJsonSchema();
      final required = schema['required'] as List;
      expect(required, contains('name'));
      expect(required, isNot(contains('bio')));
    });

    test('no required key when all fields are optional', () {
      final schema =
          FieldSet({'x': Field<String>(required: false)}).toJsonSchema();
      expect(schema.containsKey('required'), isFalse);
    });

    test('property types match Dart types', () {
      final schema =
          FieldSet({
            'name': Field<String>(),
            'age': Field<int>(),
            'score': Field<double>(),
            'active': Field<bool>(),
          }).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['name'] as Map)['type'], 'string');
      expect((props['age'] as Map)['type'], 'integer');
      expect((props['score'] as Map)['type'], 'number');
      expect((props['active'] as Map)['type'], 'boolean');
    });

    test('optional field has nullable: true', () {
      final schema =
          FieldSet({'bio': Field<String>(required: false)}).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['bio'] as Map)['nullable'], isTrue);
    });

    test('required field has no nullable key', () {
      final schema = FieldSet({'name': Field<String>()}).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['name'] as Map).containsKey('nullable'), isFalse);
    });

    test('validator schema properties are merged into property', () {
      final schema =
          FieldSet({
            'email': Field<String>(validators: [EmailValidator()]),
            'name': Field<String>(validators: [MaxLengthValidator(50)]),
            'age': Field<int>(
              validators: [RangeValidator<int>(min: 0, max: 120)],
            ),
          }).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['email'] as Map)['format'], 'email');
      expect((props['name'] as Map)['maxLength'], 50);
      expect((props['age'] as Map)['minimum'], 0);
      expect((props['age'] as Map)['maximum'], 120);
    });

    test('example appears in property when set', () {
      final schema =
          FieldSet({'name': Field<String>(example: 'Alice')}).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['name'] as Map)['example'], 'Alice');
    });

    test('description appears in property when set', () {
      final schema =
          FieldSet({
            'name': Field<String>(description: 'The user full name'),
          }).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['name'] as Map)['description'], 'The user full name');
    });

    test('schema matches old hand-written UserDTO schema shape', () {
      final schema =
          FieldSet({
            'name': Field<String>(
              validators: [NotEmptyValidator(), MaxLengthValidator(100)],
              example: 'Alice',
            ),
            'email': Field<String>(
              validators: [EmailValidator()],
              example: 'alice@example.com',
            ),
            'age': Field<int>(
              validators: [RangeValidator<int>(min: 0, max: 150)],
              example: 30,
            ),
          }).toJsonSchema();

      expect(schema['type'], 'object');
      final props = schema['properties'] as Map;
      expect(props.keys, containsAll(['name', 'email', 'age']));
      expect((props['name'] as Map)['maxLength'], 100);
      expect((props['email'] as Map)['format'], 'email');
      expect((props['age'] as Map)['minimum'], 0);
      expect((props['age'] as Map)['maximum'], 150);
      final required = schema['required'] as List;
      expect(required, containsAll(['name', 'email', 'age']));
    });
  });
}

ValidationException _catchValidation(void Function() fn) {
  try {
    fn();
  } on ValidationException catch (e) {
    return e;
  }
  throw StateError('Expected ValidationException but none was thrown');
}
