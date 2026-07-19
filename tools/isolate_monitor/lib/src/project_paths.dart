import 'dart:io';

class ProjectPaths {
  ProjectPaths({
    required this.projectRoot,
    this.dartPackageName,
  });

  final String projectRoot;
  final String? dartPackageName;

  static String? readDartPackageName(String projectRoot) {
    final pubspec = File('$projectRoot${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) {
      return null;
    }
    final match = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    return match?.group(1);
  }

  /// Resolves a log reference like `package:app/lib/foo.dart:12:3` or
  /// `/path/to/file.dart:12` to an absolute host file path.
  String? resolveReference(String reference) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty || projectRoot.isEmpty) {
      return null;
    }

    var normalized = trimmed;
    if (normalized.startsWith('(') && normalized.endsWith(')')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }

    final match = RegExp(r'^(.+):(\d+)(?::(\d+))?$').firstMatch(normalized);
    if (match == null) {
      return _resolvePath(normalized);
    }

    final filePart = match.group(1)!.trim();
    return _resolvePath(filePart);
  }

  String? _resolvePath(String filePart) {
    var path = filePart.trim();
    if (path.startsWith('(') && path.endsWith(')')) {
      path = path.substring(1, path.length - 1);
    }

    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath();
      } on Object {
        path = path.replaceFirst('file://', '');
      }
    } else if (path.startsWith('package:')) {
      final packageMatch = RegExp(r'^package:([^/]+)/(.+)$').firstMatch(path);
      if (packageMatch == null) {
        return null;
      }
      final packageName = packageMatch.group(1)!;
      var relative = packageMatch.group(2)!;
      if (dartPackageName != null && packageName != dartPackageName) {
        return null;
      }
      if (!relative.startsWith('lib/') && !relative.startsWith('lib\\')) {
        relative = 'lib${Platform.pathSeparator}$relative';
      }
      path = '$projectRoot${Platform.pathSeparator}$relative';
    } else if (!_isAbsoluteHostPath(path)) {
      path = '$projectRoot${Platform.pathSeparator}$path';
    }

    final normalized = File(path).absolute.path;
    if (File(normalized).existsSync()) {
      return normalized;
    }

    if (projectRoot.isNotEmpty) {
      final underProject = File(
        '$projectRoot${Platform.pathSeparator}$filePart',
      ).absolute.path;
      if (File(underProject).existsSync()) {
        return underProject;
      }
    }

    return null;
  }

  bool _isAbsoluteHostPath(String path) {
    if (path.startsWith('/')) {
      return true;
    }
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  (String? path, int line, int column) parseLocation(String reference) {
    var trimmed = reference.trim();
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    final match = RegExp(r'^(.+):(\d+)(?::(\d+))?$').firstMatch(trimmed);
    if (match == null) {
      final path = resolveReference(reference);
      return (path, 1, 1);
    }

    final line = int.tryParse(match.group(2) ?? '') ?? 1;
    final column = int.tryParse(match.group(3) ?? '') ?? 1;
    final path = resolveReference(reference);
    return (path, line, column);
  }
}
