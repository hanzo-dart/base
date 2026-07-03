import 'record.dart';

/// Builds URLs for record file download.
class FileService {
  FileService(this._baseUrl);

  final String _baseUrl;

  /// Full URL to a record's file.
  ///
  /// Pass [thumb] for a server-generated thumbnail (e.g. `100x100`) and
  /// [token] for a private-file access token from `requestFileToken`.
  Uri getUrl(
    RecordModel record,
    String filename, {
    String? thumb,
    String? token,
  }) {
    if (filename.isEmpty || record.id.isEmpty) {
      return Uri.parse(_baseUrl);
    }

    final collection = record.collectionId.isNotEmpty
        ? record.collectionId
        : record.collectionName;

    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;

    final path = [
      base,
      'v1',
      'files',
      Uri.encodeComponent(collection),
      Uri.encodeComponent(record.id),
      Uri.encodeComponent(filename),
    ].join('/');

    final query = <String, String>{
      if (thumb != null && thumb.isNotEmpty) 'thumb': thumb,
      if (token != null && token.isNotEmpty) 'token': token,
    };

    return Uri.parse(path)
        .replace(queryParameters: query.isEmpty ? null : query);
  }
}
