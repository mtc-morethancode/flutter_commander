import 'package:flutter/foundation.dart';

import '../commander/commander.dart';
import 'undo_redo_intents.dart';

/// A mixin that adds undo/redo (time-travel) state management to any [Commander].
///
/// Eliminates the rigid inheritance diamond problem (such as ReplayBloc / HydratedReplayBloc)
/// by providing a composable mixin that can be combined freely with any other mixin
/// (e.g. `SavedStateMixin`).
///
/// Features:
/// - 100% idiomatic Dart mixin architecture (`with UndoRedoMixin<S, E>`).
/// - Direct imperative UI invocation (`commander.undo()`, `commander.redo()`).
/// - Declarative intent dispatch (`context.dispatch(const UndoIntent())`).
/// - Reactive availability flags ([canUndo], [canRedo]).
/// - Configurable history limit via [historyLimit] with automatic FIFO eviction.
/// - Selective state recording via [shouldRecordState] (e.g. skipping loading/transient states).
/// - Multi-step operations via [undoSteps] and [redoSteps].
/// - Lifecycle hooks: [onUndo], [onRedo], and [onHistoryCleared].
/// - Unmodifiable inspection stacks ([undoStack], [redoStack]).
///
/// Example:
/// ```dart
/// class CanvasCommander extends Commander<CanvasState, CanvasEffect>
///     with UndoRedoMixin<CanvasState, CanvasEffect> {
///   CanvasCommander() : super(const CanvasState.initial());
///
///   @override
///   int get historyLimit => 25; // keep last 25 operations
/// }
/// ```
mixin UndoRedoMixin<S, E> on Commander<S, E> {
  final List<S> _undoStack = <S>[];
  final List<S> _redoStack = <S>[];
  bool _isUndoingOrRedoing = false;
  S? _lastRecordedState;

  /// The maximum number of undo steps to retain in history.
  ///
  /// When the history size exceeds this limit, the oldest states are discarded (FIFO).
  /// If `null`, history size is unlimited.
  /// If `0`, state history recording is disabled.
  /// Defaults to `50`.
  int? get historyLimit => 50;

  /// Whether to automatically register command handlers for [UndoIntent],
  /// [RedoIntent], and [ClearHistoryIntent] during [onInit].
  ///
  /// Enabled by default (`true`).
  bool get autoRegisterUndoRedoIntents => true;

  /// Whether to clear [undoStack] and [redoStack] when state is restored externally
  /// (e.g. from disk storage or saved state restoration).
  ///
  /// Defaults to `true`.
  bool get clearHistoryOnExternalRestore => true;

  /// Whether there is at least one previous state in the undo history stack.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether there is at least one undone state in the redo history stack.
  bool get canRedo => _redoStack.isNotEmpty;

  /// The number of previous states available to undo.
  int get undoHistoryCount => _undoStack.length;

  /// The number of undone states available to redo.
  int get redoHistoryCount => _redoStack.length;

  /// An unmodifiable view of the undo history stack.
  ///
  /// The last element in this list is the most recent past state (i.e. the next state
  /// that [undo] will restore).
  List<S> get undoStack => List.unmodifiable(_undoStack);

  /// An unmodifiable view of the redo history stack.
  ///
  /// The last element in this list is the next undone state that [redo] will restore.
  List<S> get redoStack => List.unmodifiable(_redoStack);

  @override
  void onInit() {
    super.onInit();
    _lastRecordedState ??= state;
    if (autoRegisterUndoRedoIntents) {
      on<UndoIntent>((scope, intent) => undoSteps(intent.steps));
      on<RedoIntent>((scope, intent) => redoSteps(intent.steps));
      on<ClearHistoryIntent>((scope, intent) => clearHistory());
    }
  }

  /// Hook to determine whether a transition from [oldState] to [newState]
  /// should be recorded in the undo history stack.
  ///
  /// Can be overridden to exclude transient, loading, or non-user-driven state transitions.
  /// Defaults to `true`.
  @protected
  bool shouldRecordState(S oldState, S newState) => true;

  @override
  void onStateChanged(S oldState, S newState) {
    super.onStateChanged(oldState, newState);
    if (_isUndoingOrRedoing || isDisposed) return;

    final limit = historyLimit;
    if (limit != null && limit <= 0) {
      _undoStack.clear();
      _redoStack.clear();
      _lastRecordedState = newState;
      return;
    }

    final baseline = _lastRecordedState ?? oldState;
    if (shouldRecordState(baseline, newState)) {
      _undoStack.add(baseline);
      _redoStack.clear();
      _lastRecordedState = newState;
      _enforceHistoryLimit();
    }
  }

  @override
  void onStateRestored(S oldState, S newState) {
    super.onStateRestored(oldState, newState);
    if (!_isUndoingOrRedoing) {
      _lastRecordedState = newState;
      if (clearHistoryOnExternalRestore) {
        if (_undoStack.isNotEmpty || _redoStack.isNotEmpty) {
          _undoStack.clear();
          _redoStack.clear();
          onHistoryCleared();
        }
      }
    }
  }

  void _enforceHistoryLimit() {
    final limit = historyLimit;
    if (limit == null) return;
    if (limit <= 0) {
      _undoStack.clear();
      return;
    }
    if (_undoStack.length > limit) {
      final excess = _undoStack.length - limit;
      _undoStack.removeRange(0, excess);
    }
  }

  /// Undoes the last recorded state change.
  ///
  /// Reverts state to the previous state in history and pushes the current
  /// state to [redoStack].
  ///
  /// If [canUndo] is `false`, this method is a no-op.
  void undo() {
    if (!canUndo || isDisposed) return;

    final previousCurrent = state;
    final targetState = _undoStack.removeLast();
    _redoStack.add(previousCurrent);

    _isUndoingOrRedoing = true;
    try {
      restoreState(targetState);
      _lastRecordedState = targetState;
    } finally {
      _isUndoingOrRedoing = false;
    }

    onUndo(targetState, previousCurrent);
  }

  /// Redoes the last undone state change.
  ///
  /// Reverts state to the next state in [redoStack] and pushes the current
  /// state back to [undoStack].
  ///
  /// If [canRedo] is `false`, this method is a no-op.
  void redo() {
    if (!canRedo || isDisposed) return;

    final previousCurrent = state;
    final targetState = _redoStack.removeLast();
    _undoStack.add(previousCurrent);
    _enforceHistoryLimit();

    _isUndoingOrRedoing = true;
    try {
      restoreState(targetState);
      _lastRecordedState = targetState;
    } finally {
      _isUndoingOrRedoing = false;
    }

    onRedo(targetState, previousCurrent);
  }

  /// Performs [steps] undo operations in succession.
  ///
  /// Stops early if [canUndo] becomes `false`.
  /// If [steps] is `<= 0`, does nothing.
  void undoSteps(int steps) {
    if (steps <= 0) return;
    for (var i = 0; i < steps && canUndo; i++) {
      undo();
    }
  }

  /// Performs [steps] redo operations in succession.
  ///
  /// Stops early if [canRedo] becomes `false`.
  /// If [steps] is `<= 0`, does nothing.
  void redoSteps(int steps) {
    if (steps <= 0) return;
    for (var i = 0; i < steps && canRedo; i++) {
      redo();
    }
  }

  /// Clears both [undoStack] and [redoStack] while keeping the current state.
  ///
  /// Notifies listeners so any UI elements bound to [canUndo] or [canRedo]
  /// can update their enabled/disabled visual states.
  void clearHistory() {
    if (_undoStack.isEmpty && _redoStack.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    _lastRecordedState = state;
    onHistoryCleared();
    notifyListeners();
  }

  /// Clears only the [redoStack] while preserving [undoStack].
  void clearRedo() {
    if (_redoStack.isEmpty) return;
    _redoStack.clear();
    notifyListeners();
  }

  /// Clears only the [undoStack] while preserving [redoStack].
  void clearUndo() {
    if (_undoStack.isEmpty) return;
    _undoStack.clear();
    notifyListeners();
  }

  /// Lifecycle callback invoked when an [undo] operation completes.
  ///
  /// [revertedState] is the new current state, and [previousState] is the state
  /// that was active immediately before [undo] was called.
  @protected
  @mustCallSuper
  void onUndo(S revertedState, S previousState) {}

  /// Lifecycle callback invoked when a [redo] operation completes.
  ///
  /// [restoredState] is the new current state, and [previousState] is the state
  /// that was active immediately before [redo] was called.
  @protected
  @mustCallSuper
  void onRedo(S restoredState, S previousState) {}

  /// Lifecycle callback invoked when history is cleared.
  @protected
  @mustCallSuper
  void onHistoryCleared() {}

  @override
  void dispose() {
    _undoStack.clear();
    _redoStack.clear();
    super.dispose();
  }
}
