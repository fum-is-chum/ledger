import 'dart:async';

import 'package:ledger_flutter/ledger_flutter.dart';

import 'ledger_device_type.dart';

class LedgerBleSearchManager extends BleSearchManager {
  final List<Uuid> _withServices =
      LedgerDeviceType.ble.map((e) => Uuid.parse(e.serviceId)).toList();

  final _bleManager = FlutterReactiveBle();
  final LedgerOptions _options;
  final PermissionRequestCallback? onPermissionRequest;

  final _scannedIds = <String>{};
  bool _isScanning = false;
  StreamSubscription? _scanSubscription;
  StreamController<LedgerDevice> streamController =
      StreamController.broadcast();

  LedgerBleSearchManager({
    required LedgerOptions options,
    this.onPermissionRequest,
  }) : _options = options;

  @override
  Stream<LedgerDevice> scan({LedgerOptions? options}) async* {
    // Check for permissions
    final granted = (await onPermissionRequest?.call(status)) ?? true;
    if (!granted) {
      return;
    }

    if (_isScanning) {
      return;
    }

    // Start scanning
    _isScanning = true;
    _scannedIds.clear();
    streamController.close();
    streamController = StreamController.broadcast();

    _scanSubscription?.cancel();
    _scanSubscription = _bleManager
        .scanForDevices(
      withServices: _withServices,
      scanMode: options?.scanMode ?? _options.scanMode,
      requireLocationServicesEnabled: options?.requireLocationServicesEnabled ??
          _options.requireLocationServicesEnabled,
    )
        .listen(
      (device) {
        if (_scannedIds.contains(device.id)) {
          return;
        }

        final deviceInfo = LedgerDeviceType.ble.firstWhere(
          (element) =>
              device.serviceUuids.contains(Uuid.parse(element.serviceId)),
          orElse: () => LedgerDeviceType.nanoX,
        );

        final lDevice = LedgerDevice(
          id: device.id,
          name: device.name,
          connectionType: ConnectionType.ble,
          rssi: device.rssi,
          deviceInfo: deviceInfo,
        );

        _scannedIds.add(lDevice.id);
        streamController.add(lDevice);
      },
    );

    Future.delayed(options?.maxScanDuration ?? _options.maxScanDuration, () {
      stop();
    });

    yield* streamController.stream;
  }

  @override
  Future<void> stop() async {
    if (!_isScanning) {
      return;
    }

    _isScanning = false;
    _scanSubscription?.cancel();
    streamController.close();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  /// Returns the current status of the BLE subsystem of the host device.
  BleStatus get status => _bleManager.status;
}
