/// Interface for tracking revoked JWT tokens.
///
/// Implement this to plug in any revocation backend (Redis, database, etc.).
/// The default [InMemoryTokenStore] is suitable for single-process servers;
/// replace it with a persistent store in production multi-instance deployments.
///
/// ```dart
/// final jwtService = JwtService(
///   ...,
///   tokenStore: InMemoryTokenStore(),
/// );
///
/// // In a logout handler:
/// await jwtService.revokeToken(accessToken);
/// ```
abstract class TokenStore {
  /// Marks the token identified by [jti] as revoked.
  Future<void> revoke(String jti);

  /// Returns `true` if the token identified by [jti] has been revoked.
  Future<bool> isRevoked(String jti);
}

/// An in-memory implementation of [TokenStore].
///
/// Revocations are lost on process restart. Suitable for development and
/// single-instance servers. Replace with a Redis or database-backed store
/// for production multi-instance deployments.
class InMemoryTokenStore implements TokenStore {
  final Set<String> _revoked = {};

  @override
  Future<void> revoke(String jti) async => _revoked.add(jti);

  @override
  Future<bool> isRevoked(String jti) async => _revoked.contains(jti);

  /// Removes all revoked entries — useful for testing.
  void clear() => _revoked.clear();
}
