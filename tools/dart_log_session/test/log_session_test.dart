import 'dart:convert';
import 'dart:io';

import 'package:dart_log_session/src/jsonc.dart';
import 'package:dart_log_session/src/log_options.dart';
import 'package:dart_log_session/src/workspace_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('decodeJsonc', () {
    test('handles comments and trailing commas but not strings', () {
      final result = decodeJsonc('''
{
  // line comment
  "url": "http://example.com/*not a comment*/", /* block */
  "list": [1, 2,],
}
''');
      expect(result, {
        'url': 'http://example.com/*not a comment*/',
        'list': [1, 2],
      });
    });
  });

  group('discoverLogOptions', () {
    final root = findDartCodeRoot(Directory.current.path);

    test('finds the checkout', () => expect(root, isNotNull));

    test('finds settings and launch args', () {
      final byName = {for (final o in discoverLogOptions(root!)) o.name: o};
      expect(byName['analyzerLogFile']!.isSetting, isTrue);
      expect(byName['analyzerLogFile']!.isLaunchArg, isFalse);
      expect(byName['webDaemonLogFile']!.isSetting, isTrue);
      expect(byName['webDaemonLogFile']!.isLaunchArg, isTrue);
      expect(byName['webDaemonLogFile']!.isLegacy, isTrue);
      expect(byName.keys, everyElement(endsWith('LogFile')));
    });
  });

  group('writers', () {
    late Directory ws;
    setUp(() => ws = Directory.systemTemp.createTempSync('dls'));
    tearDown(() => ws.deleteSync(recursive: true));

    final options = [
      LogOption(name: 'aLogFile', isSetting: true, isLaunchArg: false),
      LogOption(name: 'bLogFile', isSetting: true, isLaunchArg: true),
      LogOption(
        name: 'oldLogFile',
        isSetting: true,
        isLaunchArg: false,
        isLegacy: true,
      ),
    ];

    test('merge into existing JSONC and keep a backup', () {
      File(p.join(ws.path, '.vscode', 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{ // keep me\n "editor.tabSize": 2, }');
      final paths = assignLogPaths(options, '/logs');

      final file = writeSettings(
        workspace: ws.path,
        options: options,
        paths: paths,
        includeLegacy: false,
      );
      final json = jsonDecode(file.readAsStringSync()) as Map;
      expect(json['editor.tabSize'], 2);
      expect(json['dart.aLogFile'], paths['aLogFile']);
      expect(json.containsKey('dart.oldLogFile'), isFalse);
      expect(File('${file.path}.bak').existsSync(), isTrue);
    });

    test('launch config is replaced, not duplicated', () {
      final paths = assignLogPaths(options, '/logs');
      for (var i = 0; i < 2; i++) {
        writeLaunchConfig(
          workspace: ws.path,
          options: options,
          paths: paths,
          name: 'n',
          program: 'lib/main.dart',
          deviceId: 'chrome',
        );
      }
      final json = jsonDecode(
        File(p.join(ws.path, '.vscode', 'launch.json')).readAsStringSync(),
      ) as Map;
      final configs = json['configurations'] as List;
      expect(configs, hasLength(1));
      expect(configs.single['bLogFile'], paths['bLogFile']);
      expect(configs.single.containsKey('aLogFile'), isFalse);
      expect(configs.single['deviceId'], 'chrome');
    });
  });
}
