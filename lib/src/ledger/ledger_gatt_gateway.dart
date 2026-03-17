import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:ledger_scallop/ledger_scallop.dart';

/// https://learn.adafruit.com/introduction-to-bluetooth-low-energy/gatt
/// https://gist.github.com/btchip/e4994180e8f4710d29c975a49de46e3a
class LedgerGattGateway extends GattGateway {
  static const _exchangeTimeout = Duration(seconds: 10);
  static const _iosNotificationReadyDelay = Duration(milliseconds: 250);
  static const _iosRetryDelays = [
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
    Duration(seconds: 1),
  ];

  final FlutterReactiveBle bleManager;
  final BlePacker _packer;
  final DiscoveredLedger ledger;
  final LedgerGattReader _gattReader;
  final Function? _onError;

  Characteristic? characteristicWrite;
  Characteristic? characteristicWriteCmd;
  Characteristic? characteristicNotify;
  int _mtu;
  _PendingRequest? _pendingRequest;
  Future<void> _exchangeTail = Future.value();
  bool _started = false;
  bool _closed = false;

  LedgerGattGateway({
    required this.bleManager,
    required this.ledger,
    LedgerGattReader? gattReader,
    BlePacker? packer,
    int mtu = 23,
    Function? onError,
  })  : _gattReader = gattReader ?? LedgerGattReader(),
        _packer = packer ?? LedgerPacker(),
        _mtu = mtu,
        _onError = onError;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    final supported = isRequiredServiceSupported();
    if (!supported) {
      throw LedgerException(message: 'Required service not supported');
    }

    _mtu = await bleManager.requestMtu(
      deviceId: ledger.device.id,
      mtu: mtu,
    );

