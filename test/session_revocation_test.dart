import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

JwtService _service({
  TokenStore? store,
  Future<void> Function(Map<String, dynamic>)? onReuse,
}) => JwtService(
  accessTokenSecret: 'access-secret-for-tests-only',
  refreshTokenSecret: 'refresh-secret-for-tests-only',
  issuer: 'test-issuer',
  audience: 'test-audience',
  tokenStore: store,
  onRefreshTokenReuse: onReuse,
);

void main() {
  group('JwtService.revokeAllForUser', () {
    test('invalidates outstanding access tokens for the subject', () async {
      final svc = _service(store: InMemoryTokenStore());
      final pair = svc.generateTokenPair(claims: {'sub': 'u1'});
      expect(await svc.verifyAccessToken(pair.accessToken), isNotNull);

      expect(await svc.revokeAllForUser('u1'), isTrue);
      expect(await svc.verifyAccessToken(pair.accessToken), isNull);
    });

    test('invalidates outstanding refresh tokens without firing the '
        'reuse callback', () async {
      var reuseFired = false;
      final svc = _service(
        store: InMemoryTokenStore(),
        onReuse: (_) async => reuseFired = true,
      );
      final pair = svc.generateTokenPair(claims: {'sub': 'u1'});

      await svc.revokeAllForUser('u1');
      expect(await svc.verifyRefreshToken(pair.refreshToken), isNull);
      expect(reuseFired, isFalse);
    });

    test('tokens issued after the revocation verify normally', () async {
      final svc = _service(store: InMemoryTokenStore());
      svc.generateTokenPair(claims: {'sub': 'u1'});
      await svc.revokeAllForUser('u1');

      // iat has second granularity; a login in the *next* second is a new
      // session and must not be affected.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final fresh = svc.generateTokenPair(claims: {'sub': 'u1'});
      expect(await svc.verifyAccessToken(fresh.accessToken), isNotNull);
      expect(await svc.verifyRefreshToken(fresh.refreshToken), isNotNull);
    });

    test('does not affect other subjects', () async {
      final svc = _service(store: InMemoryTokenStore());
      final alice = svc.generateTokenPair(claims: {'sub': 'alice'});
      final bob = svc.generateTokenPair(claims: {'sub': 'bob'});

      await svc.revokeAllForUser('alice');
      expect(await svc.verifyAccessToken(alice.accessToken), isNull);
      expect(await svc.verifyAccessToken(bob.accessToken), isNotNull);
    });

    test('returns false when no tokenStore is configured', () async {
      expect(await _service().revokeAllForUser('u1'), isFalse);
    });

    test(
      'refresh-token reuse + revokeAllForUser kills the stolen session',
      () async {
        late JwtService svc;
        svc = _service(
          store: InMemoryTokenStore(),
          onReuse: (payload) async {
            final sub = payload['sub'];
            if (sub is String) await svc.revokeAllForUser(sub);
          },
        );

        // Victim logs in; attacker steals and uses the refresh token first.
        final stolen = svc.generateTokenPair(claims: {'sub': 'victim'});
        final attackerPayload = await svc.verifyRefreshToken(
          stolen.refreshToken,
        );
        expect(attackerPayload, isNotNull);
        final attackerPair = svc.generateTokenPair(claims: {'sub': 'victim'});

        // Victim retries the same refresh token → reuse detected → whole
        // session revoked, including the attacker's freshly minted tokens.
        expect(await svc.verifyRefreshToken(stolen.refreshToken), isNull);
        expect(await svc.verifyAccessToken(attackerPair.accessToken), isNull);
        expect(await svc.verifyRefreshToken(attackerPair.refreshToken), isNull);
      },
    );
  });

  group('TokenStore subject revocation entries', () {
    test('expire after their ttl', () async {
      final store = InMemoryTokenStore();
      await store.revokeSubject(
        'u1',
        cutoffEpochSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ttl: const Duration(milliseconds: 50),
      );
      expect(await store.subjectRevocationCutoff('u1'), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await store.subjectRevocationCutoff('u1'), isNull);
    });

    test('unknown subject has no cutoff', () async {
      expect(await InMemoryTokenStore().subjectRevocationCutoff('x'), isNull);
    });
  });
}
