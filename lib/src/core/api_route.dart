import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'api_methods.dart';
import 'serializable.dart';

class ApiRoute<ApiInput, ApiOutput> {
  final ApiMethod method;
  final String path;
  final Future<ApiOutput> Function(Request, ApiInput?) typedHandler;

  /// Optional function to parse request body into `RequestInput`
  final ApiInput? Function(Map<String, dynamic>)? dtoParser;

  final List<Middleware> middlewares;

  final String? summary;
  final String? description;
  final Map<String, dynamic>? requestSchema;
  final Map<String, dynamic>? responseSchema;

  const ApiRoute({
    required this.method,
    required this.path,
    required this.typedHandler,
    this.dtoParser,
    this.middlewares = const [],
    this.summary,
    this.description,
    this.requestSchema,
    this.responseSchema,
  });

  /// Shelf-compatible handler
  Handler get handler => (Request request) async {
    try {
      ApiInput? dto;

      if (dtoParser != null) {
        final body = await request.readAsString();
        dto = dtoParser?.call(jsonDecode(body));
      }

      final result = await typedHandler(request, dto);

      return Response.ok(
        _serialize(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: _serialize({
          'error': 'Internal Server Error',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  };
}

String _serialize(dynamic data) {
  if (data is String) return data;
  if (data is Map || data is List) return jsonEncode(data);
  if (data is Serializable) return jsonEncode(data.toJson());

  throw Exception("Unable to serialize response of type ${data.runtimeType}");
}
