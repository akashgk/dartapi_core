import 'dart:async';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _req() =>
    Request('GET', Uri.parse('http://localhost/test'));

void main() {
  group('BackgroundTaskQueue', () {
    test('executes added tasks', () async {
      final log = <String>[];
      final queue = BackgroundTaskQueue();
      queue.add(() async => log.add('task-1'));
      queue.add(() async => log.add('task-2'));
      await queue.run();
      expect(log, equals(['task-1', 'task-2']));
    });

    test('swallows errors in tasks without throwing', () async {
      final queue = BackgroundTaskQueue();
      queue.add(() async => throw Exception('boom'));
      await expectLater(queue.run(), completes);
    });

    test('continues after a failing task', () async {
      final log = <String>[];
      final queue = BackgroundTaskQueue();
      queue.add(() async => throw Exception('fail'));
      queue.add(() async => log.add('ran'));
      await queue.run();
      expect(log, equals(['ran']));
    });
  });

  group('backgroundTaskMiddleware', () {
    test('response is returned normally', () async {
      final handler = backgroundTaskMiddleware()(
        (_) => Response.ok('done'),
      );
      final res = await handler(_req());
      expect(res.statusCode, equals(200));
      expect(await res.readAsString(), equals('done'));
    });

    test('background task runs after response', () async {
      final completer = Completer<String>();
      final handler = backgroundTaskMiddleware()((req) {
        req.backgroundTasks.add(() async => completer.complete('ran'));
        return Response.ok('ok');
      });
      await handler(_req());
      expect(await completer.future.timeout(Duration(seconds: 2)), equals('ran'));
    });

    test('multiple tasks all run', () async {
      final log = <int>[];
      final handler = backgroundTaskMiddleware()((req) {
        req.backgroundTasks.add(() async => log.add(1));
        req.backgroundTasks.add(() async => log.add(2));
        req.backgroundTasks.add(() async => log.add(3));
        return Response.ok('ok');
      });
      await handler(_req());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(log, containsAll([1, 2, 3]));
    });
  });

  group('BackgroundTaskExtension', () {
    test('returns no-op queue when middleware not in pipeline', () {
      final req = _req();
      // Should not throw even without backgroundTaskMiddleware
      expect(() => req.backgroundTasks.add(() async {}), returnsNormally);
    });

    test('returns the queue from context when middleware is present', () async {
      BackgroundTaskQueue? captured;
      final handler = backgroundTaskMiddleware()((req) {
        captured = req.backgroundTasks;
        return Response.ok('ok');
      });
      await handler(_req());
      expect(captured, isA<BackgroundTaskQueue>());
    });
  });
}
