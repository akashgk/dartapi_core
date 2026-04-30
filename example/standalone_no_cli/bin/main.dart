import 'dart:io';
import 'package:dartapi_core/dartapi_core.dart';
import 'package:my_api/hello_controller.dart';

// DartAPI is the central application object.
// It owns middleware, controllers, and the HTTP server lifecycle.
Future<void> main() async {
  final app = DartAPI(appName: 'my_api');

  // ── Optional middleware ────────────────────────────────────────────────────
  //
  // Enable only what you need. Each call registers a Shelf middleware into
  // the pipeline that wraps every request before it reaches a controller.

  app.enableCompression();   // gzip responses > 1 KB
  app.enableHealthCheck();   // GET /health → {"status":"ok","uptime":"..."}

  // ── Controllers ───────────────────────────────────────────────────────────
  //
  // addControllers() registers each controller's routes with the router.
  // Order matters for path matching — more specific paths first.

  app.addControllers([
    HelloController(),
  ]);

  // ── Docs ──────────────────────────────────────────────────────────────────
  //
  // enableDocs() must be called *after* addControllers() so the generator
  // can collect all registered routes.

  app.enableDocs(title: 'My API', version: '1.0.0');

  // ── Start ─────────────────────────────────────────────────────────────────

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  await app.start(port: port);
}
