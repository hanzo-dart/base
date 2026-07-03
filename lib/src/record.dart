import 'dart:convert';

/// A single Hanzo Base record.
///
/// Wraps the raw JSON map with typed accessors for the common system
/// fields. Arbitrary user fields are available via [operator []] or [get].
class RecordModel {
  RecordModel({
    this.id = '',
    this.collectionId = '',
    this.collectionName = '',
    this.created = '',
    this.updated = '',
    Map<String, dynamic> data = const {},
  }) : data = {
          ...data,
          if (id.isNotEmpty) 'id': id,
          if (collectionId.isNotEmpty) 'collectionId': collectionId,
          if (collectionName.isNotEmpty) 'collectionName': collectionName,
          if (created.isNotEmpty) 'created': created,
          if (updated.isNotEmpty) 'updated': updated,
        };

  factory RecordModel.fromJson(Map<String, dynamic> json) {
    return RecordModel(
      id: (json['id'] ?? '').toString(),
      collectionId: (json['collectionId'] ?? '').toString(),
      collectionName: (json['collectionName'] ?? '').toString(),
      created: (json['created'] ?? '').toString(),
      updated: (json['updated'] ?? '').toString(),
      data: json,
    );
  }

  final String id;
  final String collectionId;
  final String collectionName;
  final String created;
  final String updated;

  /// The full record body, including system and user fields.
  final Map<String, dynamic> data;

  /// Read a user field.
  dynamic operator [](String key) => data[key];

  /// Read a user field with a typed fallback.
  T get<T>(String key, T defaultValue) {
    final value = data[key];
    return value is T ? value : defaultValue;
  }

  Map<String, dynamic> toJson() => data;

  @override
  String toString() => jsonEncode(data);
}

/// A paginated list of records returned by `getList`.
class ListResult {
  ListResult({
    required this.page,
    required this.perPage,
    required this.totalItems,
    required this.totalPages,
    required this.items,
  });

  factory ListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ListResult(
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['perPage'] as num?)?.toInt() ?? 0,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(RecordModel.fromJson)
              .toList()
          : const [],
    );
  }

  final int page;
  final int perPage;
  final int totalItems;
  final int totalPages;
  final List<RecordModel> items;
}

/// The result of an auth request: the IAM-issued token and the record.
class RecordAuth {
  RecordAuth({required this.token, required this.record});

  factory RecordAuth.fromJson(Map<String, dynamic> json) {
    final record = json['record'];
    return RecordAuth(
      token: (json['token'] ?? '').toString(),
      record: record is Map<String, dynamic>
          ? RecordModel.fromJson(record)
          : RecordModel(),
    );
  }

  final String token;
  final RecordModel record;
}
