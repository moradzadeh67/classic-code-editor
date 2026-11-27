import 'package:material_ui/material_ui.dart';

/// The toolbar's 16x16 pixel-art icons, in the style of a Windows 9x IDE.
///
/// Original artwork drawn for this app (no bitmaps are copied from any other
/// product). Each icon is a 16x16 grid of characters, one per pixel, looked up
/// in [_palette]; `.` is transparent. The palette is fixed on purpose: like
/// the bitmaps of the era, the icons keep their colors on every theme.
enum RetroToolbarIconType {
  newFile,
  open,
  save,
  analyze,
  cut,
  copy,
  paste,
  undo,
  redo,
  run,
  stop,
  debug,
  stepOver,
  stepInto,
  stepOut,
  resume,
}

/// Classic 16-color palette (plus brown and amber for the clipboard and the
/// folder).
const Map<String, Color> _palette = <String, Color>{
  'k': Color(0xFF000000), // black
  'w': Color(0xFFFFFFFF), // white
  'g': Color(0xFFC0C0C0), // light gray
  'd': Color(0xFF808080), // dark gray
  'n': Color(0xFF000080), // navy
  'y': Color(0xFFFFFF00), // yellow
  'o': Color(0xFFD8A800), // amber (folder back)
  'u': Color(0xFF996633), // brown (clipboard)
  'r': Color(0xFFFF0000), // red
  'G': Color(0xFF008000), // green
};

const List<String> _newFile = <String>[
  '................',
  '...kkkkkkk......',
  '...kwwwwwkk.....',
  '...kwwwwwkwk....',
  '...kwwwwwkkkk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kwwwwwwwwk...',
  '...kkkkkkkkkk...',
  '................',
];

const List<String> _open = <String>[
  '................',
  '................',
  '................',
  '.kkkkk..........',
  'koooook.........',
  'kooooookkkkkkk..',
  'koooooooooooook.',
  'koookkkkkkkkkkkk',
  'kookyyyyyyyyyyk.',
  'kokyyyyyyyyyyk..',
  'kkyyyyyyyyyyk...',
  'kkkkkkkkkkkk....',
  '................',
  '................',
  '................',
  '................',
];

const List<String> _save = <String>[
  '................',
  '.kkkkkkkkkkkkkk.',
  '.knwwwwwwwwwwnk.',
  '.knwwwwwwwwwwnk.',
  '.knwwwwwwwwwwnk.',
  '.knwwwwwwwwwwnk.',
  '.knnnnnnnnnnnnk.',
  '.knnnnnnnnnnnnk.',
  '.knnggggggggnnk.',
  '.knngkkgggggnnk.',
  '.knngkkgggggnnk.',
  '.knngkkgggggnnk.',
  '.kknggggggggnnk.',
  '..kkkkkkkkkkkkk.',
  '................',
  '................',
];

const List<String> _analyze = <String>[
  '................',
  '................',
  '................',
  '................',
  '............GG..',
  '...........GGG..',
  '..........GGG...',
  '..GG.....GGG....',
  '..GGG...GGG.....',
  '...GGG.GGG......',
  '....GGGGG.......',
  '.....GGG........',
  '......G.........',
  '................',
  '................',
  '................',
];

const List<String> _cut = <String>[
  '................',
  '....k.....k.....',
  '....k.....k.....',
  '....kk...kk.....',
  '.....k...k......',
  '.....kk.kk......',
  '......kkk.......',
  '.......k........',
  '......nkn.......',
  '....nnn.nnn.....',
  '...n..n.n..n....',
  '...n..n.n..n....',
  '...n..n.n..n....',
  '....nn...nn.....',
  '................',
  '................',
];

const List<String> _copy = <String>[
  'kkkkkkk.........',
  'kwwwwwk.........',
  'kwkkkwk.........',
  'kwwwwwk.........',
  'kwkkkwk.........',
  'kwwwwkkkkkkkk...',
  'kwkkkkwwwwwwk...',
  'kwwwwkwkkkkwk...',
  'kkkkkkwwwwwwk...',
  '.....kwkkkkwk...',
  '.....kwwwwwwk...',
  '.....kwkkkkwk...',
  '.....kwwwwwwk...',
  '.....kkkkkkkk...',
  '................',
  '................',
];

