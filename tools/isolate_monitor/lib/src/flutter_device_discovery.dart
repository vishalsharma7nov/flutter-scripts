import 'dart:convert';
import 'dart:io';

import 'adb_device_manager.dart';

class MonitorDevice {
  const MonitorDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.connection,
    required this.source,
    this.available = true,
    this.connected = false,
    this.mirrorable = false,
    this.address,
    this.sdk,
    this.state,
    this.model,
  });

  final String id;
  final String name;
  final String platform;
  final String connection;
  final String source;
  final bool available;
  final bool connected;
  final bool mirrorable;
  final String? address;
  final String? sdk;
  final String? state;
  final String? model;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        'connection': connection,
        'source': source,
        'available': available,
        'connected': connected,
        'mirrorable': mirrorable,
        'address': address,
        'sdk': sdk,
        'state': state,
        'model': model,
      };
}

class DeviceCatalog {
  const DeviceCatalog({
    required this.android,
    required this.ios,
    required this.discoveredAndroid,
    required this.adbDevices,
    this.flutterAvailable = false,
    this.adbAvailable = false,
  });

  final List<MonitorDevice> android;
  final List<MonitorDevice> ios;
  final List<MonitorDevice> discoveredAndroid;
  final List<AdbDevice> adbDevices;
  final bool flutterAvailable;
  final bool adbAvailable;

  Map<String, Object?> toJson() => <String, Object?>{
        'android': android.map((d) => d.toJson()).toList(),
        'ios': ios.map((d) => d.toJson()).toList(),
        'discoveredAndroid': discoveredAndroid.map((d) => d.toJson()).toList(),
        'devices': adbDevices.map((d) => d.toJson()).toList(),
        'flutterAvailable': flutterAvailable,
        'adbAvailable': adbAvailable,
      };
}

class FlutterDeviceDiscovery {
  FlutterDeviceDiscovery({this.useFvm = false});

  final bool useFvm;

  Future<bool> hasFlutterCli() => _flutterOnPath();

  Future<DeviceCatalog> buildCatalog(AdbDeviceManager? adbManager) async {
    final adbDevices =
        adbManager != null && await adbManager.ensureAdb()
            ? await adbManager.listDevices()
            : <AdbDevice>[];

    final flutterDevices = await _listFlutterDevices();
    final mdnsDevices = adbManager != null
        ? await _discoverAndroidMdns(adbManager)
        : <MonitorDevice>[];
    final iosXcDevices =
        Platform.isMacOS ? await _listIosViaXcdevice() : <MonitorDevice>[];

    final android = <MonitorDevice>[];
    final ios = <MonitorDevice>[];
    final seenAndroid = <String>{};
    final seenIos = <String>{};

    void addAndroid(MonitorDevice device) {
      final key = device.id.isNotEmpty ? device.id : device.address ?? device.name;
      if (seenAndroid.add(key)) {
        android.add(device);
      }
    }

    void addIos(MonitorDevice device) {
      final key = device.id.isNotEmpty ? device.id : device.name;
      if (seenIos.add(key)) {
        ios.add(device);
      }
    }

    for (final adb in adbDevices) {
      addAndroid(
        MonitorDevice(
          id: adb.serial,
          name: adb.model ?? adb.serial,
          platform: 'android',
          connection: adb.connection,
          source: 'adb',
          available: adb.isOnline,
          connected: adb.isOnline,
          mirrorable: adb.isOnline,
          state: adb.state,
          model: adb.model,
          address: adb.connection == 'network' ? adb.serial : null,
        ),
      );
    }

    for (final device in flutterDevices) {
      if (device.platform == 'android') {
        addAndroid(device);
      } else if (device.platform == 'ios') {
        addIos(device);
      }
    }

    for (final device in iosXcDevices) {
      addIos(device);
    }

    final connectedAddresses = adbDevices
        .where((d) => d.serial.contains(':'))
        .map((d) => d.serial.toLowerCase())
        .toSet();

    final discoveredAndroid = <MonitorDevice>[];
    for (final device in mdnsDevices) {
      final address = (device.address ?? '').toLowerCase();
      if (address.isNotEmpty && connectedAddresses.contains(address)) {
        continue;
      }
      discoveredAndroid.add(device);
    }

    android.sort(_compareDevices);
    ios.sort(_compareDevices);
    discoveredAndroid.sort(_compareDevices);

    return DeviceCatalog(
      android: android,
      ios: ios,
      discoveredAndroid: discoveredAndroid,
      adbDevices: adbDevices,
      flutterAvailable: flutterDevices.isNotEmpty || await _flutterOnPath(),
      adbAvailable: adbManager?.isAvailable ?? false,
    );
  }

  Future<List<MonitorDevice>> _listFlutterDevices() async {
    final executable = await _resolveFlutterExecutable();
    if (executable == null) {
      return const <MonitorDevice>[];
    }

    final args = executable.args;
    args.addAll(['devices', '--machine']);
    try {
      final result = await Process.run(executable.command, args);
      if (result.exitCode != 0) {
        return const <MonitorDevice>[];
      }
      final raw = (result.stdout as String).trim();
      if (raw.isEmpty) {
        return const <MonitorDevice>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <MonitorDevice>[];
      }

      final devices = <MonitorDevice>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final platform = _platformFromFlutter(entry['targetPlatform'] as String?);
        if (platform != 'android' && platform != 'ios') {
          continue;
        }

        final id = (entry['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) {
          continue;
        }

        final emulator = entry['emulator'] == true;
        devices.add(
          MonitorDevice(
            id: id,
            name: (entry['name'] as String?)?.trim() ?? id,
            platform: platform,
            connection: emulator
                ? 'emulator'
                : platform == 'ios'
                    ? 'usb'
                    : 'usb',
            source: 'flutter',
            available: entry['isSupported'] != false,
            connected: entry['isSupported'] != false,
            mirrorable: platform == 'android' && entry['isSupported'] != false,
            sdk: entry['sdk'] as String?,
          ),
        );
      }
      return devices;
    } on Object {
      return const <MonitorDevice>[];
    }
  }

