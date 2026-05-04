import 'package:shelf/shelf.dart';

/// Adds common security headers to every response.
///
/// Call `app.enableSecurityHeaders()` to apply with safe defaults, or pass
/// explicit values to tighten the policy for your application.
///
/// Headers added by default:
///
/// | Header | Default value |
/// |--------|--------------|
/// | `X-Frame-Options` | `DENY` — prevents click-jacking |
/// | `X-Content-Type-Options` | `nosniff` — stops MIME-sniffing |
/// | `Referrer-Policy` | `strict-origin-when-cross-origin` |
/// | `X-XSS-Protection` | `1; mode=block` |
/// | `Permissions-Policy` | blocks camera, mic, geolocation |
///
/// Optional (off by default — set to a non-null value to enable):
/// - `contentSecurityPolicy` — e.g. `"default-src 'self'"`.
/// - `strictTransportSecurity` — e.g. `"max-age=31536000; includeSubDomains"`.
///   Only send this over HTTPS.
///
/// ```dart
/// app.enableSecurityHeaders(
///   contentSecurityPolicy: "default-src 'self'; img-src *",
///   strictTransportSecurity: 'max-age=31536000; includeSubDomains',
/// );
/// ```
Middleware securityHeadersMiddleware({
  String xFrameOptions = 'DENY',
  String xContentTypeOptions = 'nosniff',
  String referrerPolicy = 'strict-origin-when-cross-origin',
  String xXssProtection = '1; mode=block',
  String permissionsPolicy = 'camera=(), microphone=(), geolocation=()',
  String? contentSecurityPolicy,
  String? strictTransportSecurity,
}) {
  final fixed = <String, String>{
    'x-frame-options': xFrameOptions,
    'x-content-type-options': xContentTypeOptions,
    'referrer-policy': referrerPolicy,
    'x-xss-protection': xXssProtection,
    'permissions-policy': permissionsPolicy,
    if (contentSecurityPolicy != null)
      'content-security-policy': contentSecurityPolicy,
    if (strictTransportSecurity != null)
      'strict-transport-security': strictTransportSecurity,
  };

  return (Handler inner) {
    return (Request request) async {
      final response = await inner(request);
      return response.change(headers: {...response.headers, ...fixed});
    };
  };
}
