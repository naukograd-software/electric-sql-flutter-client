import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream updates flow', () {
    test('insert/update/delete are observed', () async {
      final stream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
        },
        subscribe: true,
      ));
      final shape = Shape(stream);

      // Wait initial up-to-date
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await shape.rows.timeout(const Duration(seconds: 30));
      final initialLen = shape.currentRows.length;

      // Insert
      final id = await insertWidget(name: 'itest-insert');

      await _waitUntil(() => shape.currentRows.length == initialLen + 1, timeout: const Duration(seconds: 30));
      expect(shape.currentRows.any((r) => r['name'] == 'itest-insert'), isTrue);

      // Update
      await updateWidget(id: id, name: 'itest-updated');
      await _waitUntil(() => shape.currentRows.any((r) => r['id'].toString() == id && r['name'] == 'itest-updated'),
          timeout: const Duration(seconds: 30));

      // Delete
      await deleteWidget(id: id);
      await _waitUntil(() => shape.currentRows.length == initialLen, timeout: const Duration(seconds: 30));
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



