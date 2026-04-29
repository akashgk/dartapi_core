import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test RSA key pair (2048-bit, NOT for production use)
// ─────────────────────────────────────────────────────────────────────────────
const _rsaPrivateKey = '''-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC/eo6D0o33u4sK
j450oXMwmFajpRUyYUrW/TpSPMZ+oB8tgfnrYUJc6C1k3DYH0qfN8ubq7RQUyXq4
GY8q3qmEuct9HYd6rI12cYm4+KQwVs2t2vx2uVHeoIwk4nD8V5aaNigo+MGLjDd9
JkWaONB9Ox1jpt0z7h0mnDQVd5x0Zevo0hIn22Hpa3YuIPy9wa5IAulfQKOJoV5u
LmjnROqnNYHvlmW+QOXBQU/Ozf5AGuSE3rXj/3bmtBnzeBqYWlGdXpJEGLlNUoGU
xiCXSbuHmUVeMUtQU8NL99S5LYzVDxs5+RPhpCknJKBnUQkn/70TGZrLKXhYfg0A
jIIMo3r1AgMBAAECggEAGJEoZNhod5773WyCygsG5Pa+svtUx2R9Pi06RN/gVdHE
fkm9X4pYgeQWIukwE3vfJMjkAMNPPsWE9cbtvAHafRl7dr+JqN8nvUke8vkP09Xn
SMWee7sWOnqd0IOvHGk+fOWy7GLSLk3ctrVo27srYM3rXORFYErOOaxz8Ecq7zIF
Tfv/tr1zhl3WR5VU1PcPrx/P1VQy30JZ26B/pB6RS6prUXfYQb4WQ55HPWk0xdZ1
AO3H0XsxI/dxhNzZXIjp0dgFLiO5F9tOI3T81vr8cbquMFhvYfV8+k6RMbmfVQkg
B3Ss5Xqer56dPhCTQ6F36lfTiLi42uwrn+WASr3ANwKBgQD4L3PPCPukA/0+Ktw6
VnoK5loyaDxjIntlN8eIlAas2E/BgUNWmz/2YbX95P3jURUE1178PgJiNpEMZ1Vd
ru7dutPXfb5RO2uvXkXypmagylD+I3rIK8CFsknxTEnp+O4Po12gPDEe0FmNlVav
EiDJRxEw+7VuG28Acm6ypk3vDwKBgQDFggJfOsmRyVGFAvX0P6x0HAAIif2foyok
FI0L70EPauSgLXC8jQy3mzNeGdeW1G/nlO+iiEnvvNxMXLSvr9Ls/SQNQv/evlzT
3TsisT8RKGKpYmzXvRR7sy0HPEYEyFsp3SCzUW9SLs8wFogBFlnX/aqs/JSs0+Jq
KE2iVUx1uwKBgQCDLCFbVXYas/kO+Hw5YSdTx3f4mFsCUmFBl/+f0gzNIe7VaUp7
5cYipHYZ4QPHNz2St3n+e4+q9QgotBzMTP72th3tEQqbyHob0AnMO+KWLRgtmfb1
ARraDudB335ZaTX5kfCUFfwoOxp52GpeUYh+mU8ewoqbzWgXpmOXjIo4RQKBgQCr
B5TkP/TysIFODC1Nz6GXffOtcUjV5yYDzmQBVLJjFm5aIl9Ad2fuyo+lyfz9mII6
6KbGePyFhGbEHXc9t6SQIfkJHt6RVQjvUeD2fsQdKHqfMSMNgqdtItA4NsJvO8xt
qRW7Eiay5OP3QVuOjXtJZVlZqPNZ4bVrtfDcRL8MJwKBgQDcAm8zo+8Q5dpV4fO0
E3Jxh1sH9Rum3QWBwjzzqM41Z1J5/ZBiUneBEOgl7VXRar8RkOtwcR76uBBO6KE+
3NG5i25FwFQJ4+NZQWP7G9QLbLMlHYWmi48ilZ1APxl8LI8Q67G7dT/Z0cgvN8+S
8cx6AuCCtyMC28/yMCUpS/Y7oA==
-----END PRIVATE KEY-----''';

