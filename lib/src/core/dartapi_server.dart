import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_static/shelf_static.dart';

import 'api_exception.dart';
import 'background_task.dart';
import 'base_controller.dart';
import 'global_exception_handler.dart';
import 'health_controller.dart';
import 'logger.dart';
import 'metrics_controller.dart';
import 'router_manager.dart';
import 'service_registry.dart';
import '../middleware/body_size_limit_middleware.dart';
import '../middleware/compression_middleware.dart';
import '../middleware/metrics_middleware.dart';
import '../middleware/rate_limit_middleware.dart';
import '../middleware/request_id_middleware.dart';
import '../middleware/security_headers_middleware.dart';
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

  /// How long [stop] waits for in-flight requests to complete before
  /// force-closing their connections. Defaults to 30 seconds.
  ///
  /// SIGINT/SIGTERM trigger a graceful drain bounded by this period, so a
  /// rolling deploy (e.g. Kubernetes) never kills requests mid-flight.
  final Duration shutdownGracePeriod;

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
  bool _rateLimitTrustProxy = false;
  int? _bodySizeLimitMaxBytes;
  Middleware? _securityHeaders;
  LogFormat _logFormat = LogFormat.text;
  List<String> _logExcludePaths = const [];

  // ── Runtime state ──────────────────────────────────────────────────────────

  /// The port the server is bound to, or `null` when not running.
  ///
  /// Useful with `start(port: 0)`, which binds an ephemeral port.
  int? get port => _server?.port;

  HttpServer? _server;
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];
  bool _stopped = false;

  DartAPI({
    this.corsOrigin = '*',
    this.appName = 'dartapi',
    this.shutdownGracePeriod = const Duration(seconds: 30),
  });

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
  ///
  /// The key is the IP of the TCP connection. Behind a reverse proxy or load
  /// balancer set [trustProxy] to `true` so the first `X-Forwarded-For`
  /// entry is used instead — otherwise every client shares the proxy's IP.
  /// Never enable it on a directly exposed server (the header is spoofable).
  void enableRateLimit({
    required int maxRequests,
    required Duration window,
    String Function(Request)? keyExtractor,
    bool trustProxy = false,
  }) {
    _rateLimitMaxRequests = maxRequests;
    _rateLimitWindow = window;
    _rateLimitKeyExtractor = keyExtractor;
    _rateLimitTrustProxy = trustProxy;
  }

  /// Rejects requests whose `Content-Length` exceeds [maxBytes] with
  /// `413 Payload Too Large` before the body is read.
  ///
  /// Default limit: 1 MB. Only enforced when the client sends `Content-Length`.
  ///
  /// ```dart
  /// app.enableBodySizeLimit(maxBytes: 512 * 1024); // 512 KB
  /// ```
  void enableBodySizeLimit({int maxBytes = 1024 * 1024}) {
    _bodySizeLimitMaxBytes = maxBytes;
  }

  /// Adds common security headers to every response.
  ///
  /// Defaults protect against click-jacking, MIME-sniffing, and XSS.
  /// Pass explicit values to tighten the policy for your application.
  ///
  /// ```dart
  /// app.enableSecurityHeaders(
  ///   contentSecurityPolicy: "default-src 'self'",
  ///   strictTransportSecurity: 'max-age=31536000; includeSubDomains',
  /// );
  /// ```
  void enableSecurityHeaders({
    String xFrameOptions = 'DENY',
    String xContentTypeOptions = 'nosniff',
    String referrerPolicy = 'strict-origin-when-cross-origin',
    String xXssProtection = '1; mode=block',
    String permissionsPolicy = 'camera=(), microphone=(), geolocation=()',
    String? contentSecurityPolicy,
    String? strictTransportSecurity,
  }) {
    _securityHeaders = securityHeadersMiddleware(
      xFrameOptions: xFrameOptions,
      xContentTypeOptions: xContentTypeOptions,
      referrerPolicy: referrerPolicy,
      xXssProtection: xXssProtection,
      permissionsPolicy: permissionsPolicy,
      contentSecurityPolicy: contentSecurityPolicy,
      strictTransportSecurity: strictTransportSecurity,
    );
  }

  /// Configures the built-in request logging (always on).
  ///
  /// Use [format] to switch to structured JSON logs and [excludePaths] to
  /// silence noisy endpoints:
  ///
  /// ```dart
  /// app.configureLogging(
  ///   format: LogFormat.json,
  ///   excludePaths: ['/health', '/metrics'],
  /// );
  /// ```
  void configureLogging({
    LogFormat format = LogFormat.text,
    List<String> excludePaths = const [],
  }) {
    _logFormat = format;
    _logExcludePaths = excludePaths;
  }

  /// Registers `GET /metrics` in Prometheus text format and adds
  /// [metricsMiddleware] to the pipeline so every request is instrumented.
  void enableMetrics() {
    _metricsEnabled = true;
    _router.registerController(MetricsController());
  }

  /// Registers `GET /health` — returns `{"status":"ok","uptime":"..."}`.
  ///
  /// Pass [checks] to include named dependency checks in the response body.
  /// The `status` field becomes `"degraded"` if any check returns unhealthy.
  ///
  /// ```dart
  /// app.enableHealthCheck(checks: [
  ///   () async {
  ///     final ok = await db.ping().timeout(Duration(seconds: 2),
  ///         onTimeout: () => false);
  ///     return HealthCheckResult(name: 'database', healthy: ok);
  ///   },
  /// ]);
  /// ```
  void enableHealthCheck({
    List<Future<HealthCheckResult> Function()> checks = const [],
  }) => _router.registerController(HealthController(checks: checks));

  /// Registers OpenAPI docs at `/openapi.json`, `/docs` (Swagger UI), and
  /// `/redoc`.
  ///
  /// Routes are collected lazily when the spec is first requested, so this
  /// can be called before or after [addControllers]. The spec is generated
  /// once and cached.
  ///
  /// [servers] lists base URLs for the spec's `servers` array (drives
  /// Swagger UI's "Try it out" and generated clients). [apiKeyHeader] is the
  /// header documented for [SecurityScheme.apiKey] routes — match it to
  /// `apiKeyMiddleware`'s `headerName`. [tagDescriptions] adds descriptions
  /// to tag groups in Swagger UI and ReDoc.
  ///
  /// UI assets load from jsdelivr at pinned versions; override
  /// [swaggerUiCssUrl] / [swaggerUiJsUrl] / [redocJsUrl] to self-host them
  /// (e.g. via [serveStatic]) for air-gapped deployments.
  ///
  /// ```dart
  /// app.enableDocs(
  ///   title: 'My API',
  ///   servers: ['https://api.example.com'],
  ///   tagDescriptions: {'Users': 'User management endpoints'},
  /// );
  /// ```
  void enableDocs({
    String title = 'API',
    String version = '1.0.0',
    String description = '',
    List<String> servers = const [],
    String apiKeyHeader = 'X-API-Key',
    Map<String, Map<String, dynamic>> schemas = const {},
    Map<String, String> tagDescriptions = const {},
    String? swaggerUiCssUrl,
    String? swaggerUiJsUrl,
    String? redocJsUrl,
  }) {
    _router.registerController(
      DocsController(
        routesProvider: () => _router.collectedRoutes,
        title: title,
        version: version,
        description: description,
        servers: servers,
        apiKeyHeader: apiKeyHeader,
        schemas: schemas,
        tagDescriptions: tagDescriptions,
        swaggerUiCssUrl: swaggerUiCssUrl,
        swaggerUiJsUrl: swaggerUiJsUrl,
        redocJsUrl: redocJsUrl,
      ),
    );
  }

  // ── Controllers ───────────────────────────────────────────────────────────

  /// Registers the routes of every controller in [controllers].
  ///
  /// Pass [prefix] to mount all of them under a common base path — the
  /// standard way to version an API:
  ///
  /// ```dart
  /// app.addControllers([UserController()], prefix: '/api/v1');
  /// // GET /users  →  GET /api/v1/users (also reflected in /openapi.json)
  /// ```
  void addControllers(List<BaseController> controllers, {String prefix = ''}) {
    for (final controller in controllers) {
      _router.registerController(controller, prefix: prefix);
    }
  }

  /// Serves files from [directory] under [urlPrefix].
  ///
  /// ```dart
  /// app.serveStatic('/public', 'web');
  /// // GET /public/logo.png → web/logo.png
  /// ```
  ///
  /// [defaultDocument] (e.g. `'index.html'`) is served for directory
  /// requests. Set [listDirectories] to `true` to render a directory
  /// listing when no default document exists.
  void serveStatic(
    String urlPrefix,
    String directory, {
    String? defaultDocument,
    bool listDirectories = false,
  }) {
    _router.mount(
      urlPrefix,
      createStaticHandler(
        directory,
        defaultDocument: defaultDocument,
        listDirectories: listDirectories,
      ),
    );
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Binds the HTTP server on [address]:[port] (default `0.0.0.0:8080`).
  ///
  /// Set [shared] to `true` when multiple isolates run on the same port —
  /// the OS load-balances connections across all of them.
  ///
  /// Pass [securityContext] to serve HTTPS directly (most deployments
  /// terminate TLS at a proxy instead and can ignore this):
  ///
  /// ```dart
  /// final context = SecurityContext()
  ///   ..useCertificateChain('cert.pem')
  ///   ..usePrivateKey('key.pem');
  /// await app.start(port: 443, securityContext: context);
  /// ```
  ///
  /// Pipeline order (outermost first):
  ///   requestId → globalException → rateLimit → timeout → backgroundTasks →
  ///   bodySizeLimit → logging → CORS → compression → metrics →
  ///   securityHeaders → router
  Future<void> start({
    int port = 8080,
    Object address = '0.0.0.0',
    bool shared = false,
    SecurityContext? securityContext,
  }) async {
    for (final hook in _startupHooks) {
      await hook();
    }

    var pipeline = const Pipeline()
        .addMiddleware(requestIdMiddleware())
        .addMiddleware(
          globalExceptionMiddleware(
            onError: (error, stackTrace) {
              log('[$appName] Unhandled error: $error\n$stackTrace');
              if (error is ApiException) return error;
              return const ApiException(500, 'Internal Server Error');
            },
          ),
        );

    if (_rateLimitMaxRequests != null) {
      pipeline = pipeline.addMiddleware(
        rateLimitMiddleware(
          maxRequests: _rateLimitMaxRequests!,
          window: _rateLimitWindow!,
          keyExtractor: _rateLimitKeyExtractor,
          trustProxy: _rateLimitTrustProxy,
        ),
      );
    }

    if (_requestTimeout != null) {
      pipeline = pipeline.addMiddleware(timeoutMiddleware(_requestTimeout!));
    }

    if (_backgroundTasksEnabled) {
      pipeline = pipeline.addMiddleware(backgroundTaskMiddleware());
    }

    if (_bodySizeLimitMaxBytes != null) {
      pipeline = pipeline.addMiddleware(
        bodySizeLimitMiddleware(maxBytes: _bodySizeLimitMaxBytes!),
      );
    }

    pipeline = pipeline
        .addMiddleware(
          loggingMiddleware(format: _logFormat, excludePaths: _logExcludePaths),
        )
        .addMiddleware(
          corsHeaders(
            headers: {
              ACCESS_CONTROL_ALLOW_ORIGIN: corsOrigin,
              ACCESS_CONTROL_ALLOW_METHODS:
                  'GET, POST, PUT, DELETE, PATCH, OPTIONS',
              ACCESS_CONTROL_ALLOW_HEADERS:
                  'Authorization, Content-Type, X-Request-Id',
            },
          ),
        );

    if (_compressionEnabled) {
      pipeline = pipeline.addMiddleware(
        compressionMiddleware(threshold: _compressionThreshold),
      );
    }

    if (_metricsEnabled) {
      pipeline = pipeline.addMiddleware(metricsMiddleware());
    }

    if (_securityHeaders != null) {
      pipeline = pipeline.addMiddleware(_securityHeaders!);
    }

    final handler = pipeline.addHandler(_router.handler.call);
    _server = await io.serve(
      handler,
      address,
      port,
      shared: shared,
      securityContext: securityContext,
    );
    _stopped = false;
    final scheme = securityContext != null ? 'https' : 'http';
    log('[$appName] Server running on $scheme://localhost:$port');

    _signalSubscriptions.add(
      ProcessSignal.sigint.watch().listen((_) => _shutdownAndExit()),
    );
    if (!Platform.isWindows) {
      _signalSubscriptions.add(
        ProcessSignal.sigterm.watch().listen((_) => _shutdownAndExit()),
      );
    }
  }

  /// Stops the server gracefully: stops accepting new connections, waits up
  /// to [shutdownGracePeriod] for in-flight requests to complete (then
  /// force-closes stragglers), and finally runs shutdown hooks.
  ///
  /// Hooks run *after* the drain so a hook that closes the database cannot
  /// break requests that are still completing.
  ///
  /// Set [force] to `true` to abort in-flight requests immediately instead
  /// of draining. Safe to call more than once.
  Future<void> stop({bool force = false}) async {
    if (_stopped) return;
    _stopped = true;
    log('[$appName] Shutting down...');
    for (final sub in _signalSubscriptions) {
      await sub.cancel();
    }
    _signalSubscriptions.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      if (!force) {
        await _drain(server);
      }
      // Destroys any connections still open (idle keep-alives or requests
      // that outlived the grace period).
      await server.close(force: true);
    }
    for (final hook in _shutdownHooks) {
      await hook();
    }
  }

  /// Stops accepting new connections, then waits (bounded by
  /// [shutdownGracePeriod]) until no connection is still serving a request.
  ///
  /// `connectionsInfo().active` stays non-zero until the response has been
  /// fully written to the socket — dart:io's `close(force: false)` alone
  /// does not wait for that.
  Future<void> _drain(HttpServer server) async {
    await server.close();
    final deadline = DateTime.now().add(shutdownGracePeriod);
    while (server.connectionsInfo().active > 0) {
      if (DateTime.now().isAfter(deadline)) {
        log(
          '[$appName] Shutdown grace period '
          '(${shutdownGracePeriod.inSeconds}s) exceeded — force-closing '
          '${server.connectionsInfo().active} active connection(s).',
        );
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _shutdownAndExit() async {
    await stop();
    exit(0);
  }
}
