import 'tab_file.dart';

/// One resolver's answer: the language to use **and**, when the buffer clearly
/// belongs to another one, the language it looks like.
///
/// The extension stays authoritative — a mismatch never changes
/// [language]; it only lets Run/Debug refuse to compile the wrong thing while
/// the logo, the colors and the runner keep agreeing on one answer.
class LanguageResolution {
  const LanguageResolution({required this.language, this.mismatch});

  /// The language to use (extension, explicit selection or sniffed content).
  final LanguageConfig language;

  /// The language the content unambiguously looks like when it is *not*
  /// [language]'s; null when there is nothing to report.
  final LanguageConfig? mismatch;

  bool get hasMismatch => mismatch != null;

  /// The one Console line Run/Debug prints instead of starting a process.
  String mismatchMessage({String? fileName}) {
    final name = fileName ?? 'This buffer';
    final looksLike = mismatch!.displayName;
    final wanted = mismatch!.extension;
    return '$name looks like $looksLike, not ${language.displayName}. '
        'Use Save As with a $wanted extension, or choose $looksLike in the '
        'language dropdown.';
  }
}

class LanguageConfig {
  final String extension;
  final String displayName;
  final String runCommand;
  final String? formatCommand;
  final String highlightLanguage;

  /// Line-comment prefix used by Toggle Comment (`//` or `#`).
  ///
  /// `null` means "this language has no line comment", which makes Toggle
  /// Comment a no-op instead of guessing a prefix.
  final String? commentPrefix;

  const LanguageConfig({
    required this.extension,
    required this.displayName,
    required this.runCommand,
    this.formatCommand,
    required this.highlightLanguage,
    this.commentPrefix,
  });

  static const List<LanguageConfig> supportedLanguages = [
    LanguageConfig(
      extension: '.dart',
      displayName: 'Dart',
      runCommand: 'dart run',
      formatCommand: 'dart format',
      highlightLanguage: 'dart',
      commentPrefix: '//',
    ),
    LanguageConfig(
      extension: '.c',
      displayName: 'C',
      runCommand: 'clang',
      formatCommand: 'clang-format',
      highlightLanguage: 'c',
      commentPrefix: '//',
    ),
    LanguageConfig(
      extension: '.cpp',
      displayName: 'C++',
      runCommand: 'clang++',
      formatCommand: 'clang-format',
      highlightLanguage: 'cpp',
      commentPrefix: '//',
    ),
    LanguageConfig(
      extension: '.py',
      displayName: 'Python',
      runCommand: 'python3',
      formatCommand: 'black',
      highlightLanguage: 'python',
      commentPrefix: '#',
    ),
    LanguageConfig(
      extension: '.s',
      displayName: 'ARM64 Assembly',
      runCommand: 'clang -g -arch arm64',
      formatCommand: null,
      highlightLanguage: 'armasm',
      commentPrefix: '//',
    ),
  ];

  /// Alias extensions that share one config (clang builds all of these as C++).
  static const Map<String, String> _extensionAliases = {
    'cp': '.cpp',
    'cc': '.cpp',
    'cxx': '.cpp',
    'c++': '.cpp',
    'hpp': '.cpp',
    'hxx': '.cpp',
    'hh': '.cpp',
  };

  /// Language named by the file extension, or `null` when the path has no
  /// extension we support (e.g. an untitled buffer called `Untitled`).
  static LanguageConfig? _extensionMatch(String? filePath) {
    if (filePath == null) return null;
    final dot = filePath.lastIndexOf('.');
    if (dot < 0 || dot == filePath.length - 1) return null;
    final ext = filePath.substring(dot + 1).toLowerCase();
    final normalized = _extensionAliases[ext] ?? '.$ext';
    for (final lang in supportedLanguages) {
      if (lang.extension == normalized) return lang;
    }
    return null;
  }

  /// The config named by the path's extension, or `null` when the path has no
  /// recognised one.
  static LanguageConfig? fromExtensionOrNull(String? filePath) =>
      _extensionMatch(filePath);

