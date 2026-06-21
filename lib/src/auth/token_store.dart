/// Interface for tracking revoked JWT identifiers.
///
/// Implement this to plug in any revocation backend (Redis, database, etc.).
/// The default [InMemoryTokenStore] is suitable for single-process servers;
/// replace it with a persistent store in production multi-instance deployments.
///
/// A revocation entry is keyed by a string identifier — either a token's `jti`
/// (a single token) or a session's `sid` (a whole access + refresh family) —
/// and carries the moment after which the entry is no longer meaningful.
/// Because a JWT is rejected on its own once it has expired, the revocation
/// record only needs to live until [expiresAt]; backends should drop it
/// afterwards so the denylist does not grow without bound. Redis-style stores
/// can map [expiresAt] directly onto a key TTL.
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
  /// Marks [id] as revoked until [expiresAt].
  ///
  /// [id] is a token `jti` or a session `sid`. Implementations should expire
  /// the entry at [expiresAt] (e.g. via a TTL) since the underlying token is
  /// invalid past that point regardless.
  Future<void> revoke(String id, DateTime expiresAt);

  /// Returns `true` if [id] is currently revoked.
  ///
  /// Entries whose `expiresAt` has already passed must be treated as not
  /// revoked (and may be discarded).
  Future<bool> isRevoked(String id);
}

/// An in-memory implementation of [TokenStore].
///
/// Revocations are lost on process restart. Suitable for development and
/// single-instance servers. Replace with a Redis or database-backed store
/// for production multi-instance deployments.
///
/// Entries are pruned automatically once their expiry passes, so the denylist
/// only ever holds identifiers for tokens that are still otherwise valid.
class InMemoryTokenStore implements TokenStore {
  /// Maps a revoked identifier to the instant after which it can be forgotten.
  final Map<String, DateTime> _revoked = {};

  @override
  Future<void> revoke(String id, DateTime expiresAt) async {
    _pruneExpired();
    // Keep the latest expiry if the same id is revoked more than once.
    final existing = _revoked[id];
    if (existing == null || expiresAt.isAfter(existing)) {
      _revoked[id] = expiresAt;
    }
  }

  @override
  Future<bool> isRevoked(String id) async {
    final expiresAt = _revoked[id];
    if (expiresAt == null) return false;
    if (!expiresAt.isAfter(DateTime.now())) {
      _revoked.remove(id);
      return false;
    }
    return true;
  }

  /// Drops every entry whose expiry has already passed.
  void _pruneExpired() {
    final now = DateTime.now();
    _revoked.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  /// Removes all revoked entries — useful for testing.
  void clear() => _revoked.clear();
}