const List<String> _paste = <String>[
  '......kkkk......',
  '..kkkkgddgkkkk..',
  '.kuuukggggkuuuk.',
  '.kuuuukkkkuuuuk.',
  '.kuuuuuuuuuuuuk.',
  '.kuuuuukkkkkkkkk',
  '.kuuuuukwwwwwwwk',
  '.kuuuuukwkkkkkwk',
  '.kuuuuukwwwwwwwk',
  '.kuuuuukwkkkkkwk',
  '.kuuuuukwwwwwwwk',
  '.kuuuuukwkkkwwwk',
  '.kuuuuukwwwwwwwk',
  '.kkkkkkkkkkkkkkk',
  '................',
  '................',
];

const List<String> _run = <String>[
  '................',
  '................',
  '................',
  '......G.........',
  '......GG........',
  '......GGG.......',
  '......GGGG......',
  '......GGGGG.....',
  '......GGGGGG....',
  '......GGGGG.....',
  '......GGGG......',
  '......GGG.......',
  '......GG........',
  '......G.........',
  '................',
  '................',
];

const List<String> _stop = <String>[
  '................',
  '................',
  '................',
  '................',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '....rrrrrrrr....',
  '................',
  '................',
  '................',
  '................',
];

const List<String> _stepOver = <String>[
  '................',
  '................',
  '.....nnnnn......',
  '....n.....n.....',
  '...n.......n....',
  '...n.......n....',
  '...n.....nnnnn..',
  '...n......nnn...',
  '...........n....',
  '................',
  '................',
  '......kkk.......',
  '......kkk.......',
  '......kkk.......',
  '................',
  '................',
];

const List<String> _stepInto = <String>[
  '................',
  '.......n........',
  '.......n........',
  '.......n........',
  '.......n........',
  '.......n........',
  '....n..n..n.....',
  '.....n.n.n......',
  '......nnn.......',
  '.......n........',
  '................',
  '......kkk.......',
  '......kkk.......',
  '......kkk.......',
  '................',
  '................',
];

const List<String> _stepOut = <String>[
  '................',
  '.......n........',
  '......nnn.......',
  '.....n.n.n......',
  '....n..n..n.....',
  '.......n........',
  '.......n........',
  '.......n........',
  '.......n........',
  '................',
  '................',
  '......kkk.......',
  '......kkk.......',
  '......kkk.......',
  '................',
  '................',
];

const List<String> _resume = <String>[
  '................',
  '................',
  '................',
  '...nn.n.........',
  '...nn.nn........',
  '...nn.nnn.......',
  '...nn.nnnn......',
  '...nn.nnnnn.....',
  '...nn.nnnnnn....',
  '...nn.nnnnn.....',
  '...nn.nnnn......',
  '...nn.nnn.......',
  '...nn.nn........',
  '...nn.n.........',
  '................',
  '................',
];

/// The 16 rows of [type]'s pixel icon, or null for the vector icons: the two
/// arrows (Undo, Redo, [_UTurnArrowPainter]) and the Debug bug
/// ([_BugPainter]).
List<String>? retroToolbarIconRows(RetroToolbarIconType type) => switch (type) {
  RetroToolbarIconType.newFile => _newFile,
  RetroToolbarIconType.open => _open,
  RetroToolbarIconType.save => _save,
  RetroToolbarIconType.analyze => _analyze,
  RetroToolbarIconType.cut => _cut,
  RetroToolbarIconType.copy => _copy,
  RetroToolbarIconType.paste => _paste,
  RetroToolbarIconType.undo || RetroToolbarIconType.redo => null,
  RetroToolbarIconType.run => _run,
  RetroToolbarIconType.stop => _stop,
  RetroToolbarIconType.debug => null,
  RetroToolbarIconType.stepOver => _stepOver,
  RetroToolbarIconType.stepInto => _stepInto,
  RetroToolbarIconType.stepOut => _stepOut,
  RetroToolbarIconType.resume => _resume,
};

