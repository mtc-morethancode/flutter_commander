import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test Models & Intents
// ---------------------------------------------------------------------------

@immutable
class CounterState {
  const CounterState(this.count, {this.isLoading = false});
  final int count;
  final bool isLoading;

  CounterState copyWith({int? count, bool? isLoading}) {
    return CounterState(
      count ?? this.count,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          isLoading == other.isLoading;

  @override
  int get hashCode => Object.hash(count, isLoading);

  @override
  String toString() => 'CounterState(count: $count, isLoading: $isLoading)';
}

class IncrementIntent extends CommandIntent {
  const IncrementIntent([this.amount = 1]);
  final int amount;
}

class SetLoadingIntent extends CommandIntent {
  const SetLoadingIntent(this.isLoading);
  final bool isLoading;
}

// ---------------------------------------------------------------------------
// Test Commanders
// ---------------------------------------------------------------------------

class BasicUndoRedoCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  BasicUndoRedoCommander([int initialCount = 0])
      : super(CounterState(initialCount)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
    on<SetLoadingIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(isLoading: intent.isLoading));
    });
  }
}

class LimitedUndoRedoCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  LimitedUndoRedoCommander({required this.limit}) : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
  }

  final int? limit;

  @override
  int? get historyLimit => limit;
}

class FilteredUndoRedoCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  FilteredUndoRedoCommander() : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
    on<SetLoadingIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(isLoading: intent.isLoading));
    });
  }

  @override
  bool shouldRecordState(CounterState oldState, CounterState newState) {
    // Only record when count actually changes, ignoring pure loading transitions
    return oldState.count != newState.count;
  }
}

class HookTrackingCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  HookTrackingCommander() : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
  }

  final List<String> hookCalls = [];

  @override
  void onUndo(CounterState revertedState, CounterState previousState) {
    super.onUndo(revertedState, previousState);
    hookCalls.add('undo:${revertedState.count}<-${previousState.count}');
  }

  @override
  void onRedo(CounterState restoredState, CounterState previousState) {
    super.onRedo(restoredState, previousState);
    hookCalls.add('redo:${restoredState.count}<-${previousState.count}');
  }

  @override
  void onHistoryCleared() {
    super.onHistoryCleared();
    hookCalls.add('cleared');
  }
}

class NoAutoIntentCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  NoAutoIntentCommander() : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
  }

  @override
  bool get autoRegisterUndoRedoIntents => false;
}

class DynamicLimitCommander extends Commander<CounterState, void>
    with UndoRedoMixin<CounterState, void> {
  DynamicLimitCommander() : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
  }

  int? currentLimit = 10;

  @override
  int? get historyLimit => currentLimit;
}

// Custom mixin to test multiple mixins composition without diamond problem
mixin ExtraFeatureMixin<S, E> on Commander<S, E> {
  bool extraFeatureInitialized = false;

  @override
  void onInit() {
    super.onInit();
    extraFeatureInitialized = true;
  }

  void externalRestore(S newState) {
    restoreState(newState);
  }
}

class MultiMixinCommander extends Commander<CounterState, void>
    with ExtraFeatureMixin<CounterState, void>, UndoRedoMixin<CounterState, void> {
  MultiMixinCommander() : super(const CounterState(0)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + intent.amount));
    });
  }
}

class TestObserver extends CommanderObserver {
  final List<String> transitions = [];

  @override
  void onStateChanged(
    Commander<dynamic, dynamic>? commander,
    dynamic oldState,
    dynamic newState,
  ) {
    transitions.add('${(oldState as CounterState).count}->${(newState as CounterState).count}');
  }
}

class TestInterceptor extends CommandInterceptor {
  final List<String> transitions = [];

