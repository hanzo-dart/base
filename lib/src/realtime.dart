import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'record.dart';

/// A realtime change delivered over the SSE stream.
class RealtimeEvent {
  RealtimeEvent({required this.action, required this.record});

  /// One of `create`, `update`, `delete`.
  final String action;
  final RecordModel record;
}

typedef RealtimeCallback = void Function(RealtimeEvent event);

/// Connection state of the realtime stream.
enum RealtimeState { disconnected, connecting, connected }

class _Subscription {
  _Subscription(this.collection, this.topic);
  final String collection;
  final String topic;
  final callbacks = <RealtimeCallback>{};
}

/// SSE-based realtime subscription manager.
///
/// Opens a single `GET /v1/realtime` stream, deduplicates subscriptions by
/// `collection/topic`, submits them to the server, and fans incoming events
/// out to matching callbacks. Reconnects with exponential backoff.
class RealtimeService {
  RealtimeService(
    String baseUrl,
    this._getToken, {
    http.Client Function()? clientFactory,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _clientFactory = clientFactory ?? http.Client.new;

  final String _baseUrl;
  final String Function() _getToken;
  final http.Client Function() _clientFactory;

  final _subscriptions = <String, _Subscription>{};

  http.Client? _client;
  StreamSubscription<String>? _streamSub;
  String? _clientId;
  RealtimeState _state = RealtimeState.disconnected;
  bool _intentionalDisconnect = false;

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const _baseReconnectDelayMs = 500;
  static const _maxReconnectDelayMs = 30000;

  RealtimeState get state => _state;

  /// Subscribe to `collection`/`topic` (topic `*` = all records, or a record
  /// id). Returns a function that removes this subscription.
  void Function() subscribe(
    String collection,
    String topic,
    RealtimeCallback callback,
  ) {
    final key = '$collection::$topic';
    final sub = _subscriptions.putIfAbsent(
      key,
      () => _Subscription(collection, topic),
    );
    sub.callbacks.add(callback);

    if (_client == null) {
      _connect();
    } else if (_clientId != null) {
      unawaited(_submitSubscriptions());
    }

    return () {
      sub.callbacks.remove(callback);
      if (sub.callbacks.isEmpty) {
        _subscriptions.remove(key);
        if (_clientId != null) {
          unawaited(_submitSubscriptions());
        }
      }
      if (_subscriptions.isEmpty) {
        disconnect();
      }
    };
  }

  /// Remove all callbacks for `collection`, or every subscription when null.
  void unsubscribe([String? collection]) {
    if (collection == null) {
      _subscriptions.clear();
    } else {
      _subscriptions.removeWhere((_, sub) => sub.collection == collection);
    }
    if (_clientId != null) {
      unawaited(_submitSubscriptions());
    }
    if (_subscriptions.isEmpty) {
      disconnect();
    }
  }

  /// Close the stream and drop all state.
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamSub?.cancel();
    _streamSub = null;
    _client?.close();
    _client = null;
    _clientId = null;
    _state = RealtimeState.disconnected;
  }

  Future<void> _connect() async {
    if (_client != null) {
      return;
    }
    _intentionalDisconnect = false;
    _state = RealtimeState.connecting;

    final client = _clientFactory();
    _client = client;

    try {
      final request = http.Request('GET', Uri.parse('$_baseUrl/v1/realtime'))
        ..headers['Accept'] = 'text/event-stream';
      final token = _getToken();
      if (token.isNotEmpty) {
        request.headers['Authorization'] = token;
      }

      final response = await client.send(request);
      if (response.statusCode >= 400) {
        _onDisconnect();
        return;
      }

      var event = 'message';
      final data = StringBuffer();

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.isEmpty) {
            _dispatch(event, data.toString());
            event = 'message';
            data.clear();
            return;
          }
          if (line.startsWith(':')) {
            return; // comment / keep-alive
          }
          if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            if (data.isNotEmpty) {
              data.write('\n');
            }
            data.write(line.substring(5).trimLeft());
          }
        },
        onError: (_) => _onDisconnect(),
        onDone: _onDisconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _onDisconnect();
    }
  }

  void _dispatch(String event, String data) {
    if (data.isEmpty) {
      return;
    }
    dynamic payload;
    try {
      payload = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (payload is! Map<String, dynamic>) {
      return;
    }

    if (event == 'CONNECT' || event == 'PB_CONNECT') {
      _clientId = payload['clientId']?.toString();
      _reconnectAttempts = 0;
      _state = RealtimeState.connected;
      unawaited(_submitSubscriptions());
      return;
    }

    final action = payload['action']?.toString() ?? '';
    final rawRecord = payload['record'];
    if (rawRecord is! Map<String, dynamic>) {
      return;
    }
    final record = RecordModel.fromJson(rawRecord);
    if (record.id.isEmpty) {
      return;
    }

    for (final sub in _subscriptions.values) {
      if (sub.collection != record.collectionName) {
        continue;
      }
      if (sub.topic != '*' && sub.topic != record.id) {
        continue;
      }
      final realtimeEvent = RealtimeEvent(action: action, record: record);
      for (final callback in sub.callbacks.toList()) {
        callback(realtimeEvent);
      }
    }
  }

  Future<void> _submitSubscriptions() async {
    final clientId = _clientId;
    if (clientId == null) {
      return;
    }
    final topics = _subscriptions.values
        .map((sub) => '${sub.collection}/${sub.topic}')
        .toList();

    try {
      final token = _getToken();
      final client = _clientFactory();
      try {
        await client.post(
          Uri.parse('$_baseUrl/v1/realtime'),
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': token,
          },
          body: jsonEncode({'clientId': clientId, 'subscriptions': topics}),
        );
      } finally {
        client.close();
      }
    } catch (_) {
      // will retry on next reconnect
    }
  }

  void _onDisconnect() {
    _streamSub?.cancel();
    _streamSub = null;
    _client?.close();
    _client = null;
    _clientId = null;
    _state = RealtimeState.disconnected;

    if (!_intentionalDisconnect && _subscriptions.isNotEmpty) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final exp = _baseReconnectDelayMs * (1 << _reconnectAttempts);
    final capped = exp > _maxReconnectDelayMs ? _maxReconnectDelayMs : exp;
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(milliseconds: capped), _connect);
  }
}
