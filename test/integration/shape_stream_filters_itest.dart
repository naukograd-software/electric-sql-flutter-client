import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream where/columns', () {
    test('filters by where and selects columns', () async {
      // Arrange data
      final id1 = await insertWidget(name: 'foo');
      final id2 = await insertWidget(name: 'bar');

      final stream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
          'where': "name LIKE 'f%'",
          'columns': ['id', 'name'],
        },
        subscribe: true,
      ));
      final shape = Shape(stream);

      final rows = await shape.rows.timeout(const Duration(seconds: 30));
      expect(rows.any((r) => r['name'] == 'foo'), isTrue);
      expect(rows.any((r) => r['name'] == 'bar'), isFalse);

      // Update to break the filter
      await updateWidget(id: id1, name: 'zzz');
      await _waitUntil(() => shape.currentRows.every((r) => r['name'] != 'foo'),
          timeout: const Duration(seconds: 30));

      // columns check: no extra unexpected columns
      expect(shape.currentRows.every((r) => r.keys.toSet().containsAll({'id', 'name'})), isTrue);
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