  @override
  void onStateChanged(dynamic oldState, dynamic newState) {
    transitions.add('${(oldState as CounterState).count}->${(newState as CounterState).count}');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UndoRedoMixin Core Functionality', () {
    test('initial state has empty stacks and cannot undo or redo', () {
      final commander = BasicUndoRedoCommander();
      expect(commander.canUndo, isFalse);
      expect(commander.canRedo, isFalse);
      expect(commander.undoHistoryCount, 0);
      expect(commander.redoHistoryCount, 0);
      expect(commander.undoStack, isEmpty);
      expect(commander.redoStack, isEmpty);
      expect(commander.state.count, 0);
    });

    test('updates state and populates undo stack while keeping redo empty', () async {
      final commander = BasicUndoRedoCommander();

      await commander.dispatch(const IncrementIntent(1));
      expect(commander.state.count, 1);
      expect(commander.canUndo, isTrue);
      expect(commander.canRedo, isFalse);
      expect(commander.undoHistoryCount, 1);
      expect(commander.undoStack, equals([const CounterState(0)]));

      await commander.dispatch(const IncrementIntent(2));
      expect(commander.state.count, 3);
      expect(commander.undoHistoryCount, 2);
      expect(
        commander.undoStack,
        equals([const CounterState(0), const CounterState(1)]),
      );
    });

    test('undo() reverts state and enables redo', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(1));
      expect(commander.state.count, 2);

      // Undo once: 2 -> 1
      commander.undo();
      expect(commander.state.count, 1);
      expect(commander.canUndo, isTrue);
      expect(commander.canRedo, isTrue);
      expect(commander.undoStack, equals([const CounterState(0)]));
      expect(commander.redoStack, equals([const CounterState(2)]));

      // Undo again: 1 -> 0
      commander.undo();
      expect(commander.state.count, 0);
      expect(commander.canUndo, isFalse);
      expect(commander.canRedo, isTrue);
      expect(commander.undoStack, isEmpty);
      expect(commander.redoStack, equals([const CounterState(2), const CounterState(1)]));
    });

    test('redo() restores reverted state and restores undo stack', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(1));
      commander.undo();
      commander.undo();
      expect(commander.state.count, 0);

      // Redo once: 0 -> 1
      commander.redo();
      expect(commander.state.count, 1);
      expect(commander.canUndo, isTrue);
      expect(commander.canRedo, isTrue);
      expect(commander.undoStack, equals([const CounterState(0)]));
      expect(commander.redoStack, equals([const CounterState(2)]));

      // Redo again: 1 -> 2
      commander.redo();
      expect(commander.state.count, 2);
      expect(commander.canUndo, isTrue);
      expect(commander.canRedo, isFalse);
      expect(
        commander.undoStack,
        equals([const CounterState(0), const CounterState(1)]),
      );
      expect(commander.redoStack, isEmpty);
    });

    test('branching history clears redo stack upon new state update', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1)); // 0 -> 1
      await commander.dispatch(const IncrementIntent(1)); // 1 -> 2
      commander.undo(); // 2 -> 1 (redo has 2)
      expect(commander.canRedo, isTrue);

      // Perform a new action from state 1
      await commander.dispatch(const IncrementIntent(10)); // 1 -> 11
      expect(commander.state.count, 11);
      expect(commander.canRedo, isFalse);
      expect(commander.redoStack, isEmpty);
      expect(
        commander.undoStack,
        equals([const CounterState(0), const CounterState(1)]),
      );
    });

    test('undo() and redo() are safe no-ops when cannot undo or redo', () {
      final commander = BasicUndoRedoCommander();
      expect(() => commander.undo(), returnsNormally);
      expect(() => commander.redo(), returnsNormally);
      expect(commander.state.count, 0);
    });

    test('undoSteps() and redoSteps() execute multiple transitions', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1)); // 1
      await commander.dispatch(const IncrementIntent(1)); // 2
      await commander.dispatch(const IncrementIntent(1)); // 3
      await commander.dispatch(const IncrementIntent(1)); // 4
      expect(commander.state.count, 4);

      commander.undoSteps(2);
      expect(commander.state.count, 2);

      commander.redoSteps(2);
      expect(commander.state.count, 4);

      // Safe bounds checking: asking for 100 steps stops safely when stack exhausted
      commander.undoSteps(100);
      expect(commander.state.count, 0);
      expect(commander.canUndo, isFalse);

      commander.redoSteps(100);
      expect(commander.state.count, 4);
      expect(commander.canRedo, isFalse);

      // Negative or zero steps does nothing
      commander.undoSteps(0);
      commander.undoSteps(-5);
      expect(commander.state.count, 4);
      commander.redoSteps(0);
      commander.redoSteps(-3);
      expect(commander.state.count, 4);
    });
  });

  group('History Limit & Memory Safety', () {
    test('enforces history limit by discarding oldest entries FIFO', () async {
      final commander = LimitedUndoRedoCommander(limit: 3);

      for (var i = 1; i <= 6; i++) {
        await commander.dispatch(const IncrementIntent(1));
      }
      expect(commander.state.count, 6);
      expect(commander.undoHistoryCount, 3);
      expect(
        commander.undoStack,
        equals([
          const CounterState(3),
          const CounterState(4),
          const CounterState(5),
        ]),
      );

      commander.undo();
      expect(commander.state.count, 5);
      commander.undo();
      expect(commander.state.count, 4);
      commander.undo();
      expect(commander.state.count, 3);
      expect(commander.canUndo, isFalse); // Oldest 0, 1, 2 were evicted
    });

    test('historyLimit 0 disables history recording', () async {
      final commander = LimitedUndoRedoCommander(limit: 0);
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(1));
      expect(commander.state.count, 2);
      expect(commander.canUndo, isFalse);
      expect(commander.undoStack, isEmpty);
    });

    test('null historyLimit permits unlimited history', () async {
      final commander = LimitedUndoRedoCommander(limit: null);
      for (var i = 0; i < 75; i++) {
        await commander.dispatch(const IncrementIntent(1));
      }
      expect(commander.state.count, 75);
      expect(commander.undoHistoryCount, 75);
    });

    test('dynamically setting historyLimit to 0 clears undo stack on redo', () async {
      final commander = DynamicLimitCommander();
      await commander.dispatch(const IncrementIntent(1));
      commander.undo();
      expect(commander.canRedo, isTrue);

      commander.currentLimit = 0;
      commander.redo();
      expect(commander.state.count, 1);
      expect(commander.canUndo, isFalse);
      expect(commander.undoStack, isEmpty);
    });
  });

  group('Selective State Recording (shouldRecordState)', () {
    test('skips intermediate states that do not satisfy shouldRecordState', () async {
      final commander = FilteredUndoRedoCommander();

      // Step 1: count 0 -> 1
      await commander.dispatch(const IncrementIntent(1));
      expect(commander.state, const CounterState(1));

      // Step 2: setLoading = true (count remains 1)
      await commander.dispatch(const SetLoadingIntent(true));
      expect(commander.state, const CounterState(1, isLoading: true));
      // Undo stack should only contain state 0, NOT the intermediate loading state
      expect(commander.undoStack, equals([const CounterState(0)]));

      // Step 3: count 1 -> 2 and setLoading = false
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const SetLoadingIntent(false));
      expect(commander.state, const CounterState(2, isLoading: false));

      // Undoing reverts from 2 to 1 (cleanly bypassing the loading state!)
      commander.undo();
      expect(commander.state.count, 1);
      commander.undo();
      expect(commander.state.count, 0);
    });
  });

  group('Clearing History & Partial Resets', () {
    test('clearHistory() resets both stacks and notifies listeners', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(1));
      commander.undo();
      expect(commander.canUndo, isTrue);
      expect(commander.canRedo, isTrue);

      var notified = false;
      commander.addListener(() => notified = true);

      commander.clearHistory();
      expect(commander.canUndo, isFalse);
      expect(commander.canRedo, isFalse);
      expect(commander.undoStack, isEmpty);
      expect(commander.redoStack, isEmpty);
      expect(notified, isTrue);

      // Calling again when already empty does not notify redundantly
      notified = false;
      commander.clearHistory();
      expect(notified, isFalse);
    });

    test('clearRedo() and clearUndo() reset respective stacks', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(1));
      commander.undo(); // 1 in undo, 1 in redo

      commander.clearRedo();
      expect(commander.canRedo, isFalse);
      expect(commander.canUndo, isTrue);

      commander.clearUndo();
      expect(commander.canUndo, isFalse);
    });
  });

  group('Lifecycle Hooks', () {
    test('onUndo, onRedo, and onHistoryCleared callbacks are invoked', () async {
      final commander = HookTrackingCommander();
      await commander.dispatch(const IncrementIntent(1)); // 0 -> 1
      await commander.dispatch(const IncrementIntent(2)); // 1 -> 3

      commander.undo();
      expect(commander.hookCalls, contains('undo:1<-3'));

      commander.redo();
      expect(commander.hookCalls, contains('redo:3<-1'));

      commander.clearHistory();
      expect(commander.hookCalls, contains('cleared'));
    });
  });

  group('Observer & Interceptor Integration', () {
    test('notifies CommanderObserver and CommandInterceptor on undo and redo', () async {
      final observer = TestObserver();
      Commander.observer = observer;

      final interceptor = TestInterceptor();
      final commander = BasicUndoRedoCommander();
      commander.addInterceptor(interceptor);

      await commander.dispatch(const IncrementIntent(1)); // 0 -> 1
      await commander.dispatch(const IncrementIntent(1)); // 1 -> 2
      expect(observer.transitions, equals(['0->1', '1->2']));
      expect(interceptor.transitions, equals(['0->1', '1->2']));

      commander.undo(); // 2 -> 1
      expect(observer.transitions, equals(['0->1', '1->2', '2->1']));
      expect(interceptor.transitions, equals(['0->1', '1->2', '2->1']));

      commander.redo(); // 1 -> 2
      expect(observer.transitions, equals(['0->1', '1->2', '2->1', '1->2']));
      expect(interceptor.transitions, equals(['0->1', '1->2', '2->1', '1->2']));

      Commander.observer = null;
    });
  });

  group('Intent-Driven Undo/Redo Dispatching', () {
    test('handles UndoIntent, RedoIntent, and ClearHistoryIntent automatically', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      await commander.dispatch(const IncrementIntent(2));
      expect(commander.state.count, 3);

      await commander.dispatch(const UndoIntent());
      expect(commander.state.count, 1);

      await commander.dispatch(const RedoIntent());
      expect(commander.state.count, 3);

      await commander.dispatch(const UndoIntent(2));
      expect(commander.state.count, 0);

      await commander.dispatch(const RedoIntent(2));
      expect(commander.state.count, 3);

      await commander.dispatch(const ClearHistoryIntent());
      expect(commander.canUndo, isFalse);
      expect(commander.canRedo, isFalse);
    });

    test('autoRegisterUndoRedoIntents = false does not register intent handlers', () async {
      final commander = NoAutoIntentCommander();
      await commander.dispatch(const IncrementIntent(1));

      // Dispatching unregistered intent throws UnregisteredIntentException
      expect(
        () => commander.dispatch(const UndoIntent()),
        throwsA(isA<UnregisteredIntentException>()),
      );
    });

    test('intent value equality, hashCode, assertions, and toString', () {
      const undo1 = UndoIntent();
      const undo2 = UndoIntent(2);
      expect(undo1, equals(const UndoIntent(1)));
      expect(undo1 == undo1, isTrue);
      expect(undo2, isNot(equals(undo1)));
      expect(undo1 == Object(), isFalse);
      expect(undo1.hashCode, equals(1.hashCode));
      expect(undo2.hashCode, equals(2.hashCode));
      expect(() => UndoIntent(0), throwsA(isA<AssertionError>()));

      const redo1 = RedoIntent();
      const redo2 = RedoIntent(2);
      expect(redo1, equals(const RedoIntent(1)));
      expect(redo1 == redo1, isTrue);
      expect(redo2, isNot(equals(redo1)));
      expect(redo1 == Object(), isFalse);
      expect(redo1.hashCode, equals(1.hashCode));
      expect(redo2.hashCode, equals(2.hashCode));
      expect(() => RedoIntent(0), throwsA(isA<AssertionError>()));

      // ignore: prefer_const_constructors
      final clear1 = ClearHistoryIntent();
      const clear2 = ClearHistoryIntent();
      expect(clear1, equals(clear2));
      expect(clear1 == clear1, isTrue);
      expect(clear1 == Object(), isFalse);
      expect(clear1.hashCode, equals(clear2.hashCode));

      expect(undo2.toString(), 'UndoIntent(steps: 2)');
      expect(const RedoIntent(3).toString(), 'RedoIntent(steps: 3)');
      expect(clear1.toString(), 'ClearHistoryIntent()');
    });
  });

  group('Multiple Mixin Composition & External Restoration', () {
    test('composes freely with other mixins without diamond inheritance', () async {
      final commander = MultiMixinCommander();
      expect(commander.extraFeatureInitialized, isTrue);

      await commander.dispatch(const IncrementIntent(5));
      expect(commander.state.count, 5);
      expect(commander.canUndo, isTrue);

      // External restore (e.g. from SavedStateMixin) resets history
      commander.externalRestore(const CounterState(100));
      expect(commander.state.count, 100);
      expect(commander.canUndo, isFalse);
      expect(commander.canRedo, isFalse);

      // Subsequent changes start fresh from restored state
      await commander.dispatch(const IncrementIntent(10));
      expect(commander.state.count, 110);
      expect(commander.canUndo, isTrue);
      commander.undo();
      expect(commander.state.count, 100);
    });
  });

  group('Disposal & Safety Guards', () {
    test('calling undo or redo after dispose does not throw or mutate', () async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(1));
      commander.dispose();

      expect(commander.undoStack, isEmpty);
      expect(commander.redoStack, isEmpty);
      expect(() => commander.undo(), returnsNormally);
      expect(() => commander.redo(), returnsNormally);
      expect(() => commander.clearHistory(), returnsNormally);
    });
  });

  group('Flutter Widgets Integration (UI & Context Dispatch)', () {
    testWidgets('CommanderBuilder reactively updates canUndo and canRedo buttons', (tester) async {
      final commander = BasicUndoRedoCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<BasicUndoRedoCommander>.value(
            value: commander,
            child: Scaffold(
              body: CommanderBuilder<BasicUndoRedoCommander, CounterState, CounterState>(
                builder: (context, state) {
                  final cmd = context.commander<BasicUndoRedoCommander>();
                  return Column(
                    children: [
                      Text('Count: ${state.count}'),
                      ElevatedButton(
                        key: const Key('btn-undo'),
                        onPressed: cmd.canUndo ? cmd.undo : null,
                        child: const Text('Undo'),
                      ),
                      ElevatedButton(
                        key: const Key('btn-redo'),
                        onPressed: cmd.canRedo ? cmd.redo : null,
                        child: const Text('Redo'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Initially Count: 0, Undo disabled, Redo disabled
      expect(find.text('Count: 0'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-undo'))).enabled, isFalse);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-redo'))).enabled, isFalse);

      // Update state
      await commander.dispatch(const IncrementIntent(5));
      await tester.pump();
      expect(find.text('Count: 5'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-undo'))).enabled, isTrue);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-redo'))).enabled, isFalse);

      // Tap Undo button
      await tester.tap(find.byKey(const Key('btn-undo')));
      await tester.pump();
      expect(find.text('Count: 0'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-undo'))).enabled, isFalse);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-redo'))).enabled, isTrue);

      // Tap Redo button
      await tester.tap(find.byKey(const Key('btn-redo')));
      await tester.pump();
      expect(find.text('Count: 5'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-undo'))).enabled, isTrue);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn-redo'))).enabled, isFalse);
    });

    testWidgets('context.dispatch dispatches UndoIntent from deeply nested widgets', (tester) async {
      final commander = BasicUndoRedoCommander();
      await commander.dispatch(const IncrementIntent(42));

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<BasicUndoRedoCommander>.value(
            value: commander,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('btn-dispatch-undo'),
                    onPressed: () {
                      context.dispatch<BasicUndoRedoCommander>(const UndoIntent());
                    },
                    child: const Text('Dispatch Undo'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(commander.state.count, 42);
      await tester.tap(find.byKey(const Key('btn-dispatch-undo')));
      await tester.pump();
      expect(commander.state.count, 0);
    });
  });
}