const _rsaPublicKey = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv3qOg9KN97uLCo+OdKFz
MJhWo6UVMmFK1v06UjzGfqAfLYH562FCXOgtZNw2B9KnzfLm6u0UFMl6uBmPKt6p
hLnLfR2HeqyNdnGJuPikMFbNrdr8drlR3qCMJOJw/FeWmjYoKPjBi4w3fSZFmjjQ
fTsdY6bdM+4dJpw0FXecdGXr6NISJ9th6Wt2LiD8vcGuSALpX0CjiaFebi5o50Tq
pzWB75ZlvkDlwUFPzs3+QBrkhN614/925rQZ83gamFpRnV6SRBi5TVKBlMYgl0m7
h5lFXjFLUFPDS/fUuS2M1Q8bOfkT4aQpJySgZ1EJJ/+9Exmayyl4WH4NAIyCDKN6
9QIDAQAB
-----END PUBLIC KEY-----''';

const _wrongPublicKey = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyLlNE1CVKoepSs9X9GRC
x6RTNi27YkMGPKwsV2qP6Pb5X8K0W0RZeNqBMfxPxCDiMoN/3FijkRNvXvEACAVi
1XjBhiJuX1jIJT1oVMl8gbXBwjnEFHSuLnS1HFgqiFEE8RIbDmBVBL8vvGfaFo8g
L10fMo2W3FLQ0b7mJFH9g4OqFcmEJL13DKSxV3a0UeAFPBCIYGJ3+VeJQhWklvqS
h2J2aPi4OQpYNWvdG/yDI07Hh/6DynJz4RqnUi0yYb/LGN/VEpPZFbHVeSvGBGe4
jJGZS4jQ6+c1dASRqQW6ggP/EvtmDp3vkLGBRE65pz3LFI7T4YXJGhfb0qO6XQID
AQAB
-----END PUBLIC KEY-----''';

// ─────────────────────────────────────────────────────────────────────────────
// Shared constants
// ─────────────────────────────────────────────────────────────────────────────
const _accessSecret = 'test-access-secret';
const _refreshSecret = 'test-refresh-secret';
const _issuer = 'dartapi-test';
const _audience = 'dartapi-users';

JwtService _hs256({TokenStore? store}) => JwtService(
  accessTokenSecret: _accessSecret,
  refreshTokenSecret: _refreshSecret,
  issuer: _issuer,
  audience: _audience,
  tokenStore: store,
);

Request _request(String path, {Map<String, String>? headers}) =>
    Request('GET', Uri.parse('http://localhost$path'), headers: headers ?? {});

