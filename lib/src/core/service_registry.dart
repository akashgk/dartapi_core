/// A simple, type-safe service locator with lazy-singleton instantiation
/// and circular dependency detection.
///
/// Every registered type is treated as a **lazy singleton** — the factory is
/// called at most once (on the first [get]) and the result is cached for all
/// subsequent calls.  Pre-built instances can be registered with
/// [registerSingleton] and are returned as-is.
///
/// ```dart
/// final registry = ServiceRegistry();
///
/// // Eager singleton — already constructed
/// registry.registerSingleton<DartApiDB>(db);
///
/// // Lazy singleton — factory receives the registry to resolve sub-deps
/// registry.register<UserRepository>(
///   (r) => DbUserRepository(r.get<DartApiDB>()),
/// );
/// registry.register<UserService>(
///   (r) => UserService(repository: r.get<UserRepository>()),
/// );
///
/// final svc = registry.get<UserService>(); // constructed once, reused after
/// ```
class ServiceRegistry {
  final Map<Type, _Entry> _entries = {};

  /// Set of types currently being resolved — used to detect circular deps.
  final Set<Type> _resolving = {};

  // ── Registration ───────────────────────────────────────────────────────────

  /// Registers a **lazy singleton** factory for [T].
  ///
  /// [factory] receives this [ServiceRegistry] so it can resolve
  /// sub-dependencies via [get].  It is called at most once; the resulting
  /// instance is cached and returned on all future [get<T>()] calls.
  ///
  /// Throws [StateError] if [T] is already registered.
  void register<T>(T Function(ServiceRegistry) factory) {
    _assertNotRegistered<T>();
    _entries[T] = _Entry.factory((r) => factory(r));
  }

  /// Registers a pre-built [instance] as an eager singleton for [T].
  ///
  /// Throws [StateError] if [T] is already registered.
  void registerSingleton<T>(T instance) {
    _assertNotRegistered<T>();
    _entries[T] = _Entry.singleton(instance);
  }

  // ── Resolution ────────────────────────────────────────────────────────────

  /// Returns the instance for [T], constructing it lazily on the first call.
  ///
  /// Subsequent calls return the cached instance (singleton behaviour).
  ///
  /// Throws [StateError] if [T] is not registered.
  /// Throws [StateError] if a circular dependency is detected.
  T get<T>() {
    final entry = _entries[T];
    if (entry == null) {
      throw StateError(
        'No registration found for type $T. '
        'Call register<$T>() or registerSingleton<$T>() before calling get<$T>().',
      );
    }

    if (entry.resolved) return entry.instance as T;

    // Circular dependency guard
    if (_resolving.contains(T)) {
      final chain = [..._resolving, T].map((t) => t.toString()).join(' → ');
      throw StateError('Circular dependency detected: $chain');
    }

    _resolving.add(T);
    try {
      final T instance = entry.factory!(this) as T;
      entry
        .._instance = instance
        .._resolved = true;
      return instance;
    } finally {
      _resolving.remove(T);
    }
  }

  // ── Inspection / management ────────────────────────────────────────────────

  /// Returns `true` if a registration exists for [T].
  bool isRegistered<T>() => _entries.containsKey(T);

  /// Removes the registration for [T].
  ///
  /// If [T] was already resolved, the cached instance is discarded.
  void unregister<T>() => _entries.remove(T);

  /// Removes all registrations and clears all cached instances.
  void clear() => _entries.clear();

  // ── Private helpers ───────────────────────────────────────────────────────

  void _assertNotRegistered<T>() {
    if (_entries.containsKey(T)) {
      throw StateError(
        'Type $T is already registered in this ServiceRegistry. '
        'Call unregister<$T>() first if you intend to replace it.',
      );
    }
  }
}

/// Internal storage for a single service registration.
class _Entry {
  final dynamic Function(ServiceRegistry)? factory;
  dynamic _instance;
  bool _resolved;

  _Entry.factory(this.factory)
      : _instance = null,
        _resolved = false;

  _Entry.singleton(dynamic instance)
      : factory = null,
        _instance = instance,
        _resolved = true;

  bool get resolved => _resolved;
  dynamic get instance => _instance;
}
