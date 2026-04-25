import 'dart:developer';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'api_exception.dart';
import 'background_task.dart';
import 'base_controller.dart';
import 'global_exception_handler.dart';
import 'health_controller.dart';
import 'logger.dart';
import 'metrics_controller.dart';
import 'router_manager.dart';
import 'service_registry.dart';
import '../middleware/compression_middleware.dart';
import '../middleware/metrics_middleware.dart';
import '../middleware/rate_limit_middleware.dart';
import '../middleware/request_id_middleware.dart';
import '../middleware/timeout_middleware.dart';
import '../openapi/docs_controller.dart';

/// Central application class — configure middleware, register controllers,
/// and call [start] to bind the HTTP server.
///
/// ```dart
/// final app = DartAPI();
///
/// app.enableCompression();
/// app.enableBackgroundTasks();
/// app.enableTimeout(const Duration(seconds: 30));
/// app.enableRateLimit(maxRequests: 200, window: const Duration(minutes: 1));
///
/// app.addControllers([UserController(...), ProductController(...)]);
///
/// app.enableHealthCheck();
/// app.enableMetrics();
/// app.enableDocs(title: 'My API', version: '1.0.0');
///
/// await app.start(port: 8080);
/// ```
class DartAPI {
  final RouterManager _router = RouterManager();
  final ServiceRegistry _registry = ServiceRegistry();

  /// CORS origin sent in `Access-Control-Allow-Origin`. Defaults to `'*'`.
  final String corsOrigin;

  /// Application name used in log messages.
  final String appName;

  final List<Future<void> Function()> _startupHooks = [];
  final List<Future<void> Function()> _shutdownHooks = [];

  // ── Opt-in middleware state ────────────────────────────────────────────────
  bool _metricsEnabled = false;
  bool _compressionEnabled = false;
  int _compressionThreshold = 1024;
  bool _backgroundTasksEnabled = false;
  Duration? _requestTimeout;
  int? _rateLimitMaxRequests;
  Duration? _rateLimitWindow;
  String Function(Request)? _rateLimitKeyExtractor;

  DartAPI({this.corsOrigin = '*', this.appName = 'dartapi'});

  // ── Service registry (DI) ─────────────────────────────────────────────────

  /// The underlying [ServiceRegistry] used for dependency injection.
  ///
  /// Prefer the convenience methods [register], [registerSingleton], and [get]
  /// over accessing this directly.
  ServiceRegistry get registry => _registry;

  /// Registers a lazy-singleton factory for [T].
  ///
  /// [factory] receives the [ServiceRegistry] so it can resolve
  /// sub-dependencies via [get].
  ///
  /// ```dart
  /// app.register<UserService>(
  ///   (r) => UserService(repository: r.get<UserRepository>()),
  /// );
  /// ```
  void register<T>(T Function(ServiceRegistry) factory) =>
      _registry.register<T>(factory);

  /// Registers a pre-built [instance] as an eager singleton for [T].
  ///
  /// ```dart
  /// app.registerSingleton<DartApiDB>(db);
  /// ```
  void registerSingleton<T>(T instance) =>
      _registry.registerSingleton<T>(instance);

  /// Returns the resolved instance for [T].
  ///
  /// Constructs the instance lazily on the first call; subsequent calls return
  /// the cached singleton.
  ///
  /// Throws [StateError] if [T] is not registered or a circular dependency
  /// is detected.
  T get<T>() => _registry.get<T>();

  /// Returns `true` if [T] has been registered via [register] or
  /// [registerSingleton].
  bool isRegistered<T>() => _registry.isRegistered<T>();

  // ── Hooks ─────────────────────────────────────────────────────────────────

  /// Registers a callback to run once before the server starts accepting requests.
  void onStartup(Future<void> Function() hook) => _startupHooks.add(hook);

  /// Registers a callback to run when SIGINT or SIGTERM is received.
  void onShutdown(Future<void> Function() hook) => _shutdownHooks.add(hook);

  // ── Opt-in middleware ──────────────────────────────────────────────────────

  /// Gzip-compresses responses above [threshold] bytes when the client sends
  /// `Accept-Encoding: gzip`. Highly recommended for JSON APIs.
  void enableCompression({int threshold = 1024}) {
    _compressionEnabled = true;
    _compressionThreshold = threshold;
  }

  /// Enables `request.backgroundTasks` in every handler — schedule fire-and-
  /// forget async work that runs after the response has been sent.
  ///
  /// ```dart
  /// Future<User> createUser(Request req, UserDTO? dto) async {
  ///   final user = await _service.createUser(dto!);
  ///   req.backgroundTasks.add(() => emailService.sendWelcome(user.email));
  ///   return user; // response sent; welcome email fires after
  /// }
  /// ```
  void enableBackgroundTasks() => _backgroundTasksEnabled = true;

