import '../core/intent.dart';
import 'undo_redo_mixin.dart';

/// Command intent to undo one or more previous state transitions in a commander
/// equipped with [UndoRedoMixin].
class UndoIntent extends CommandIntent {
  /// Creates an [UndoIntent].
  ///
  /// [steps] specifies the number of states to undo (defaults to 1).
  const UndoIntent([this.steps = 1])
      : assert(steps > 0, 'steps must be greater than 0');

  /// The number of steps to undo.
  final int steps;

  @override
  String toString() => 'UndoIntent(steps: $steps)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UndoIntent &&
          runtimeType == other.runtimeType &&
          steps == other.steps;

  @override
  int get hashCode => steps.hashCode;
}

/// Command intent to redo one or more previously undone state transitions in a commander
/// equipped with [UndoRedoMixin].
class RedoIntent extends CommandIntent {
  /// Creates a [RedoIntent].
  ///
  /// [steps] specifies the number of states to redo (defaults to 1).
  const RedoIntent([this.steps = 1])
      : assert(steps > 0, 'steps must be greater than 0');

  /// The number of steps to redo.
  final int steps;

  @override
  String toString() => 'RedoIntent(steps: $steps)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RedoIntent &&
          runtimeType == other.runtimeType &&
          steps == other.steps;

  @override
  int get hashCode => steps.hashCode;
}

/// Command intent to clear the undo and redo history stacks in a commander
/// equipped with [UndoRedoMixin].
class ClearHistoryIntent extends CommandIntent {
  /// Creates a [ClearHistoryIntent].
  const ClearHistoryIntent();

  @override
  String toString() => 'ClearHistoryIntent()';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClearHistoryIntent && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
