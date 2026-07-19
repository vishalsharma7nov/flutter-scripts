import 'dart:io';

import 'project_paths.dart';

class FileOpenResult {
  FileOpenResult({
    required this.ok,
    this.path,
    this.line = 1,
    this.column = 1,
    this.opener,
    this.error,
  });

  final bool ok;
  final String? path;
  final int line;
  final int column;
  final String? opener;
  final String? error;
}

class FileOpener {
  FileOpener({
    required this.projectPaths,
    this.openerName,
  });

  final ProjectPaths projectPaths;
  final String? openerName;

  String get activeOpener => _resolveOpener();

  Future<FileOpenResult> openReference(String reference) async {
    final (path, line, column) = projectPaths.parseLocation(reference);
    if (path == null) {
      return FileOpenResult(
        ok: false,
        error: 'Could not resolve file reference: $reference',
      );
    }
    return openPath(path, line: line, column: column);
  }

  Future<FileOpenResult> openPath(
    String path, {
    int line = 1,
    int column = 1,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return FileOpenResult(
        ok: false,
        path: path,
        line: line,
        column: column,
        error: 'File not found: $path',
      );
    }

    final opener = _resolveOpener();
    var opened = await _openWith(opener, path, line, column);
    var usedOpener = opener;
    if (!opened) {
      final fallback = _fallbackOpener();
      if (fallback != null && fallback != opener) {
        opened = await _openWith(fallback, path, line, column);
        if (opened) {
          usedOpener = fallback;
        }
      }
    }
    if (!opened) {
      return FileOpenResult(
        ok: false,
        path: path,
        line: line,
        column: column,
        opener: usedOpener,
        error: 'No editor available to open $path',
      );
    }

    return FileOpenResult(
      ok: true,
      path: path,
      line: line,
      column: column,
      opener: usedOpener,
    );
  }

  String? _fallbackOpener() {
    if (Platform.isMacOS) {
      return 'macos-open';
    }
    if (Platform.isWindows) {
      return 'windows-notepad';
    }
    if (_commandExists('xdg-open')) {
      return 'xdg-open';
    }
    return null;
  }

  String _resolveOpener() {
    final override = openerName?.trim() ?? '';
    if (override.isNotEmpty && override != 'auto') {
      return override;
    }

    final fromEnv = Platform.environment['ISOLATE_MONITOR_FILE_OPENER']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty && fromEnv != 'auto') {
      return fromEnv;
    }

    if (_commandExists('cursor')) {
      return 'cursor';
    }
    if (_commandExists('code')) {
      return 'code';
    }
    if (_commandExists('idea')) {
      return 'idea';
    }
    if (Platform.isWindows) {
      return 'windows-notepad';
    }
    if (Platform.isMacOS) {
      return 'macos-open';
    }
    if (_commandExists('xdg-open')) {
      return 'xdg-open';
    }
    return 'none';
  }

  Future<bool> _openWith(
    String opener,
    String path,
    int line,
    int column,
  ) async {
    switch (opener) {
      case 'cursor':
        return _runEditor(['cursor', '-g', '$path:$line:$column']);
      case 'code':
      case 'vscode':
        return _runEditor(['code', '-g', '$path:$line:$column']);
      case 'idea':
        return _runEditor(['idea', '--line', '$line', path]);
      case 'macos-open':
        if (line > 1 && _commandExists('cursor')) {
          return _runEditor(['cursor', '-g', '$path:$line:$column']);
        }
        if (line > 1 && _commandExists('code')) {
          return _runEditor(['code', '-g', '$path:$line:$column']);
        }
        final textEdit = await Process.run('open', ['-a', 'TextEdit', path]);
        if (textEdit.exitCode == 0) {
          return true;
        }
        final fallback = await Process.run('open', [path]);
        return fallback.exitCode == 0;
      case 'windows-notepad':
        if (line > 1 && _commandExists('cursor')) {
          return _runEditor(['cursor', '-g', '$path:$line:$column']);
        }
        if (line > 1 && _commandExists('code')) {
          return _runEditor(['code', '-g', '$path:$line:$column']);
        }
        final notepad = await Process.run('cmd', [
          '/c',
          'start',
          '',
          'notepad.exe',
          path,
        ]);
        return notepad.exitCode == 0;
      case 'xdg-open':
        if (line > 1 && _commandExists('code')) {
          return _runEditor(['code', '-g', '$path:$line:$column']);
        }
        final result = await Process.run('xdg-open', [path]);
        return result.exitCode == 0;
      case 'none':
        return false;
      default:
        return _runEditor([opener, '-g', '$path:$line:$column']);
    }
  }

  Future<bool> _runEditor(List<String> command) async {
    try {
      final result = await Process.run(command.first, command.skip(1).toList());
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  bool _commandExists(String command) {
    final result = Process.runSync('which', [command]);
    return result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty;
  }
}
