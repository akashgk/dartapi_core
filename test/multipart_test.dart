import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _boundary = 'testboundary123';

/// Builds a raw multipart/form-data body string.
String _multipartBody(List<Map<String, String>> parts) {
  final buf = StringBuffer();
  for (final part in parts) {
    buf.write('--$_boundary\r\n');
    buf.write('Content-Disposition: form-data; name="${part['name']}"');
    if (part['filename'] != null) {
      buf.write('; filename="${part['filename']}"');
    }
    buf.write('\r\n');
    if (part['contentType'] != null) {
      buf.write('Content-Type: ${part['contentType']}\r\n');
    }
    buf.write('\r\n');
    buf.write(part['value'] ?? '');
    buf.write('\r\n');
  }
  buf.write('--$_boundary--\r\n');
  return buf.toString();
}

Request _req(String body) => Request(
  'POST',
  Uri.parse('http://localhost/upload'),
  body: body,
  headers: {'content-type': 'multipart/form-data; boundary=$_boundary'},
);

void main() {
  group('UploadedFile', () {
    test('text returns UTF-8 decoded body', () {
      final file = UploadedFile(
        fieldName: 'note',
        filename: null,
        contentType: 'text/plain',
        bytes: utf8.encode('hello'),
      );
      expect(file.text, equals('hello'));
    });

    test('isFile is true when filename is set', () {
      final file = UploadedFile(
        fieldName: 'avatar',
        filename: 'photo.jpg',
        contentType: 'image/jpeg',
        bytes: [],
      );
      expect(file.isFile, isTrue);
    });

    test('isFile is false for plain form fields', () {
      final file = UploadedFile(
        fieldName: 'title',
        filename: null,
        contentType: 'text/plain',
        bytes: [],
      );
      expect(file.isFile, isFalse);
    });
  });

  group('MultipartExtensions.isMultipart', () {
    test('true for multipart/form-data', () {
      expect(_req('').isMultipart, isTrue);
    });

    test('false for application/json', () {
      final req = Request(
        'POST',
        Uri.parse('http://localhost/'),
        headers: {'content-type': 'application/json'},
      );
      expect(req.isMultipart, isFalse);
    });
  });

  group('MultipartExtensions.multipartFiles()', () {
    test('parses a plain text field', () async {
      final body = _multipartBody([
        {'name': 'username', 'value': 'akash'},
      ]);
      final parts = await _req(body).multipartFiles();
      expect(parts, hasLength(1));
      expect(parts.first.fieldName, equals('username'));
      expect(parts.first.text, equals('akash'));
      expect(parts.first.isFile, isFalse);
    });

    test('parses a file part', () async {
      final body = _multipartBody([
        {
          'name': 'avatar',
          'filename': 'photo.jpg',
          'contentType': 'image/jpeg',
          'value': 'FAKEJPEG',
        },
      ]);
      final parts = await _req(body).multipartFiles();
      expect(parts, hasLength(1));
      expect(parts.first.fieldName, equals('avatar'));
      expect(parts.first.filename, equals('photo.jpg'));
      expect(parts.first.contentType, equals('image/jpeg'));
      expect(parts.first.isFile, isTrue);
    });

    test('parses multiple parts', () async {
      final body = _multipartBody([
        {'name': 'title', 'value': 'My Doc'},
        {'name': 'file', 'filename': 'doc.txt', 'value': 'content'},
      ]);
      final parts = await _req(body).multipartFiles();
      expect(parts, hasLength(2));
      expect(parts[0].fieldName, equals('title'));
      expect(parts[1].fieldName, equals('file'));
    });
  });

  group('MultipartExtensions.file()', () {
    test('returns named file part', () async {
      final body = _multipartBody([
        {'name': 'avatar', 'filename': 'img.png', 'value': 'PNG'},
      ]);
      final f = await _req(body).file('avatar');
      expect(f, isNotNull);
      expect(f!.filename, equals('img.png'));
    });

    test('returns null when field not present', () async {
      final body = _multipartBody([
        {'name': 'other', 'value': 'x'},
      ]);
      expect(await _req(body).file('avatar'), isNull);
    });
  });

  group('MultipartExtensions.formFields()', () {
    test('returns only non-file fields as map', () async {
      final body = _multipartBody([
        {'name': 'title', 'value': 'Hello'},
        {'name': 'file', 'filename': 'f.txt', 'value': 'data'},
      ]);
      final fields = await _req(body).formFields();
      expect(fields, equals({'title': 'Hello'}));
      expect(fields.containsKey('file'), isFalse);
    });
  });

  group('MultipartExtensions error handling', () {
    test('throws FormatException when boundary is missing', () async {
      final req = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: 'data',
        headers: {'content-type': 'multipart/form-data'},
      );
      expect(req.multipartFiles(), throwsA(isA<FormatException>()));
    });
  });
}
