import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Shelf middleware that validates API keys from a request header.
///
/// Returns `401 Unauthorized` when the key is absent or not in [validKeys].
/// On success, the validated key is stored in `request.context['api_key']`
/// for downstream handlers.
///
/// ```dart
/// ApiRoute(
///   method: ApiMethod.post,
///   path: '/webhooks/stripe',
///   middlewares: [
///     apiKeyMiddleware(validKeys: {'secret-webhook-key'}),
///   ],
///   typedHandler: handleStripeWebhook,
/// )
/// ```
Middleware apiKeyMiddleware({
  required Set<String> validKeys,

  /// The header name to read the API key from. Defaults to `X-API-Key`.
  String headerName = 'X-API-Key',
}) {
  return (Handler inner) {
    return (Request request) async {
      final key = request.headers[headerName];

      if (key == null || key.isEmpty || !validKeys.contains(key)) {
        return Response(
          401,
          body: jsonEncode({'error': 'Invalid or missing API key'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return inner(request.change(context: {'api_key': key}));
    };
  };
}
