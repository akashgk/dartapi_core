import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

// ── Sample types used across tests ───────────────────────────────────────────

abstract class Repository {
  String get name;
}

class InMemoryRepository implements Repository {
  @override
  final String name = 'in-memory';
}

class DbRepository implements Repository {
  final String _db;
  DbRepository(this._db);
  @override
  String get name => 'db:$_db';
}

class Service {
  final Repository repo;
  Service(this.repo);
}

class Controller {
  final Service service;
  Controller(this.service);
}

// For circular dependency tests
class A {
  // ignore: unused_field
  final B _b;
  A(this._b);
}

class B {
  // ignore: unused_field
  final A _a;
  B(this._a);
}

// Counting calls
int _factoryCallCount = 0;
Service _countedServiceFactory(ServiceRegistry r) {
  _factoryCallCount++;
  return Service(r.get<Repository>());
}

void main() {
  // ── ServiceRegistry ───────────────────────────────────────────────────────

  group('ServiceRegistry — register & get', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('get returns instance from factory', () {
      r.register<Repository>((_) => InMemoryRepository());
      final repo = r.get<Repository>();
      expect(repo, isA<InMemoryRepository>());
    });

    test('get returns same instance on repeated calls (lazy singleton)', () {
      r.register<Repository>((_) => InMemoryRepository());
      final a = r.get<Repository>();
      final b = r.get<Repository>();
      expect(identical(a, b), isTrue);
    });

    test(
      'factory is called exactly once regardless of how many times get is called',
      () {
        _factoryCallCount = 0;
        r.register<Repository>((_) => InMemoryRepository());
        r.register<Service>(_countedServiceFactory);
        r.get<Service>();
        r.get<Service>();
        r.get<Service>();
        expect(_factoryCallCount, 1);
      },
    );

    test(
      'factory receives the registry so it can resolve sub-dependencies',
      () {
        r.register<Repository>((_) => InMemoryRepository());
        r.register<Service>((reg) => Service(reg.get<Repository>()));
        final svc = r.get<Service>();
        expect(svc.repo, isA<InMemoryRepository>());
      },
    );

    test('three-level resolution chain works correctly', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.register<Service>((reg) => Service(reg.get<Repository>()));
      r.register<Controller>((reg) => Controller(reg.get<Service>()));
      final ctrl = r.get<Controller>();
      expect(ctrl.service.repo, isA<InMemoryRepository>());
    });

    test('multiple independent types are resolved independently', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.register<Service>((reg) => Service(reg.get<Repository>()));
      final repo = r.get<Repository>();
      final svc = r.get<Service>();
      expect(repo, isA<Repository>());
      expect(svc, isA<Service>());
      expect(identical(svc.repo, repo), isTrue);
    });

    test('factory can capture external values via closure', () {
      const label = 'prod-db';
      r.register<Repository>((_) => DbRepository(label));
      expect(r.get<Repository>().name, 'db:$label');
    });
  });

  group('ServiceRegistry — registerSingleton', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('returns the exact pre-built instance', () {
      final instance = InMemoryRepository();
      r.registerSingleton<Repository>(instance);
      expect(identical(r.get<Repository>(), instance), isTrue);
    });

    test('singleton is returned on every call', () {
      final instance = InMemoryRepository();
      r.registerSingleton<Repository>(instance);
      expect(identical(r.get<Repository>(), r.get<Repository>()), isTrue);
    });

    test('singleton can be resolved by factory of another type', () {
      final repo = InMemoryRepository();
      r.registerSingleton<Repository>(repo);
      r.register<Service>((reg) => Service(reg.get<Repository>()));
      expect(identical(r.get<Service>().repo, repo), isTrue);
    });
  });

  group('ServiceRegistry — missing registration', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('get throws StateError for unregistered type', () {
      expect(() => r.get<Repository>(), throwsStateError);
    });

    test('error message names the missing type', () {
      expect(
        () => r.get<Service>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Service'),
          ),
        ),
      );
    });

    test('error message suggests register or registerSingleton', () {
      expect(
        () => r.get<Repository>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('register'), contains('registerSingleton')),
          ),
        ),
      );
    });
  });

  group('ServiceRegistry — double registration', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('register twice throws StateError', () {
      r.register<Repository>((_) => InMemoryRepository());
      expect(
        () => r.register<Repository>((_) => InMemoryRepository()),
        throwsStateError,
      );
    });

    test('registerSingleton twice throws StateError', () {
      r.registerSingleton<Repository>(InMemoryRepository());
      expect(
        () => r.registerSingleton<Repository>(InMemoryRepository()),
        throwsStateError,
      );
    });

    test('register then registerSingleton throws StateError', () {
      r.register<Repository>((_) => InMemoryRepository());
      expect(
        () => r.registerSingleton<Repository>(InMemoryRepository()),
        throwsStateError,
      );
    });

    test('double registration error message names the type', () {
      r.register<Repository>((_) => InMemoryRepository());
      expect(
        () => r.register<Repository>((_) => InMemoryRepository()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Repository'),
          ),
        ),
      );
    });
  });

  group('ServiceRegistry — circular dependency detection', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('direct self-reference throws StateError', () {
      r.register<Repository>((reg) => reg.get<Repository>());
      expect(() => r.get<Repository>(), throwsStateError);
    });

    test('A → B → A circular chain throws StateError', () {
      r.register<A>((reg) => A(reg.get<B>()));
      r.register<B>((reg) => B(reg.get<A>()));
      expect(() => r.get<A>(), throwsStateError);
    });

    test('circular error message contains the dependency chain', () {
      r.register<A>((reg) => A(reg.get<B>()));
      r.register<B>((reg) => B(reg.get<A>()));
      expect(
        () => r.get<A>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('A'), contains('B'), contains('→')),
          ),
        ),
      );
    });

    test('registry is usable after catching a circular dependency error', () {
      r.register<A>((reg) => A(reg.get<B>()));
      r.register<B>((reg) => B(reg.get<A>()));
      try {
        r.get<A>();
      } on StateError {
        // swallowed
      }
      // After the failure the _resolving set should be cleared — a different
      // type should still be resolvable.
      r.register<Repository>((_) => InMemoryRepository());
      expect(r.get<Repository>(), isA<InMemoryRepository>());
    });
  });

  group('ServiceRegistry — isRegistered', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('returns false for unregistered type', () {
      expect(r.isRegistered<Repository>(), isFalse);
    });

    test('returns true after register', () {
      r.register<Repository>((_) => InMemoryRepository());
      expect(r.isRegistered<Repository>(), isTrue);
    });

    test('returns true after registerSingleton', () {
      r.registerSingleton<Repository>(InMemoryRepository());
      expect(r.isRegistered<Repository>(), isTrue);
    });

    test('returns false after unregister', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.unregister<Repository>();
      expect(r.isRegistered<Repository>(), isFalse);
    });
  });

  group('ServiceRegistry — unregister', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('get throws after unregister', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.unregister<Repository>();
      expect(() => r.get<Repository>(), throwsStateError);
    });

    test('unregister of unregistered type does not throw', () {
      expect(() => r.unregister<Repository>(), returnsNormally);
    });

    test('can re-register after unregister', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.unregister<Repository>();
      r.registerSingleton<Repository>(DbRepository('new'));
      expect(r.get<Repository>().name, startsWith('db:'));
    });
  });

  group('ServiceRegistry — clear', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test('clear removes all registrations', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.register<Service>((reg) => Service(reg.get<Repository>()));
      r.clear();
      expect(r.isRegistered<Repository>(), isFalse);
      expect(r.isRegistered<Service>(), isFalse);
    });

    test('get throws for every type after clear', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.clear();
      expect(() => r.get<Repository>(), throwsStateError);
    });

    test('can register again after clear', () {
      r.register<Repository>((_) => InMemoryRepository());
      r.clear();
      r.registerSingleton<Repository>(DbRepository('fresh'));
      expect(r.get<Repository>().name, startsWith('db:'));
    });
  });

  group('ServiceRegistry — type safety', () {
    late ServiceRegistry r;
    setUp(() => r = ServiceRegistry());

    test(
      'different concrete types can be registered as different abstract types',
      () {
        // Register InMemoryRepository under Repository
        r.register<Repository>((_) => InMemoryRepository());
        // Register separately as InMemoryRepository (concrete)
        r.register<InMemoryRepository>((_) => InMemoryRepository());

        final asAbstract = r.get<Repository>();
        final asConcrete = r.get<InMemoryRepository>();

        expect(asAbstract, isA<InMemoryRepository>());
        expect(asConcrete, isA<InMemoryRepository>());
        // They are separate registrations → separate instances
        expect(identical(asAbstract, asConcrete), isFalse);
      },
    );

    test('registered instance type is preserved through resolution', () {
      r.register<Repository>((_) => DbRepository('test'));
      expect(r.get<Repository>(), isA<DbRepository>());
    });
  });

  // ── DartAPI integration ───────────────────────────────────────────────────

  group('DartAPI — registry integration', () {
    late DartAPI app;
    setUp(() => app = DartAPI());

    test('app.register delegates to internal ServiceRegistry', () {
      app.register<Repository>((_) => InMemoryRepository());
      expect(app.isRegistered<Repository>(), isTrue);
    });

    test('app.registerSingleton delegates to internal ServiceRegistry', () {
      app.registerSingleton<Repository>(InMemoryRepository());
      expect(app.isRegistered<Repository>(), isTrue);
    });

    test('app.get resolves a registered factory', () {
      app.register<Repository>((_) => InMemoryRepository());
      expect(app.get<Repository>(), isA<InMemoryRepository>());
    });

    test('app.get resolves a registered singleton', () {
      final repo = InMemoryRepository();
      app.registerSingleton<Repository>(repo);
      expect(identical(app.get<Repository>(), repo), isTrue);
    });

    test('app.get follows dependency chain through registry', () {
      app.register<Repository>((_) => InMemoryRepository());
      app.register<Service>((r) => Service(r.get<Repository>()));
      final svc = app.get<Service>();
      expect(svc.repo, isA<InMemoryRepository>());
    });

    test('app.isRegistered returns false for unregistered type', () {
      expect(app.isRegistered<Service>(), isFalse);
    });

    test('app.registry exposes the underlying ServiceRegistry', () {
      expect(app.registry, isA<ServiceRegistry>());
    });

    test('app.registry and app.get share the same instance pool', () {
      app.register<Repository>((_) => InMemoryRepository());
      final viaGet = app.get<Repository>();
      final viaRegistry = app.registry.get<Repository>();
      expect(identical(viaGet, viaRegistry), isTrue);
    });

    test('app.get throws StateError for unregistered type', () {
      expect(() => app.get<Service>(), throwsStateError);
    });

    test('registry is independent across DartAPI instances', () {
      final app2 = DartAPI();
      app.register<Repository>((_) => InMemoryRepository());
      expect(app2.isRegistered<Repository>(), isFalse);
    });
  });
}
