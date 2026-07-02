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
  ///
  /// [ttl] is how long the revocation entry must be retained — the caller
  /// passes the time remaining until the token's own `exp`, after which the
  /// token is rejected anyway and the entry can be dropped. Backends should
  /// use it to expire entries (e.g. Redis `SET key 1 EX ttl`) so the store
  /// does not grow forever. A `null` ttl means "keep indefinitely".
  Future<void> revoke(String jti, {Duration? ttl});

  /// Returns `true` if the token identified by [jti] has been revoked.
  Future<bool> isRevoked(String jti);

  /// Atomically revokes [jti] and returns `true` if this call performed the
  /// revocation (the token was still active), or `false` if it was already
  /// revoked.
  ///
  /// Used for refresh-token rotation, where exactly one concurrent use of a
  /// token may succeed. The default implementation is check-then-revoke,
  /// which is **not** atomic across processes — distributed backends should
  /// override it with an atomic operation (e.g. Redis `SET key 1 NX EX ttl`,
  /// or an `INSERT ... ON CONFLICT DO NOTHING` in SQL).
  Future<bool> revokeIfActive(String jti, {Duration? ttl}) async {
    if (await isRevoked(jti)) return false;
    await revoke(jti, ttl: ttl);
    return true;
  }
}

/// An in-memory implementation of [TokenStore].
///
/// Revocations are lost on process restart. Suitable for development and
/// single-instance servers. Replace with a Redis or database-backed store
/// for production multi-instance deployments.
///
/// Entries revoked with a [Duration] ttl are pruned automatically once the
/// ttl has passed, so memory usage is bounded by the number of tokens
/// revoked within one token lifetime.
class InMemoryTokenStore extends TokenStore {
  /// jti → moment the entry itself may be discarded (`null` = keep forever).
  final Map<String, DateTime?> _revoked = {};

  /// Entries checked per call while pruning expired revocations.
  static const _pruneBatch = 64;

  @override
  Future<void> revoke(String jti, {Duration? ttl}) async {
    _prune();
    _revoked[jti] = ttl == null ? null : DateTime.now().add(ttl);
  }

  @override
  Future<bool> isRevoked(String jti) async => _isRevokedSync(jti);

  @override
  Future<bool> revokeIfActive(String jti, {Duration? ttl}) async {
    // Synchronous check-and-set — atomic within the isolate.
    if (_isRevokedSync(jti)) return false;
    _revoked[jti] = ttl == null ? null : DateTime.now().add(ttl);
    _prune();
    return true;
  }

  bool _isRevokedSync(String jti) {
    final expiresAt = _revoked[jti];
    if (!_revoked.containsKey(jti)) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _revoked.remove(jti);
      return false;
    }
    return true;
  }

  /// Incrementally drops expired entries so the map stays bounded without
  /// a timer or a full scan on every call.
  void _prune() {
    if (_revoked.length <= _pruneBatch) return;
    final now = DateTime.now();
    var scanned = 0;
    final expired = <String>[];
    for (final entry in _revoked.entries) {
      if (scanned++ >= _pruneBatch) break;
      final expiresAt = entry.value;
      if (expiresAt != null && now.isAfter(expiresAt)) expired.add(entry.key);
    }
    expired.forEach(_revoked.remove);
  }

  /// Removes all revoked entries — useful for testing.
  void clear() => _revoked.clear();
}
