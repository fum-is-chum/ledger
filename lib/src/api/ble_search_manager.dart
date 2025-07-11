import 'package:ledger/ledger.dart';

abstract class BleSearchManager {
  Stream<LedgerDevice> scan({LedgerOptions? options});

  Future<void> stop();

  Future<void> dispose();
}
