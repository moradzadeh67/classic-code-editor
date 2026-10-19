# Classic Code Editor — Privacy

Classic Code Editor is a **local, offline-first desktop IDE**. It has no accounts, no telemetry and no
backend.

## What the app touches on your machine

| Action | What happens | Where it goes |
|---|---|---|
| Opening / saving files | You pick files with the standard macOS picker; the content stays in memory and on your disk | Your disk only |
| Running code (`F5`) | Starts a **local** `dart` / `python3` / `clang` process | Your machine only |
| Debugging | Attaches to a **local** Dart VM Service (WebSocket on localhost), a local Python `sys.settrace` tracer, or `clang` + `lldb` | Your machine only |
| Language server (LSP) | A local language server is spawned and spoken to over stdio | Your machine only |
| Terminal panel | Runs shell commands you type, in the working directory you opened | Your machine only |
| Theme preference | Written to a small JSON file (`.retro_theme_config.json`, in the app's working directory) | Your disk only |
| Editor font size | `editor_settings.json` in the app's Application Support folder (`path_provider`) | Your disk only, never leaves the machine |
| Session + recent files | `session.json` in the same Application Support folder: the **paths** of the open files, the active file and up to 10 recent paths. Buffer contents are **not** stored | Your disk only, never leaves the machine |

## What is **not** collected

- No analytics, no crash reporting, no usage statistics.
- No account, no sign-in, no cloud sync.
- Your code, file names, terminal output and diagnostics are never uploaded anywhere.
- There are no API keys, tokens or secrets in this repository, and the app needs none.

> ⚠️ **Two honest caveats**
> 1. **Code you run is code you run.** The integrated runner and debugger execute programs with your
>    user's privileges — that is their purpose. Only run code you trust.
> 2. **macOS App Sandbox is disabled** (`com.apple.security.app-sandbox = false`) because an IDE must be
>    able to spawn compilers, debuggers and shells. The app therefore has the same file access as any
>    normal unsigned app you launch.

## Uninstalling / cleaning up

Delete `Classic Code Editor.app`; optionally remove the `.retro_theme_config.json` file from the folder
you ran it in. Nothing else is stored outside your own project files.

## Reporting a problem

Open an issue on [GitHub](https://github.com/moradzadeh67/classic-code-editor/issues). Please do not paste
private source code, paths with personal names, or credentials into an issue or a screenshot.