  /// Returns `408 Request Timeout` if any handler does not complete within [timeout].
  void enableTimeout(Duration timeout) => _requestTimeout = timeout;

  /// Applies a global token-bucket rate limiter keyed by client IP by default.
  ///
  /// Clients exceeding [maxRequests] within [window] receive `429 Too Many
  /// Requests` with `Retry-After` and `X-RateLimit-*` headers.
  void enableRateLimit({
    required int maxRequests,
    required Duration window,
    String Function(Request)? keyExtractor,
  }) {
    _rateLimitMaxRequests = maxRequests;
    _rateLimitWindow = window;
    _rateLimitKeyExtractor = keyExtractor;
  }

  /// Registers `GET /metrics` in Prometheus text format and adds
  /// [metricsMiddleware] to the pipeline so every request is instrumented.
  void enableMetrics() {
    _metricsEnabled = true;
    _router.registerController(MetricsController());
  }

  /// Registers `GET /health` — returns `{"status":"ok","uptime":"..."}`.
  void enableHealthCheck() => _router.registerController(HealthController());

  /// Registers OpenAPI docs at `/openapi.json`, `/docs` (Swagger UI), and
  /// `/redoc`. Call this *after* [addControllers] so all routes are collected.
  void enableDocs({String title = 'API', String version = '1.0.0'}) {
    _router.registerController(
      DocsController(
        apiRoutes: _router.collectedRoutes,
        title: title,
        version: version,
      ),
    );
  }

  // ── Controllers ───────────────────────────────────────────────────────────

  void addControllers(List<BaseController> controllers) {
    for (final controller in controllers) {
      _router.registerController(controller);
    }
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Binds the HTTP server on [port].
  ///
  /// Set [shared] to `true` when multiple isolates run on the same port —
  /// the OS load-balances connections across all of them.
  ///
  /// Pipeline order (outermost first):
  ///   requestId → globalException → rateLimit → timeout →
  ///   backgroundTasks → logging → CORS → compression → metrics → router
  Future<void> start({int port = 8080, bool shared = false}) async {
    for (final hook in _startupHooks) {
      await hook();
    }

    var pipeline = const Pipeline()
        .addMiddleware(requestIdMiddleware())
        .addMiddleware(globalExceptionMiddleware(
          onError: (error, stackTrace) {
            log('[$appName] Unhandled error: $error\n$stackTrace');
            if (error is ApiException) return error;
            return const ApiException(500, 'Internal Server Error');
          },
        ));

    if (_rateLimitMaxRequests != null) {
      pipeline = pipeline.addMiddleware(rateLimitMiddleware(
        maxRequests: _rateLimitMaxRequests!,
        window: _rateLimitWindow!,
        keyExtractor: _rateLimitKeyExtractor,
      ));
    }

    if (_requestTimeout != null) {
      pipeline = pipeline.addMiddleware(timeoutMiddleware(_requestTimeout!));
    }

    if (_backgroundTasksEnabled) {
      pipeline = pipeline.addMiddleware(backgroundTaskMiddleware());
    }

    pipeline = pipeline
        .addMiddleware(loggingMiddleware())
        .addMiddleware(corsHeaders(headers: {
          ACCESS_CONTROL_ALLOW_ORIGIN: corsOrigin,
          ACCESS_CONTROL_ALLOW_METHODS:
              'GET, POST, PUT, DELETE, PATCH, OPTIONS',
          ACCESS_CONTROL_ALLOW_HEADERS:
              'Authorization, Content-Type, X-Request-Id',
        }));

    if (_compressionEnabled) {
      pipeline = pipeline
          .addMiddleware(compressionMiddleware(threshold: _compressionThreshold));
    }

    if (_metricsEnabled) {
      pipeline = pipeline.addMiddleware(metricsMiddleware());
    }

    final handler = pipeline.addHandler(_router.handler.call);
    final server = await io.serve(handler, '0.0.0.0', port, shared: shared);
    log('[$appName] Server running on http://localhost:$port');

    Future<void> shutdown() async {
      log('[$appName] Shutting down...');
      for (final hook in _shutdownHooks) {
        await hook();
      }
      await server.close(force: true);
    }

    ProcessSignal.sigint.watch().listen((_) async {
      await shutdown();
      exit(0);
    });
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) async {
        await shutdown();
        exit(0);
      });
    }
  }
}
