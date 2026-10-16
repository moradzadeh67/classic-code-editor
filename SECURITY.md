# Security Policy

Classic Code Editor **runs and debugs code on your machine**, so it deliberately has broad local
privileges. Security reports are welcome.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting
(<https://github.com/moradzadeh67/classic-code-editor/security/advisories> → *Report a vulnerability*),
or contact the author via <https://github.com/moradzadeh67>.

Include: affected version, macOS version, steps to reproduce, and the impact you see.

## Design facts worth knowing (not bugs)

- **The macOS App Sandbox is disabled** so the app can spawn `dart`, `python3`, `clang`, `lldb` and
  language servers. This is a deliberate trade-off for an IDE, documented in
  [docs/PRIVACY.md](docs/PRIVACY.md).
- **Code execution is the feature.** Running or debugging a file executes that program with your user's
  privileges.
- **Local sockets only**: the Dart VM Service connection is `localhost`-bound.
- The app is **unsigned/not notarized**, so Gatekeeper will warn on first launch.

## Please never

- Paste private source code or credentials into an issue, a log or a screenshot.
- Test against systems you do not own or have permission to use.
