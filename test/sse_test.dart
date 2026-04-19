import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

void main() {
  group('SseEvent.format', () {
    test('formats data-only event', () {
      expect(SseEvent(data: 'hello').format(), equals('data: hello\n\n'));
    });

    test('includes id when set', () {
      final f = SseEvent(data: 'x', id: '42').format();
      expect(f, contains('id: 42\n'));
    });

    test('includes event type when set', () {
      final f = SseEvent(data: 'x', event: 'update').format();
      expect(f, contains('event: update\n'));
    });

    test('includes retry when set', () {
      final f = SseEvent(data: 'x', retry: Duration(seconds: 5)).format();
      expect(f, contains('retry: 5000\n'));
    });

    test('prefixes each line of multi-line data', () {
      final f = SseEvent(data: 'line1\nline2').format();
      expect(f, contains('data: line1\n'));
      expect(f, contains('data: line2\n'));
    });

    test('ends with blank line', () {
      expect(SseEvent(data: 'x').format(), endsWith('\n\n'));
    });
  });

  group('sseResponse', () {
    test('sets correct Content-Type', () {
      final res = sseResponse(const Stream.empty());
      expect(res.headers['content-type'], contains('text/event-stream'));
    });

    test('sets cache-control: no-cache', () {
      final res = sseResponse(const Stream.empty());
      expect(res.headers['cache-control'], equals('no-cache'));
    });

    test('sets x-accel-buffering: no', () {
      final res = sseResponse(const Stream.empty());
      expect(res.headers['x-accel-buffering'], equals('no'));
    });

    test('streams encoded events', () async {
      final events = Stream.fromIterable([
        SseEvent(data: 'first'),
        SseEvent(data: 'second', event: 'update'),
      ]);
      final res = sseResponse(events);
      final body =
          await res.read().expand((b) => b).toList().then(utf8.decode);
      expect(body, contains('data: first'));
      expect(body, contains('event: update'));
    });
  });
}
