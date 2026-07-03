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

  // ── Subject-level (whole-session) revocation ───────────────────────────────

  /// `sub` → (revocation cutoff in epoch seconds, entry expiry).
  final Map<String, (int, DateTime?)> _subjectCutoffs = {};

  /// Revokes **every token of [sub] issued at or before [cutoffEpochSeconds]**
  /// — the "log this user out everywhere" operation, typically triggered by
  /// refresh-token reuse (theft signal) or an account compromise.
  ///
  /// [ttl] is how long the entry must be retained — pass the refresh-token
  /// lifetime, after which every affected token has expired on its own.
  ///
  /// The default implementation stores the cutoff in process memory —
  /// correct for a single process only. Distributed backends should override
  /// this and [subjectRevocationCutoff] with a shared store (e.g. Redis
  /// `SET sub:<sub> <cutoff> EX <ttl>`).
  Future<void> revokeSubject(
    String sub, {
    required int cutoffEpochSeconds,
    Duration? ttl,
  }) async {
    _subjectCutoffs[sub] = (
      cutoffEpochSeconds,
      ttl == null ? null : DateTime.now().add(ttl),
    );
  }

  /// Returns the epoch-seconds cutoff at or before which [sub]'s tokens are
  /// revoked, or `null` when the subject has no active revocation.
  Future<int?> subjectRevocationCutoff(String sub) async {
    final entry = _subjectCutoffs[sub];
    if (entry == null) return null;
    final (cutoff, expiresAt) = entry;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _subjectCutoffs.remove(sub);
      return null;
    }
    return cutoff;
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
