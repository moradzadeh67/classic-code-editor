class LanguageConfig {
  final String extension;
  final String displayName;
  final String runCommand;
  final String? formatCommand;
  final String highlightLanguage;

  const LanguageConfig({
    required this.extension,
    required this.displayName,
    required this.runCommand,
    this.formatCommand,
    required this.highlightLanguage,
  });

  static const List<LanguageConfig> supportedLanguages = [
    LanguageConfig(
      extension: '.dart',
      displayName: 'Dart',
      runCommand: 'dart run',
      formatCommand: 'dart format',
      highlightLanguage: 'dart',
    ),
    LanguageConfig(
      extension: '.c',
      displayName: 'C',
      runCommand: 'clang',
      formatCommand: 'clang-format',
      highlightLanguage: 'c',
    ),
    LanguageConfig(
      extension: '.cpp',
      displayName: 'C++',
      runCommand: 'clang++',
      formatCommand: 'clang-format',
      highlightLanguage: 'cpp',
    ),
    LanguageConfig(
      extension: '.py',
      displayName: 'Python',
      runCommand: 'python3',
      formatCommand: 'black',
      highlightLanguage: 'python',
    ),
  ];

  static LanguageConfig fromExtension(String? filePath) {
    if (filePath == null) return supportedLanguages[0];
    final ext = filePath.toLowerCase().split('.').last;
    return supportedLanguages.firstWhere(
      (lang) => lang.extension == '.$ext',
      orElse: () => supportedLanguages[0],
    );
  }
}
