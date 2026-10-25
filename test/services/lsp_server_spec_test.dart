import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/services/lsp_server_spec.dart';

void main() {
  group('LspServerSpec.candidatesForLanguage', () {
    test('maps every supported language to its server', () {
      expect(
        LspServerSpec.candidatesForLanguage('dart').single.id,
        'dart',
      );
      expect(
        LspServerSpec.candidatesForLanguage('c').single.id,
        'clangd',
      );
      expect(
        LspServerSpec.candidatesForLanguage('cpp').single.id,
        'clangd',
      );
    });

    test('prefers pyright and keeps pylsp as the fallback', () {
      final ids = LspServerSpec.candidatesForLanguage(
        'python',
      ).map((spec) => spec.id).toList();

      expect(ids, <String>['pyright', 'pylsp']);
    });

    test('has no server for assembly or unknown languages', () {
      expect(LspServerSpec.candidatesForLanguage('armasm'), isEmpty);
      expect(LspServerSpec.candidatesForLanguage('plaintext'), isEmpty);
    });
  });

  group('LspServerSpec.candidatesForFile', () {
    test('uses the file extension', () {
      expect(LspServerSpec.candidatesForFile('/tmp/main.py').first.id, 'pyright');
      expect(LspServerSpec.candidatesForFile('/tmp/main.cpp').single.id, 'clangd');
      expect(LspServerSpec.candidatesForFile('/tmp/main.s'), isEmpty);
      expect(LspServerSpec.candidatesForFile(null).single.id, 'dart');
    });
  });

  group('server arguments', () {
    test('clangd is launched without --stdio', () {
      // Apple's clangd rejects --stdio; it speaks stdio by default. Passing the
      // flag makes the server exit immediately and every C/C++ feature dies.
      expect(LspServerSpec.clangd.arguments, isNot(contains('--stdio')));
      expect(LspServerSpec.clangd.executableNames, contains('/usr/bin/clangd'));
    });

    test('pyright needs --stdio, the Dart server needs its client identity', () {
      expect(LspServerSpec.pyright.arguments, contains('--stdio'));
      expect(LspServerSpec.dart.arguments, contains('language-server'));
      expect(
        LspServerSpec.dart.arguments,
        contains('--client-id=${LspServerSpec.clientId}'),
      );
    });

    test('clangd alone asks for compile_flags.txt', () {
      expect(LspServerSpec.clangd.usesCompileFlags, isTrue);
      expect(LspServerSpec.dart.usesCompileFlags, isFalse);
      expect(LspServerSpec.pyright.usesCompileFlags, isFalse);
      expect(LspServerSpec.pylsp.usesCompileFlags, isFalse);
    });

    test('every real server ships a usable install hint', () {
      for (final spec in <LspServerSpec>[
        LspServerSpec.dart,
        LspServerSpec.clangd,
        LspServerSpec.pyright,
        LspServerSpec.pylsp,
      ]) {
        expect(spec.installHint, isNotEmpty, reason: spec.id);
        expect(spec.executableNames, isNotEmpty, reason: spec.id);
        expect(spec.languageIds, isNotEmpty, reason: spec.id);
      }
    });
  });

  group('support checks', () {
    test('a spec only accepts its own language ids', () {
      expect(LspServerSpec.clangd.supports('c'), isTrue);
      expect(LspServerSpec.clangd.supports('cpp'), isTrue);
      expect(LspServerSpec.clangd.supports('dart'), isFalse);
      expect(LspServerSpec.off.supports('c'), isFalse);
      expect(LspServerSpec.off.languageIds, isEmpty);
    });
  });
}
