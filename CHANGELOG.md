# Changelog

## 0.1.0

Initial release. Clean, minimal Dart client for Hanzo Base:

- Hanzo IAM-native auth: `MemoryAuthStore` (default) and `AsyncAuthStore`,
  local JWT `exp` validation, `authWithPassword` / `authWithOAuth2Code` /
  `authRefresh`.
- Records / collections CRUD: `getList`, `getFullList`, `getOne`,
  `getFirstListItem`, `create`, `update`, `delete` (with multipart upload).
- Realtime over SSE: `collection(name).subscribe/unsubscribe` with
  auto-reconnect.
- File URLs: `files.getUrl(record, filename, {thumb, token})`.
- Safe filter binding via `base.filter('a = {:x}', {'x': v})`.

Mirrors the `@hanzo/base` JavaScript client. Written from scratch — no
external backend framework.
