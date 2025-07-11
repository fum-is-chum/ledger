import 'dart:async';
import 'dart:convert';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ledger_ethereum/ledger_ethereum.dart';
import 'package:ledger_example/bloc/ledger_event.dart';
import 'package:ledger_example/bloc/ledger_state.dart';
import 'package:ledger_example/channel/ledger_channel.dart';
import 'package:web3dart_avacus/crypto.dart';
import 'package:web3dart_avacus/web3dart_avacus.dart';

class LedgerBleBloc extends Bloc<LedgerBleEvent, LedgerBleState> {
  final LedgerChannel channel;
  StreamSubscription? _scanSubscription;

  LedgerBleBloc({
    required this.channel,
  }) : super(
          const LedgerBleState(
            devices: [],
            accounts: [],
          ),
        ) {
    on<LedgerBleScanStarted>(_onScanStarted, transformer: restartable());
    on<LedgerBleUsbStarted>(_onUsbStarted);
    on<LedgerBleConnectRequested>(_onConnectStarted);
    on<LedgerBleSignPersonalMessageRequested>(_onSignPersonalMessageRequested);
    on<LedgerBleSignTypedDataRequested>(_onSignTypedDataRequested);
    on<LedgerBleSignTransactionRequested>(_onSignTransactionRequested);
    on<LedgerBleDisconnectRequested>(_onDisconnectStarted);
  }

  Future<void> _onScanStarted(LedgerBleScanStarted event, Emitter emit) async {
    emit(state.copyWith(
      status: () => LedgerBleStatus.scanning,
    ));

    await emit.forEach(
      channel.ledger.scan(),
      onData: (data) {
        return state.copyWith(
          status: () => LedgerBleStatus.scanning,
          devices: () => [...state.devices, data],
        );
      },
    );
  }

  Future<void> _onUsbStarted(LedgerBleUsbStarted event, Emitter emit) async {
    final devices = await channel.ledger.listUsbDevices();
    final currentState = state;

    emit(currentState.copyWith(
      status: () => LedgerBleStatus.scanning,
      devices: () => [...state.devices, ...devices],
    ));
  }

  Future<void> _onConnectStarted(
    LedgerBleConnectRequested event,
    Emitter emit,
  ) async {
    final device = event.device;
    await channel.ledger.stopScanning();
    await channel.ledger.connect(device);

    final accounts = <String>[];

    try {
      final ethereumApp = EthereumLedgerApp(channel.ledger);

      final addresses = await ethereumApp.getAccounts(device);
      final address = addresses.firstOrNull;
      if (address != null) {
        accounts.add(address);
      }

      emit(state.copyWith(
        status: () => LedgerBleStatus.connected,
        selectedDevice: () => device,
        accounts: () => accounts,
      ));
    } catch (ex) {
      await channel.ledger.disconnect(device);

      emit(state.copyWith(
        status: () => LedgerBleStatus.failure,
        selectedDevice: () => device,
        accounts: () => accounts,
        error: () => ex,
      ));
    }
  }

  Future<void> _onSignPersonalMessageRequested(
    LedgerBleSignPersonalMessageRequested event,
    Emitter emit,
  ) async {
    final device = event.device;

    try {
      final ethereumApp = EthereumLedgerApp(channel.ledger);

      const message = 'This is message';
      final signature = await ethereumApp.signPersonalMessage(
          device, Uint8List.fromList(utf8.encode(message)));
      final signatureInHex = bytesToHex(signature);
      print(signatureInHex);

      emit(state.copyWith(
        signature: () => signatureInHex,
      ));
    } catch (ex) {
      if (kDebugMode) {
        print(ex);
      }
    }
  }

  Future<void> _onSignTypedDataRequested(
    LedgerBleSignTypedDataRequested event,
    Emitter emit,
  ) async {
    final device = event.device;

    try {
      final ethereumApp = EthereumLedgerApp(channel.ledger);

      const jsonMessage =
          r'''{"types":{"EIP712Domain":[{"type":"string","name":"name"},{"type":"string","name":"version"},{"type":"uint256","name":"chainId"},{"type":"address","name":"verifyingContract"}],"Part":[{"name":"account","type":"address"},{"name":"value","type":"uint96"}],"Mint721":[{"name":"tokenId","type":"uint256"},{"name":"tokenURI","type":"string"},{"name":"creators","type":"Part[]"},{"name":"royalties","type":"Part[]"}]},"domain":{"name":"Mint721","version":"1","chainId":4,"verifyingContract":"0x2547760120aed692eb19d22a5d9ccfe0f7872fce"},"primaryType":"Mint721","message":{"@type":"ERC721","contract":"0x2547760120aed692eb19d22a5d9ccfe0f7872fce","tokenId":"1","uri":"ipfs://ipfs/hash","creators":[{"account":"0xc5eac3488524d577a1495492599e8013b1f91efa","value":10000}],"royalties":[],"tokenURI":"ipfs://ipfs/hash"}}''';

      final signature =
          await ethereumApp.signEIP712Message(device, jsonMessage);

      final signatureInHex = bytesToHex(signature);
      print('signature: $signatureInHex');

      emit(state.copyWith(
        signature: () => signatureInHex,
      ));
    } catch (ex) {
      if (kDebugMode) {
        print(ex);
      }
    }
  }

  Future<void> _onSignTransactionRequested(
    LedgerBleSignTransactionRequested event,
    Emitter emit,
  ) async {
    final device = event.device;

    try {
      final ethereumApp = EthereumLedgerApp(channel.ledger);

      final tx = Transaction(
          to: EthereumAddress.fromHex(
              '0x0AE982e6C7e6e489C9b53e58eBEb2F7dF0615049'),
          value: EtherAmount.fromUnitAndValue(EtherUnit.wei, '0x9184e72a000'),
          maxGas: BigInt.parse('0x5208').toInt(),
          maxFeePerGas:
              EtherAmount.fromUnitAndValue(EtherUnit.wei, '0xe2300c4b8'),
          maxPriorityFeePerGas:
              EtherAmount.fromUnitAndValue(EtherUnit.wei, '0x826299e00'),
          nonce: 0,
          data: Uint8List.fromList(hexToBytes('0x')));

      final txBytes = TransactionHandler.encodeTx(tx, BigInt.from(137));
      print('tx in hex: ${bytesToHex(txBytes, include0x: true)}');

      final signature = await ethereumApp.signTransaction(device, txBytes);
      final signatureInHex = bytesToHex(signature);
      print('tx signature in hex: $signatureInHex');

      emit(state.copyWith(
        signature: () => signatureInHex,
      ));
    } catch (ex) {
      if (kDebugMode) {
        print(ex);
      }
    }
  }

  Future<void> _onDisconnectStarted(
    LedgerBleDisconnectRequested event,
    Emitter emit,
  ) async {
    final device = event.device;
    await channel.ledger.disconnect(device);

    emit(state.copyWith(
      status: () => LedgerBleStatus.idle,
      devices: () => [],
      selectedDevice: () => null,
      accounts: () => [],
      signature: () => null,
    ));
  }

  @override
  Future<void> close() async {
    _scanSubscription?.cancel();
    final device = state.device;
    if (device != null) {
      await channel.ledger.dispose(
        onError: (error) {},
      );
    }

    return super.close();
  }
}
