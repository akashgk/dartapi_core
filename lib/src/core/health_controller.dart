import 'dart:async';
import 'package:shelf/shelf.dart';
import 'api_route.dart';
import 'api_methods.dart';
import 'base_controller.dart';
import 'serializable.dart';

/// Result of a named health check supplied to [HealthController].
///
/// ```dart
/// app.enableHealthCheck(checks: [
///   () async {
///     final ok = await db.ping().timeout(Duration(seconds: 2),
///         onTimeout: () => false);
///     return HealthCheckResult(name: 'database', healthy: ok,
///         message: ok ? null : 'ping timed out');
///   },
/// ]);
/// ```
class HealthCheckResult {
  final String name;
  final bool healthy;
  final String? message;

  const HealthCheckResult({
    required this.name,
    required this.healthy,
    this.message,
  });

  Map<String, dynamic> toJson() => {
    'healthy': healthy,
    if (message != null) 'message': message,
  };
}

/// A minimal controller that exposes `GET /health`.
///
/// Register via `app.enableHealthCheck()`. Pass [checks] to include named
/// sub-checks in the response; [status] is `"degraded"` if any check fails.
///
/// Without checks:
/// ```json
/// { "status": "ok", "uptime": "3h 14m 7s" }
/// ```
///
/// With checks:
/// ```json
/// {
///   "status": "degraded",
///   "uptime": "3h 14m 7s",
///   "checks": {
///     "database": { "healthy": true },
///     "cache":    { "healthy": false, "message": "connection refused" }
///   }
/// }
/// ```
class HealthController extends BaseController {
  final Stopwatch _uptime = Stopwatch()..start();
  final List<Future<HealthCheckResult> Function()> _checks;

  HealthController({
    List<Future<HealthCheckResult> Function()> checks = const [],
  }) : _checks = checks;

  @override
  List<ApiRoute> get routes => [
    ApiRoute<void, _HealthPayload>(
      method: ApiMethod.get,
      path: '/health',
      typedHandler: _handle,
      summary: 'Health check',
      description: 'Returns server status and uptime.',
      responseSchema: {
        'type': 'object',
        'properties': {
          'status': {'type': 'string', 'example': 'ok'},
          'uptime': {'type': 'string', 'example': '3h 14m 7s'},
          'checks': {
            'type': 'object',
            'additionalProperties': {
              'type': 'object',
              'properties': {
                'healthy': {'type': 'boolean'},
                'message': {'type': 'string'},
              },
            },
          },
        },
      },
    ),
  ];

  Future<_HealthPayload> _handle(Request request, void _) async {
    if (_checks.isEmpty) {
      return _HealthPayload(_formatUptime(_uptime.elapsed), const {});
    }
    final results = await Future.wait(_checks.map((c) => c()));
    final checksMap = {for (final r in results) r.name: r};
    return _HealthPayload(_formatUptime(_uptime.elapsed), checksMap);
  }

  static String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    parts.add('${s}s');
    return parts.join(' ');
  }
}

class _HealthPayload implements Serializable {
  final String uptime;
  final Map<String, HealthCheckResult> checks;

  _HealthPayload(this.uptime, this.checks);

  bool get _allHealthy => checks.values.every((c) => c.healthy);

  @override
  Map<String, dynamic> toJson() => {
    'status': checks.isEmpty || _allHealthy ? 'ok' : 'degraded',
    'uptime': uptime,
    if (checks.isNotEmpty)
      'checks': {for (final e in checks.entries) e.key: e.value.toJson()},
  };
}
