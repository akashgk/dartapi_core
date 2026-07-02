// The HS256 constructor takes required non-nullable secrets but stores them
// in nullable fields (null when using RS256), so initializing formals can't
// be used there.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'token_store.dart';

/// A matched access/refresh token pair issued together by
/// [JwtService.generateTokenPair].
class TokenPair {
  final String accessToken;
  final String refreshToken;

  const TokenPair({required this.accessToken, required this.refreshToken});
}

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
///
/// // Login:
/// final pair = jwtService.generateTokenPair(claims: {'sub': user.id});
///
/// // Logout:
/// await jwtService.revokeToken(pair.accessToken);
/// await jwtService.revokeToken(pair.refreshToken);
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

  /// Called when an already-rotated refresh token is presented again.
  ///
  /// Under refresh-token rotation, each refresh token is single-use. A second
  /// use of the same token is the classic signal that the token was stolen
  /// (either the attacker or the legitimate user used it first — the other
  /// party's attempt trips this). Per the OAuth 2.0 Security BCP, respond by
  /// revoking the whole session, e.g. force the user to log in again:
  ///
  /// ```dart
  /// JwtService(
  ///   ...,
  ///   tokenStore: store,
  ///   onRefreshTokenReuse: (payload) async {
  ///     await sessions.terminateAllForUser(payload['sub'] as String);
  ///   },
  /// )
  /// ```
  ///
  /// Only fires when a [tokenStore] is configured. The reused token is still
  /// rejected (verification returns `null`) regardless of this callback.
  final Future<void> Function(Map<String, dynamic> payload)?
  onRefreshTokenReuse;

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
    this.onRefreshTokenReuse,
  }) : accessTokenSecret = accessTokenSecret,
       refreshTokenSecret = refreshTokenSecret,
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
    this.onRefreshTokenReuse,
  }) : algorithm = JWTAlgorithm.RS256,
       privateKeyPem = privateKeyPem,
       publicKeyPem = publicKeyPem,
       accessTokenSecret = null,
       refreshTokenSecret = null;

  // ---------------------------------------------------------------------------
  // Internal key helpers
  // ---------------------------------------------------------------------------

  // Keys are cached so RSA PEM strings are parsed once, not on every call.
  late final JWTKey _signKey =
      privateKeyPem != null
          ? RSAPrivateKey(privateKeyPem!)
          : SecretKey(accessTokenSecret!);

  late final JWTKey _accessVerifyKey =
      publicKeyPem != null
          ? RSAPublicKey(publicKeyPem!)
          : SecretKey(accessTokenSecret!);

  late final JWTKey _refreshSignKey =
      privateKeyPem != null
          ? RSAPrivateKey(privateKeyPem!)
          : SecretKey(refreshTokenSecret!);

  late final JWTKey _refreshVerifyKey =
      publicKeyPem != null
          ? RSAPublicKey(publicKeyPem!)
          : SecretKey(refreshTokenSecret!);

  // ---------------------------------------------------------------------------
  // Token generation
  // ---------------------------------------------------------------------------

  /// Generates a signed access token containing the provided [claims].
  ///
  /// The token includes standard claims (`iss`, `aud`, `iat`, `exp`, `jti`,
  /// `type`) merged with any additional [claims] you provide.
  String generateAccessToken({required Map<String, dynamic> claims}) =>
      _generateToken(type: 'access', expiry: accessTokenExpiry, claims: claims);

  /// Generates a matched access/refresh [TokenPair] from [claims].
  ///
  /// This is the recommended way to issue tokens at login and on refresh —
  /// both tokens are minted directly from the claims, so a refresh token can
  /// never be derived from a (possibly stolen) access token.
  ///
  /// ```dart
  /// // Login handler:
  /// final pair = jwtService.generateTokenPair(
  ///   claims: {'sub': user.id, 'email': user.email},
  /// );
  ///
  /// // Refresh handler:
  /// final payload = await jwtService.verifyRefreshToken(oldRefreshToken);
  /// if (payload == null) throw ApiException(401, 'Invalid refresh token');
  /// final pair = jwtService.generateTokenPair(
  ///   claims: {'sub': payload['sub'], 'email': payload['email']},
  /// );
  /// ```
  TokenPair generateTokenPair({required Map<String, dynamic> claims}) =>
      TokenPair(
        accessToken: generateAccessToken(claims: claims),
        refreshToken: _generateToken(
          type: 'refresh',
          expiry: refreshTokenExpiry,
          claims: claims,
          key: _refreshSignKey,
        ),
      );

  String _generateToken({
    required String type,
    required Duration expiry,
    required Map<String, dynamic> claims,
    JWTKey? key,
  }) {
    final now = DateTime.now();
    // Standard claims come last so caller-supplied claims cannot override
    // token identity or lifetime.
    final payload = {
      ...claims,
      'jti': _generateUniqueTokenId(),
      'iss': issuer,
      'aud': audience,
      'type': type,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(expiry).millisecondsSinceEpoch ~/ 1000,
    };
    return JWT(payload).sign(key ?? _signKey, algorithm: algorithm);
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
    if (tokenStore != null &&
        await tokenStore!.isRevoked(payload['jti'] as String)) {
      return null;
    }
    return payload;
  }

  /// Verifies a refresh token and returns its payload, or `null` if invalid.
  ///
  /// When a [tokenStore] is configured, the token is rotated: it is revoked
  /// atomically as part of verification, so each refresh token can be used
  /// exactly once — even under concurrent requests, only one caller receives
  /// the payload.
  ///
  /// Presenting an already-rotated token is rejected and additionally fires
  /// [onRefreshTokenReuse], since reuse indicates the token may be stolen.
  Future<Map<String, dynamic>?> verifyRefreshToken(String token) async {
    final payload = _verifyRefreshTokenSync(token);
    if (payload == null) return null;
    final store = tokenStore;
    if (store != null) {
      final rotated = await store.revokeIfActive(
        payload['jti'] as String,
        ttl: _remainingTtl(payload),
      );
      if (!rotated) {
        // Second use of a single-use token — possible theft. Reject it and
        // let the application revoke the whole session.
        await onRefreshTokenReuse?.call(payload);
        return null;
      }
    }
    return payload;
  }

  /// Verifies [token]'s signature and revokes it so future verification
  /// calls return `null`. Accepts both access and refresh tokens — call it
  /// with each of them in a logout handler.
  ///
  /// Returns `true` when the token was valid and is now revoked. Returns
  /// `false` — without touching the store — when no [tokenStore] is
  /// configured or the token is malformed, expired, or fails signature
  /// verification. Requiring a valid signature prevents an attacker from
  /// revoking other users' sessions with forged tokens.
  Future<bool> revokeToken(String token) async {
    final store = tokenStore;
    if (store == null) return false;
    final payload =
        _verifyAccessTokenSync(token) ?? _verifyRefreshTokenSync(token);
    if (payload == null) return false;
    await store.revoke(payload['jti'] as String, ttl: _remainingTtl(payload));
    return true;
  }

  /// Time until the token's `exp` — how long a revocation entry must live.
  /// Includes a one-minute grace margin to absorb clock skew.
  Duration? _remainingTtl(Map<String, dynamic> payload) {
    final exp = payload['exp'];
    if (exp is! int) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      exp * 1000,
    ).difference(DateTime.now());
    return (remaining.isNegative ? Duration.zero : remaining) +
        const Duration(minutes: 1);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

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

  static final Random _random = Random.secure();

  String _generateUniqueTokenId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
