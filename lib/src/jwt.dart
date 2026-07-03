import 'dart:convert';

/// Decode the payload of a JWT without verifying its signature.
///
/// Returns an empty map for malformed tokens. Used to read the Hanzo
/// IAM-issued token's claims (e.g. `exp`, `id`) locally.
Map<String, dynamic> getTokenPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    return const {};
  }
  try {
    final decoded =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final data = jsonDecode(decoded);
    return data is Map<String, dynamic> ? data : const {};
  } catch (_) {
    return const {};
  }
}

/// Whether a JWT's `exp` claim has passed.
///
/// [expirationThreshold] seconds are subtracted from `exp` so callers can
/// refresh early. Tokens without an `exp` claim are treated as expired.
bool isTokenExpired(String token, [int expirationThreshold = 0]) {
  final payload = getTokenPayload(token);
  final exp = payload['exp'];
  if (exp is! num) {
    return true;
  }
  final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000;
  return exp - expirationThreshold <= nowSeconds;
}
