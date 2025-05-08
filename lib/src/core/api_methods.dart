/// Represents supported HTTP methods for an API route.
///
/// This enum is used to define which HTTP verb an [ApiRoute] responds to.
/// The [value] property contains the string representation (e.g., "GET", "POST").
enum ApiMethod {
  /// HTTP GET method, typically used to fetch data.
  get('GET'),

  /// HTTP POST method, typically used to create a new resource.
  post('POST'),

  /// HTTP PUT method, typically used to update a resource completely.
  put('PUT'),

  /// HTTP DELETE method, used to delete a resource.
  delete('DELETE'),

  /// HTTP PATCH method, used to partially update a resource.
  patch('PATCH'),

  /// HTTP HEAD method, used to retrieve headers without the response body.
  head('HEAD'),

  /// HTTP OPTIONS method, used to describe the communication options.
  options('OPTIONS');

  /// The string representation of the HTTP method.
  final String value;

  /// Creates an [ApiMethod] with the given [value].
  const ApiMethod(this.value);
}
