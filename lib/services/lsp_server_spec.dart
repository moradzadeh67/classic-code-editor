import '../models/language_config.dart';

/// Describes one language server this IDE knows how to launch.
///
/// A spec is pure data: how to find the binary, what arguments it needs, which
/// `LanguageConfig.highlightLanguage` ids it understands, and what to tell the
/// user when it is missing. Selecting a server happens per *language*, never per
/// file, through [candidatesForLanguage].
class LspServerSpec {
  const LspServerSpec({
    required this.id,
    required this.displayName,
    required this.languageIds,
    required this.executableNames,
    required this.arguments,
    required this.installHint,
    this.usesCompileFlags = false,
    this.initializationOptions = const <String, dynamic>{},
  });

  /// Stable id used as the manager's cache key (`dart`, `clangd`, …).
  final String id;

  /// Name shown in the status bar and in fallback messages.
  final String displayName;

  /// `LanguageConfig.highlightLanguage` values this server understands.
  final Set<String> languageIds;

  /// Absolute paths tried first, then bare names looked up on `PATH`.
  final List<String> executableNames;

  /// Arguments passed to the executable. clangd gets **none**: Apple's build
  /// rejects `--stdio` and speaks stdio by default.
  final List<String> arguments;

  /// One-line install hint printed to the Console when the server is missing.
  final String installHint;

  /// clangd only sees the macOS SDK through a `compile_flags.txt`.
  final bool usesCompileFlags;

  /// Extra `initializationOptions` for servers that need them.
  final Map<String, dynamic> initializationOptions;

  /// Whether this server can serve [languageId].
  bool supports(String languageId) => languageIds.contains(languageId);

  /// Client identity sent in the LSP `initialize` handshake.
  static const String clientId = 'ClassicCodeEditor';

  /// Client version sent in the LSP `initialize` handshake.
  static const String clientVersion = '1.5.0';

  /// The official Dart language server, shipped with the Dart SDK.
  static const LspServerSpec dart = LspServerSpec(
    id: 'dart',
    displayName: 'Dart',
    languageIds: <String>{'dart'},
    executableNames: <String>['dart'],
    arguments: <String>[
      'language-server',
      '--client-id=$clientId',
      '--client-version=$clientVersion',
    ],
    installHint: 'install the Dart SDK (https://dart.dev/get-dart) and make '
        'sure `dart` is on PATH',
  );

  /// clangd from the Xcode Command Line Tools (`/usr/bin/clangd`) or Homebrew.
  static const LspServerSpec clangd = LspServerSpec(
    id: 'clangd',
    displayName: 'clangd',
    languageIds: <String>{'c', 'cpp'},
    executableNames: <String>[
      '/usr/bin/clangd',
      '/opt/homebrew/opt/llvm/bin/clangd',
      '/usr/local/opt/llvm/bin/clangd',
      'clangd',
    ],
    arguments: <String>[],
    usesCompileFlags: true,
    installHint: 'run `xcode-select --install` (ships /usr/bin/clangd) or '
        '`brew install llvm`',
  );

  /// pyright's language server (preferred over pylsp: much better inference).
  static const LspServerSpec pyright = LspServerSpec(
    id: 'pyright',
    displayName: 'pyright',
    languageIds: <String>{'python'},
    executableNames: <String>[
      '/opt/homebrew/bin/pyright-langserver',
      '/usr/local/bin/pyright-langserver',
      'pyright-langserver',
    ],
    arguments: <String>['--stdio'],
    installHint: 'run `npm install -g pyright`',
  );

  /// python-lsp-server, the fallback when pyright is absent.
  static const LspServerSpec pylsp = LspServerSpec(
    id: 'pylsp',
    displayName: 'pylsp',
    languageIds: <String>{'python'},
    executableNames: <String>['pylsp'],
    arguments: <String>[],
    installHint: 'run `python3 -m pip install python-lsp-server`',
  );

  /// Sentinel for "no language server applies to this file" (Assembly, unknown).
  static const LspServerSpec off = LspServerSpec(
    id: 'off',
    displayName: 'Off',
    languageIds: <String>{},
    executableNames: <String>[],
    arguments: <String>[],
    installHint: '',
  );

  /// Servers that can serve [languageId], most preferred first.
  ///
  /// Returns an empty list for languages with no server (ARM64 Assembly) — the
  /// caller then leaves the built-in analyzer in charge.
  static List<LspServerSpec> candidatesForLanguage(String languageId) {
    switch (languageId) {
      case 'dart':
        return const <LspServerSpec>[dart];
      case 'c':
      case 'cpp':
        return const <LspServerSpec>[clangd];
      case 'python':
        return const <LspServerSpec>[pyright, pylsp];
      default:
        return const <LspServerSpec>[];
    }
  }

  /// [candidatesForLanguage] for a file path (unknown paths fall back to Dart,
  /// matching `LanguageConfig.fromExtension`).
  static List<LspServerSpec> candidatesForFile(String? filePath) {
    return candidatesForLanguage(
      LanguageConfig.fromExtension(filePath).highlightLanguage,
    );
  }
}
