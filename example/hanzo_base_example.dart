import 'package:hanzo_base/hanzo_base.dart';

Future<void> main() async {
  final base = HanzoBase('https://base.hanzo.ai');

  // Authenticate against a Hanzo IAM-backed auth collection.
  await base.collection('users').authWithPassword('me@example.com', 'secret');

  // List records.
  final page = await base.collection('posts').getList(
        perPage: 20,
        filter: base.filter('published = {:v}', {'v': true}),
        sort: '-created',
      );
  for (final record in page.items) {
    // ignore: avoid_print
    print('${record.id}: ${record['title']}');
  }

  // Subscribe to realtime changes.
  final unsubscribe = base.collection('posts').subscribe('*', (event) {
    // ignore: avoid_print
    print('${event.action}: ${event.record.id}');
  });

  // Later: stop listening and release resources.
  unsubscribe();
  base.close();
}
