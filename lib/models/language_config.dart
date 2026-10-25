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
