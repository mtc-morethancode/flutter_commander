# Composable Time-Travel & Undo / Redo (`UndoRedoMixin`) ⏪⏩

Built on Dart 3's idiomatic mixin architecture, **`UndoRedoMixin<S, E>`** gives any `Commander` full history navigation and time-travel capabilities. Because it is a mixin rather than a rigid base class, it composes seamlessly with persistence (`SavedStateMixin`) and custom mixins with zero type conflicts.

---

## 1. Basic Mixin Usage

```dart
class CanvasCommander extends Commander<CanvasState, CanvasEffect>
    with UndoRedoMixin<CanvasState, CanvasEffect> {
  CanvasCommander() : super(const CanvasState.initial()) {
    on<DrawShapeIntent>((scope, intent) {
      scope.updateState((s) => s.addShape(intent.shape));
    });
  }

  // Optional: customize the history limit (defaults to 50, FIFO eviction)
  @override
  int get historyLimit => 25;

  // Optional: filter out transient / loading states from history
  @override
  bool shouldRecordHistory(CanvasState previousState, CanvasState newState) {
    return !newState.isDragging;
  }
}
```

---

## 2. Direct UI Invocation & Reactive Button States

Because `Commander` implements `Listenable`, button states dynamically update when `canUndo` and `canRedo` change:

```dart
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final commander = context.commander<CanvasCommander>();

    return ListenableBuilder(
      listenable: commander,
      builder: (context, _) {
        return Row(
          children: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: commander.canUndo ? commander.undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: commander.canRedo ? commander.redo : null,
              tooltip: 'Redo',
            ),
          ],
        );
      },
    );
  }
}
```

---

## 3. Intent-Driven Dispatch

`UndoRedoMixin` automatically registers handlers for `UndoIntent`, `RedoIntent`, and `ClearHistoryIntent`. Deeply nested widgets or keyboard shortcuts (e.g. `Ctrl+Z` / `Cmd+Z`) can trigger undo/redo declaratively without a direct reference to the commander:

```dart
// Undo 1 step:
context.dispatch<CanvasCommander>(const UndoIntent());

// Undo 3 steps at once:
context.dispatch<CanvasCommander>(const UndoIntent(3));

// Redo 1 step:
context.dispatch<CanvasCommander>(const RedoIntent());

// Clear history:
context.dispatch<CanvasCommander>(const ClearHistoryIntent());
```