  /// Language for [filePath]; falls back to Dart for unknown/untitled buffers
  /// (the fallback has no `commentPrefix` semantics of its own — callers that
  /// need a comment decide from the real file path).
  static LanguageConfig fromExtension(String? filePath) =>
      _extensionMatch(filePath) ?? supportedLanguages[0];

  /// Language for an editor buffer: the extension when it names a supported
  /// language, otherwise the content is sniffed so unsaved tabs (`Untitled`)
  /// still get their real grammar instead of the Dart fallback.
  static LanguageConfig fromPathOrContent(String? filePath, String content) =>
      _extensionMatch(filePath) ??
      _sniffContent(content) ??
      supportedLanguages[0];

  /// The single resolver behind the runner, the highlighter and the logo.
  ///
  /// * an explicit toolbar selection wins and never reports a mismatch;
  /// * a path with no recognised extension keeps today's behaviour (sniffing);
  /// * otherwise the extension wins and, when the content unambiguously belongs
  ///   to another language, [LanguageResolution.mismatch] names it.
  static LanguageResolution resolve(
    String? filePath,
    String content, {
    String preferredLanguage = 'Auto',
  }) {
    if (preferredLanguage != 'Auto') {
      return LanguageResolution(
        language: _explicitLanguage(filePath, preferredLanguage),
      );
    }

    final ext = _extensionMatch(filePath);
    if (ext == null) {
      return LanguageResolution(language: fromPathOrContent(filePath, content));
    }
    return LanguageResolution(
      language: ext,
      mismatch: _clearMismatch(content, ext),
    );
  }

  /// The effective language of [tab]: its own explicit selection when set,
  /// otherwise the extension/content resolver.
  ///
  /// The runner, the Debug button, the highlighter and the language logo all
  /// read this, so they can never disagree about one tab.
  static LanguageResolution resolveTab(TabFile? tab) => resolve(
    tab?.filePath,
    tab?.content ?? '',
    preferredLanguage: tab?.languageOverride ?? 'Auto',
  );

  static LanguageConfig _explicitLanguage(
    String? filePath,
    String preferredLanguage,
  ) {
    switch (preferredLanguage) {
      case 'Dart':
        return fromExtension('test.dart');
      case 'Python':
        return fromExtension('test.py');
      case 'C':
        return fromExtension('test.c');
      case 'C++':
        return fromExtension('test.cpp');
      case 'ARM64 Assembly':
      case 'Assembly':
      case 'asm':
        return fromExtension('test.s');
      default:
        return fromExtension(filePath);
    }
  }

  /// The language whose signal is unmistakable in [content], or null.
  ///
  /// Deliberately narrow: one clear signal only, and never for content that is
  /// plausible for the current extension. "When in doubt, no mismatch."
  static LanguageConfig? _clearMismatch(
    String content,
    LanguageConfig current,
  ) {
    // Assembly is the one extension where a C preprocessor line is normal,
    // so it gets its own rule instead of the generic C signal.
    if (current.highlightLanguage == 'armasm') {
      return _assemblyMismatch(content);
    }

    final signals = <LanguageConfig>[
      if (_looksLikeDart(content)) fromExtension('test.dart'),
      if (_looksLikePython(content)) fromExtension('test.py'),
      if (_looksLikeC(content)) fromExtension('test.c'),
    ];
    if (signals.isEmpty) return null;

    // Two different clear signals at once is not a clear signal.
    final distinct = signals.map((s) => s.extension).toSet();
    if (distinct.length > 1) return null;

    final detected = signals.first;
    if (detected.extension == current.extension) return null;
    // C and C++ are one toolchain family: a `.c` buffer with C++ markers, or a
    // `.cpp` buffer with plain C, is not a wrong-language buffer.
    if (_isCppFamily(detected) && _isCppFamily(current)) return null;
    return detected;
  }

