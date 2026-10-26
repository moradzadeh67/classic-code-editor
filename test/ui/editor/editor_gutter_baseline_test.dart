import 'dart:io';
import 'dart:typed_data';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// The gutter number must sit **on the code's baseline**, not merely inside the
/// same row box.
///
/// The row box is easy (`itemExtent: lineHeight`), the baseline is not: the
/// number is a smaller font (11px vs 13px), so the ambient `height` inherited
/// from the editor theme decides where the digit lands inside that box. With the
/// inherited 1.43 the digit sat ~1px above the code - visibly worse with
/// Recursive than with Menlo. The fix is an explicit
/// `height: lineHeight / lineNumberFontSize` with the default (proportional)
/// leading; `TextLeadingDistribution.even` moves it 1px up again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> register(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    await (FontLoader(family)..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(Uint8List.fromList(bytes)),
          ),
        ))
        .load();
  }

  setUpAll(() async {
    await register('Menlo', '/System/Library/Fonts/Menlo.ttc');
    await register(
      'RecursiveMonoCasual',
      'assets/fonts/RecursiveMonoCslSt-Regular.ttf',
    );
  });

  tearDown(() {
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
  });

  for (final family in EditorFontFamily.values) {
    for (final size in <double>[8, 13, 32]) {
      testWidgets('${family.id}@$size numbers sit on the code baseline', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        EditorSettingsService.instance.setFontSize(size);
        EditorSettingsService.instance.setFontFamily(family);

        final text = List<String>.generate(
          6,
          (i) => 'line ${i + 1};',
        ).join('\n');
        final fileService = FileService();
        addTearDown(fileService.dispose);
        fileService.openFilePath('/tmp/baseline.cpp', text);
        final lsp = _QuietLspService();
        addTearDown(lsp.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CodeEditorPanel(fileService: fileService, lspService: lsp),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final metrics = EditorMetrics.forFontSize(size, family: family);
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;

        // The code's baseline, in global coordinates.
        final rowTop = editable
            .localToGlobal(
              editable
                  .getLocalRectForCaret(
                    TextPosition(offset: text.indexOf('line 3')),
                  )
                  .topLeft,
            )
            .dy;
        final codePainter = TextPainter(
          textDirection: TextDirection.ltr,
          strutStyle: metrics.strutStyle,
        )..text = TextSpan(text: 'line 3;', style: metrics.textStyle);
        codePainter.layout();
        final codeBaseline =
            rowTop +
            codePainter.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );
        final codeBox = codePainter.height;
        codePainter.dispose();

        // The gutter number as painted.
        final numberFinder = find.text('3');
        final numberParagraph = tester.renderObject<RenderParagraph>(
          numberFinder,
        );
        final numberBaseline =
            tester.getTopLeft(numberFinder).dy +
            numberParagraph.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );

        expect(
          numberParagraph.size.height,
          closeTo(codeBox, 0.01),
          reason:
              '${family.id}@$size: the number row and the code row must be the '
              'same height',
        );
        expect(
          numberBaseline,
          closeTo(codeBaseline, 0.5),
          reason:
              '${family.id}@$size: the digit must sit on the code baseline '
              '(was ${(numberBaseline - codeBaseline).toStringAsFixed(2)}px off)',
        );
      });
    }
  }
}

class _QuietLspService extends LspService {
  @override
  bool get isConnected => false;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
    {String? triggerCharacter, int? triggerKind}) async => const <CompletionItem>[];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}
