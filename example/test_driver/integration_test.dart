import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes the screenshots of integration_test/docs_screenshots_test.dart to
/// $DOCS_SHOTS (default build/docs_screenshots).
Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final String dir =
            Platform.environment['DOCS_SHOTS'] ?? 'build/docs_screenshots';
        File('$dir/$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        return true;
      },
);
