import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Map.validateAll', () {
    test('passes when all fields are valid', () {
      final json = {'email': 'a@b.com', 'password': 'secret123'};
      expect(
        () => json.validateAll({
          'email':    () => json.verifyKey<String>('email',    validators: [EmailValidator('Invalid email')]),
          'password': () => json.verifyKey<String>('password', validators: [MinLengthValidator(6)]),
        }),
        returnsNormally,
      );
    });

    test('throws ValidationException with all failures', () {
      final json = {'email': 'not-an-email', 'password': 'abc'};
      ValidationException? caught;
      try {
        json.validateAll({
          'email':    () => json.verifyKey<String>('email',    validators: [EmailValidator('Invalid email')]),
          'password': () => json.verifyKey<String>('password', validators: [MinLengthValidator(8)]),
        });
      } on ValidationException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.errors.length, equals(2));
      expect(caught.errors.map((e) => e['field']), containsAll(['email', 'password']));
    });

    test('reports only the fields that fail', () {
      final json = {'email': 'a@b.com', 'password': 'x'};
      ValidationException? caught;
      try {
        json.validateAll({
          'email':    () => json.verifyKey<String>('email',    validators: [EmailValidator('Invalid email')]),
          'password': () => json.verifyKey<String>('password', validators: [MinLengthValidator(8)]),
        });
      } on ValidationException catch (e) {
        caught = e;
      }
      expect(caught!.errors.length, equals(1));
      expect(caught.errors.first['field'], equals('password'));
    });

    test('missing required field is collected as an error', () {
      final json = <String, dynamic>{};
      ValidationException? caught;
      try {
        json.validateAll({
          'name': () => json.verifyKey<String>('name'),
        });
      } on ValidationException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.errors.first['field'], equals('name'));
    });
  });

  group('ApiRoute — ValidationException returns 422 with errors list', () {
    test('handler returns 422 with errors array on ValidationException', () async {
      final route = ApiRoute<Map<String, dynamic>, String>(
        method: ApiMethod.post,
        path: '/test',
        dtoParser: (json) {
          json.validateAll({
            'email': () => json.verifyKey<String>('email', validators: [EmailValidator('Invalid email')]),
            'name':  () => json.verifyKey<String>('name',  validators: [NotEmptyValidator('Name is required')]),
          });
          return json;
        },
        typedHandler: (req, _) async => 'ok',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: jsonEncode({'email': 'bad', 'name': ''}),
      );

      final response = await route.handler(request);
      expect(response.statusCode, equals(422));
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body.containsKey('errors'), isTrue);
      expect((body['errors'] as List).length, equals(2));
    });
  });
}
