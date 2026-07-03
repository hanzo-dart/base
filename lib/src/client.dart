import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'collection.dart';
import 'exception.dart';
import 'files.dart';
import 'realtime.dart';

/// The main Hanzo Base client.
///
/// ```dart
/// final base = HanzoBase('https://base.hanzo.ai');
/// await base.collection('users').authWithPassword('me@example.com', 'secret');
/// final posts = await base.collection('posts').getList(perPage: 20);
/// ```
///
/// Auth is Hanzo IAM-native: [authStore] holds the IAM-issued JWT and
/// validates its `exp` claim locally.
class HanzoBase {
  HanzoBase(
    String baseUrl, {
    AuthStore? authStore,
    this.lang = 'en-US',
    http.Client Function()? httpClientFactory,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        authStore = authStore ?? MemoryAuthStore(),
        _clientFactory = httpClientFactory ?? http.Client.new {
    _httpClient = _clientFactory();
    files = FileService(this.baseUrl);
    realtime = RealtimeService(
      this.baseUrl,
      () => this.authStore.isValid ? this.authStore.token : '',
      clientFactory: _clientFactory,
    );
  }

  /// The Hanzo Base instance base url (e.g. `https://base.hanzo.ai`).
  final String baseUrl;

  /// Holds the current Hanzo IAM session.
  final AuthStore authStore;

  /// `Accept-Language` header sent with every request.
  String lang;

  /// Realtime (SSE) subscriptions.
  late final RealtimeService realtime;

  /// Record file URL builder.
  late final FileService files;

  final http.Client Function() _clientFactory;
  late final http.Client _httpClient;
  final _collections = <String, CollectionService>{};

  /// Returns the [CollectionService] for the given collection id or name.
  CollectionService collection(String idOrName) {
    return _collections.putIfAbsent(
      idOrName,
      () => CollectionService(this, idOrName),
    );
  }

  /// Server health check.
  Future<Map<String, dynamic>> health() async {
    final result = await send('/v1/health');
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }

  /// Sends a request to the Hanzo Base API and returns the decoded JSON body.
  ///
  /// Adds the IAM `Authorization` header when a valid session exists.
  /// Attach [files] to send a multipart request. Throws [HanzoException] on
  /// non-2xx responses.
  Future<dynamic> send(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
    List<http.MultipartFile> files = const [],
  }) async {
    final url = _buildUrl(path, query);

    http.BaseRequest request;
    if (files.isEmpty) {
      final jsonRequest = http.Request(method, url);
      if (body != null && body.isNotEmpty) {
        jsonRequest.body = jsonEncode(body);
        jsonRequest.headers['Content-Type'] = 'application/json';
      }
      request = jsonRequest;
    } else {
      final multipart = http.MultipartRequest(method, url)..files.addAll(files);
      (body ?? const {}).forEach((key, value) {
        multipart.fields[key] = value is String ? value : jsonEncode(value);
      });
      request = multipart;
    }

    request.headers.addAll(headers);
    if (!request.headers.containsKey('Authorization') && authStore.isValid) {
      request.headers['Authorization'] = authStore.token;
    }
    request.headers.putIfAbsent('Accept-Language', () => lang);

    http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request);
    } on http.ClientException catch (e) {
      throw HanzoException(url: url, originalError: e, isAbort: true);
    } catch (e) {
      throw HanzoException(url: url, originalError: e);
    }

    final responseBody = await streamed.stream.bytesToString();
    dynamic data;
    if (responseBody.isNotEmpty) {
      try {
        data = jsonDecode(responseBody);
      } catch (_) {
        data = responseBody;
      }
    }

    if (streamed.statusCode >= 400) {
      throw HanzoException(
        url: url,
        statusCode: streamed.statusCode,
        response: data is Map<String, dynamic> ? data : const {},
      );
    }

    return data;
  }

  /// Safely interpolate `{:param}` placeholders into a filter expression.
  ///
  /// String values are single-quote escaped; [DateTime]s become UTC literals.
  ///
  /// ```dart
  /// base.collection('posts').getList(
  ///   filter: base.filter('title ~ {:t}', {'t': userInput}),
  /// );
  /// ```
  String filter(String expr, [Map<String, dynamic> params = const {}]) {
    if (params.isEmpty) {
      return expr;
    }
    var result = expr;
    params.forEach((key, raw) {
      final String literal;
      if (raw == null || raw is num || raw is bool) {
        literal = raw.toString();
      } else if (raw is DateTime) {
        literal = "'${raw.toUtc().toIso8601String().replaceFirst('T', ' ')}'";
      } else if (raw is String) {
        literal = "'${raw.replaceAll("'", "\\'")}'";
      } else {
        literal = "'${jsonEncode(raw).replaceAll("'", "\\'")}'";
      }
      result = result.replaceAll('{:$key}', literal);
    });
    return result;
  }

  /// Closes the underlying HTTP client and the realtime connection.
  void close() {
    realtime.disconnect();
    _httpClient.close();
  }

  Uri _buildUrl(String path, Map<String, dynamic> query) {
    final normalizedQuery = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) {
        return;
      }
      normalizedQuery[key] = value is Iterable
          ? value.map((v) => v.toString()).toList()
          : value.toString();
    });

    final uri = Uri.parse('$baseUrl$path');
    if (normalizedQuery.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {
      ...uri.queryParametersAll,
      ...normalizedQuery,
    });
  }
}
