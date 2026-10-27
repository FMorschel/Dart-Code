import 'dart:io';

import 'package:dart_log_session/src/log_options.dart';
import 'package:dart_log_session/src/workspace_writer.dart';
import 'package:path/path.dart' as p;

const _usage = '''
Enables every Dart-Code log file option in a workspace and gets it ready to
start a debug session.

Usage: dart run dart_log_session [options]

  --workspace <dir>   Workspace to configure (default: current directory).
  --dart-code <dir>   Dart-Code checkout to read the options from
                      (default: the checkout containing this tool).
  --log-dir <dir>     Where the log files go
                      (default: <workspace>/.dart_code_logs/<timestamp>).
  --name <name>       Launch configuration name (default: Logged session).
  --program <file>    Program to launch (default: lib/main.dart).
  --device <id>       Flutter device id, for example chrome.
  --no-legacy         Skip settings that only apply to legacy debug adapters.
  --list              Print the discovered options and exit.
  --dry-run           Print what would be written without touching any file.
  --open              Open the workspace in VS Code afterwards.
  --code <command>    VS Code command used by --open (default: code).
  -h, --help          Show this help.
''';

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

int main(List<String> argv) {
  final flags = <String>{};
  final values = <String, String>{};
  const valueOptions = {
    'workspace', 'dart-code', 'log-dir', 'name', 'program', 'device', 'code', //
  };
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (arg == '-h') {
      flags.add('help');
    } else if (arg.startsWith('--')) {
      final key = arg.substring(2);
      if (valueOptions.contains(key)) {
        if (i + 1 >= argv.length) _fail('Missing value for $arg.\n\n$_usage');
        values[key] = argv[++i];
      } else if (const {
        'help', 'list', 'dry-run', 'open', 'no-legacy', //
      }.contains(key)) {
        flags.add(key);
      } else {
        _fail('Unknown option $arg.\n\n$_usage');
      }
    } else {
      _fail('Unexpected argument $arg.\n\n$_usage');
    }
  }

  if (flags.contains('help')) {
    stdout.write(_usage);
    return 0;
  }

  final root = values['dart-code'] ??
      findDartCodeRoot(p.dirname(Platform.script.toFilePath()));
  if (root == null) {
    _fail('Could not find a Dart-Code checkout. Pass --dart-code <dir>.');
  }
  final options = discoverLogOptions(root);
  if (options.isEmpty) _fail('No log file options found in $root.');

  if (flags.contains('list')) {
    for (final o in options) {
      final where = [
        if (o.isSetting) 'setting',
        if (o.isLaunchArg) 'launch arg',
      ].join(' + ');
      stdout.writeln(
        '${o.name.padRight(32)} $where${o.isLegacy ? ' (legacy)' : ''}',
      );
      if (o.description != null) stdout.writeln('    ${o.description}');
    }
    return 0;
  }

  final workspace = p.absolute(values['workspace'] ?? Directory.current.path);
  if (!Directory(workspace).existsSync()) {
    _fail('Workspace $workspace does not exist.');
  }
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .split('Z')
      .first;
  final logDir = p.absolute(
    values['log-dir'] ?? p.join(workspace, '.dart_code_logs', stamp),
  );
  final includeLegacy = !flags.contains('no-legacy');
  final used = options.where((o) => includeLegacy || !o.isLegacy).toList();
  final paths = assignLogPaths(used, logDir);
  final name = values['name'] ?? 'Logged session';

  if (flags.contains('dry-run')) {
    stdout.writeln('Would write ${used.length} log options into $workspace:');
    paths.forEach((k, v) => stdout.writeln('  $k -> $v'));
    return 0;
  }

  Directory(logDir).createSync(recursive: true);
  final settings = writeSettings(
    workspace: workspace,
    options: used,
    paths: paths,
    includeLegacy: includeLegacy,
  );
  final launch = writeLaunchConfig(
    workspace: workspace,
    options: used,
    paths: paths,
    name: name,
    program: values['program'] ?? 'lib/main.dart',
    deviceId: values['device'],
  );

  stdout
    ..writeln('Read ${options.length} log options from $root')
    ..writeln('Wrote ${settings.path}')
    ..writeln('Wrote ${launch.path}')
    ..writeln('Logs will appear in $logDir');

  if (flags.contains('open')) {
    final code = values['code'] ?? 'code';
    try {
      Process.runSync(code, [workspace], runInShell: Platform.isWindows);
    } on ProcessException catch (e) {
      _fail('Could not run "$code": ${e.message}');
    }
  }

  stdout
    ..writeln()
    ..writeln('Next steps (VS Code cannot be told to start a session from '
        'outside):')
    ..writeln('  1. Open or reload the window so extension-level logs '
        '(analyzer, DTD, daemons...) pick up the new settings.')
    ..writeln('  2. Run "$name" from the Run and Debug panel.');
  return 0;
}
