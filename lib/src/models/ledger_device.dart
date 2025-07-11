import 'package:ledger_flutter/src/ledger/connection_type.dart';
import 'package:ledger_usb/usb_device.dart';

import '../ledger/ledger_device_type.dart';

class LedgerDevice {
  final String id;
  final String name;
  final ConnectionType connectionType;
  final int rssi;
  final LedgerDeviceType deviceInfo;

  LedgerDevice({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.deviceInfo,
    this.rssi = 0,
  });

  factory LedgerDevice.fromUsbDevice(UsbDevice device) {
    return LedgerDevice(
        id: device.identifier,
        name: device.productName,
        connectionType: ConnectionType.usb,
        deviceInfo: LedgerDeviceType.values.firstWhere(
          (e) => device.productId >> 8 == e.productIdMM,
          orElse: () => LedgerDeviceType.nanoX,
        ));
  }

  LedgerDevice copyWith(
      {String Function()? id,
      String Function()? name,
      ConnectionType Function()? connectionType,
      int Function()? rssi,
      LedgerDeviceType Function()? deviceInfo}) {
    return LedgerDevice(
      id: id != null ? id() : this.id,
      name: name != null ? name() : this.name,
      connectionType:
          connectionType != null ? connectionType() : this.connectionType,
      rssi: rssi != null ? rssi() : this.rssi,
      deviceInfo: deviceInfo != null ? deviceInfo() : this.deviceInfo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
