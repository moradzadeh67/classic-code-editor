import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/models/syntax_scheme.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/editor/autocomplete_popup.dart';
import 'package:classic_code_editor/utils/completion_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The completion popup shows a kind badge (M/F/C/K/…) and, when the server
/// sent one, the item's detail on the same line.
void main() {
  setUp(() {
    EditorSettingsService.instance.setSyntaxScheme(SyntaxScheme.standard);
  });

  tearDown(() {
    EditorSettingsService.instance.setSyntaxScheme(SyntaxScheme.standard);
  });

  CompletionItem item({
    required String label,
    required String kind,
    required int? kindInt,
    String? detail,
  }) => CompletionItem(
    label: label,
    kind: kind,
    kindInt: kindInt,
    detail: detail,
  );

  Widget wrap(List<CompletionItem> items) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          AutocompletePopup(
            items: items,
            anchor: const Rect.fromLTWH(10, 10, 2, 18),
            bounds: const Size(420, 320),
            selectedIndex: 0,
            maxWidth: 260,
            onSelect: (_) {},
            onDismiss: () {},
          ),
        ],
      ),
    ),
  );

  testWidgets('each row shows its kind letter and the detail inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap([
        item(
          label: 'print',
          kind: 'method',
          kindInt: 3,
          detail: 'void print(Object? object)',
        ),
        item(label: 'Point', kind: 'class', kindInt: 7),
      ]),
    );

    final badges = tester
        .widgetList<CompletionBadgeChip>(find.byType(CompletionBadgeChip))
        .toList();
    expect(badges, hasLength(2));
    expect(badges[0].letter, 'M');
    expect(badges[1].letter, 'C');

    // The detail is on the same line: right-aligned, dimmed and ellipsized.
    final detail = tester.widget<Text>(find.text('void print(Object? object)'));
    expect(detail.maxLines, 1);
    expect(detail.softWrap, isFalse);
    expect(detail.overflow, TextOverflow.ellipsis);
    expect(detail.textAlign, TextAlign.right);

    // No wrapping means no taller row, so both rows keep the same height.
    expect(tester.getSize(find.byType(CompletionBadgeChip).first).height, 16);
    expect(
      tester.getSize(find.text('print')).height,
      tester.getSize(find.text('Point')).height,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits in all four themes without overflowing', (tester) async {
    addTearDown(() => ThemeService.instance.switchTheme(ThemeType.vc6));
    final items = [
      item(
        label: 'a_very_long_label_that_must_be_truncated_not_wrapped',
        kind: 'field',
        kindInt: 5,
        detail:
            'final Map<String, List<double>> a_very_long_detail_that_must_be_truncated',
      ),
      item(
        label: 'setState',
        kind: 'method',
        kindInt: 2,
        detail: 'void setState(VoidCallback fn)',
      ),
      item(label: 'forEach', kind: 'method', kindInt: 3),
    ];

    for (final theme in ThemeType.values) {
      ThemeService.instance.switchTheme(theme);
      await tester.pumpWidget(wrap(items));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: theme.name);
      // The list is lazy, so only the rows that fit are built.
      expect(find.byType(CompletionBadgeChip), findsWidgets);
      // The long detail stays on one line, truncated inside the popup.
      final detail = tester.widget<Text>(
        find.textContaining('final Map<String'),
      );
      expect(detail.maxLines, 1);
      // The long label is truncated too, never wrapped.
      final label = tester.widget<Text>(
        find.text('a_very_long_label_that_must_be_truncated_not_wrapped'),
      );
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.byKey(AutocompletePopup.listKey)).width,
        lessThanOrEqualTo(420),
      );
    }
  });

  testWidgets('badge colours come from the active syntax scheme', (
    tester,
  ) async {
    final items = [
      item(label: 'print', kind: 'method', kindInt: 3),
      item(label: 'count', kind: 'variable', kindInt: 6),
    ];
    await tester.pumpWidget(wrap(items));

    CompletionBadgeChip badge(int index) => tester
        .widgetList<CompletionBadgeChip>(find.byType(CompletionBadgeChip))
        .elementAt(index);

    final standardCallable = completionBadgeColor(
      CompletionKindCategory.callable,
      SyntaxScheme.standard,
    );
    expect(badge(0).color, standardCallable);
    expect(badge(1).color, completionBadgeColor(
      CompletionKindCategory.value,
      SyntaxScheme.standard,
    ));

    // Switching the scheme repaints the badges without rebuilding the popup.
    EditorSettingsService.instance.setSyntaxScheme(SyntaxScheme.colorful);
    await tester.pump();

    final colorfulCallable = completionBadgeColor(
      CompletionKindCategory.callable,
      SyntaxScheme.colorful,
    );
    expect(colorfulCallable, isNot(standardCallable));
    expect(badge(0).color, colorfulCallable);
  });
}