    await _startNotificationReader();
    _started = true;
  }

  @override
  Future<void> disconnect() async {
    if (_closed) {
      return;
    }

    _closed = true;
    await _gattReader.close();
    _completePendingError(
      LedgerException(message: 'Disconnected from Ledger BLE device.'),
    );
    await ledger.disconnect();
  }

  @override
  Future<T> sendOperation<T>(
    LedgerOperation<T> operation, {
    LedgerTransformer? transformer,
  }) {
    return _serializeExchange<T>(
      () => _sendOperationInternal<T>(operation, transformer),
    );
  }

  @override
  bool isRequiredServiceSupported() {
    characteristicWrite = null;
    characteristicWriteCmd = null;
    characteristicNotify = null;

    try {
      final deviceInfo = ledger.device.deviceInfo;
      final service = getService(Uuid.parse(deviceInfo.serviceId));
      if (service == null) {
        return false;
      }

      characteristicWrite = getCharacteristic(
        service,
        Uuid.parse(deviceInfo.writeCharacteristicKey),
      );
      if (deviceInfo.writeCmdKey != null) {
        characteristicWriteCmd = getCharacteristic(
          service,
          Uuid.parse(deviceInfo.writeCmdKey!),
        );
      }
      characteristicNotify = getCharacteristic(
        service,
        Uuid.parse(deviceInfo.notifyCharacteristicKey),
      );
    } catch (_) {
      return false;
    }

    return (characteristicWrite != null || characteristicWriteCmd != null) &&
        characteristicNotify != null;
  }

  @override
  void onServicesInvalidated() {
    characteristicWrite = null;
    characteristicWriteCmd = null;
    characteristicNotify = null;
  }

  int get mtu => _mtu;

  @override
  Service? getService(Uuid service) {
    try {
      return ledger.services.firstWhere((s) => s.id == service);
    } on StateError {
      return null;
    }
  }

  @override
  Characteristic? getCharacteristic(
    Service service,
    Uuid characteristic,
  ) {
    try {
      return service.characteristics.firstWhere((c) => c.id == characteristic);
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> close() async {
    await disconnect();
  }

  Future<T> _serializeExchange<T>(Future<T> Function() action) {
    final previous = _exchangeTail.catchError((_) {});
    final release = Completer<void>();
    _exchangeTail = release.future;
    final result = Completer<T>();

    previous.whenComplete(() async {
      try {
        result.complete(await action());
      } catch (ex, st) {
        result.completeError(ex, st);
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
      }
    });

    return result.future;
  }

  Future<T> _sendOperationInternal<T>(
    LedgerOperation<T> operation,
    LedgerTransformer? transformer,
  ) async {
    if (_closed) {
      throw LedgerException(message: 'Ledger BLE session is closed.');
    }

    if (!_started) {
      await start();
    }

    final request = _PendingRequest(
      operation: operation,
      transformer: transformer,
    );
    _pendingRequest = request;

    try {
      final writer = ByteDataWriter();
      final output = await operation.write(writer);
      final characteristic = _writeCharacteristic;
      for (final payload in output) {
        final packets = _packer.pack(payload, mtu);
        for (final packet in packets) {
          await _writePacket(characteristic, packet);
        }
      }

      final value = await request.completer.future.timeout(
        _exchangeTimeout,
        onTimeout: () {
          _completePendingError(
            LedgerException(
              message: 'Timed out waiting for Ledger BLE response.',
            ),
          );
          throw LedgerException(
            message: 'Timed out waiting for Ledger BLE response.',
          );
        },
      );

      return value as T;
    } catch (ex) {
      if (identical(_pendingRequest, request)) {
        _pendingRequest = null;
      }
      throw _mapTransportError(ex);
    }
  }

  Future<void> _startNotificationReader() async {
    final characteristic = _notifyCharacteristic;
    _gattReader.read(
      bleManager.subscribeToCharacteristic(characteristic),
      onData: _onNotificationData,
      onError: _onNotificationError,
    );

    if (Platform.isIOS) {
      await Future<void>.delayed(_iosNotificationReadyDelay);
    }
  }

  Future<void> _restartNotificationReader() async {
    if (!_started || _closed) {
      return;
    }

    await _gattReader.close();
    await _startNotificationReader();
  }

  Future<void> _writePacket(
    QualifiedCharacteristic characteristic,
    List<int> packet,
  ) async {
    Object? lastError;
    final delays = Platform.isIOS ? _iosRetryDelays : const [Duration.zero];

    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
        await _restartNotificationReader();
      }

      try {
        await _performWrite(characteristic, packet);
        return;
      } catch (ex) {
        lastError = ex;
        if (!_isTransientIosGattError(ex)) {
          throw _mapTransportError(ex);
        }
      }
    }

    throw _mapTransportError(lastError ?? LedgerException());
  }

  Future<void> _performWrite(
    QualifiedCharacteristic characteristic,
    List<int> packet,
  ) {
    if (characteristicWriteCmd != null) {
      return bleManager.writeCharacteristicWithoutResponse(
        characteristic,
        value: packet,
      );
    }

    return bleManager.writeCharacteristicWithResponse(
      characteristic,
      value: packet,
    );
  }

  Future<void> _onNotificationData(Uint8List data) async {
    final request = _pendingRequest;
    if (request == null) {
      return;
    }

    try {
      final reader = ByteDataReader();
      if (request.transformer != null) {
        final transformed = await request.transformer!.onTransform([data]);
        reader.add(transformed);
      } else {
        reader.add(data);
      }

      final response = await request.operation.read(reader);
      _pendingRequest = null;
      request.completer.complete(response);
    } catch (ex, st) {
      _completePendingError(ex, st);
    }
  }

  void _onNotificationError(Object ex) {
    final mapped = _mapTransportError(ex);
    _completePendingError(mapped);
    _onError?.call(mapped);
  }

  void _completePendingError(Object ex, [StackTrace? st]) {
    final request = _pendingRequest;
    if (request == null) {
      return;
    }

    _pendingRequest = null;
    if (!request.completer.isCompleted) {
      request.completer.completeError(ex, st);
    }
  }

  QualifiedCharacteristic get _notifyCharacteristic => QualifiedCharacteristic(
        serviceId: characteristicNotify!.service.id,
        characteristicId: characteristicNotify!.id,
        deviceId: ledger.device.id,
      );

  QualifiedCharacteristic get _writeCharacteristic {
    final characteristic = characteristicWriteCmd ?? characteristicWrite;
    return QualifiedCharacteristic(
      serviceId: characteristic!.service.id,
      characteristicId: characteristic.id,
      deviceId: ledger.device.id,
    );
  }

  LedgerException _mapTransportError(Object ex) {
    if (ex is LedgerException) {
      return ex;
    }

    if (ex is PlatformException) {
      return LedgerException.fromPlatformException(ex);
    }

    if (_isInsufficientEncryptionError(ex)) {
      return LedgerException(
        message:
            'BLE pairing required. Accept Bluetooth pairing on phone + Ledger, then retry.',
        cause: ex,
      );
    }

    final message = ex.toString();
    return LedgerException(
      message: message.startsWith('Exception: ')
          ? message.substring('Exception: '.length)
          : message,
      cause: ex,
    );
  }

  bool _isTransientIosGattError(Object ex) {
    if (!Platform.isIOS) {
      return false;
    }

    final text = ex.toString().toLowerCase();
    return text.contains('cbatterrordomain code=14') ||
        text.contains('unlikely error') ||
        text.contains('cbatterrordomain code=15') ||
        text.contains('cbatterrordomain:15') ||
        text.contains('encryption is insufficient');
  }

  bool _isInsufficientEncryptionError(Object ex) {
    final text = ex.toString().toLowerCase();
    return text.contains('cbatterrordomain code=15') ||
        text.contains('cbatterrordomain:15') ||
        text.contains('encryption is insufficient');
  }
}

class _PendingRequest {
  final LedgerOperation<dynamic> operation;
  final LedgerTransformer? transformer;
  final Completer<dynamic> completer;

  _PendingRequest({
    required this.operation,
    required this.transformer,
  }) : completer = Completer<dynamic>.sync();
}
