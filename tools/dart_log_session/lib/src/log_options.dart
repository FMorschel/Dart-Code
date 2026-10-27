import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A log file option that Dart-Code understands.
class LogOption {
  /// The bare name, for example `analyzerLogFile`.
  final String name;

  /// Whether this is a `dart.<name>` extension setting.
  final bool isSetting;

  /// Whether this is a field on the `dart` launch configuration.
  final bool isLaunchArg;

  /// First sentence of the setting description, if there is one.
  final String? description;

  /// Whether the setting only applies to the legacy debug adapters.
  final bool isLegacy;

  LogOption({
    required this.name,
    required this.isSetting,
    required this.isLaunchArg,
    this.description,
    this.isLegacy = false,
  });

  String get settingKey => 'dart.$name';
}

/// Finds the root of a Dart-Code checkout by walking up from [start].
String? findDartCodeRoot(String start) {
  var dir = p.normalize(p.absolute(start));
  while (true) {
    final packageJson = File(p.join(dir, 'package.json'));
    if (packageJson.existsSync() &&
        Directory(p.join(dir, 'src', 'extension')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

/// Reads every log file option from a Dart-Code checkout.
///
/// Settings come from `package.json`, launch arguments from the
/// `DartLaunchArgs` interface, so new options upstream are picked up without
/// changes here.
List<LogOption> discoverLogOptions(String dartCodeRoot) {
  final settings = _settingsFromPackageJson(
    File(p.join(dartCodeRoot, 'package.json')),
  );
  final launchArgs = _launchArgsFromInterfaces(
    File(p.join(dartCodeRoot, 'src', 'shared', 'debugging', 'interfaces.ts')),
  );

  final names = {...settings.keys, ...launchArgs}.toList()..sort();
  return [
    for (final name in names)
      LogOption(
        name: name,
        isSetting: settings.containsKey(name),
        isLaunchArg: launchArgs.contains(name),
        description: settings[name]?.description,
        isLegacy: settings[name]?.isLegacy ?? false,
      ),
  ];
}

final _settingKey = RegExp(r'^dart\.(\w+LogFile)$');

({String? description, bool isLegacy}) _describe(Object? setting) {
  final markdown = setting is Map ? setting['markdownDescription'] : null;
  if (markdown is! String) return (description: null, isLegacy: false);
  final isLegacy = markdown.contains('LEGACY');
  final text = markdown
      .replaceAll(RegExp(r'\*\*LEGACY[^*]*\*\*'), '')
      .replaceAll('`', '')
      .trim();
  final sentence = text.split(RegExp(r'(?<=\.)\s')).first.trim();
  return (description: sentence, isLegacy: isLegacy);
}

Map<String, ({String? description, bool isLegacy})> _settingsFromPackageJson(
  File file,
) {
  final found = <String, ({String? description, bool isLegacy})>{};
  void walk(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final match = _settingKey.firstMatch('${entry.key}');
        if (match != null && entry.value is Map) {
          found[match.group(1)!] = _describe(entry.value);
        }
        walk(entry.value);
      }
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(jsonDecode(file.readAsStringSync()));
  return found;
}

Set<String> _launchArgsFromInterfaces(File file) {
  if (!file.existsSync()) return {};
  final source = file.readAsStringSync();
  final start = source.indexOf('interface DartLaunchArgs');
  if (start == -1) return {};
  final end = source.indexOf('\n}', start);
  final body = source.substring(start, end == -1 ? source.length : end);
  return RegExp(r'^\s*(\w+LogFile)\??\s*:', multiLine: true)
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}
