import 'package:shelf/shelf.dart';
import 'api_route.dart';
import 'api_methods.dart';
import 'base_controller.dart';
import 'serializable.dart';

/// A minimal controller that exposes `GET /health`.
///
/// Register it via `app.enableHealthCheck()` (called after `addControllers`).
///
/// Response body:
/// ```json
/// { "status": "ok", "uptime": "3h 14m 7s" }
/// ```
class HealthController extends BaseController {
  final DateTime _startedAt = DateTime.now();

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
        },
      },
    ),
  ];

  Future<_HealthPayload> _handle(Request request, void _) async {
    return _HealthPayload(_formatUptime(DateTime.now().difference(_startedAt)));
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
  const _HealthPayload(this.uptime);

  @override
  Map<String, dynamic> toJson() => {'status': 'ok', 'uptime': uptime};
}
