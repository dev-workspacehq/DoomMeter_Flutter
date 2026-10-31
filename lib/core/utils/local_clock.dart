import 'package:injectable/injectable.dart';

/// Injectable device time so date rules can also be tested across midnight.
@lazySingleton
class LocalClock {
  DateTime now() => DateTime.now();
}
