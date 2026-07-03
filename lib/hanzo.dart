/// Dart SDK for [Hanzo Base](https://hanzo.ai) — the reactive backend.
///
/// Records/collections CRUD, realtime (SSE), and file URLs, with
/// [Hanzo IAM](https://hanzo.id)-native auth. Mirrors the `@hanzo/base`
/// JavaScript client.
library;

export 'src/auth_store.dart';
export 'src/client.dart' show HanzoBase;
export 'src/collection.dart' show CollectionService;
export 'src/exception.dart' show HanzoException;
export 'src/files.dart' show FileService;
export 'src/jwt.dart' show getTokenPayload, isTokenExpired;
export 'src/realtime.dart'
    show RealtimeService, RealtimeEvent, RealtimeCallback, RealtimeState;
export 'src/record.dart' show RecordModel, ListResult, RecordAuth;
