import 'dart:async';

import 'package:shelf/shelf.dart';

/// A queue of async callbacks that run after the HTTP response has been returned.
///
/// Obtain a queue inside a handler via `request.backgroundTasks`, then add tasks
/// with [add]. The tasks are executed by [backgroundTaskMiddleware] after the
/// response Future resolves — the client receives the response immediately while
/// the work proceeds in the background.
///
/// ```dart
/// Future<String> createUser(Request request, UserDTO? dto) async {
///   request.backgroundTasks.add(() => emailService.sendWelcome(dto!.email));
///   return 'User created';
/// }
/// ```
class BackgroundTaskQueue {
  final _tasks = <Future<void> Function()>[];

  /// Schedules [task] to run after the response is sent.
  void add(Future<void> Function() task) => _tasks.add(task);

  /// Executes all queued tasks sequentially, swallowing any errors.
  Future<void> run() async {
    for (final task in _tasks) {
      try {
        await task();
      } catch (_) {}
    }
  }
}

/// Middleware that enables [BackgroundTaskQueue] for every request.
///
/// Add it to your pipeline once — handlers can then call
/// `request.backgroundTasks.add(...)` to schedule post-response work.
///
/// ```dart
/// Pipeline()
///   .addMiddleware(backgroundTaskMiddleware())
///   .addMiddleware(loggingMiddleware())
///   .addHandler(router.handler)
/// ```
Middleware backgroundTaskMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      final queue = BackgroundTaskQueue();
      final updated =
          request.change(context: {...request.context, 'backgroundTasks': queue});
      final response = await inner(updated);
      unawaited(queue.run());
      return response;
    };
  };
}

/// Convenience extension so handlers can schedule tasks without casting.
extension BackgroundTaskExtension on Request {
  /// The [BackgroundTaskQueue] attached to this request.
  ///
  /// Returns a no-op queue if [backgroundTaskMiddleware] is not in the pipeline,
  /// so handlers won't throw even in test environments without the middleware.
  BackgroundTaskQueue get backgroundTasks =>
      context['backgroundTasks'] as BackgroundTaskQueue? ??
      BackgroundTaskQueue();
}
