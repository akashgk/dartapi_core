/// Header parsing helpers for auth middleware.
extension TokenHelpers on Map<String, String> {
  String? _authorization(String type) {
    final value = this['Authorization']?.split(' ');
    if (value != null && value.length == 2 && value.first == type) {
      return value.last;
    }
    return null;
  }

  String? bearer() => _authorization('Bearer');
  String? basic() => _authorization('Basic');

  /// Returns the Bearer or Basic token from the Authorization header, or null.
  String? getToken() => bearer() ?? basic();
}
