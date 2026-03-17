import 'dart:async';

import 'package:ledger_scallop/ledger_scallop.dart';

class LedgerBleConnectionManager extends BleConnectionManager {
  final _bleManager = FlutterReactiveBle();
  final LedgerOptions _options;
  final PermissionRequestCallback? onPermissionRequest;
  final _connectedDevices = <LedgerDevice, GattGateway>{};
  final _connectionSubscriptions =
      <LedgerDevice, StreamSubscription<ConnectionStateUpdate>>{};

  LedgerBleConnectionManager({
    required LedgerOptions options,
    this.onPermissionRequest,
  }) : _options = options;

  @override
  Future<void> connect(
    LedgerDevice device, {
    LedgerOptions? options,
  }) async {
    final granted = (await onPermissionRequest?.call(status)) ?? true;
    if (!granted) {
      return;
    }

    await disconnect(device);

    final connectCompleter = Completer<void>();
    final serviceId = Uuid.parse(device.deviceInfo.serviceId);
    final discoveryMap = _servicesWithCharacteristics(device);

    late final StreamSubscription<ConnectionStateUpdate> subscription;
    subscription = _bleManager
        .connectToAdvertisingDevice(
      id: device.id,
      withServices: [serviceId],
      servicesWithCharacteristicsToDiscover: discoveryMap,
      prescanDuration: options?.prescanDuration ?? _options.prescanDuration,
      connectionTimeout:
          options?.connectionTimeout ?? _options.connectionTimeout,
    )
        .listen(
      (state) async {
        if (state.connectionState == DeviceConnectionState.connected &&
            !_connectedDevices.containsKey(device)) {
          try {
            final services = await _bleManager.getDiscoveredServices(device.id);
            final ledger = DiscoveredLedger(
              device: device,
              subscription: subscription,
              services: services,
            );

            final gateway = LedgerGattGateway(
              bleManager: _bleManager,
              ledger: ledger,
              mtu: options?.mtu ?? _options.mtu,
            );

            await gateway.start();
            _connectedDevices[device] = gateway;

            if (!connectCompleter.isCompleted) {
              connectCompleter.complete();
            }
          } catch (ex, st) {
            await _cleanup(device);
            if (!connectCompleter.isCompleted) {
              connectCompleter.completeError(ex, st);
            }
          }
        }

        if (state.connectionState == DeviceConnectionState.disconnected) {
          await _cleanup(device);
          if (!connectCompleter.isCompleted) {
            connectCompleter.completeError(
              LedgerException(
                message: 'Device disconnected while establishing BLE session.',
              ),
            );
          }
        }
      },
      onError: (ex, st) async {
        await _cleanup(device);
        if (!connectCompleter.isCompleted) {
          connectCompleter.completeError(ex, st);
        }
      },
    );

    _connectionSubscriptions[device] = subscription;
    return connectCompleter.future;
  }

  @override
  Future<T> sendOperation<T>(
    LedgerDevice device,
    LedgerOperation<T> operation,
    LedgerTransformer? transformer,
  ) async {
    final gateway = _connectedDevices[device];
    if (gateway == null) {
      throw LedgerException(message: 'Unable to send request.');
    }

    return gateway.sendOperation<T>(
      operation,
      transformer: transformer,
    );
  }

  @override
  BleStatus get status => _bleManager.status;

  @override
  Stream<BleStatus> get statusStateChanges => _bleManager.statusStream;

  @override
  List<LedgerDevice> get devices => _connectedDevices.keys.toList();

  @override
  Stream<ConnectionStateUpdate> get deviceStateChanges =>
      _bleManager.connectedDeviceStream;

  @override
  Future<void> disconnect(LedgerDevice device) => _cleanup(device);

  @override
  Future<void> dispose() async {
    final devices = _connectedDevices.keys.toList();
    for (final device in devices) {
      await _cleanup(device);
    }

    final danglingSubscriptions = _connectionSubscriptions.keys.toList();
    for (final device in danglingSubscriptions) {
      await _cleanup(device);
    }
  }

  Future<void> _cleanup(LedgerDevice device) async {
    final gateway = _connectedDevices.remove(device);
    if (gateway != null) {
      await gateway.disconnect();
    }

    final subscription = _connectionSubscriptions.remove(device);
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  Map<Uuid, List<Uuid>> _servicesWithCharacteristics(LedgerDevice device) {
    final serviceId = Uuid.parse(device.deviceInfo.serviceId);
    return {
      serviceId: [
        Uuid.parse(device.deviceInfo.writeCharacteristicKey),
        Uuid.parse(device.deviceInfo.notifyCharacteristicKey),
        if (device.deviceInfo.writeCmdKey != null)
          Uuid.parse(device.deviceInfo.writeCmdKey!),
      ],
    };
  }
}
