import 'dart:convert';
import 'package:shelf/shelf.dart';

/// An HTTP response returned by [DartApiTestClient].
class TestResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  const TestResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Decodes the response body as JSON and casts it to [T].
  ///
  /// ```dart
  /// final users = res.json<List>();
  /// final user  = res.json<Map<String, dynamic>>();
  /// ```
  T json<T>() => jsonDecode(body) as T;
}

/// In-process HTTP test client — calls a Shelf [Handler] directly without
/// opening a TCP socket.
///
/// Wrap your [DartAPI] handler (or any Shelf handler) and make HTTP requests
/// in tests with zero network overhead.
///
/// ```dart
/// import 'package:dartapi_core/dartapi_core.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   late DartApiTestClient client;
///
///   setUp(() {
///     final router = RouterManager();
///     router.registerController(UserController(...));
///     client = DartApiTestClient(router.handler.call);
///   });
///
///   test('GET /users returns 200', () async {
///     final res = await client.get('/users');
///     expect(res.statusCode, 200);
///     expect(res.json<List>(), isNotEmpty);
///   });
/// }
/// ```
class DartApiTestClient {
  final Handler _handler;
  final Map<String, String> _defaultHeaders;

  /// Creates a test client wrapping [handler].
  ///
  /// [defaultHeaders] are merged into every request — useful for setting
  /// `Authorization: Bearer …` once for an entire test suite.
  DartApiTestClient(this._handler, {Map<String, String>? defaultHeaders})
      : _defaultHeaders = defaultHeaders ?? {};

  Future<TestResponse> get(String path, {Map<String, String>? headers}) =>
      _send('GET', path, headers: headers);

  Future<TestResponse> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      _send('POST', path, body: body, headers: headers);

  Future<TestResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      _send('PUT', path, body: body, headers: headers);

  Future<TestResponse> delete(
    String path, {
    Map<String, String>? headers,
  }) =>
      _send('DELETE', path, headers: headers);

  Future<TestResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      _send('PATCH', path, body: body, headers: headers);

  Future<TestResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final merged = {..._defaultHeaders, ...?headers};
    String? bodyStr;
    if (body != null) {
      bodyStr = body is String ? body : jsonEncode(body);
      merged.putIfAbsent('content-type', () => 'application/json');
    }

    final request = Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: merged,
      body: bodyStr ?? '',
    );

    final response = await _handler(request);
    final responseBody = await response.readAsString();

    return TestResponse(
      statusCode: response.statusCode,
      headers: Map<String, String>.from(response.headers),
      body: responseBody,
    );
  }
}
