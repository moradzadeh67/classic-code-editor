# Third-party notices

Classic Code Editor is MIT licensed (see [LICENSE](LICENSE)). It bundles the
font files below; each keeps its own license. Nothing here is modified: the
files are redistributed byte-for-byte as published by their authors.

---

## Recursive Mono Casual (static faces)

Bundled in [`assets/fonts/`](assets/fonts/):

- `RecursiveMonoCslSt-Regular.ttf`
- `RecursiveMonoCslSt-Bold.ttf`
- `RecursiveMonoCslSt-Italic.ttf`
- `RecursiveMonoCslSt-BdItalic.ttf`

Upstream project: <https://github.com/arrowtype/recursive>
Declared in `pubspec.yaml` under the family alias `RecursiveMonoCasual`.

Copyright 2020 The Recursive Project Authors
(<https://github.com/arrowtype/recursive>)

This Font Software is licensed under the SIL Open Font License, Version 1.1.

The complete, verbatim license text is shipped unmodified next to the fonts as
[`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) — that file, not this summary, is
the authoritative copy.

---

## Menlo

Menlo (the editor's default) is a font bundled with macOS. This project does
**not** redistribute it: it is referenced by its system family name and is only
ever used from the host installation, so its licensing stays with Apple and
macOS.

Monaco was offered in an earlier build but has been removed from the editor; no
Monaco font file is bundled or shipped by this project.

---

## Other components

Flutter, `flutter_code_editor`, `highlight`, the Dart Language Server, the Dart
VM Service and LLDB are used under their respective licenses; see
[README > Credits & Attribution](README.md#-credits--attribution).
