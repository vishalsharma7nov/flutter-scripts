import 'dart:io';

class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    required this.connection,
    this.model,
  });

  final String serial;
  final String state;
  final String connection;
  final String? model;

  bool get isOnline => state == 'device';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': serial,
        'serial': serial,
        'state': state,
        'connection': connection,
        'model': model,
        'name': model,
        'online': isOnline,
      };
}

class AdbActionResult {
  const AdbActionResult({
    required this.ok,
    this.message,
    this.error,
  });

  final bool ok;
  final String? message;
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'message': message,
        'error': error,
      };
}

class AdbDeviceManager {
  String? _adb;

  Future<bool> ensureAdb() async {
    if (_adb != null) {
      return true;
    }
    _adb = await _resolveCommand('adb');
    return _adb != null;
  }

  bool get isAvailable => _adb != null;

  Future<List<AdbDevice>> listDevices() async {
    if (!await ensureAdb()) {
      return const <AdbDevice>[];
    }

    final result = await Process.run(_adb!, ['devices', '-l']);
    if (result.exitCode != 0) {
      return const <AdbDevice>[];
    }

    final devices = <AdbDevice>[];
    final lines = (result.stdout as String).split('\n');
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }

      final serial = parts[0];
      final state = parts[1];
      final model = _readModelFromDeviceLine(trimmed);
      devices.add(
        AdbDevice(
          serial: serial,
          state: state,
          connection: _connectionKind(serial),
          model: model,
        ),
      );
    }
    return devices;
  }

  Future<AdbActionResult> connect(String hostPort) async {
    final target = hostPort.trim();
    if (target.isEmpty) {
      return const AdbActionResult(
        ok: false,
        error: 'Enter device address as host:port (e.g. 192.168.1.20:5555)',
      );
    }
    if (!RegExp(r'^.+:\d{1,5}$').hasMatch(target)) {
      return const AdbActionResult(
        ok: false,
        error: 'Invalid address. Use host:port (e.g. 192.168.1.20:5555)',
      );
    }

    if (!await ensureAdb()) {
      return const AdbActionResult(ok: false, error: 'adb not found on PATH');
    }

    final result = await Process.run(_adb!, ['connect', target]);
    final output = '${result.stdout}${result.stderr}'.trim();
    final ok = result.exitCode == 0 &&
        !output.toLowerCase().contains('failed') &&
        !output.toLowerCase().contains('unable');
    return AdbActionResult(
      ok: ok,
      message: output.isEmpty ? 'Connected to $target' : output,
      error: ok ? null : (output.isEmpty ? 'adb connect failed' : output),
    );
  }

  Future<AdbActionResult> pair({
    required String host,
    required String port,
    required String code,
  }) async {
    final address = '${host.trim()}:${port.trim()}';
    final pairingCode = code.trim();
    if (host.trim().isEmpty || port.trim().isEmpty || pairingCode.isEmpty) {
      return const AdbActionResult(
        ok: false,
        error: 'Host, port, and pairing code are required',
      );
    }

    if (!await ensureAdb()) {
      return const AdbActionResult(ok: false, error: 'adb not found on PATH');
    }

    final result = await Process.run(_adb!, ['pair', address, pairingCode]);
    final output = '${result.stdout}${result.stderr}'.trim();
    final ok = result.exitCode == 0 &&
        output.toLowerCase().contains('success');
    return AdbActionResult(
      ok: ok,
      message: output.isEmpty ? 'Paired with $address' : output,
      error: ok ? null : (output.isEmpty ? 'adb pair failed' : output),
    );
  }

  Future<AdbActionResult> disconnect(String serial) async {
    final target = serial.trim();
    if (target.isEmpty) {
      return const AdbActionResult(ok: false, error: 'Missing device serial');
    }

    if (!await ensureAdb()) {
      return const AdbActionResult(ok: false, error: 'adb not found on PATH');
    }

    final result = await Process.run(_adb!, ['disconnect', target]);
    final output = '${result.stdout}${result.stderr}'.trim();
    final ok = result.exitCode == 0;
    return AdbActionResult(
      ok: ok,
      message: output.isEmpty ? 'Disconnected $target' : output,
      error: ok ? null : (output.isEmpty ? 'adb disconnect failed' : output),
    );
  }

  Future<String?> deviceModel(String serial) async {
    if (!await ensureAdb()) {
      return null;
    }
    final result = await Process.run(
      _adb!,
      ['-s', serial, 'shell', 'getprop', 'ro.product.model'],
    );
    if (result.exitCode != 0) {
      return null;
    }
    final model = (result.stdout as String).trim();
    return model.isEmpty ? null : model;
  }

  String? _readModelFromDeviceLine(String line) {
    final match = RegExp(r'\bmodel:(\S+)').firstMatch(line);
    return match?.group(1);
  }

  String _connectionKind(String serial) {
    if (serial.contains(':')) {
      return 'network';
    }
    if (serial.startsWith('emulator-')) {
      return 'emulator';
    }
    return 'usb';
  }

  Future<String?> _resolveCommand(String command) async {
    final result = await Process.run('which', [command]);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }
}

Future<String?> localLanIPv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return address.address;
        }
      }
    }
  } on Object {
    return null;
  }
  return null;
}
