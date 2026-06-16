import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'token_store.dart';

/// Service for generating and verifying JWTs.
///
/// Supports two key modes:
/// - **HS256** (symmetric, default): one shared secret per token type.
/// - **RS256** (asymmetric): an RSA key pair shared across services; use
///   [JwtService.rs256].
///
/// Optionally accepts a [TokenStore] to enable token revocation:
/// ```dart
/// final jwtService = JwtService(
///   accessTokenSecret: '...',
///   refreshTokenSecret: '...',
///   issuer: 'my-app',
///   audience: 'my-users',
///   tokenStore: InMemoryTokenStore(),
/// );
/// ```
class JwtService {
  // HS256 secrets — null when using RS256.
  final String? accessTokenSecret;
  final String? refreshTokenSecret;

  // RS256 PEM strings — null when using HS256.
  final String? privateKeyPem;
  final String? publicKeyPem;

  final String issuer;
  final String audience;
  final Duration accessTokenExpiry;
  final Duration refreshTokenExpiry;
  final JWTAlgorithm algorithm;

  /// Optional revocation store. When set, [verifyAccessToken] and
  /// [verifyRefreshToken] will reject tokens that have been revoked via
  /// [revokeToken].
  final TokenStore? tokenStore;

  /// Creates a [JwtService] using HMAC-SHA256 (HS256) symmetric keys.
  JwtService({
    required String accessTokenSecret,
    required String refreshTokenSecret,
    required this.issuer,
    required this.audience,
    this.accessTokenExpiry = const Duration(hours: 1),
    this.refreshTokenExpiry = const Duration(days: 7),
    this.algorithm = JWTAlgorithm.HS256,
    this.tokenStore,
  }) : accessTokenSecret = accessTokenSecret, // ignore: prefer_initializing_formals
       refreshTokenSecret = refreshTokenSecret, // ignore: prefer_initializing_formals
       privateKeyPem = null,
       publicKeyPem = null;

  /// Creates a [JwtService] using RS256 (RSA-SHA256) asymmetric keys.
  ///
  /// [privateKeyPem] is used to sign tokens (kept server-side only).
  /// [publicKeyPem] is used to verify tokens (can be shared with other services).
  ///
  /// Both access and refresh tokens share the same key pair.
  ///
  /// ```dart
  /// final jwt = JwtService.rs256(
  ///   privateKeyPem: File('private.pem').readAsStringSync(),
  ///   publicKeyPem:  File('public.pem').readAsStringSync(),
  ///   issuer: 'my-app',
  ///   audience: 'my-users',
  /// );
  /// ```
  JwtService.rs256({
    required String privateKeyPem,
    required String publicKeyPem,
    required this.issuer,
    required this.audience,
    this.accessTokenExpiry = const Duration(hours: 1),
    this.refreshTokenExpiry = const Duration(days: 7),
    this.tokenStore,
  }) : algorithm = JWTAlgorithm.RS256,
       privateKeyPem = privateKeyPem, // ignore: prefer_initializing_formals
       publicKeyPem = publicKeyPem, // ignore: prefer_initializing_formals
       accessTokenSecret = null,
       refreshTokenSecret = null;

  // ---------------------------------------------------------------------------
  // Internal key helpers
  // ---------------------------------------------------------------------------

  JWTKey get _signKey =>
      privateKeyPem != null
          ? RSAPrivateKey(privateKeyPem!)
          : SecretKey(accessTokenSecret!);

  JWTKey get _accessVerifyKey =>
      publicKeyPem != null
          ? RSAPublicKey(publicKeyPem!)
          : SecretKey(accessTokenSecret!);

  JWTKey get _refreshSignKey =>
      privateKeyPem != null
          ? RSAPrivateKey(privateKeyPem!)
          : SecretKey(refreshTokenSecret!);

  JWTKey get _refreshVerifyKey =>
      publicKeyPem != null
          ? RSAPublicKey(publicKeyPem!)
          : SecretKey(refreshTokenSecret!);

  // ---------------------------------------------------------------------------
  // Token generation
  // ---------------------------------------------------------------------------

  /// Generates a signed access token containing the provided [claims].
  ///
  /// The token includes standard claims (`iss`, `aud`, `iat`, `exp`, `jti`,
  /// `sid`, `type`) merged with any additional [claims] you provide.
  ///
  /// `sid` is a session identifier shared by an access token and the refresh
  /// token derived from it (see [generateRefreshToken]). Revoking a token via
  /// [revokeToken] revokes the whole session, so logging out with an access
  /// token also invalidates its companion refresh token. Pass an explicit
  /// `sid` in [claims] to attach a new token to an existing session.
  String generateAccessToken({required Map<String, dynamic> claims}) {
    final payload = {
      'jti': _generateUniqueTokenId(),
      'sid': _generateUniqueTokenId(),
      'iss': issuer,
      'aud': audience,
      'type': 'access',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp':
          DateTime.now().add(accessTokenExpiry).millisecondsSinceEpoch ~/ 1000,
      ...claims,
    };
    return JWT(payload).sign(_signKey, algorithm: algorithm);
  }

