import 'dart:io';

/// Native OS threads via adb (Android). Useful when Dart VM isolates
/// are unavailable in true --release builds.
class NativeThreadInfo {
  const NativeThreadInfo({
    required this.tid,
    required this.name,
    this.pid,
    this.state,
  });

  final String tid;
  final String name;
  final String? pid;
  final String? state;

  Map<String, Object?> toJson() => <String, Object?>{
        'tid': tid,
        'name': name,
        'pid': pid,
        'state': state,
      };
}

Future<Map<String, Object?>> fetchNativeThreads({
  required String deviceSerial,
  required String packageName,
}) async {
  if (deviceSerial.trim().isEmpty) {
    return <String, Object?>{
      'ok': false,
      'error': 'No device selected',
      'threads': <Object>[],
      'hints': _hints(),
    };
  }
  if (packageName.trim().isEmpty) {
    return <String, Object?>{
      'ok': false,
      'error': 'No Android package id',
      'threads': <Object>[],
      'hints': _hints(),
    };
  }

  final adb = await _whichAdb();
  if (adb == null) {
    return <String, Object?>{
      'ok': false,
      'error': 'adb not found on PATH',
      'threads': <Object>[],
      'hints': _hints(),
    };
  }

  final pid = await _resolvePid(adb, deviceSerial, packageName);
  if (pid == null || pid.isEmpty) {
    return <String, Object?>{
      'ok': false,
      'error': 'App process not running for $packageName',
      'package': packageName,
      'device': deviceSerial,
      'threads': <Object>[],
      'hints': _hints(),
    };
  }

  final threads = await _listThreads(adb, deviceSerial, pid);
  return <String, Object?>{
    'ok': true,
    'package': packageName,
    'device': deviceSerial,
    'pid': pid,
    'threadCount': threads.length,
    'threads': threads.map((t) => t.toJson()).toList(),
    'source': 'adb',
    'hints': _hints(),
    'note':
        'Dart isolates are unavailable in --release. These are native OS threads via adb.',
  };
}

List<String> _hints() => <String>[
      'adb: Native threads listed here when the app process is running',
      'Android Studio: Profiler → CPU / Threads',
      'Instruments (iOS): Time Profiler / Threads',
    ];

Future<String?> _whichAdb() async {
  final result = await Process.run('which', ['adb']);
  if (result.exitCode != 0) {
    return null;
  }
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

Future<String?> _resolvePid(
  String adb,
  String serial,
  String packageName,
) async {
  final pidof = await Process.run(adb, <String>[
    '-s',
    serial,
    'shell',
    'pidof',
    '-s',
    packageName,
  ]);
  if (pidof.exitCode == 0) {
    final pid = (pidof.stdout as String).trim().split(RegExp(r'\s+')).first;
    if (RegExp(r'^\d+$').hasMatch(pid)) {
      return pid;
    }
  }

  final ps = await Process.run(adb, <String>[
    '-s',
    serial,
    'shell',
    'ps',
    '-A',
  ]);
  if (ps.exitCode != 0) {
    return null;
  }
  for (final line in (ps.stdout as String).split('\n')) {
    if (!line.contains(packageName)) {
      continue;
    }
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && RegExp(r'^\d+$').hasMatch(parts[1])) {
      return parts[1];
    }
  }
  return null;
}

Future<List<NativeThreadInfo>> _listThreads(
  String adb,
  String serial,
  String pid,
) async {
  final psT = await Process.run(adb, <String>[
    '-s',
    serial,
    'shell',
    'ps',
    '-T',
    '-p',
    pid,
  ]);
  if (psT.exitCode == 0) {
    final parsed = _parsePsT(psT.stdout as String, pid);
    if (parsed.isNotEmpty) {
      return parsed;
    }
  }

  final task = await Process.run(adb, <String>[
    '-s',
    serial,
    'shell',
    'sh',
    '-c',
    'for t in /proc/$pid/task/*; do tid=\${t##*/}; name=\$(cat \$t/comm 2>/dev/null); echo "\$tid \$name"; done',
  ]);
  if (task.exitCode != 0) {
    return const <NativeThreadInfo>[];
  }
  final threads = <NativeThreadInfo>[];
  for (final line in (task.stdout as String).split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty || !RegExp(r'^\d+$').hasMatch(parts.first)) {
      continue;
    }
    threads.add(
      NativeThreadInfo(
        tid: parts.first,
        name: parts.length > 1 ? parts.sublist(1).join(' ') : parts.first,
        pid: pid,
      ),
    );
  }
  return threads;
}

List<NativeThreadInfo> _parsePsT(String stdout, String pid) {
  final lines = stdout.split('\n');
  if (lines.isEmpty) {
    return const <NativeThreadInfo>[];
  }
  final header = lines.first.toUpperCase();
  final tidIdx = _columnIndex(header, <String>['TID']);
  final nameIdx = _columnIndex(header, <String>['NAME', 'CMD', 'ARGS']);
  final pidIdx = _columnIndex(header, <String>['PID']);
  final threads = <NativeThreadInfo>[];
  for (final line in lines.skip(1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final tid = tidIdx != null && tidIdx < parts.length
        ? parts[tidIdx]
        : (parts.length > 1 ? parts[1] : parts.first);
    if (!RegExp(r'^\d+$').hasMatch(tid)) {
      continue;
    }
    final name = nameIdx != null && nameIdx < parts.length
        ? parts.sublist(nameIdx).join(' ')
        : parts.last;
    final rowPid = pidIdx != null && pidIdx < parts.length ? parts[pidIdx] : pid;
    threads.add(NativeThreadInfo(tid: tid, name: name, pid: rowPid));
  }
  return threads;
}

int? _columnIndex(String header, List<String> names) {
  final cols = header.trim().split(RegExp(r'\s+'));
  for (final name in names) {
    final idx = cols.indexOf(name);
    if (idx >= 0) {
      return idx;
    }
  }
  return null;
}
