import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'auth_utils.dart';
import 'jwt_service.dart';

/// Middleware to protect routes using JWT Bearer token authentication.
///
/// Returns `403 Forbidden` when the token is absent, expired, or invalid.
/// On success, the decoded payload is stored in `request.context['user']`
/// for downstream handlers.
///
/// ```dart
/// ApiRoute(
///   method: ApiMethod.get,
///   path: '/me',
///   middlewares: [authMiddleware(jwtService)],
///   typedHandler: (req, _) async {
///     final user = req.context['user'] as Map<String, dynamic>;
///     return {'id': user['sub']};
///   },
/// )
/// ```
Middleware authMiddleware(JwtService jwtService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final token = request.headers.getToken();

      if (token == null || token.isEmpty) {
        return Response.forbidden(
          jsonEncode({'error': 'Missing or invalid token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final payload = await jwtService.verifyAccessToken(token);

      if (payload == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Invalid token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      request = request.change(context: {'user': payload});
      return innerHandler(request);
    };
  };
}
