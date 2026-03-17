<br />
<div align="center">
  <a href="https://www.ledger.com/">
    <img src="https://cdn1.iconfinder.com/data/icons/minicons-4/64/ledger-512.png" width="100"/>
  </a>

<h1 align="center">ledger_scallop</h1>

<p align="center">
    A Flutter plugin to scan, connect & sign transactions using Ledger devices using USB & BLE
    <br />
    <a href="https://pub.dev/documentation/ledger_scallop/latest/"><strong>« Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/fum-is-chum/ledger/issues">Report Bug</a>
    · <a href="https://github.com/fum-is-chum/ledger/issues">Request Feature</a>
  </p>
</div>
<br/>

---

## Overview
This package has been forked from [ledger-flutter](https://github.com/RootSoft/ledger-flutter)

Ledger devices are the perfect hardware wallets for managing your crypto & NFTs on the go.
This Flutter plugin makes it easy to find nearby Ledger devices, connect with them and sign transactions over USB and/or BLE.


## Supported devices

|         | BLE                | USB                |
|---------|--------------------|--------------------|
| Android | :heavy_check_mark: | :heavy_check_mark: |
| iOS     | :heavy_check_mark: | :x:                |

## Getting started

### Installation

Install the latest version of this package via pub.dev:

```yaml
ledger: ^latest-version
```

You might want to install additional Ledger App Plugins to support different blockchains. See the [Ledger Plugins](#custom-ledger-app-plugins) section below.

For example, adding Sui support:

```yaml
ledger_sui: ^latest-version
```

### Setup

Create a new instance of `LedgerOptions` and pass it to the the `Ledger` constructor.

```dart
final options = LedgerOptions(
  maxScanDuration: const Duration(milliseconds: 5000),
);


final ledger = Ledger(
  options: options,
);
```

<details>
<summary>Android</summary>

The package uses the following permissions:

* ACCESS_FINE_LOCATION : this permission is needed because old Nexus devices need location services in order to provide reliable scan results
* BLUETOOTH : allows apps to connect to a paired bluetooth device
* BLUETOOTH_ADMIN: allows apps to discover and pair bluetooth devices

Add the following permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>

<!--bibo01 : hardware option-->
<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>

<!-- required for API 18 - 30 -->
<uses-permission
    android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />

<!-- API 31+ -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
```
</details>

<details>
<summary>iOS</summary>

For iOS, it is required you add the following entries to the `Info.plist` file of your app. 
It is not allowed to access Core Bluetooth without this.

For more in depth details: [Blog post on iOS bluetooth permissions](https://betterprogramming.pub/handling-ios-13-bluetooth-permissions-26c6a8cbb816?gi=c982a53f1c06)

**iOS13 and higher**

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses bluetooth to find, connect and sign transactions with your Ledger</string>
```

**iOS12 and lower**

```xml
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses bluetooth to find, connect and sign transactions with your Ledger</string>
```

</details>

### Ledger App Plugins

Each blockchain follows it own protocol which needs to be implemented before being able to get public keys & sign transactions.
We introduced the concept of Ledger App Plugins so any developer can easily create and integrate their own Ledger App Plugin and share it with the community.

We added the first support for the Sui blockchain:

`pubspec.yaml`
```yaml
ledger_sui: ^latest-version
```

```dart
final suiApp = SuiLedgerApp(ledger);
final publicKeys = await suiApp.getAccounts(device);
```

#### Existing plugins

- [Algorand](https://pub.dev/packages/ledger_algorand)
- [Sui](https://pub.dev/packages/ledger_sui)
- [Create my own plugin](#custom-ledger-app-plugins)

## Usage

### Scanning nearby devices

You can scan for nearby Ledger devices using the `scan()` method. This returns a `Stream` that can be listened to which emits when a new device has been found.

```dart
final subscription = ledger.scan().listen((device) => print(device));
```

Scanning stops once `maxScanDuration` is passed or the `stop()` method is called.
The `maxScanDuration` is the maximum amount of time BLE discovery should run in order to find nearby devices.


```dart
await ledger.stop();
```

#### Permissions

The Ledger Flutter plugin uses [Bluetooth Low Energy]() which requires certain permissions to be handled on both iOS & Android.
The plugin sends a callback every time a permission is required. All you have to do is override the `onPermissionRequest` and let the wonderful [permission_handler](https://pub.dev/packages/permission_handler) package handle the rest.

```dart
final ledger = Ledger(
  options: options,
  onPermissionRequest: (status) async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    if (status != BleStatus.ready) {
      return false;
    }

    return statuses.values.where((status) => status.isDenied).isEmpty;
  },
);
```

### Connect to a Ledger device

Once a `LedgerDevice` has been found, you can easily connect to the device using the `connect()` method.

```dart
await ledger.connect(device);
```

A `LedgerException` is thrown if unable to connect to the device. 

The package also includes a `devices` stream which updates on connection changes.

```dart
final subscription = ledger.devices.listen((state) => print(state));
```

### Get public keys

Depending on the required blockchain and Ledger Application Plugin, the `getAccounts()` method can be used to fetch the public keys from the Ledger Nano device.


Based on the implementation and supported protocol, there might be only one public key in the list of accounts.

```dart
final suiApp = SuiLedgerApp(ledger);
final ledgerAccounts = await suiApp.getAccountsWithDetails(device);
```

### Disconnect

Use the `disconnect()` method to close an established connection with a ledger device.

```dart
await ledger.disconnect(device);
```

### Dispose

Always use the `close()` method to close all connections and dispose any potential listeners to not leak any resources.

```dart
await ledger.close();
```


### LedgerException

Every method might throw a `LedgerException` which contains the message, cause and potential error code.

```dart
try {
  await channel.ledger.connect(device);
} on LedgerException catch (ex) {
  await channel.ledger.disconnect(device);
}
```
## Custom Ledger App Plugins

Each blockchain follows it own [APDU](https://developers.ledger.com/docs/nano-app/application-structure/) protocol which needs to be implemented before being able to get public keys & sign transactions.

You can always check the implementation details in [ledger_sui]().

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag `enhancement`.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/my-feature`)
3. Commit your Changes (`git commit -m 'feat: my new feature`)
4. Push to the Branch (`git push origin feature/my-feature`)
5. Open a Pull Request

Please read our [Contributing guidelines](CONTRIBUTING.md) and try to follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## License

Project-specific changes in this repository are released under the Apache
License 2.0. This repository also includes material derived from the
MIT-licensed upstream [wakumo/ledger](https://github.com/wakumo/ledger).
See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for details.
