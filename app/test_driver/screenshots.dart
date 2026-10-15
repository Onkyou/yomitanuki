// Host-side driver for integration_test/screenshots_test.dart: saves every
// `binding.takeScreenshot(name)` as build/screenshots/<name>.png.
//
//   flutter drive --driver=test_driver/screenshots.dart \
//     --target=integration_test/screenshots_test.dart -d <simulator>
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('build/screenshots/$name.png')
            ..createSync(recursive: true);
          file.writeAsBytesSync(bytes);
          return true;
        },
  );
}
