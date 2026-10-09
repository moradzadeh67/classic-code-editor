import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/services/debugger_factory.dart';
import 'package:borland_dart/services/file_service.dart';
import 'package:borland_dart/services/lsp_service.dart';
import 'package:borland_dart/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A language server that never connects, keeping the widget tests offline.
class _OfflineLspService extends LspService {
  @override
  bool get isConnected => false;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async => const <CompletionItem>[];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
);

const _dartSample = '''
int addBonus(int base, int bonus) {
  int total = base + bonus;
  return total;
}

void main() {
  String greeting = "Hello (Dart)!";
  int sum = 0;
  for (int i = 1; i <= 3; i++) {
    sum = sum + i;
  }
  print(greeting);
}
''';

const _pythonSample = '''
def add_bonus(base, bonus):
    total = base + bonus
    return total

def main():
    greeting = "Hello (Python)!"
    total_sum = 0
    for i in range(1, 4):
        total_sum = total_sum + i
    print(greeting)

main()
''';

const _cSample = '''
#include <stdio.h>

int add_bonus(int base, int bonus) {
    int total = base + bonus;
    return total;
}

int main() {
    int sum = 0;
    int i;
    printf("Hello (C)!");
    for (i = 1; i <= 3; i++) {
        sum = sum + i;
    }
    return 0;
}
''';

const _cppSample = '''
#include <iostream>
#include <string>

int addBonus(int base, int bonus) {
    int total = base + bonus;
    return total;
}

int main() {
    int sum = 0;
    for (int i = 1; i <= 3; i++) {
        sum = sum + i;
    }
    return 0;
}
''';

/// Every language the IDE supports, with a sample and the file path used to
/// resolve which debugger owns it.
const _cases = <String, (String path, String code, int pausedLine)>{
  'Dart': ('/tmp/main.dart', _dartSample, 3),
  'Python': ('/tmp/main.py', _pythonSample, 2),
  'C': ('/tmp/main.c', _cSample, 4),
  'C++': ('/tmp/main.cpp', _cppSample, 5),
};

void main() {
  group('paused-line arrow is language agnostic', () {
    for (final entry in _cases.entries) {
      testWidgets('${entry.key} renders the ▶ marker in the gutter', (
        tester,
      ) async {
        final (path, code, pausedLine) = entry.value;

        final fileService = FileService();
        addTearDown(fileService.dispose);
        fileService.openFilePath(path, code);

        final lsp = _OfflineLspService();
        addTearDown(lsp.dispose);

        final factory = DebuggerFactory();
        addTearDown(factory.dispose);

        // The factory - not the widget - decides which debugger drives the
        // active tab, exactly like the IDE shell does.
        final debugger = factory.forCode(path, code);

        CodeEditorPanel build() => CodeEditorPanel(
          fileService: fileService,
          lspService: lsp,
          debugger: debugger,
        );

        await tester.pumpWidget(_wrap(build()));
        await tester.pumpAndSettle();

        // Nothing is drawn while the debugger is idle.
        expect(find.text('▶'), findsNothing);

        debugger.state = DebugState.paused;
        debugger.currentPausedLine = pausedLine;

        await tester.pumpWidget(_wrap(build()));
        await tester.pump();

        expect(find.text('▶'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('C and C++ share the same gutter-capable debugger', (
      tester,
    ) async {
      final factory = DebuggerFactory();
      addTearDown(factory.dispose);

      final c = factory.forCode('/tmp/main.c', _cSample);
      final cpp = factory.forCode('/tmp/main.cpp', _cppSample);

      expect(c, same(factory.cDebugger));
      expect(cpp, same(factory.cDebugger));
      expect(c, same(cpp));
    });

    testWidgets(
      'an unsaved buffer still resolves to an arrow-capable debugger',
      (tester) async {
        final factory = DebuggerFactory();
        addTearDown(factory.dispose);

        // No path at all: the runner's content sniffing must pick the language,
        // and every language must map to a debugger that reports a paused line.
        for (final entry in _cases.entries) {
          final (_, code, _) = entry.value;
          final debugger = factory.forCode(null, code);
          expect(
            debugger,
            same(factory.forCode(null, code)),
            reason: '${entry.key} should resolve to a stable debugger instance',
          );
          expect(
            factory.all,
            contains(debugger),
            reason: '${entry.key} resolved outside the factory',
          );
        }
      },
    );
  });

  group('gutter rows align with the editor text', () {
    testWidgets('consecutive lines are exactly one editor line apart', (
      tester,
    ) async {
      final fileService = FileService();
      addTearDown(fileService.dispose);
      fileService.openFilePath('/tmp/main.cpp', _cppSample);

      final lsp = _OfflineLspService();
      addTearDown(lsp.dispose);

      final factory = DebuggerFactory();
      addTearDown(factory.dispose);
      final debugger = factory.cDebugger;

      CodeEditorPanel build() => CodeEditorPanel(
        fileService: fileService,
        lspService: lsp,
        debugger: debugger,
      );

      await tester.pumpWidget(_wrap(build()));
      await tester.pumpAndSettle();

      debugger.state = DebugState.paused;
      debugger.currentPausedLine = 2;
      await tester.pumpWidget(_wrap(build()));
      await tester.pump();
      final firstY = tester.getCenter(find.text('▶')).dy;

      debugger.currentPausedLine = 12;
      await tester.pumpWidget(_wrap(build()));
      await tester.pump();
      final twelfthY = tester.getCenter(find.text('▶')).dy;

      // Regression guard: the gutter used to hardcode a 19.0 row height while
      // the editor renders 13 * 1.45 = 18.85 per line, so the marker drifted
      // ~0.15px per line and ended up on the wrong row in longer files.
      expect(twelfthY - firstY, closeTo(10 * editorLineHeight, 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