// ─────────────────────────────────────────────────────────────────────────────
// TokenStore
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('InMemoryTokenStore', () {
    late InMemoryTokenStore store;

    setUp(() => store = InMemoryTokenStore());

    test('isRevoked returns false for unknown jti', () async {
      expect(await store.isRevoked('unknown'), isFalse);
    });

    test('revoke marks jti as revoked', () async {
      await store.revoke('jti-1');
      expect(await store.isRevoked('jti-1'), isTrue);
    });

    test('revoking one jti does not affect others', () async {
      await store.revoke('jti-1');
      expect(await store.isRevoked('jti-2'), isFalse);
    });

    test('revoking same jti twice is idempotent', () async {
      await store.revoke('jti-1');
      await store.revoke('jti-1');
      expect(await store.isRevoked('jti-1'), isTrue);
    });

    test('clear removes all revoked entries', () async {
      await store.revoke('jti-1');
      await store.revoke('jti-2');
      store.clear();
      expect(await store.isRevoked('jti-1'), isFalse);
      expect(await store.isRevoked('jti-2'), isFalse);
    });

    test('multiple jtis are tracked independently', () async {
      await store.revoke('a');
      await store.revoke('b');
      await store.revoke('c');
      expect(await store.isRevoked('a'), isTrue);
      expect(await store.isRevoked('b'), isTrue);
      expect(await store.isRevoked('c'), isTrue);
      expect(await store.isRevoked('d'), isFalse);
    });

    test('implements TokenStore interface', () {
      expect(store, isA<TokenStore>());
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // JwtService — HS256
  // ─────────────────────────────────────────────────────────────────────────

  group('JwtService (HS256)', () {
    late JwtService svc;
    setUp(() => svc = _hs256());

    group('access token generation', () {
      test('returns a non-empty JWT string', () {
        final token = svc.generateAccessToken(claims: {'sub': 'u1'});
        expect(token, isNotEmpty);
        expect(token.split('.').length, 3); // header.payload.sig
      });

      test('payload contains standard claims', () async {
        final token = svc.generateAccessToken(claims: {'sub': 'u1'});
        final payload = await svc.verifyAccessToken(token);
        expect(payload!['sub'], 'u1');
        expect(payload['type'], 'access');
        expect(payload['iss'], _issuer);
        expect(payload['aud'], _audience);
        expect(payload['jti'], isNotEmpty);
        expect(payload['iat'], isA<int>());
        expect(payload['exp'], isA<int>());
      });

      test('extra claims are preserved', () async {
        final token = svc.generateAccessToken(
          claims: {'sub': 'u1', 'role': 'admin', 'email': 'a@b.com'},
        );
        final payload = await svc.verifyAccessToken(token);
        expect(payload!['role'], 'admin');
        expect(payload['email'], 'a@b.com');
      });

      test('exp is in the future', () async {
        final token = svc.generateAccessToken(claims: {'sub': 'u1'});
        final payload = await svc.verifyAccessToken(token);
        final exp = payload!['exp'] as int;
        expect(
          DateTime.fromMillisecondsSinceEpoch(
            exp * 1000,
          ).isAfter(DateTime.now()),
          isTrue,
        );
      });
    });

    group('refresh token generation', () {
      test('returns a non-empty JWT string', () {
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svc.generateRefreshToken(accessToken: access);
        expect(refresh, isNotEmpty);
      });

      test('payload type is refresh', () async {
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svc.generateRefreshToken(accessToken: access);
        final payload = await svc.verifyRefreshToken(refresh);
        expect(payload!['type'], 'refresh');
        expect(payload['sub'], 'u1');
      });

      test('throws on invalid access token input', () {
        expect(
          () => svc.generateRefreshToken(accessToken: 'bad.token.here'),
          throwsException,
        );
      });

      test('refresh JTI differs from access JTI', () async {
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svc.generateRefreshToken(accessToken: access);
        final ap = await svc.verifyAccessToken(access);
        final rp = await svc.verifyRefreshToken(refresh);
        expect(ap!['jti'], isNot(equals(rp!['jti'])));
      });
    });

    group('access token verification', () {
      test('valid token returns payload', () async {
        final token = svc.generateAccessToken(claims: {'sub': 'u1'});
        expect(await svc.verifyAccessToken(token), isNotNull);
      });

      test('returns null for empty string', () async {
        expect(await svc.verifyAccessToken(''), isNull);
      });

      test('returns null for garbage string', () async {
        expect(await svc.verifyAccessToken('not.a.jwt'), isNull);
      });

      test('returns null for tampered payload', () async {
        final token = svc.generateAccessToken(claims: {'sub': 'u1'});
        final parts = token.split('.');
        final fakePayload = base64Url.encode(
          utf8.encode('{"sub":"hacker","type":"access"}'),
        );
        expect(
          await svc.verifyAccessToken('${parts[0]}.$fakePayload.${parts[2]}'),
          isNull,
        );
      });

      test('returns null for expired token', () async {
        final expired = JWT({
          'sub': 'u1',
          'type': 'access',
          'iss': _issuer,
          'aud': _audience,
          'jti': 'x',
          'iat':
              DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch ~/
              1000,
          'exp':
              DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }).sign(SecretKey(_accessSecret));
        expect(await svc.verifyAccessToken(expired), isNull);
      });

      test('returns null for wrong issuer', () async {
        final token = JWT({
          'sub': 'u1',
          'type': 'access',
          'iss': 'wrong-issuer',
          'aud': _audience,
          'jti': 'x',
          'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }).sign(SecretKey(_accessSecret));
        expect(await svc.verifyAccessToken(token), isNull);
      });

      test('returns null for wrong audience', () async {
        final token = JWT({
          'sub': 'u1',
          'type': 'access',
          'iss': _issuer,
          'aud': 'wrong-audience',
          'jti': 'x',
          'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }).sign(SecretKey(_accessSecret));
        expect(await svc.verifyAccessToken(token), isNull);
      });

      test('returns null for missing required claims', () async {
        final token = JWT({
          'username': 'u',
          'type': 'access',
        }).sign(SecretKey(_accessSecret));
        expect(await svc.verifyAccessToken(token), isNull);
      });

      test('access token cannot be used as refresh token', () async {
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        expect(await svc.verifyRefreshToken(access), isNull);
      });

      test('refresh token cannot be used as access token', () async {
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svc.generateRefreshToken(accessToken: access);
        expect(await svc.verifyAccessToken(refresh), isNull);
      });

      test('wrong secret returns null', () async {
        final otherSvc = JwtService(
          accessTokenSecret: 'different-secret',
          refreshTokenSecret: _refreshSecret,
          issuer: _issuer,
          audience: _audience,
        );
        final token = otherSvc.generateAccessToken(claims: {'sub': 'u1'});
        expect(await svc.verifyAccessToken(token), isNull);
      });
    });

    group('token revocation', () {
      late InMemoryTokenStore store;
      late JwtService svcWithStore;

      setUp(() {
        store = InMemoryTokenStore();
        svcWithStore = _hs256(store: store);
      });

      test('unrevoked token verifies normally', () async {
        final token = svcWithStore.generateAccessToken(claims: {'sub': 'u1'});
        expect(await svcWithStore.verifyAccessToken(token), isNotNull);
      });

      test('revoked access token returns null', () async {
        final token = svcWithStore.generateAccessToken(claims: {'sub': 'u1'});
        await svcWithStore.revokeToken(token);
        expect(await svcWithStore.verifyAccessToken(token), isNull);
      });

      test('revoking one token does not affect others', () async {
        final t1 = svcWithStore.generateAccessToken(claims: {'sub': 'u1'});
        final t2 = svcWithStore.generateAccessToken(claims: {'sub': 'u2'});
        await svcWithStore.revokeToken(t1);
        expect(await svcWithStore.verifyAccessToken(t1), isNull);
        expect(await svcWithStore.verifyAccessToken(t2), isNotNull);
      });

      test('revoked refresh token returns null', () async {
        final access = svcWithStore.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svcWithStore.generateRefreshToken(accessToken: access);
        await svcWithStore.revokeToken(refresh);
        expect(await svcWithStore.verifyRefreshToken(refresh), isNull);
      });

      test('revokeToken is a no-op when no tokenStore configured', () async {
        final noStore = _hs256();
        final token = noStore.generateAccessToken(claims: {'sub': 'u1'});
        await noStore.revokeToken(token);
        expect(await noStore.verifyAccessToken(token), isNotNull);
      });

      test('revokeToken is silent on malformed token', () async {
        await expectLater(
          svcWithStore.revokeToken('not.a.valid.jwt.at.all'),
          completes,
        );
      });

      test('revokeToken is silent on two-part token', () async {
        await expectLater(svcWithStore.revokeToken('a.b'), completes);
      });
    });

    group('refresh token rotation', () {
      test(
        'first use succeeds, second use rejected (tokenStore present)',
        () async {
          final store = InMemoryTokenStore();
          final svc = _hs256(store: store);
          final access = svc.generateAccessToken(claims: {'sub': 'u1'});
          final refresh = svc.generateRefreshToken(accessToken: access);

          expect(await svc.verifyRefreshToken(refresh), isNotNull);
          expect(await svc.verifyRefreshToken(refresh), isNull); // rotated
        },
      );

      test('without tokenStore refresh token can be reused', () async {
        final svc = _hs256();
        final access = svc.generateAccessToken(claims: {'sub': 'u1'});
        final refresh = svc.generateRefreshToken(accessToken: access);

        expect(await svc.verifyRefreshToken(refresh), isNotNull);
        expect(await svc.verifyRefreshToken(refresh), isNotNull);
      });
    });

    group('JTI uniqueness', () {
      test('1000 concurrent tokens all have unique JTIs', () async {
        final tokens = await Future.wait(
          List.generate(
            1000,
            (_) => Future(() => svc.generateAccessToken(claims: {'sub': 'u1'})),
          ),
        );
        final payloads = await Future.wait(tokens.map(svc.verifyAccessToken));
        final jtis = payloads.map((p) => p!['jti'] as String).toList();
        expect(
          jtis.toSet().length,
          jtis.length,
          reason: 'All 1000 JTIs must be unique',
        );
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // JwtService — RS256
  // ─────────────────────────────────────────────────────────────────────────

  group('JwtService (RS256)', () {
    late JwtService rs256;

    setUp(() {
      rs256 = JwtService.rs256(
        privateKeyPem: _rsaPrivateKey,
        publicKeyPem: _rsaPublicKey,
        issuer: _issuer,
        audience: _audience,
      );
    });

    test('algorithm is RS256', () {
      expect(rs256.algorithm, JWTAlgorithm.RS256);
    });

    test('generates access token verifiable with public key', () async {
      final token = rs256.generateAccessToken(claims: {'sub': 'u1'});
      final payload = await rs256.verifyAccessToken(token);
      expect(payload, isNotNull);
      expect(payload!['sub'], 'u1');
      expect(payload['type'], 'access');
    });

    test('generates refresh token verifiable with public key', () async {
      final access = rs256.generateAccessToken(claims: {'sub': 'u1'});
      final refresh = rs256.generateRefreshToken(accessToken: access);
      final payload = await rs256.verifyRefreshToken(refresh);
      expect(payload, isNotNull);
      expect(payload!['type'], 'refresh');
    });

    test('rejects token verified with wrong public key', () async {
      final token = rs256.generateAccessToken(claims: {'sub': 'u1'});
      final wrong = JwtService.rs256(
        privateKeyPem: _rsaPrivateKey,
        publicKeyPem: _wrongPublicKey,
        issuer: _issuer,
        audience: _audience,
      );
      expect(await wrong.verifyAccessToken(token), isNull);
    });

    test('rejects HS256 token when verifying with RS256 service', () async {
      final hs256Token = _hs256().generateAccessToken(claims: {'sub': 'u1'});
      expect(await rs256.verifyAccessToken(hs256Token), isNull);
    });

    test('privateKeyPem and publicKeyPem are set; secrets are null', () {
      expect(rs256.privateKeyPem, isNotNull);
      expect(rs256.publicKeyPem, isNotNull);
      expect(rs256.accessTokenSecret, isNull);
      expect(rs256.refreshTokenSecret, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // authMiddleware
  // ─────────────────────────────────────────────────────────────────────────

  group('authMiddleware', () {
    late JwtService svc;
    late Handler protected;

    setUp(() {
      svc = _hs256();
      protected = authMiddleware(svc)(
        (req) => Response.ok(
          jsonEncode({'user': req.context['user']}),
          headers: {'Content-Type': 'application/json'},
        ),
      );
    });

    test('allows request with valid Bearer token', () async {
      final token = svc.generateAccessToken(claims: {'sub': 'u1'});
      final res = await protected(
        _request('/secure', headers: {'Authorization': 'Bearer $token'}),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect((body['user'] as Map)['sub'], 'u1');
    });

    test('stores decoded payload in request.context[user]', () async {
      final token = svc.generateAccessToken(
        claims: {'sub': 'u42', 'role': 'admin'},
      );
      Map<String, dynamic>? capturedUser;
      final handler = authMiddleware(svc)((req) {
        capturedUser = req.context['user'] as Map<String, dynamic>?;
        return Response.ok('ok');
      });
      await handler(
        _request('/x', headers: {'Authorization': 'Bearer $token'}),
      );
      expect(capturedUser, isNotNull);
      expect(capturedUser!['sub'], 'u42');
      expect(capturedUser!['role'], 'admin');
    });

    test('returns 403 when Authorization header is absent', () async {
      final res = await protected(_request('/secure'));
      expect(res.statusCode, 403);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['error'], contains('Missing or invalid token'));
    });

    test('returns 403 when token is invalid', () async {
      final res = await protected(
        _request(
          '/secure',
          headers: {'Authorization': 'Bearer bad.token.here'},
        ),
      );
      expect(res.statusCode, 403);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['error'], contains('Invalid token'));
    });

    test('returns 403 when token is expired', () async {
      final expired = JWT({
        'sub': 'u1',
        'type': 'access',
        'iss': _issuer,
        'aud': _audience,
        'jti': 'x',
        'iat':
            DateTime.now()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch ~/
            1000,
        'exp':
            DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey(_accessSecret));
      final res = await protected(
        _request('/secure', headers: {'Authorization': 'Bearer $expired'}),
      );
      expect(res.statusCode, 403);
    });

    test('returns 403 when token is tampered', () async {
      final token = svc.generateAccessToken(claims: {'sub': 'u1'});
      final parts = token.split('.');
      final tampered =
          '${parts[0]}.${base64Url.encode(utf8.encode('{}'))}.${parts[2]}';
      final res = await protected(
        _request('/secure', headers: {'Authorization': 'Bearer $tampered'}),
      );
      expect(res.statusCode, 403);
    });

    test('returns 403 when token is revoked', () async {
      final store = InMemoryTokenStore();
      final svcWithStore = _hs256(store: store);
      final handler = authMiddleware(svcWithStore)((_) => Response.ok('ok'));
      final token = svcWithStore.generateAccessToken(claims: {'sub': 'u1'});
      await svcWithStore.revokeToken(token);
      final res = await handler(
        _request('/secure', headers: {'Authorization': 'Bearer $token'}),
      );
      expect(res.statusCode, 403);
    });

    test('response content-type is application/json on rejection', () async {
      final res = await protected(_request('/secure'));
      expect(res.headers['content-type'], contains('application/json'));
    });

    test('passes request through to inner handler on success', () async {
      var innerCalled = false;
      final handler = authMiddleware(svc)((_) {
        innerCalled = true;
        return Response.ok('ok');
      });
      final token = svc.generateAccessToken(claims: {'sub': 'u1'});
      await handler(
        _request('/x', headers: {'Authorization': 'Bearer $token'}),
      );
      expect(innerCalled, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // apiKeyMiddleware
  // ─────────────────────────────────────────────────────────────────────────

  group('apiKeyMiddleware', () {
    const validKey = 'secret-key-123';
    late Handler handler;

    setUp(() {
      handler = apiKeyMiddleware(validKeys: {validKey, 'other-key'})(
        (req) => Response.ok(
          jsonEncode({'key': req.context['api_key']}),
          headers: {'Content-Type': 'application/json'},
        ),
      );
    });

    test('allows request with valid API key', () async {
      final res = await handler(
        _request('/api', headers: {'X-API-Key': validKey}),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['key'], validKey);
    });

    test('allows any key from the valid set', () async {
      final res = await handler(
        _request('/api', headers: {'X-API-Key': 'other-key'}),
      );
      expect(res.statusCode, 200);
    });

    test('stores validated key in request.context[api_key]', () async {
      String? captured;
      final h = apiKeyMiddleware(validKeys: {validKey})((req) {
        captured = req.context['api_key'] as String?;
        return Response.ok('ok');
      });
      await h(_request('/api', headers: {'X-API-Key': validKey}));
      expect(captured, validKey);
    });

    test('returns 401 when header is absent', () async {
      final res = await handler(_request('/api'));
      expect(res.statusCode, 401);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['error'], contains('API key'));
    });

    test('returns 401 for empty API key', () async {
      final res = await handler(_request('/api', headers: {'X-API-Key': ''}));
      expect(res.statusCode, 401);
    });

    test('returns 401 for invalid API key', () async {
      final res = await handler(
        _request('/api', headers: {'X-API-Key': 'wrong-key'}),
      );
      expect(res.statusCode, 401);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['error'], 'Invalid or missing API key');
    });

    test('response content-type is application/json on rejection', () async {
      final res = await handler(_request('/api'));
      expect(res.headers['content-type'], contains('application/json'));
    });

    test('supports custom header name', () async {
      final h = apiKeyMiddleware(
        validKeys: {validKey},
        headerName: 'X-Admin-Key',
      )((_) => Response.ok('ok'));

      final allowed = await h(
        _request('/api', headers: {'X-Admin-Key': validKey}),
      );
      expect(allowed.statusCode, 200);

      final rejected = await h(
        _request('/api', headers: {'X-API-Key': validKey}), // wrong header name
      );
      expect(rejected.statusCode, 401);
    });

    test('multiple valid keys all pass', () async {
      final h = apiKeyMiddleware(validKeys: {'k1', 'k2', 'k3'})(
        (_) => Response.ok('ok'),
      );
      for (final key in ['k1', 'k2', 'k3']) {
        final res = await h(_request('/api', headers: {'X-API-Key': key}));
        expect(res.statusCode, 200, reason: 'key $key should be accepted');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TokenHelpers (auth_utils extension)
  // ─────────────────────────────────────────────────────────────────────────

  group('TokenHelpers', () {
    test('getToken returns Bearer token', () {
      final headers = {'Authorization': 'Bearer my-token'};
      expect(headers.getToken(), 'my-token');
    });

    test('getToken returns Basic token', () {
      final headers = {'Authorization': 'Basic my-credentials'};
      expect(headers.getToken(), 'my-credentials');
    });

    test('getToken returns null when Authorization header absent', () {
      expect(<String, String>{}.getToken(), isNull);
    });

    test('getToken returns null for unrecognised scheme', () {
      expect({'Authorization': 'Digest abc'}.getToken(), isNull);
    });

    test('bearer() extracts Bearer token', () {
      expect({'Authorization': 'Bearer tok'}.bearer(), 'tok');
    });

    test('bearer() returns null for Basic header', () {
      expect({'Authorization': 'Basic tok'}.bearer(), isNull);
    });

    test('basic() extracts Basic token', () {
      expect({'Authorization': 'Basic creds'}.basic(), 'creds');
    });

    test('basic() returns null for Bearer header', () {
      expect({'Authorization': 'Bearer tok'}.basic(), isNull);
    });

    test('getToken prefers Bearer over Basic', () {
      // Only one Authorization header is realistic, but the getter tries Bearer first.
      expect({'Authorization': 'Bearer tok'}.getToken(), 'tok');
    });

    test('malformed Authorization header returns null', () {
      expect({'Authorization': 'BearerWithNoSpace'}.getToken(), isNull);
      expect({'Authorization': 'Bearer'}.getToken(), isNull);
    });
  });
}