  Future<List<MonitorDevice>> _listIosViaXcdevice() async {
    try {
      final result = await Process.run('xcrun', ['xcdevice', 'list']);
      if (result.exitCode != 0) {
        return const <MonitorDevice>[];
      }
      final raw = (result.stdout as String).trim();
      if (raw.isEmpty) {
        return const <MonitorDevice>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <MonitorDevice>[];
      }

      final devices = <MonitorDevice>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }

        final platformRaw = (entry['platform'] as String?) ?? '';
        final isSimulator = entry['simulator'] == true;
        if (!platformRaw.contains('iphone') && !platformRaw.contains('ipad')) {
          continue;
        }

        final id = (entry['identifier'] as String?)?.trim() ?? '';
        if (id.isEmpty) {
          continue;
        }

        final name = (entry['name'] as String?)?.trim() ?? id;
        final available = entry['available'] == true;
        final iface = (entry['interface'] as String?)?.trim() ?? '';
        if (isSimulator && !available) {
          continue;
        }
        if (!isSimulator && !available && iface != 'usb' && iface != 'network') {
          // Still list physical devices discovered on LAN (may need pairing).
        }
        final connection = isSimulator
            ? 'simulator'
            : iface.isNotEmpty
                ? iface
                : 'network';

        devices.add(
          MonitorDevice(
            id: id,
            name: name,
            platform: 'ios',
            connection: connection,
            source: 'xcdevice',
            available: available,
            connected: available,
            mirrorable: false,
            sdk: entry['operatingSystemVersion'] as String?,
            model: entry['modelName'] as String?,
            state: available ? 'available' : 'discovered',
          ),
        );
      }
      return devices;
    } on Object {
      return const <MonitorDevice>[];
    }
  }

  Future<bool> _flutterOnPath() async {
    return (await _resolveFlutterExecutable()) != null;
  }

  Future<_FlutterExecutable?> _resolveFlutterExecutable() async {
    if (useFvm) {
      final fvm = await _which('fvm');
      if (fvm != null) {
        return _FlutterExecutable(command: fvm, args: ['flutter']);
      }
    }
    final flutter = await _which('flutter');
    if (flutter != null) {
      return _FlutterExecutable(command: flutter, args: const []);
    }
    return null;
  }

  Future<String?> _which(String command) async {
    final result = await Process.run('which', [command]);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  String _platformFromFlutter(String? targetPlatform) {
    final value = (targetPlatform ?? '').toLowerCase();
    if (value.startsWith('android')) {
      return 'android';
    }
    if (value.startsWith('ios')) {
      return 'ios';
    }
    return 'other';
  }

  int _compareDevices(MonitorDevice a, MonitorDevice b) {
    if (a.connected != b.connected) {
      return a.connected ? -1 : 1;
    }
    if (a.available != b.available) {
      return a.available ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<List<MonitorDevice>> _discoverAndroidMdns(
    AdbDeviceManager adbManager,
  ) async {
    if (!await adbManager.ensureAdb()) {
      return const <MonitorDevice>[];
    }

    final adb = await _which('adb');
    if (adb == null) {
      return const <MonitorDevice>[];
    }

    final result = await Process.run(adb, ['mdns', 'services']);
    if (result.exitCode != 0) {
      return const <MonitorDevice>[];
    }

    final output = '${result.stdout}\n${result.stderr}';
    final devices = <MonitorDevice>[];
    final addressPattern = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3}:\d{1,5})');

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.toLowerCase().startsWith('list of discovered')) {
        continue;
      }

      final lower = trimmed.toLowerCase();
      final isPairing = lower.contains('pairing');
      final isConnect = lower.contains('connect') || lower.contains('adb-tls');
      if (!isPairing && !isConnect) {
        continue;
      }

      final matches = addressPattern.allMatches(trimmed).toList();
      if (matches.isEmpty) {
        continue;
      }

      final address = matches.last.group(1)!;
      final instance = _readMdnsInstanceName(trimmed, address);
      devices.add(
        MonitorDevice(
          id: address,
          name: instance,
          platform: 'android',
          connection: isPairing ? 'mdns-pairing' : 'mdns-connect',
          source: 'mdns',
          available: true,
          connected: false,
          mirrorable: !isPairing,
          address: address,
          state: isPairing ? 'pairing' : 'discovered',
        ),
      );
    }

    return devices;
  }

  String _readMdnsInstanceName(String line, String address) {
    final withoutAddress = line.replaceAll(address, '').trim();
    final parts = withoutAddress.split(RegExp(r'\s+'));
    for (final part in parts.reversed) {
      if (part.contains('_tcp') || part.contains('adb-tls')) {
        continue;
      }
      if (part.contains('-') && !part.contains('.')) {
        return part.replaceAll('-', '.');
      }
      if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part) && part.length > 2) {
        return part;
      }
    }
    return address;
  }
}

class _FlutterExecutable {
  const _FlutterExecutable({required this.command, required this.args});

  final String command;
  final List<String> args;
}
