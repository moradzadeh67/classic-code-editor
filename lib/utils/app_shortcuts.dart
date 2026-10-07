import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 1. Define Intents (What the user wants to do)
class SaveIntent extends Intent {
  const SaveIntent();
}

class NewFileIntent extends Intent {
  const NewFileIntent();
}

class RunIntent extends Intent {
  const RunIntent();
}

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

// 2. Define the Shortcut Map (Which keys trigger which Intent)
final Map<ShortcutActivator, Intent> appShortcuts = {
  // Save: Ctrl+S (Windows/Linux) or Cmd+S (Mac)
  const SingleActivator(LogicalKeyboardKey.keyS, control: true):
      const SaveIntent(),
  const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
      const SaveIntent(),

  // New File: Ctrl+N or Cmd+N
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewFileIntent(),
  const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
      const NewFileIntent(),

  // Run: F5
  const SingleActivator(LogicalKeyboardKey.f5): const RunIntent(),

  // Undo: Ctrl+Z or Cmd+Z
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
      const UndoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
      const UndoIntent(),

  // Redo: Ctrl+Y or Cmd+Y
  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
      const RedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyY, meta: true):
      const RedoIntent(),
};
