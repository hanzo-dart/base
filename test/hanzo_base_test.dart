import 'dart:convert';

import 'package:hanzo_base/hanzo_base.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Builds an unsigned JWT with the given payload (for local exp checks).
String jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'none'})}.${seg(payload)}.sig';
}

HanzoBase clientWith(
  Future<http.Response> Function(http.Request request) handler, {
  AuthStore? authStore,
}) {
  return HanzoBase(
    'https://base.hanzo.ai',
    authStore: authStore,
    httpClientFactory: () => MockClient((r) => handler(r)),
  );
}

void main() {
  group('jwt', () {
    test('decodes payload', () {
      final payload = getTokenPayload(jwt({'id': 'u1', 'exp': 9999999999}));
      expect(payload['id'], 'u1');
    });

    test('malformed token -> empty', () {
      expect(getTokenPayload('not-a-jwt'), isEmpty);
    });

    test('expiration', () {
      expect(isTokenExpired(jwt({'exp': 9999999999})), isFalse);
      expect(isTokenExpired(jwt({'exp': 1})), isTrue);
      expect(isTokenExpired(jwt({})), isTrue);
    });
  });

  group('MemoryAuthStore', () {
    test('isValid tracks token exp', () {
      final store = MemoryAuthStore();
      expect(store.isValid, isFalse);
      store.save(jwt({'exp': 9999999999}), RecordModel(id: 'u1'));
      expect(store.isValid, isTrue);
      expect(store.record?.id, 'u1');
      store.save(jwt({'exp': 1}), null);
      expect(store.isValid, isFalse);
    });

    test('onChange fires and unsubscribes', () {
      final store = MemoryAuthStore();
      final seen = <String>[];
      final off = store.onChange((token, _) => seen.add(token));
      store.save('a', null);
      off();
      store.save('b', null);
      expect(seen, ['a']);
    });
  });

  group('AsyncAuthStore', () {
    test('persists on save and seeds from initial', () {
      var persisted = '';
      final store = AsyncAuthStore(save: (d) async => persisted = d);
      store.save(jwt({'exp': 9999999999}), RecordModel(id: 'u1'));
      expect(persisted, contains('u1'));

      final restored = AsyncAuthStore(save: (_) async {}, initial: persisted);
      expect(restored.token, isNotEmpty);
      expect(restored.record?.id, 'u1');
    });
  });

  group('records CRUD', () {
    test('getList parses ListResult and builds url', () async {
      late Uri seenUrl;
      final base = clientWith((r) async {
        seenUrl = r.url;
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 20,
            'totalItems': 1,
            'totalPages': 1,
            'items': [
              {'id': 'r1', 'collectionName': 'posts', 'title': 'hi'}
            ],
          }),
          200,
        );
      });

      final result = await base.collection('posts').getList(perPage: 20);
      expect(result.totalItems, 1);
      expect(result.items.single.id, 'r1');
      expect(result.items.single['title'], 'hi');
      expect(seenUrl.path, '/v1/collections/posts/records');
      expect(seenUrl.queryParameters['perPage'], '20');
    });

    test('getOne', () async {
      final base = clientWith((r) async {
        expect(r.method, 'GET');
        expect(r.url.path, '/v1/collections/posts/records/r1');
        return http.Response(jsonEncode({'id': 'r1'}), 200);
      });
      final rec = await base.collection('posts').getOne('r1');
      expect(rec.id, 'r1');
    });

    test('create sends JSON body', () async {
      final base = clientWith((r) async {
        expect(r.method, 'POST');
        expect(jsonDecode(r.body)['title'], 'new');
        return http.Response(jsonEncode({'id': 'r2', 'title': 'new'}), 200);
      });
      final rec = await base.collection('posts').create({'title': 'new'});
      expect(rec.id, 'r2');
    });

    test('update sends PATCH', () async {
      final base = clientWith((r) async {
        expect(r.method, 'PATCH');
        return http.Response(jsonEncode({'id': 'r1', 'title': 'x'}), 200);
      });
      final rec = await base.collection('posts').update('r1', {'title': 'x'});
      expect(rec['title'], 'x');
    });

    test('delete sends DELETE', () async {
      var called = false;
      final base = clientWith((r) async {
        called = r.method == 'DELETE';
        return http.Response('', 204);
      });
      await base.collection('posts').delete('r1');
      expect(called, isTrue);
    });

    test('error response throws HanzoException', () async {
      final base = clientWith(
          (r) async => http.Response(jsonEncode({'message': 'nope'}), 404));
      expect(
        () => base.collection('posts').getOne('missing'),
        throwsA(isA<HanzoException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'nope')),
      );
    });
  });

  group('auth', () {
    test('authWithPassword stores IAM token', () async {
      final base = clientWith((r) async {
        expect(r.url.path, '/v1/collections/users/auth-with-password');
        expect(jsonDecode(r.body)['identity'], 'me@example.com');
        return http.Response(
          jsonEncode({
            'token': jwt({'exp': 9999999999}),
            'record': {'id': 'u1'},
          }),
          200,
        );
      });

      final auth = await base
          .collection('users')
          .authWithPassword('me@example.com', 'pw');
      expect(auth.record.id, 'u1');
      expect(base.authStore.isValid, isTrue);
      expect(base.authStore.record?.id, 'u1');
    });

    test('adds Authorization header when session valid', () async {
      String? seenAuth;
      final store = MemoryAuthStore()..save(jwt({'exp': 9999999999}), null);
      final base = clientWith((r) async {
        seenAuth = r.headers['Authorization'];
        return http.Response(jsonEncode({'id': 'r1'}), 200);
      }, authStore: store);

      await base.collection('posts').getOne('r1');
      expect(seenAuth, isNotNull);
      expect(seenAuth, store.token);
    });
  });

  group('filter binding', () {
    test('escapes strings and formats values', () {
      final base = clientWith((r) async => http.Response('{}', 200));
      final expr = base.filter(
        'a = {:n} && b ~ {:s} && c = {:flag}',
        {'n': 5, 's': "o'brien", 'flag': true},
      );
      expect(expr, "a = 5 && b ~ 'o\\'brien' && c = true");
    });
  });

  group('files', () {
    test('getUrl builds a file url', () {
      final base = clientWith((r) async => http.Response('{}', 200));
      final record = RecordModel.fromJson(
          {'id': 'r1', 'collectionId': 'c1', 'collectionName': 'posts'});
      final url = base.files.getUrl(record, 'photo.png', thumb: '100x100');
      expect(url.path, '/v1/files/c1/r1/photo.png');
      expect(url.queryParameters['thumb'], '100x100');
    });
  });
}
