import 'dart:convert';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';

/// Represents a single file or field from a `multipart/form-data` request.
class UploadedFile {
  /// The form field name (`name` parameter in `Content-Disposition`).
  final String fieldName;

  /// Original filename as reported by the client. `null` for plain form fields.
  final String? filename;

  /// MIME type of the part (e.g. `image/jpeg`). Defaults to `text/plain`.
  final String contentType;

  /// Raw bytes of the part body.
  final List<int> bytes;

  const UploadedFile({
    required this.fieldName,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  /// Body decoded as UTF-8 text. Useful for plain form fields.
  String get text => utf8.decode(bytes);

  /// `true` when the part has a filename — i.e. it is an actual file upload.
  bool get isFile => filename != null;
}

/// Multipart / file-upload helpers on Shelf's [Request].
extension MultipartExtensions on Request {
  /// `true` when the request carries a `multipart/form-data` body.
  bool get isMultipart {
    final ct = headers['content-type'] ?? '';
    return ct.toLowerCase().contains('multipart/form-data');
  }

  /// Parses all parts of a `multipart/form-data` request.
  ///
  /// Throws [FormatException] if the `Content-Type` header is missing or the
  /// boundary cannot be found.
  ///
  /// ```dart
  /// final parts = await request.multipartFiles();
  /// for (final part in parts) {
  ///   if (part.isFile) saveFile(part.filename!, part.bytes);
  /// }
  /// ```
  Future<List<UploadedFile>> multipartFiles() async {
    final boundary = _boundary();
    final transformer = MimeMultipartTransformer(boundary);
    final parts = await transformer.bind(read()).toList();
    final result = <UploadedFile>[];

    for (final part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final name = _headerParam(disposition, 'name') ?? '';
      final filename = _headerParam(disposition, 'filename');
      final ct = part.headers['content-type'] ?? 'text/plain';
      final bytes = await part.fold<List<int>>([], (a, b) => [...a, ...b]);
      result.add(UploadedFile(
        fieldName: name,
        filename: filename,
        contentType: ct,
        bytes: bytes,
      ));
    }
    return result;
  }

  /// Returns the first uploaded file with the given [fieldName], or `null`.
  ///
  /// ```dart
  /// final avatar = await request.file('avatar');
  /// if (avatar == null) throw ApiException(400, 'Missing file');
  /// saveBytes(avatar.filename!, avatar.bytes);
  /// ```
  Future<UploadedFile?> file(String fieldName) async {
    final all = await multipartFiles();
    for (final f in all) {
      if (f.fieldName == fieldName) return f;
    }
    return null;
  }

  /// Returns all non-file form fields as a `Map<String, String>`.
  ///
  /// ```dart
  /// final fields = await request.formFields();
  /// final title = fields['title'] ?? '';
  /// ```
  Future<Map<String, String>> formFields() async {
    final all = await multipartFiles();
    return {
      for (final part in all.where((p) => !p.isFile))
        part.fieldName: part.text,
    };
  }

  String _boundary() {
    final ct = headers['content-type'] ?? '';
    final match = RegExp(r'boundary=([^\s;]+)').firstMatch(ct);
    if (match == null) {
      throw FormatException(
          'Missing boundary in Content-Type: $ct');
    }
    return match.group(1)!;
  }
}

/// Extracts a named parameter from a header value string.
///
/// Example: `form-data; name="avatar"; filename="photo.jpg"` with `name` → `"avatar"`.
String? _headerParam(String header, String param) {
  final match =
      RegExp('$param="([^"]*)"', caseSensitive: false).firstMatch(header);
  return match?.group(1);
}
