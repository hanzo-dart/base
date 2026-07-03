/// Normalized error thrown by every Hanzo Base request.
class HanzoException implements Exception {
  HanzoException({
    this.url,
    this.statusCode = 0,
    this.response = const {},
    this.originalError,
    this.isAbort = false,
  });

  /// The request url that produced the error.
  final Uri? url;

  /// The HTTP status code, or `0` for transport/connection errors.
  final int statusCode;

  /// The parsed JSON error body, when present.
  final Map<String, dynamic> response;

  /// The underlying error for transport failures.
  final Object? originalError;

  /// Whether the request was aborted (connection dropped).
  final bool isAbort;

  /// Server-provided error message, if any.
  String get message {
    final msg = response['message'];
    if (msg is String && msg.isNotEmpty) {
      return msg;
    }
    return originalError?.toString() ?? 'HanzoException $statusCode';
  }

  @override
  String toString() => 'HanzoException($statusCode): $message';
}
