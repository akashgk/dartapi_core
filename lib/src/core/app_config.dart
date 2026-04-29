import 'env_config.dart';

/// The active runtime environment.
enum AppEnvironment { dev, staging, uat, production }

/// Convenience [EnvConfig] subclass with the fields common to most DartAPI
/// projects (server port, debug mode, log level, database, JWT, CORS).
///
/// Extend this in your project to add application-specific fields:
///
/// ```dart
/// class MyAppConfig extends AppConfig {
///   MyAppConfig({super.environment});
///
///   String get stripeKey => env('STRIPE_KEY');
/// }
/// ```
///
/// All fields fall back to safe development defaults so the server can start
/// without any configuration.
class AppConfig extends EnvConfig {
  AppConfig({super.environment});

  // ── Environment ──────────────────────────────────────────────────────────

  /// The active [AppEnvironment] parsed from `APP_ENV`.
  AppEnvironment get appEnv => switch (env(
    'APP_ENV',
    defaultValue: 'dev',
  ).toLowerCase()) {
    'staging' => AppEnvironment.staging,
    'uat' => AppEnvironment.uat,
    'production' || 'prod' => AppEnvironment.production,
    _ => AppEnvironment.dev,
  };

  bool get isDev => appEnv == AppEnvironment.dev;
  bool get isStaging => appEnv == AppEnvironment.staging;
  bool get isUat => appEnv == AppEnvironment.uat;
  bool get isProduction => appEnv == AppEnvironment.production;

  // ── Server ───────────────────────────────────────────────────────────────

  int get port => envInt('PORT', defaultValue: 8080);

  /// Debug mode — defaults to `true` in dev, `false` elsewhere.
  bool get debug => envBool('DEBUG', defaultValue: isDev);

  /// Log level — `'debug'` in dev, `'info'` in staging/UAT, `'warn'` in production.
  String get logLevel => env(
    'LOG_LEVEL',
    defaultValue: switch (appEnv) {
      AppEnvironment.dev => 'debug',
      AppEnvironment.staging || AppEnvironment.uat => 'info',
      AppEnvironment.production => 'warn',
    },
  );

  // ── Database ─────────────────────────────────────────────────────────────

  /// When `false` the app starts with in-memory repositories — no DB required.
  bool get dbEnabled => envBool('DB_ENABLED', defaultValue: false);

  String get dbHost => env('DB_HOST', defaultValue: 'localhost');
  int get dbPort => envInt('DB_PORT', defaultValue: 5432);
  String get dbName => env('DB_NAME', defaultValue: 'app_${appEnv.name}');
  String get dbUser => env('DB_USER', defaultValue: 'postgres');
  String get dbPassword => env('DB_PASSWORD', defaultValue: 'yourpassword');
  int get dbPoolSize =>
      envInt('DB_POOL_SIZE', defaultValue: isProduction ? 20 : 5);

  // ── JWT ───────────────────────────────────────────────────────────────────

  String get jwtAccessSecret => env(
    'JWT_ACCESS_SECRET',
    defaultValue: 'dev-access-secret-not-for-production',
  );
  String get jwtRefreshSecret => env(
    'JWT_REFRESH_SECRET',
    defaultValue: 'dev-refresh-secret-not-for-production',
  );

  Duration get jwtAccessExpiry => Duration(
    minutes: envInt(
      'JWT_ACCESS_EXPIRY_MINUTES',
      defaultValue: isProduction ? 15 : 60,
    ),
  );

  Duration get jwtRefreshExpiry => Duration(
    days: envInt(
      'JWT_REFRESH_EXPIRY_DAYS',
      defaultValue: isProduction ? 7 : 30,
    ),
  );

  // ── CORS ──────────────────────────────────────────────────────────────────

  /// Allowed CORS origin — `'*'` in dev, must be set explicitly in production.
  String get corsOrigin => env('CORS_ORIGIN', defaultValue: isDev ? '*' : '');

  /// Prints a warning when production is running with development-placeholder secrets.
  void validateForProduction() {
    if (!isProduction) return;
    const devMarkers = ['dev-access-secret', 'dev-refresh-secret'];
    if (devMarkers.any(
      (m) => jwtAccessSecret.contains(m) || jwtRefreshSecret.contains(m),
    )) {
      // ignore: avoid_print
      print(
        '[WARNING] Production is running with development JWT secrets. '
        'Set JWT_ACCESS_SECRET and JWT_REFRESH_SECRET to strong random values.',
      );
    }
  }
}
