import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream forceDisconnectAndRefresh', () {
    test('refresh aborts long-poll and restarts', () async {
      final id = await insertWidget(name: 'initial title');

      final stream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
        },
        subscribe: true,
      ));
      final shape = Shape(stream);
      await shape.rows.timeout(const Duration(seconds: 30));

      await updateWidget(id: id, name: 'updated title');

      // Force refresh
      await stream.forceDisconnectAndRefresh();

      // Ensure we converge to the updated value
      await _waitUntil(
        () => shape.currentRows.any((r) => r['id'].toString() == id && r['name'] == 'updated title'),
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


