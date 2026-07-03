import 'package:http/http.dart' as http;

import 'client.dart';
import 'exception.dart';
import 'realtime.dart';
import 'record.dart';

/// Typed CRUD, auth, and realtime for a single Hanzo Base collection.
///
/// Obtain one via `base.collection('name')`.
class CollectionService {
  CollectionService(this._client, this.collectionIdOrName);

  final HanzoBase _client;
  final String collectionIdOrName;

  String get _basePath =>
      '/v1/collections/${Uri.encodeComponent(collectionIdOrName)}';

  // ---- CRUD ---------------------------------------------------------------

  /// Fetch a single page of records.
  Future<ListResult> getList({
    int page = 1,
    int perPage = 30,
    String? filter,
    String? sort,
    String? expand,
    String? fields,
  }) async {
    final result = await _client.send(
      '$_basePath/records',
      query: {
        'page': page,
        'perPage': perPage,
        ..._listQuery(filter, sort, expand, fields),
      },
    );
    return ListResult.fromJson(_asMap(result));
  }

  /// Fetch every record by paginating until exhausted.
  Future<List<RecordModel>> getFullList({
    int batch = 200,
    String? filter,
    String? sort,
    String? expand,
    String? fields,
  }) async {
    final all = <RecordModel>[];
    var page = 1;
    while (true) {
      final result = await getList(
        page: page,
        perPage: batch,
        filter: filter,
        sort: sort,
        expand: expand,
        fields: fields,
      );
      all.addAll(result.items);
      if (all.length >= result.totalItems || result.items.length < batch) {
        break;
      }
      page++;
    }
    return all;
  }

  /// Fetch a single record by id.
  Future<RecordModel> getOne(
    String id, {
    String? expand,
    String? fields,
  }) async {
    final result = await _client.send(
      '$_basePath/records/${Uri.encodeComponent(id)}',
      query: _listQuery(null, null, expand, fields),
    );
    return RecordModel.fromJson(_asMap(result));
  }

  /// Fetch the first record matching [filter], or throw 404.
  Future<RecordModel> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
  }) async {
    final result = await getList(
      page: 1,
      perPage: 1,
      filter: filter,
      expand: expand,
      fields: fields,
    );
    if (result.items.isEmpty) {
      throw HanzoException(
        statusCode: 404,
        response: const {'message': "The requested resource wasn't found."},
      );
    }
    return result.items.first;
  }

  /// Create a record. Attach [files] for multipart upload.
  Future<RecordModel> create(
    Map<String, dynamic> body, {
    List<http.MultipartFile> files = const [],
    String? expand,
    String? fields,
  }) async {
    final result = await _client.send(
      '$_basePath/records',
      method: 'POST',
      body: body,
      files: files,
      query: _listQuery(null, null, expand, fields),
    );
    return RecordModel.fromJson(_asMap(result));
  }

  /// Update a record. Attach [files] for multipart upload.
  Future<RecordModel> update(
    String id,
    Map<String, dynamic> body, {
    List<http.MultipartFile> files = const [],
    String? expand,
    String? fields,
  }) async {
    final result = await _client.send(
      '$_basePath/records/${Uri.encodeComponent(id)}',
      method: 'PATCH',
      body: body,
      files: files,
      query: _listQuery(null, null, expand, fields),
    );
    return RecordModel.fromJson(_asMap(result));
  }

  /// Delete a record.
  Future<void> delete(String id) async {
    await _client.send(
      '$_basePath/records/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  // ---- Auth (Hanzo IAM-native) --------------------------------------------

  /// Authenticate against this auth collection and store the IAM token.
  Future<RecordAuth> authWithPassword(String identity, String password) async {
    final result = await _client.send(
      '$_basePath/auth-with-password',
      method: 'POST',
      body: {'identity': identity, 'password': password},
    );
    final auth = RecordAuth.fromJson(_asMap(result));
    _client.authStore.save(auth.token, auth.record);
    return auth;
  }

  /// Exchange OAuth2 code (from Hanzo IAM) for a session.
  Future<RecordAuth> authWithOAuth2Code({
    required String provider,
    required String code,
    required String codeVerifier,
    required String redirectUrl,
    Map<String, dynamic> createData = const {},
  }) async {
    final result = await _client.send(
      '$_basePath/auth-with-oauth2',
      method: 'POST',
      body: {
        'provider': provider,
        'code': code,
        'codeVerifier': codeVerifier,
        'redirectUrl': redirectUrl,
        'createData': createData,
      },
    );
    final auth = RecordAuth.fromJson(_asMap(result));
    _client.authStore.save(auth.token, auth.record);
    return auth;
  }

  /// Refresh the current session token.
  Future<RecordAuth> authRefresh() async {
    final result = await _client.send(
      '$_basePath/auth-refresh',
      method: 'POST',
    );
    final auth = RecordAuth.fromJson(_asMap(result));
    _client.authStore.save(auth.token, auth.record);
    return auth;
  }

  Future<void> requestVerification(String email) =>
      _client.send('$_basePath/request-verification',
          method: 'POST', body: {'email': email}).then((_) {});

  Future<void> confirmVerification(String token) =>
      _client.send('$_basePath/confirm-verification',
          method: 'POST', body: {'token': token}).then((_) {});

  Future<void> requestPasswordReset(String email) =>
      _client.send('$_basePath/request-password-reset',
          method: 'POST', body: {'email': email}).then((_) {});

  Future<void> confirmPasswordReset(
    String token,
    String password,
    String passwordConfirm,
  ) =>
      _client.send('$_basePath/confirm-password-reset', method: 'POST', body: {
        'token': token,
        'password': password,
        'passwordConfirm': passwordConfirm,
      }).then((_) {});

  // ---- Realtime -----------------------------------------------------------

  /// Subscribe to realtime changes. [topic] is `*` (all) or a record id.
  /// Returns a function that cancels this subscription.
  void Function() subscribe(String topic, RealtimeCallback callback) {
    return _client.realtime.subscribe(collectionIdOrName, topic, callback);
  }

  /// Cancel all realtime subscriptions for this collection.
  void unsubscribe() {
    _client.realtime.unsubscribe(collectionIdOrName);
  }

  // ---- Internal -----------------------------------------------------------

  Map<String, dynamic> _listQuery(
    String? filter,
    String? sort,
    String? expand,
    String? fields,
  ) {
    return {
      if (filter != null && filter.isNotEmpty) 'filter': filter,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (expand != null && expand.isNotEmpty) 'expand': expand,
      if (fields != null && fields.isNotEmpty) 'fields': fields,
    };
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};
}
