# Contributing to Classic Code Editor

Thank you for your interest in contributing to Classic Code Editor! We welcome contributions from developers of all skill levels.

---

## 🚀 Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/classic-code-editor.git
   cd classic-code-editor
   ```
3. **Set up the development environment:**
   ```bash
   flutter pub get
   ```
4. **Run the tests** to ensure everything works:
   ```bash
   flutter test
   ```
5. **Create a new branch** for your feature or bug fix:
   ```bash
   git checkout -b feature-or-bugfix-name
   ```

---

## 🛠 Development Workflow

### Making Changes
- Keep your changes focused and atomic
- Write clear, descriptive commit messages
- Follow the existing code style (see `.analysis_options` if present)
- Add tests for new features or bug fixes when possible
- Update documentation as needed

### Code Style
This project follows the Dart style guide. We recommend:
- Using `dart format` before committing
- Running `flutter analyze` to check for issues
- Keeping lines to a reasonable length (typically 80-100 characters)

### Testing
- Ensure static analysis is clean: `flutter analyze` (must report
  `No issues found!`)
- Run the full test suite before submitting: `flutter test` (106 tests pass;
  1 opt-in integration test is skipped by default)
- Add unit tests for new functionality
- Ensure existing tests continue to pass
- The default suite runs **offline** — debuggers short-circuit real process
  spawns under `FLUTTER_TEST`. To exercise the real Dart VM attach/pause chain,
  run:
  ```bash
  BORLAND_REAL_VM_TEST=1 flutter test test/integration/dart_vm_pause_test.dart
  ```

---

## 📝 Pull Request Process

1. **Push your branch** to your fork:
   ```bash
   git push origin feature-or-bugfix-name
   ```
2. **Open a Pull Request** against the `main` branch of this repository
3. **Fill out the PR template** completely
4. **Respond to any review feedback** promptly
5. **Keep your branch up to date** with upstream changes if needed:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

### What makes a good PR?
- Addresses a single concern or feature
- Includes appropriate tests
- Has clear, descriptive title and description
- Follows the project's coding conventions
- Doesn't break existing functionality

---

## 🐛 Reporting Issues

Before submitting an issue, please:
1. Check if the issue has already been reported
2. Verify you're using the latest version
3. Provide a clear, reproducible example
4. Include relevant details:
   - Flutter/Dart version
   - Operating system
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots or logs if applicable

Use the issue template when creating new issues.

---

## 💡 Feature Requests

We welcome feature requests! When suggesting a feature:
- Explain the problem it solves
- Describe the proposed solution
- Consider alternative approaches
- Mention any potential drawbacks or trade-offs

---

## 🙏 Recognition

Contributors will be acknowledged in:
- The project's README
- Release notes
- GitHub contributors list

Thank you for helping make Classic Code Editor better!

---

*Last updated: 2026*