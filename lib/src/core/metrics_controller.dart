import 'package:shelf/shelf.dart';
import 'api_route.dart';
import 'api_methods.dart';
import 'base_controller.dart';
import '../middleware/metrics_middleware.dart';

/// Exposes `GET /metrics` in Prometheus text format (0.0.4).
///
/// Register it via `app.enableMetrics()` (called after `addControllers`).
///
/// The endpoint returns `Content-Type: text/plain; version=0.0.4; charset=utf-8`
/// so Prometheus can scrape it without any extra configuration.
///
/// Metrics exposed:
/// - `http_requests_total{method,path,status}` — request counter
/// - `http_request_duration_seconds{method,path}` — latency histogram
class MetricsController extends BaseController {
  @override
  List<ApiRoute> get routes => [
        ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/metrics',
          typedHandler: _handle,
          contentType: 'text/plain; version=0.0.4; charset=utf-8',
          summary: 'Prometheus metrics',
          description:
              'Returns request counters and latency histograms in Prometheus text format.',
        ),
      ];

  Future<String> _handle(Request req, void _) async =>
      MetricsRegistry.instance.serialize();
}
