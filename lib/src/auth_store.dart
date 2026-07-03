import 'dart:async';
import 'dart:convert';

import 'jwt.dart';
import 'record.dart';

/// Callback invoked whenever the stored auth token or record changes.
typedef AuthChangeCallback = void Function(String token, RecordModel? record);

/// Holds the current Hanzo IAM-issued token and the authenticated record.
///
/// The default [MemoryAuthStore] keeps state in memory and validates the
/// token's `exp` claim locally. Provide an [AsyncAuthStore] to persist the
/// session (e.g. secure storage on mobile).
abstract class AuthStore {
  String get token;
  RecordModel? get record;

  /// Whether a non-expired IAM token is present.
  bool get isValid => token.isNotEmpty && !isTokenExpired(token);

  void save(String token, RecordModel? record);
  void clear();

  /// Register a change listener. Returns a function that removes it.
  void Function() onChange(AuthChangeCallback callback,
      {bool fireImmediately = false});
}

/// In-memory auth store. The default when none is supplied.
class MemoryAuthStore extends AuthStore {
  String _token = '';
  RecordModel? _record;
  final _listeners = <AuthChangeCallback>{};

  @override
  String get token => _token;

  @override
  RecordModel? get record => _record;

  @override
  void save(String token, RecordModel? record) {
    _token = token;
    _record = record;
    _notify();
  }

  @override
  void clear() {
    _token = '';
    _record = null;
    _notify();
  }

  @override
  void Function() onChange(AuthChangeCallback callback,
      {bool fireImmediately = false}) {
    _listeners.add(callback);
    if (fireImmediately) {
      callback(_token, _record);
    }
    return () => _listeners.remove(callback);
  }

  void _notify() {
    for (final listener in _listeners.toList()) {
      listener(_token, _record);
    }
  }
}

/// Auth store backed by an async persistence layer.
///
/// Supply [save] to persist the serialized session and [initial] to seed
/// the store from previously-saved state. The value passed to [save] and
/// returned from [initial] is an opaque JSON string.
///
/// ```dart
/// AsyncAuthStore(
///   save: (data) => storage.write(key: 'hanzo_auth', value: data),
///   initial: await storage.read(key: 'hanzo_auth'),
/// );
/// ```
class AsyncAuthStore extends AuthStore {
  AsyncAuthStore({
    required Future<void> Function(String data) save,
    String? initial,
    Future<void> Function()? clear,
  })  : _save = save,
        _clear = clear {
    if (initial != null && initial.isNotEmpty) {
      _load(initial);
    }
  }

  final Future<void> Function(String data) _save;
  final Future<void> Function()? _clear;

  String _token = '';
  RecordModel? _record;
  final _listeners = <AuthChangeCallback>{};

  @override
  String get token => _token;

  @override
  RecordModel? get record => _record;

  @override
  void save(String token, RecordModel? record) {
    _token = token;
    _record = record;
    _notify();
    unawaited(_save(jsonEncode({
      'token': token,
      'record': record?.toJson(),
    })));
  }

  @override
  void clear() {
    _token = '';
    _record = null;
    _notify();
    final clear = _clear;
    if (clear != null) {
      unawaited(clear());
    } else {
      unawaited(_save(''));
    }
  }

  @override
  void Function() onChange(AuthChangeCallback callback,
      {bool fireImmediately = false}) {
    _listeners.add(callback);
    if (fireImmediately) {
      callback(_token, _record);
    }
    return () => _listeners.remove(callback);
  }

  void _load(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        _token = (data['token'] ?? '').toString();
        final record = data['record'];
        _record = record is Map<String, dynamic>
            ? RecordModel.fromJson(record)
            : null;
      }
    } catch (_) {
      // ignore corrupt persisted state
    }
  }

  void _notify() {
    for (final listener in _listeners.toList()) {
      listener(_token, _record);
    }
  }
}
