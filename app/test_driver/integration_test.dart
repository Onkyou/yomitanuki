// Host-side driver for `flutter drive --driver=test_driver/integration_test.dart
// --target=integration_test/reader_flow_test.dart`. `make gate-integration`
// uses `flutter test integration_test`, which does not need this file; it is
// here for the `flutter drive` form (timeline/profile runs).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
