import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Output format for [loggingMiddleware].
enum LogFormat {
  /// Human-readable text: `[timestamp] METHOD /path STATUS 12ms`
  text,

  /// Machine-readable JSON line — one object per request:
  /// ```json
  /// {"timestamp":"…","level":"INFO","method":"GET","path":"/users","status":200,"duration_ms":12}
  /// ```
  /// When [requestIdMiddleware] has run the `request_id` field is included automatically.
  json,
}

/// Logs every request in the chosen [format] (default: [LogFormat.text]).
///
/// ```dart
/// // Plain text (default)
/// .addMiddleware(loggingMiddleware())
///
/// // Structured JSON — ideal for Datadog, GCP Logging, ELK, etc.
/// .addMiddleware(loggingMiddleware(format: LogFormat.json))
/// ```
Middleware loggingMiddleware({LogFormat format = LogFormat.text}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final sw = Stopwatch()..start();
      final response = await innerHandler(request);
      sw.stop();

      if (format == LogFormat.json) {
        final entry = <String, dynamic>{
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'level': 'INFO',
          'method': request.method,
          'path': request.requestedUri.path,
          'status': response.statusCode,
          'duration_ms': sw.elapsedMilliseconds,
        };
        final requestId = request.context['requestId'];
        if (requestId != null) entry['request_id'] = requestId;
        // ignore: avoid_print
        print(jsonEncode(entry));
      } else {
        final ts = DateTime.now().toUtc().toIso8601String();
        // ignore: avoid_print
        print(
          '[$ts] ${request.method} ${request.requestedUri.path} ${response.statusCode} ${sw.elapsedMilliseconds}ms',
        );
      }

      return response;
    };
  };
}
