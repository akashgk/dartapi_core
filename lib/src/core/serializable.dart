/// An abstract interface for objects that can be converted to JSON.
///
/// Any class that implements [Serializable] must provide a [toJson] method
/// that returns a `Map<String, dynamic>` representation of the object.
///
/// This is commonly used for serializing API responses.
abstract class Serializable {
  /// Converts the object into a JSON-compatible map.
  Map<String, dynamic> toJson();
}
