import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final shapeUrl = Platform.environment['ELECTRIC_SHAPE_URL'] ?? 'http://localhost:3000/v1/shape';

  group('ShapeStream catch-up with offset/handle', () {
    test('applies only changes after stored offset', () async {
      // Ensure at least one row exists
      await insertWidget(name: 'before-1');
      await insertWidget(name: 'before-2');

      // First snapshot stream (single fetch)
      final snapStream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
        },
        subscribe: false,
      ));

      // Wait until it reaches up-to-date
      final completer = Completer<void>();
      late void Function() unsub;
      unsub = snapStream.subscribe((messages) {
        if (messages.any(isUpToDateMessage)) {
          unsub();
          completer.complete();
        }
      });
      await completer.future.timeout(const Duration(seconds: 30));

      final savedOffset = snapStream.lastOffset;
      final savedHandle = snapStream.shapeHandle;
      expect(savedHandle, isNotNull);

      // Now perform N changes
      const n = 3;
      for (int i = 0; i < n; i++) {
        await insertWidget(name: 'after-$i');
      }

      // Start catch-up stream from saved state
      var changes = 0;
      final catchupStream = ShapeStream(ShapeStreamOptions(
        url: shapeUrl,
        params: {
          'table': 'widgets',
        },
        offset: savedOffset,
        handle: savedHandle,
        subscribe: true,
      ));

      final done = Completer<void>();
      late void Function() unsub2;
      unsub2 = catchupStream.subscribe((messages) {
        for (final m in messages) {
          if (isChangeMessage(m)) changes++;
        }
        if (messages.any(isUpToDateMessage)) {
          unsub2();
          done.complete();
        }
      });

      await done.future.timeout(const Duration(seconds: 30));
      expect(changes, n);
    });
  });
}


