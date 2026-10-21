import 'dart:io';
import 'dart:typed_data';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/base_debugger.dart';
import 'package:classic_code_editor/services/debugger_factory.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
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
  home: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
);

/// Short lines, so nothing wraps and a drift can only come from the metrics.
String _source(int lines) {
  final buffer = StringBuffer();
  for (var i = 1; i <= lines; i++) {
    buffer.writeln('final value$i = $i;');
  }
  return buffer.toString();
}

/// Byte offset of the start of [oneBasedLine].
int _offsetOfLine(String text, int oneBasedLine) {
  var offset = 0;
  var current = 1;
  while (current < oneBasedLine) {
    final nl = text.indexOf('\n', offset);
    if (nl < 0) return -1;
    offset = nl + 1;
    current++;
  }
  return offset;
}

/// Registers [path] under [family]; false when the host cannot provide it.
Future<bool> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return false;
  final bytes = await file.readAsBytes();
  try {
    await (FontLoader(family)..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(Uint8List.fromList(bytes)),
          ),
        ))
        .load();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  /// Families whose real glyphs this test could load. A family that is missing
  /// still exercises the code path, but through `fontFamilyFallback`, so the
  /// alignment assertion stays meaningful either way.
  final loaded = <String>{};

  setUpAll(() async {
    if (await _loadFont('Menlo', '/System/Library/Fonts/Menlo.ttc')) {
      loaded.add('Menlo');
    }
    if (await _loadFont(
      'RecursiveMonoCasual',
      'assets/fonts/RecursiveMonoCslSt-Regular.ttf',
    )) {
      loaded.add('RecursiveMonoCasual');
    }
    // ignore: avoid_print
    print('fonts available to flutter_tester: $loaded');
  });

  tearDown(() {
    // The singleton is process-wide; never leak a family into another test.
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
  });

  /// Pumps the panel at the current singleton size/family.
  Future<FileService> pumpEditor(
    WidgetTester tester, {
    String text = '',
    BaseDebugger? debugger,
  }) async {
    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath('/tmp/font_gutter.dart', text);

    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(
        CodeEditorPanel(
          fileService: fileService,
          lspService: lsp,
          debugger: debugger,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fileService;
  }

  group('gutter alignment for every editor font', () {
    for (final size in <double>[8, 13, 32]) {
      for (final family in EditorFontFamily.values) {
        testWidgets('${family.id} at size $size', (tester) async {
          EditorSettingsService.instance.setFontSize(size);
          EditorSettingsService.instance.setFontFamily(family);

          final metrics = EditorMetrics.forFontSize(size, family: family);
          final text = _source(20);
          await pumpEditor(tester, text: text);

          final renderEditable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;

          double caretTop(int line) => renderEditable
              .localToGlobal(
                renderEditable
                    .getLocalRectForCaret(
                      TextPosition(offset: _offsetOfLine(text, line)),
                    )
                    .topLeft,
              )
              .dy;

          // 1. The rendered line step must equal the metrics line height. An
          // unforced strut would break this: a fallback glyph for a Persian
          // line grows the row, so line 11 would already sit several px off.
          final step = (caretTop(11) - caretTop(1)) / 10;
          expect(
            step,
            closeTo(metrics.lineHeight, 0.01),
            reason:
                '${family.id} at $size: the editor must render '
                '${metrics.lineHeight}px rows, not $step',
          );

          // 2. Each number must be centred on its own code line. At size 32 a
          // 47px row means only the first ~14 lines are on screen, so the
          // sample is clipped to what is really laid out.
          // A 47px row at size 32 leaves room for ~14 of them in the 700px
          // viewport, so the sample is clipped to a conservative budget.
          const lineCount = 20;
          final lastVisible = (600 / metrics.lineHeight).floor().clamp(
            1,
            lineCount,
          );
          final sample =
              <int>[1, 2, 5, 11, lastVisible]
                  .where((line) => line >= 1 && line <= lastVisible)
                  .toSet()
                  .toList()
                ..sort();
          expect(
            sample.length,
            greaterThanOrEqualTo(3),
            reason: 'the viewport must show enough lines to be meaningful',
          );

          for (final line in sample) {
            final codeCentre = caretTop(line) + metrics.lineHeight / 2;
            final number = find.text('$line');
            expect(number, findsOneWidget, reason: 'gutter row for line $line');
            expect(
              tester.getRect(number).center.dy,
              closeTo(codeCentre, 0.5),
              reason:
                  '${family.id} at $size: line $line number must centre on '
                  'its code line',
            );
          }

          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('the paused arrow follows the family', () {
    for (final family in EditorFontFamily.values) {
      testWidgets('▶ sits on the paused line with ${family.id}', (
        tester,
      ) async {
        const size = 13.0;
        EditorSettingsService.instance.setFontSize(size);
        EditorSettingsService.instance.setFontFamily(family);

        final factory = DebuggerFactory();
        addTearDown(factory.dispose);

        final text = _source(20);
        final debugger = factory.forCode('/tmp/font_gutter.dart', text);
        final metrics = EditorMetrics.forFontSize(size, family: family);

        final fileService = FileService();
        addTearDown(fileService.dispose);
        fileService.openFilePath('/tmp/font_gutter.dart', text);
        final lsp = _OfflineLspService();
        addTearDown(lsp.dispose);

        Widget build() => CodeEditorPanel(
          fileService: fileService,
          lspService: lsp,
          debugger: debugger,
        );

        await tester.pumpWidget(_wrap(build()));
        await tester.pumpAndSettle();
        expect(find.text('▶'), findsNothing);

        // The debugger reports a pause through its own listeners; rebuilding
        // the panel is how the IDE shell reacts, and it is what makes the
        // gutter repaint here.
        debugger.state = DebugState.paused;
        debugger.currentPausedLine = 5;
        await tester.pumpWidget(_wrap(build()));
        await tester.pump();

        expect(find.text('▶'), findsOneWidget);

        final renderEditable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final codeCentre =
            renderEditable
                .localToGlobal(
                  renderEditable
                      .getLocalRectForCaret(
                        TextPosition(offset: _offsetOfLine(text, 5)),
                      )
                      .topLeft,
                )
                .dy +
            metrics.lineHeight / 2;

        expect(
          tester.getRect(find.text('▶')).center.dy,
          closeTo(codeCentre, 0.5),
          reason: '${family.id}: the arrow must sit on line 5, not beside it',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('switching family invalidates the measurement caches', () {
    testWidgets('a later family cannot reuse the previous advance', (
      tester,
    ) async {
      EditorSettingsService.instance.setFontSize(13);
      EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
      final text = _source(20);
      await pumpEditor(tester, text: text);

      final renderEditable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      double caretTop(int line) => renderEditable
          .localToGlobal(
            renderEditable
                .getLocalRectForCaret(
                  TextPosition(offset: _offsetOfLine(text, line)),
                )
                .topLeft,
          )
          .dy;

      // Warm every cache at Menlo, then switch twice without a size change.
      for (final line in <int>[1, 5, 20]) {
        expect(caretTop(line), isNotNull);
      }

      for (final family in <EditorFontFamily>[
        EditorFontFamily.recursive,
        EditorFontFamily.menlo,
        EditorFontFamily.recursive,
      ]) {
        EditorSettingsService.instance.setFontFamily(family);
        await tester.pumpAndSettle();

        final metrics = EditorMetrics.forFontSize(13, family: family);
        expect(
          (caretTop(11) - caretTop(1)) / 10,
          closeTo(metrics.lineHeight, 0.01),
          reason: '${family.id}: row height must follow the cached metrics',
        );
        expect(find.text('20'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
