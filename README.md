# hanzo — Dart SDK for Hanzo Base

[![pub package](https://img.shields.io/pub/v/hanzo.svg)](https://pub.dev/packages/hanzo)

Small, typed Dart client for [Hanzo Base](https://hanzo.ai), the reactive
backend. Auth is [Hanzo IAM](https://hanzo.id)-native: the client holds the
IAM-issued JWT and validates its `exp` claim locally.

It mirrors the shape of the JavaScript client
[`@hanzo/base`](https://github.com/hanzo-js/base) and covers exactly what
apps need: auth, records/collections CRUD, realtime (SSE), and files.

## Install

```yaml
dependencies:
  hanzo: ^0.1.0
```

```dart
import 'package:hanzo/hanzo.dart';

final base = HanzoBase('https://base.hanzo.ai');
```

## Auth (Hanzo IAM)

```dart
await base.collection('users').authWithPassword('me@example.com', 'secret');

base.authStore.isValid;       // JWT present and unexpired
base.authStore.token;         // the IAM JWT
base.authStore.record;        // the authenticated record

base.authStore.clear();       // sign out
```

Persist the session with an `AsyncAuthStore` (e.g. secure storage):

```dart
final base = HanzoBase(
  'https://base.hanzo.ai',
  authStore: AsyncAuthStore(
    save: (data) => storage.write(key: 'hanzo_auth', value: data),
    initial: await storage.read(key: 'hanzo_auth'),
  ),
);
```

## Records / collections

```dart
final page = await base.collection('posts').getList(
  page: 1,
  perPage: 20,
  filter: base.filter('published = {:v}', {'v': true}),
  sort: '-created',
);

final one   = await base.collection('posts').getOne('RECORD_ID');
final all    = await base.collection('posts').getFullList();
final made   = await base.collection('posts').create({'title': 'hi'});
final edited = await base.collection('posts').update('RECORD_ID', {'title': 'yo'});
await base.collection('posts').delete('RECORD_ID');
```

## Realtime (SSE)

```dart
final off = base.collection('posts').subscribe('*', (e) {
  print('${e.action}: ${e.record.id}');  // create | update | delete
});

off(); // stop listening
```

## Files

```dart
final url = base.files.getUrl(record, 'photo.png', thumb: '100x100');

// upload via multipart
await base.collection('posts').create(
  {'title': 'with image'},
  files: [http.MultipartFile.fromBytes('image', bytes, filename: 'p.png')],
);
```

## Errors

Every request throws a typed `HanzoException` on failure:

```dart
try {
  await base.collection('posts').getOne('missing');
} on HanzoException catch (e) {
  print(e.statusCode); // 404
  print(e.message);    // server message
}
```

## Develop

```sh
dart pub get
dart analyze
dart test
```

## License

MIT © Hanzo AI, Inc. See [LICENSE](LICENSE).
