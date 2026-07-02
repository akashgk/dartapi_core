import 'dart:io';

import 'package:shelf/shelf.dart';

/// Returns the client IP address for [request].
///
/// By default this is the IP of the TCP connection
/// (`shelf.io.connection_info`), which cannot be spoofed.
///
/// Set [trustProxy] to `true` **only when the server sits behind a trusted
/// reverse proxy or load balancer** — then the first entry of
/// `X-Forwarded-For` (or `X-Real-IP`) is used instead, so clients are
/// identified by their real address rather than the proxy's. Never enable
/// it for a directly exposed server: those headers are client-controlled
/// and would let anyone impersonate an arbitrary IP.
///
/// Returns `'unknown'` when no connection info is available (e.g. an
/// in-process test client) and no trusted header is present.
String clientIp(Request request, {bool trustProxy = false}) {
  if (trustProxy) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.trim().isNotEmpty) {
      return realIp.trim();
    }
  }
  final connectionInfo =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return connectionInfo?.remoteAddress.address ?? 'unknown';
}