/// Whether [symbol] is a pixel color of the icon palette (`.` is
/// transparent).
bool isRetroIconPaletteSymbol(String symbol) =>
    symbol == '.' || _palette.containsKey(symbol);

/// Whole-pixel shift that centers the drawn pixels of [rows] in the 16x16
/// cell (the artwork itself may sit a little high or low in its grid).
@visibleForTesting
({int dx, int dy}) centeringShift(List<String> rows) {
  var minX = 16, maxX = -1, minY = 16, maxY = -1;
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] == '.') continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return (dx: 0, dy: 0);
  final width = maxX - minX + 1;
  final height = maxY - minY + 1;
  return (dx: (16 - width) ~/ 2 - minX, dy: (16 - height) ~/ 2 - minY);
}

/// One toolbar icon at [size] (16 = one logical pixel per icon pixel),
/// always centered in its box.
class RetroToolbarIcon extends StatelessWidget {
  const RetroToolbarIcon(this.type, {super.key, this.size = 16});

  final RetroToolbarIconType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rows = retroToolbarIconRows(type);
    final CustomPainter painter = rows != null
        ? _PixelIconPainter(rows)
        : type == RetroToolbarIconType.debug
        ? const _BugPainter()
        : _UTurnArrowPainter(mirrored: type == RetroToolbarIconType.redo);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: painter),
    );
  }
}

class _PixelIconPainter extends CustomPainter {
  _PixelIconPainter(this.rows) : shift = centeringShift(rows);

  final List<String> rows;
  final ({int dx, int dy}) shift;

  @override
  void paint(Canvas canvas, Size size) {
    final pixel = size.width / 16;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (var x = 0; x < row.length; x++) {
        final color = _palette[row[x]];
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            (x + shift.dx) * pixel,
            (y + shift.dy) * pixel,
            pixel,
            pixel,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PixelIconPainter oldDelegate) => oldDelegate.rows != rows;
}

/// The Undo arrow: a U-turn whose head points left; Redo is its mirror.
///
/// A smooth navy stroke with round ends, drawn on the same 16x16 grid as the
/// pixel icons and centered in it.
class _UTurnArrowPainter extends CustomPainter {
  const _UTurnArrowPainter({required this.mirrored});

  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 16;
    canvas.save();
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.scale(unit);

    final stroke = Paint()
      ..color = _palette['n']!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Spans x 2.5..13.5 and y 2.5..13.5: centered in the 16x16 cell.
    final body = Path()
      ..moveTo(6, 13)
      ..lineTo(9.5, 13)
      // Half circle around the right side, from the bottom up to the top.
      ..arcToPoint(
        const Offset(9.5, 6),
        radius: const Radius.circular(3.5),
        clockwise: false,
      )
      ..lineTo(3, 6);
    final head = Path()
      ..moveTo(6.2, 2.8)
      ..lineTo(3, 6)
      ..lineTo(6.2, 9.2);

    canvas.drawPath(body, stroke);
    canvas.drawPath(head, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UTurnArrowPainter oldDelegate) =>
      oldDelegate.mirrored != mirrored;
}

/// The Debug icon: a brown cockroach, drawn from the project owner's own SVG
/// (viewBox 25 x 35), path for path.
///
/// The tall artwork is scaled to [_bugHeight] icon pixels and centered on the
/// 16x16 cell, so it may use the button's padding above and below by a
/// pixel; that keeps the body readable at toolbar size.
class _BugPainter extends CustomPainter {
  const _BugPainter();

  static const double _viewWidth = 25;
  static const double _viewHeight = 35;
  static const double _bugHeight = 18;

  static const Color _leg = Color(0xFF5C2E14);
  static const Color _head = Color(0xFF3D1D0B);
  static const Color _outline = Color(0xFF4A230D);
  static const Color _shield = Color(0xFFA65A2A);
  static const Color _wings = Color(0xFF8C461E);
  static const Color _shine = Color(0xFFC97A42);

