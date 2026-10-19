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

  /// Language for [filePath]; falls back to Dart for unknown/untitled buffers
  /// (the fallback has no `commentPrefix` semantics of its own — callers that
  /// need a comment decide from the real file path).
  static LanguageConfig fromExtension(String? filePath) {
    if (filePath == null) return supportedLanguages[0];
    final ext = filePath.toLowerCase().split('.').last;
    return supportedLanguages.firstWhere(
      (lang) => lang.extension == '.$ext',
      orElse: () => supportedLanguages[0],
    );
  }

  /// Config for an unknown language: no line-comment support.
  static const LanguageConfig unknown = LanguageConfig(
    extension: '',
    displayName: 'Unknown',
    runCommand: '',
    highlightLanguage: 'plaintext',
  );
}
