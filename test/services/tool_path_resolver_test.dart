import 'package:classic_code_editor/services/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-083: a Finder-launched app must find the same tools as Terminal.
///
/// The shell answer and the file system are faked, so these are pure unit
/// tests: no process is started and no real path is touched.
void main() {
  ToolPathResolver resolver({
    required Map<String, String?> shellWhich,
    required Set<String> existing,
    Map<String, String>? environment,
  }) {
    return ToolPathResolver(
      loginShellWhich: (name) async => shellWhich[name],
      loginShellPath: () async => '/Users/me/flutter/bin:/opt/homebrew/bin',
      fileExists: existing.contains,
      environment:
          environment ??
          const <String, String>{
            'HOME': '/Users/me',
            'PATH': '/usr/bin:/bin',
          },
    );
  }

  group('ToolPathResolver', () {
    test('uses the login-shell answer first', () async {
      final lookup = await resolver(
        shellWhich: {'clangd': '/opt/homebrew/bin/clangd'},
        existing: {'/opt/homebrew/bin/clangd'},
      ).lookup('clangd');

      expect(lookup.path, '/opt/homebrew/bin/clangd');
      expect(lookup.tried.first, contains('login-shell PATH'));
    });

    test('falls back to a common location when the shell misses it', () async {
      final lookup = await resolver(
        shellWhich: const <String, String?>{},
        existing: {'/opt/homebrew/bin/pyright-langserver'},
      ).lookup('pyright-langserver');

      expect(lookup.path, '/opt/homebrew/bin/pyright-langserver');
      expect(
        lookup.tried,
        contains('/opt/homebrew/bin/pyright-langserver'),
      );
    });

    test('prefers the Dart SDK next to the Flutter on the login PATH',
        () async {
      final lookup = await resolver(
        shellWhich: {
          'flutter': '/Users/me/flutter/bin/flutter',
          'dart': '/usr/local/bin/dart',
        },
        existing: {
          '/Users/me/flutter/bin/dart',
          '/usr/local/bin/dart',
        },
      ).lookup('dart');

      expect(lookup.path, '/Users/me/flutter/bin/dart');
      expect(lookup.tried.first, contains('next to'));
    });

    test('reports nothing found with every location it tried', () async {
      final lookup = await resolver(
        shellWhich: const <String, String?>{},
        existing: const <String>{},
      ).lookup('dart');

      expect(lookup.path, isNull);
      expect(lookup.found, isFalse);
      expect(lookup.tried.join(' '), contains('login-shell PATH'));
      expect(lookup.tried, contains('/opt/homebrew/bin/dart'));
      expect(lookup.tried, contains('/usr/bin/dart'));
    });

    test('ignores an alias answer instead of spawning it', () async {
      final lookup = await resolver(
        shellWhich: {'pylsp': 'pylsp: aliased to python3 -m pylsp'},
        existing: const <String>{},
      ).lookup('pylsp');

      expect(lookup.path, isNull);
    });

    test('the child environment carries the login PATH first', () async {
      final environment = await resolver(
        shellWhich: const <String, String?>{},
        existing: const <String>{},
      ).processEnvironment();

      final path = environment['PATH']!.split(':');
      expect(path.first, '/Users/me/flutter/bin');
      expect(path, contains('/usr/bin'));
      expect(path, contains('/Users/me/.pub-cache/bin'));
      // No duplicates even though /usr/bin appears in several sources.
      expect(path.toSet().length, path.length);
    });
  });
}