  /// Generates a signed refresh token derived from a valid [accessToken].
  ///
  /// Throws if [accessToken] cannot be verified.
  String generateRefreshToken({required String accessToken}) {
    final oldPayload = _verifyAccessTokenSync(accessToken);
    if (oldPayload == null) {
      throw Exception('Invalid access token, cannot generate refresh token');
    }
    final newPayload = {
      ...oldPayload,
      'type': 'refresh',
      'jti': _generateUniqueTokenId(),
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp':
          DateTime.now().add(refreshTokenExpiry).millisecondsSinceEpoch ~/ 1000,
    };
    return JWT(newPayload).sign(_refreshSignKey, algorithm: algorithm);
  }

  // ---------------------------------------------------------------------------
  // Token verification
  // ---------------------------------------------------------------------------

  /// Verifies an access token and returns its payload, or `null` if invalid.
  ///
  /// Returns `null` when the token is:
  /// - Malformed or has an invalid signature
  /// - Expired
  /// - Issued by the wrong issuer or for the wrong audience
  /// - Revoked (when a [tokenStore] is configured)
  Future<Map<String, dynamic>?> verifyAccessToken(String token) async {
    final payload = _verifyAccessTokenSync(token);
    if (payload == null) return null;
    if (await _isRevoked(payload)) return null;
    return payload;
  }

  /// Verifies a refresh token and returns its payload, or `null` if invalid.
  ///
  /// When a [tokenStore] is configured, the token is automatically revoked
  /// after successful verification (rotation). Rotation revokes only this
  /// single refresh token (by `jti`), so a refresh token cannot be used more
  /// than once while the rest of the session — including the access token and
  /// any newly issued tokens — stays valid.
  Future<Map<String, dynamic>?> verifyRefreshToken(String token) async {
    final payload = _verifyRefreshTokenSync(token);
    if (payload == null) return null;
    if (await _isRevoked(payload)) return null;
    final jti = payload['jti'] as String?;
    if (tokenStore != null && jti != null) {
      await tokenStore!.revoke(jti, _expiryOf(payload));
    }
    return payload;
  }

  /// Revokes [token] so future verification calls return `null`.
  ///
  /// Revokes the whole session identified by the token's `sid` (falling back
  /// to its `jti` for tokens minted without one), so logging out with an
  /// access token also invalidates its companion refresh token. The revocation
  /// record is kept until the longest-lived token in the session could expire.
  ///
  /// Has no effect if no [tokenStore] was configured.
  Future<void> revokeToken(String token) async {
    if (tokenStore == null) return;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final sid = payload['sid'] as String?;
      final jti = payload['jti'] as String?;
      if (sid != null) {
        // A session can outlive an individual access token, so keep the
        // revocation until the longest-lived token (the refresh token) dies.
        await tokenStore!.revoke(
          sid,
          DateTime.now().add(refreshTokenExpiry),
        );
      } else if (jti != null) {
        await tokenStore!.revoke(jti, _expiryOf(payload));
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if [payload] is revoked either as an individual token
  /// (by `jti`) or as part of a revoked session (by `sid`).
  Future<bool> _isRevoked(Map<String, dynamic> payload) async {
    if (tokenStore == null) return false;
    final jti = payload['jti'];
    if (jti is String && await tokenStore!.isRevoked(jti)) return true;
    final sid = payload['sid'];
    if (sid is String && await tokenStore!.isRevoked(sid)) return true;
    return false;
  }

  /// The instant [payload] expires, derived from its `exp` claim. Falls back to
  /// the configured refresh expiry when `exp` is missing or malformed.
  DateTime _expiryOf(Map<String, dynamic> payload) {
    final exp = payload['exp'];
    if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().add(refreshTokenExpiry);
  }

  Map<String, dynamic>? _verifyAccessTokenSync(String token) {
    try {
      final jwt = JWT.verify(token, _accessVerifyKey);
      final payload = jwt.payload as Map<String, dynamic>;
      if (!_isValidPayload(payload)) return null;
      if (payload['iss'] != issuer) return null;
      if (payload['aud'] != audience) return null;
      if (payload['type'] != 'access') return null;
      if (DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as int) * 1000,
      ).isBefore(DateTime.now())) {
        return null;
      }
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _verifyRefreshTokenSync(String token) {
    try {
      final jwt = JWT.verify(token, _refreshVerifyKey);
      final payload = jwt.payload as Map<String, dynamic>;
      if (!_isValidPayload(payload)) return null;
      if (payload['iss'] != issuer) return null;
      if (payload['aud'] != audience) return null;
      if (payload['type'] != 'refresh') return null;
      if (DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as int) * 1000,
      ).isBefore(DateTime.now())) {
        return null;
      }
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return null;
    }
  }

  bool _isValidPayload(Map<String, dynamic> payload) {
    const required = ['sub', 'iat', 'exp', 'jti', 'iss', 'aud', 'type'];
    if (!required.every(
      (claim) => payload.containsKey(claim) && payload[claim] != null,
    )) {
      return false;
    }
    return payload['sub'] is String &&
        payload['jti'] is String &&
        payload['iss'] is String &&
        payload['aud'] is String &&
        payload['type'] is String &&
        payload['iat'] is int &&
        payload['exp'] is int;
  }

  String _generateUniqueTokenId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes);
  }
}
