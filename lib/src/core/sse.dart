import 'dart:convert';

import 'package:shelf/shelf.dart';

/// A single Server-Sent Event.
class SseEvent {
  final String data;
  final String? id;
  final String? event;
  final Duration? retry;

  const SseEvent({required this.data, this.id, this.event, this.retry});

  /// Formats the event according to the SSE wire format.
  String format() {
    final buf = StringBuffer();
    if (id != null) buf.writeln('id: $id');
    if (event != null) buf.writeln('event: $event');
    if (retry != null) buf.writeln('retry: ${retry!.inMilliseconds}');
    for (final line in data.split('\n')) {
      buf.writeln('data: $line');
    }
    buf.writeln();
    return buf.toString();
  }
}

/// Returns a Shelf [Response] that streams [events] as Server-Sent Events.
///
/// The response sets the correct `Content-Type`, disables caching, and
/// signals proxies not to buffer the stream.
///
/// ```dart
/// ApiRoute<void, void>(
///   method: ApiMethod.get,
///   path: '/events',
///   handler: (req, _) async {
///     final stream = Stream.periodic(Duration(seconds: 1), (i) =>
///       SseEvent(data: 'tick $i', event: 'tick'));
///     return sseResponse(stream.take(10));
///   },
/// )
/// ```
Response sseResponse(Stream<SseEvent> events) {
  final encoded = events.map((e) => utf8.encode(e.format()));
  return Response.ok(
    encoded,
    headers: {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache',
      'connection': 'keep-alive',
      'x-accel-buffering': 'no',
    },
  );
}
