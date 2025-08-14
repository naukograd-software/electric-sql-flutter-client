import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream integration', () {
    test('syncs initial rows then goes up-to-date (long-poll)', () async {
      final stream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
        },
        subscribe: true,
      ));

      final completer = Completer<void>();
      late void Function() unsub;
      unsub = stream.subscribe((messages) {
        final upToDate = messages.any((m) => isUpToDateMessage(m));
        if (upToDate) {
          unsub();
          completer.complete();
        }
      });

      // Wait for up-to-date or timeout
      await completer.future.timeout(const Duration(seconds: 30));

      expect(stream.isUpToDate, isTrue);
      expect(stream.lastOffset, isNotEmpty);
    });
  });
}


