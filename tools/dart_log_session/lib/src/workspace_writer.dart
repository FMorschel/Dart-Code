import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'jsonc.dart';
import 'log_options.dart';

/// Where each option's log file will be written.
Map<String, String> assignLogPaths(List<LogOption> options, String logDir) => {
      for (final o in options) o.name: p.join(logDir, '${o.name}.log'),
    };

/// Merges the log settings into `<workspace>/.vscode/settings.json`.
///
/// Returns the file written.
File writeSettings({
  required String workspace,
  required List<LogOption> options,
  required Map<String, String> paths,
  bool includeLegacy = true,
}) {
  final file = File(p.join(workspace, '.vscode', 'settings.json'));
  final json = _readObject(file);
  for (final o in options.where((o) => o.isSetting)) {
    if (o.isLegacy && !includeLegacy) continue;
    json[o.settingKey] = paths[o.name];
  }
  return _write(file, json);
}

/// Adds (or replaces) a launch configuration in `.vscode/launch.json`.
///
/// Returns the file written.
File writeLaunchConfig({
  required String workspace,
  required List<LogOption> options,
  required Map<String, String> paths,
  required String name,
  required String program,
  String? deviceId,
}) {
  final file = File(p.join(workspace, '.vscode', 'launch.json'));
  final json = _readObject(file);
  json.putIfAbsent('version', () => '0.2.0');
  final configs = (json['configurations'] as List?)?.toList() ?? [];
  configs.removeWhere((c) => c is Map && c['name'] == name);
  configs.add({
    'name': name,
    'type': 'dart',
    'request': 'launch',
    'program': program,
    if (deviceId != null) 'deviceId': deviceId,
    for (final o in options.where((o) => o.isLaunchArg)) o.name: paths[o.name],
  });
  json['configurations'] = configs;
  return _write(file, json);
}

Map<String, Object?> _readObject(File file) {
  if (!file.existsSync()) return {};
  final decoded = decodeJsonc(file.readAsStringSync());
  if (decoded is! Map) {
    throw FormatException('${file.path} is not a JSON object.');
  }
  return decoded.cast<String, Object?>();
}

File _write(File file, Map<String, Object?> json) {
  file.parent.createSync(recursive: true);
  if (file.existsSync()) {
    // Comments are lost on rewrite, so keep the original.
    file.copySync('${file.path}.bak');
  }
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('\t').convert(json)}\n',
  );
  return file;
}
