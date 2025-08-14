import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream replica=full', () {
    test('update contains unchanged columns', () async {
      final id = await insertWidget(name: 'first title');

      final stream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
          'replica': 'full',
        },
        subscribe: true,
      ));

      final received = <Map<String, dynamic>>[];
      late void Function() unsub;
      unsub = stream.subscribe((messages) {
        for (final m in messages) {
          if (isChangeMessage(m)) {
            received.add((m['value'] as Map).cast<String, dynamic>());
          }
        }
        if (isUpToDateMessage(messages.last)) unsub();
      });

      // Wait initial up-to-date
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await updateWidget(id: id, name: 'updated title');

      // Wait until we observe an update with priority present
      await _waitUntil(
        () => received.any((r) => r['id'].toString() == id && r['name'] == 'updated title' && r['priority'] == 10),
        timeout: const Duration(seconds: 30),
      );
    });
  });
}

Future<void> _waitUntil(bool Function() cond, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Condition not met within ${timeout.inSeconds}s');
}


