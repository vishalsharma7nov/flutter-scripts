import 'dart:io';

const kBackendDart = 'dart';
const kBackendGo = 'go';
const kBackendTypeScript = 'typescript';

/// Exit code that tells open-isolate-monitor.sh to relaunch the monitor.
const kMonitorRestartExitCode = 100;

const kAvailableBackends = <String>[
  kBackendDart,
  kBackendGo,
  kBackendTypeScript,
];

String normalizeBackendLanguage(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'go':
      return kBackendGo;
    case 'ts':
    case 'typescript':
    case 'node':
      return kBackendTypeScript;
    case 'dart':
    default:
      return kBackendDart;
  }
}

bool isBackendRunnable(String backend) {
  switch (normalizeBackendLanguage(backend)) {
    case kBackendDart:
    case kBackendGo:
      return true;
    default:
      return false;
  }
}

String backendDirectoryHint(String backend) {
  switch (normalizeBackendLanguage(backend)) {
    case kBackendGo:
      return 'server/go';
    case kBackendTypeScript:
      return 'server/typescript';
    default:
      return 'server/dart (live: bin/ + lib/)';
  }
}

File backendPreferenceFile({Directory? toolRoot}) {
  final root = toolRoot ?? Directory.current;
  return File('${root.path}${Platform.pathSeparator}.backend-lang');
}

String readPreferredBackend({Directory? toolRoot}) {
  final file = backendPreferenceFile(toolRoot: toolRoot);
  if (file.existsSync()) {
    try {
      final fromFile = file.readAsStringSync().trim();
      if (fromFile.isNotEmpty) {
        return normalizeBackendLanguage(fromFile);
      }
    } on Object {
      // fall through to env / default
    }
  }
  final fromEnv = Platform.environment['ISOLATE_MONITOR_BACKEND']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return normalizeBackendLanguage(fromEnv);
  }
  return kBackendDart;
}

Future<void> writePreferredBackend(
  String backend, {
  Directory? toolRoot,
}) async {
  final normalized = normalizeBackendLanguage(backend);
  final file = backendPreferenceFile(toolRoot: toolRoot);
  await file.writeAsString('$normalized\n');
}

String backendStatusMessage(String preferred) {
  final backend = normalizeBackendLanguage(preferred);
  if (isBackendRunnable(backend)) {
    return 'Restarting monitor with Dart backend (preference: $backend)…';
  }
  return 'Preference set to $backend (${backendDirectoryHint(backend)}). '
      'Restarting monitor — TypeScript is not runnable yet, '
      'so Dart stays live while you continue work under ${backendDirectoryHint(backend)}.';
}
