import 'package:shelf/shelf.dart';

extension CookieRequestExtensions on Request {
  /// Parses all cookies from the `Cookie` request header.
  ///
  /// Returns an empty map if no cookies are present.
  Map<String, String> get cookies {
    final cookieHeader = headers['cookie'] ?? '';
    if (cookieHeader.isEmpty) return const {};
    final result = <String, String>{};
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      final idx = trimmed.indexOf('=');
      if (idx < 1) continue;
      result[trimmed.substring(0, idx).trim()] =
          trimmed.substring(idx + 1).trim();
    }
    return result;
  }

  /// Returns the value of a single cookie by [name], or `null` if absent.
  String? cookie(String name) => cookies[name];
}

/// Adds a `Set-Cookie` header to [response].
///
/// ```dart
/// return setCookie(response, 'session', token,
///   maxAge: Duration(hours: 1), httpOnly: true, secure: true);
/// ```
Response setCookie(
  Response response,
  String name,
  String value, {
  Duration? maxAge,
  String? path,
  String? domain,
  String? sameSite,
  bool httpOnly = false,
  bool secure = false,
}) {
  final parts = ['$name=$value'];
  if (maxAge != null) parts.add('Max-Age=${maxAge.inSeconds}');
  if (path != null) parts.add('Path=$path');
  if (domain != null) parts.add('Domain=$domain');
  if (sameSite != null) parts.add('SameSite=$sameSite');
  if (httpOnly) parts.add('HttpOnly');
  if (secure) parts.add('Secure');

  final existing = response.headers['set-cookie'];
  final cookieValue = parts.join('; ');
  final newHeaders =
      existing != null
          ? {'set-cookie': '$existing\n$cookieValue'}
          : {'set-cookie': cookieValue};

  return response.change(headers: newHeaders);
}