  static Paint _stroke(Color color, double width, {double opacity = 1}) =>
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  static Paint _fill(Color color, {double opacity = 1}) => Paint()
    ..color = color.withValues(alpha: opacity)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 16;
    final scale = _bugHeight * unit / _viewHeight;
    canvas.save();
    canvas.translate(
      (size.width - _viewWidth * scale) / 2,
      (size.height - _viewHeight * scale) / 2,
    );
    canvas.scale(scale);

    // Antennae.
    canvas.drawPath(
      Path()
        ..moveTo(11, 8)
        ..cubicTo(9.5, 4.5, 6.5, 2.5, 3.5, 2)
        ..moveTo(14, 8)
        ..cubicTo(15.5, 4.5, 18.5, 2.5, 21.5, 2),
      _stroke(_leg, 1),
    );

    // Front, middle and back legs.
    canvas.drawPath(
      Path()
        ..moveTo(9.5, 13)
        ..lineTo(5, 10.5)
        ..lineTo(3.5, 8.5)
        ..moveTo(15.5, 13)
        ..lineTo(20, 10.5)
        ..lineTo(21.5, 8.5)
        ..moveTo(8.5, 17.5)
        ..lineTo(4, 17.5)
        ..lineTo(2.5, 20)
        ..moveTo(16.5, 17.5)
        ..lineTo(21, 17.5)
        ..lineTo(22.5, 20)
        ..moveTo(9, 22.5)
        ..lineTo(5, 25.5)
        ..lineTo(4, 30.5)
        ..moveTo(16, 22.5)
        ..lineTo(20, 25.5)
        ..lineTo(21, 30.5),
      _stroke(_leg, 1.2),
    );

    // Cerci (the two tail points).
    canvas.drawPath(
      Path()
        ..moveTo(10.5, 29.5)
        ..lineTo(9.5, 32)
        ..moveTo(14.5, 29.5)
        ..lineTo(15.5, 32),
      _stroke(_leg, 1),
    );

    // Head.
    canvas.drawCircle(const Offset(12.5, 8.5), 2, _fill(_head));

    // Pronotum (the shield behind the head) with its two dark spots.
    final shield = Path()
      ..moveTo(8.5, 12.5)
      ..cubicTo(8.5, 10, 10.3, 8.8, 12.5, 8.8)
      ..cubicTo(14.7, 8.8, 16.5, 10, 16.5, 12.5)
      ..cubicTo(16.5, 13.5, 15, 14, 12.5, 14)
      ..cubicTo(10, 14, 8.5, 13.5, 8.5, 12.5)
      ..close();
    canvas.drawPath(shield, _fill(_shield));
    canvas.drawPath(shield, _stroke(_outline, 0.8));
    final spot = _fill(_outline, opacity: 0.7);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(11.2, 11.5), width: 2, height: 2.6),
      spot,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(13.8, 11.5), width: 2, height: 2.6),
      spot,
    );

    // Body and wings.
    final body = Path()
      ..moveTo(8.5, 13.2)
      ..cubicTo(7.8, 17.5, 8.2, 25.5, 10.8, 29.5)
      ..cubicTo(11.8, 30.8, 13.2, 30.8, 14.2, 29.5)
      ..cubicTo(16.8, 25.5, 17.2, 17.5, 16.5, 13.2)
      ..cubicTo(14.5, 13.8, 10.5, 13.8, 8.5, 13.2)
      ..close();
    canvas.drawPath(body, _fill(_wings));
    canvas.drawPath(body, _stroke(_outline, 0.9));

    // Wing seam and shine.
    canvas.drawPath(
      Path()
        ..moveTo(12.5, 13.6)
        ..lineTo(12.5, 29.8),
      _stroke(_outline, 0.8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(10.5, 15.5)
        ..cubicTo(10.2, 19, 10.3, 23.5, 11.2, 26.5),
      _stroke(_shine, 0.8, opacity: 0.8),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BugPainter oldDelegate) => false;
}