  /// A `.s`/`.S` buffer holding a C or C++ program.
  ///
  /// A bare `#include` is legitimate in preprocessed assembly, so it never
  /// reports a mismatch on its own. It does when a program entry point or C++
  /// marker sits next to it — a compiler error, not assembly.
  static LanguageConfig? _assemblyMismatch(String content) {
    if (content.contains('#include <')) {
      final hasCppMarker =
          content.contains('std::') ||
          content.contains('<iostream>') ||
          content.contains('<vector>') ||
          content.contains('<string>') ||
          RegExp(
            r'^[ \t]*using\s+namespace\b',
            multiLine: true,
          ).hasMatch(content);
      if (hasCppMarker) return fromExtension('test.cpp');

      final hasEntryPoint = RegExp(
        r'^[ \t]*(int|void)\s+main\s*\(',
        multiLine: true,
      ).hasMatch(content);
      if (hasEntryPoint) return fromExtension('test.c');
    }

    // A Python or Dart program is still a mismatch, exactly as before.
    if (_looksLikeDart(content)) return fromExtension('test.dart');
    if (_looksLikePython(content)) return fromExtension('test.py');
    return null;
  }

  static bool _isCppFamily(LanguageConfig config) =>
      config.extension == '.c' || config.extension == '.cpp';

  static bool _looksLikeDart(String content) {
    if (RegExp(
      r"""import\s*['"]dart:""",
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(r"""import\s*['"]package:""").hasMatch(content)) return true;
    return RegExp(r'^\s*void\s+main\s*\(', multiLine: true).hasMatch(content);
  }

  static bool _looksLikePython(String content) {
    final lines = content.split('\n').take(20).toList();
    final hasSignal =
        RegExp(r'^def\s+', multiLine: true).hasMatch(content) ||
        RegExp(r'^import\s+(sys|os)\b', multiLine: true).hasMatch(content) ||
        RegExp(r'^from\s+\S+\s+import\b', multiLine: true).hasMatch(content);
    if (!hasSignal) return false;
    // Braces and semicolons at line ends mean the buffer is brace-language code.
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.endsWith('{') || trimmed.endsWith(';')) return false;
    }
    return true;
  }

  static bool _looksLikeC(String content) =>
      content.contains('#include <') && content.contains('int main(');

  /// Content-based detection shared by the highlighter and the runner.
  static LanguageConfig? _sniffContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    // C++ *only* markers are checked before the plain `#include` rule: almost
    // every C file starts with an `#include`, so testing `#include` first made
    // every untitled C buffer resolve to C++.
    if (trimmed.contains('std::') ||
        trimmed.contains('cout') ||
        trimmed.contains('cin') ||
        trimmed.contains('iostream') ||
        trimmed.contains('#include <string>') ||
        trimmed.contains('#include <vector>') ||
        trimmed.contains('namespace ') ||
        trimmed.contains('template<') ||
        trimmed.contains('template <')) {
      return fromExtension('test.cpp');
    }
    if (trimmed.contains('#include <stdio.h>') ||
        trimmed.contains('#include <stdlib.h>') ||
        trimmed.contains('#include <string.h>') ||
        trimmed.contains('printf(') ||
        trimmed.contains('scanf(') ||
        trimmed.contains('malloc(')) {
      return fromExtension('test.c');
    }
    if (trimmed.contains('#include')) return fromExtension('test.cpp');

    if (trimmed.contains('def ') ||
        trimmed.contains('import sys') ||
        trimmed.contains('import os') ||
        trimmed.contains('lambda ') ||
        ((trimmed.contains('print(') || trimmed.contains('elif ')) &&
            !trimmed.contains(';') &&
            !trimmed.contains('{'))) {
      return fromExtension('test.py');
    }
    if (trimmed.contains('void main(') ||
        trimmed.contains("import 'dart:") ||
        trimmed.contains('import "dart:')) {
      return fromExtension('test.dart');
    }
    if (trimmed.contains('.globl') ||
        trimmed.contains('.section') ||
        trimmed.contains('_main:')) {
      return fromExtension('test.s');
    }
    return null;
  }

  /// Config for an unknown language: no line-comment support.
  static const LanguageConfig unknown = LanguageConfig(
    extension: '',
    displayName: 'Unknown',
    runCommand: '',
    highlightLanguage: 'plaintext',
  );
}
