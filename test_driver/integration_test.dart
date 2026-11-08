// Runs integration tests in profile or release mode:
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart
//     --target=integration_test/<test>.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
