import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// State and Effects for tests
class ItemState {
  final Map<String, String> items;
  final List<String> logs;

  const ItemState({this.items = const {}, this.logs = const []});

  ItemState copyWith({Map<String, String>? items, List<String>? logs}) =>
      ItemState(items: items ?? this.items, logs: logs ?? this.logs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemState &&
          runtimeType == other.runtimeType &&
          mapEquals(items, other.items) &&
          listEquals(logs, other.logs);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(items.entries), Object.hashAll(logs));
}

class ItemEffect {
  final String message;
  const ItemEffect(this.message);
}

// Keyed Intents
class KeyedDropIntent extends CommandIntent {
  final String keyId;
  final String value;
  const KeyedDropIntent(this.keyId, this.value);
}

class KeyedRestartIntent extends CommandIntent {
  final String keyId;
  final String query;
  const KeyedRestartIntent(this.keyId, this.query);
}

class KeyedQueueIntent extends CommandIntent {
  final String keyId;
  final int step;
  const KeyedQueueIntent(this.keyId, this.step);
}

class ConcurrentTaskIntent extends CommandIntent {
  final String taskId;
  const ConcurrentTaskIntent(this.taskId);
}

class FailingIntent extends CommandIntent {
  final String message;
  const FailingIntent(this.message);
}

// Keyed Commands
class KeyedDropCommand extends Command<KeyedDropIntent, ItemState, ItemEffect> {
  final Map<String, Completer<void>> blockers = {};
  final Map<String, int> startedCount = {};
  final Map<String, int> completedCount = {};

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Object? concurrencyKey(KeyedDropIntent intent) => intent.keyId;

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    KeyedDropIntent intent,
  ) async {
    startedCount[intent.keyId] = (startedCount[intent.keyId] ?? 0) + 1;
    final blocker = blockers.putIfAbsent(intent.keyId, () => Completer<void>());
    await blocker.future;
    completedCount[intent.keyId] = (completedCount[intent.keyId] ?? 0) + 1;
    scope.updateState((s) =>
        s.copyWith(logs: [...s.logs, 'drop_${intent.keyId}_${intent.value}']));
  }
}

class KeyedRestartCommand
    extends Command<KeyedRestartIntent, ItemState, ItemEffect> {
  final Map<String, List<Completer<void>>> stepCompleters = {};
  final List<String> started = [];
  final List<String> completed = [];

  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  @override
  Object? concurrencyKey(KeyedRestartIntent intent) => intent.keyId;

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    KeyedRestartIntent intent,
  ) async {
    started.add('${intent.keyId}:${intent.query}');
    final completer = Completer<void>();
    stepCompleters.putIfAbsent(intent.keyId, () => []).add(completer);

    await completer.future;

    if (scope.isCancelled) return;

    completed.add('${intent.keyId}:${intent.query}');
    scope.updateState((s) => s.copyWith(
        logs: [...s.logs, 'restart_${intent.keyId}_${intent.query}']));
  }
}

class KeyedQueueCommand
    extends Command<KeyedQueueIntent, ItemState, ItemEffect> {
  final List<String> executionOrder = [];

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Object? concurrencyKey(KeyedQueueIntent intent) => intent.keyId;

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    KeyedQueueIntent intent,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    executionOrder.add('${intent.keyId}:${intent.step}');
    scope.updateState((s) =>
        s.copyWith(logs: [...s.logs, 'queue_${intent.keyId}_${intent.step}']));
  }
}

class LongRunningConcurrentCommand
    extends Command<ConcurrentTaskIntent, ItemState, ItemEffect> {
  final Completer<void> blocker = Completer<void>();
  bool wasCancelled = false;

  @override
  ExecutionPolicy get policy => ExecutionPolicy.concurrent;

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    ConcurrentTaskIntent intent,
  ) async {
    scope.cancellationToken.onCancelled(() {
      wasCancelled = true;
    });
    await blocker.future;
  }
}

class AlwaysFailsCommand extends Command<FailingIntent, ItemState, ItemEffect> {
  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    FailingIntent intent,
  ) async {
    throw Exception('Failed: ${intent.message}');
  }
}

// Controller with custom onError handling
class ErrorHandlingController
    extends CommanderController<ItemState, ItemEffect> {
  final List<String> caughtErrors = [];

  ErrorHandlingController() : super(const ItemState()) {
    bind(AlwaysFailsCommand());
  }

  @override
  void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
    caughtErrors.add(error.toString());
    emitSideEffect(ItemEffect('Handled: $error'));
  }
}

// Controller with default onError handling (rethrow)
class DefaultErrorController
    extends CommanderController<ItemState, ItemEffect> {
  DefaultErrorController() : super(const ItemState()) {
    bind(AlwaysFailsCommand());
  }
}

class DebounceIntent extends CommandIntent {
  final String query;
  const DebounceIntent(this.query);
}

class DebouncedSearchCommand
    extends Command<DebounceIntent, ItemState, ItemEffect> {
  final List<String> executedQueries = [];

  @override
  Duration get debounce => const Duration(milliseconds: 50);

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    DebounceIntent intent,
  ) async {
    executedQueries.add(intent.query);
    scope.updateState(
        (s) => s.copyWith(logs: [...s.logs, 'searched_${intent.query}']));
  }
}

class KeyedDebounceIntent extends CommandIntent {
  final String tab;
  final String query;
  const KeyedDebounceIntent(this.tab, this.query);
}

class KeyedDebouncedCommand
    extends Command<KeyedDebounceIntent, ItemState, ItemEffect> {
  final List<String> executed = [];

  @override
  Duration get debounce => const Duration(milliseconds: 50);

  @override
  Object? concurrencyKey(KeyedDebounceIntent intent) => intent.tab;

  @override
  Future<void> execute(
    CommandScope<ItemState, ItemEffect> scope,
    KeyedDebounceIntent intent,
  ) async {
    executed.add('${intent.tab}:${intent.query}');
  }
}

class TestObserver extends CommanderObserver {
  int createdCount = 0;
  int beforeExecuteCount = 0;
  int afterExecuteCount = 0;
  int stateChangeCount = 0;
  int effectCount = 0;
  int errorCount = 0;
  int disposedCount = 0;

  @override
  void onControllerCreated(dynamic controller) => createdCount++;

  @override
  void onBeforeExecute(dynamic controller, command, intent) =>
      beforeExecuteCount++;

  @override
  void onAfterExecute(dynamic controller, command, intent) =>
      afterExecuteCount++;

  @override
  void onStateChanged(dynamic controller, oldState, newState) =>
      stateChangeCount++;

  @override
  void onEffectEmitted(dynamic controller, effect) => effectCount++;

  @override
  void onError(dynamic controller, command, intent, error, stackTrace) =>
      errorCount++;

  @override
  void onControllerDisposed(dynamic controller) => disposedCount++;
}

void main() {
  group('Keyed Concurrency Policies', () {
    test('DROP: scopes dropping per key independently', () async {
      final dropCommand = KeyedDropCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(dropCommand);

      // 1. Dispatch key A first invocation
      final fA1 = controller.dispatch(const KeyedDropIntent('A', '1'));
      expect(dropCommand.startedCount['A'], equals(1));

      // 2. Dispatch key A second invocation -> should be dropped immediately
      final fA2 = controller.dispatch(const KeyedDropIntent('A', '2'));
      expect(dropCommand.startedCount['A'], equals(1));

      // 3. Dispatch key B invocation -> should NOT be dropped because key differs!
      final fB1 = controller.dispatch(const KeyedDropIntent('B', '1'));
      expect(dropCommand.startedCount['B'], equals(1));

      // 4. Complete blockers
      dropCommand.blockers['A']!.complete();
      dropCommand.blockers['B']!.complete();

      await Future.wait([fA1, fA2, fB1]);

      expect(dropCommand.completedCount['A'], equals(1));
      expect(dropCommand.completedCount['B'], equals(1));

      controller.dispose();
    });

    test('RESTART: cancels only the active execution with matching key',
        () async {
      final restartCommand = KeyedRestartCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(restartCommand);

      // Dispatch for key A and key B
      unawaited(controller.dispatch(const KeyedRestartIntent('A', 'query1')));
      unawaited(controller.dispatch(const KeyedRestartIntent('B', 'query1')));

      expect(restartCommand.started, containsAll(['A:query1', 'B:query1']));

      // Dispatch second query for key A (should restart key A only, NOT key B)
      unawaited(controller.dispatch(const KeyedRestartIntent('A', 'query2')));

      expect(restartCommand.started, contains('A:query2'));

      // Complete all step completers
      restartCommand.stepCompleters['A']![0].complete(); // cancelled query
      restartCommand.stepCompleters['A']![1].complete(); // active query
      restartCommand.stepCompleters['B']![0].complete(); // active query for B

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Key A completed only query2 (query1 was cancelled)
      // Key B completed query1 (was NOT cancelled by key A restart)
      expect(restartCommand.completed, containsAll(['A:query2', 'B:query1']));
      expect(restartCommand.completed, isNot(contains('A:query1')));

      controller.dispose();
    });

    test(
        'QUEUE: queues FIFO per key while processing different keys in parallel',
        () async {
      final queueCommand = KeyedQueueCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(queueCommand);

      final fA1 = controller.dispatch(const KeyedQueueIntent('A', 1));
      final fA2 = controller.dispatch(const KeyedQueueIntent('A', 2));
      final fB1 = controller.dispatch(const KeyedQueueIntent('B', 1));
      final fB2 = controller.dispatch(const KeyedQueueIntent('B', 2));

      await Future.wait([fA1, fA2, fB1, fB2]);

      // Verify FIFO within key A
      final aIndices = [
        queueCommand.executionOrder.indexOf('A:1'),
        queueCommand.executionOrder.indexOf('A:2'),
      ];
      expect(aIndices[0], lessThan(aIndices[1]));

      // Verify FIFO within key B
      final bIndices = [
        queueCommand.executionOrder.indexOf('B:1'),
        queueCommand.executionOrder.indexOf('B:2'),
      ];
      expect(bIndices[0], lessThan(bIndices[1]));

      controller.dispose();
    });

    test('Inline DSL supports concurrencyKey option', () async {
      final controller = CommanderControllerImpl(const ItemState());
      final started = <String>[];
      final completers = <String, Completer<void>>{};

      controller.registerInlineCustom<KeyedDropIntent>(
        (scope, intent) async {
          started.add('${intent.keyId}:${intent.value}');
          final completer =
              completers.putIfAbsent(intent.keyId, () => Completer<void>());
          await completer.future;
        },
        policy: ExecutionPolicy.drop,
        concurrencyKey: (intent) => intent.keyId,
      );

      final f1 = controller.dispatch(const KeyedDropIntent('K1', 'val1'));
      final f2 =
          controller.dispatch(const KeyedDropIntent('K1', 'val2')); // dropped
      final f3 = controller
          .dispatch(const KeyedDropIntent('K2', 'val1')); // distinct key, runs!

      expect(started, equals(['K1:val1', 'K2:val1']));

      completers['K1']!.complete();
      completers['K2']!.complete();
      await Future.wait([f1, f2, f3]);

      controller.dispose();
    });
  });

  group('Lifecycle & Dispose Token Cleanup', () {
    test(
        'ExecutionPolicy.concurrent commands are cancelled upon controller.dispose()',
        () async {
      final command = LongRunningConcurrentCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(command);

      unawaited(controller.dispatch(const ConcurrentTaskIntent('task-1')));

      expect(command.wasCancelled, isFalse);

      // Dispose controller while concurrent task is in flight
      controller.dispose();

      // Verify the token was properly cancelled during teardown
      expect(command.wasCancelled, isTrue);

      // Clean up blocker
      command.blocker.complete();
    });
  });

  group('CommanderController onError handling', () {
    test(
        'Overridden onError absorbs error and emits side effect without rethrowing',
        () async {
      final controller = ErrorHandlingController();
      final emittedEffects = <ItemEffect>[];
      final sub = controller.effects.listen(emittedEffects.add);

      // Should complete without throwing an unhandled exception
      await expectLater(
        controller.dispatch(const FailingIntent('Something broke')),
        completes,
      );

      // Yield for microtask delivery of broadcast stream
      await Future<void>.delayed(Duration.zero);

      expect(controller.caughtErrors,
          contains('Exception: Failed: Something broke'));
      expect(emittedEffects.length, equals(1));
      expect(emittedEffects.first.message,
          contains('Handled: Exception: Failed: Something broke'));

      await sub.cancel();
      controller.dispose();
    });

    test('Default onError rethrows original exception', () async {
      final controller = DefaultErrorController();

      await expectLater(
        () => controller.dispatch(const FailingIntent('Crash!')),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Crash!'),
        )),
      );

      controller.dispose();
    });
  });

  group('CommanderScope.select aspectKey', () {
    testWidgets('aspectKey provides stable aspect equality for context.select',
        (tester) async {
      final controller =
          CommanderControllerImpl(const ItemState(items: {'key': 'initial'}));

      int buildCount = 0;

      await tester.pumpWidget(
        CommanderScope<CommanderControllerImpl>.value(
          value: controller,
          child: Builder(
            builder: (context) {
              buildCount++;
              final val =
                  context.select<CommanderControllerImpl, ItemState, String>(
                (s) => s.items['key'] ?? '',
                aspectKey: #itemKey,
              );
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Text('Value: $val'),
              );
            },
          ),
        ),
      );

      expect(buildCount, equals(1));
      expect(find.text('Value: initial'), findsOneWidget);

      // Update unrelated part of state (logs)
      await controller.updatePublic((s) => s.copyWith(logs: ['unrelated']));
      await tester.pump();

      // Should NOT rebuild because aspectKey #itemKey did not change
      expect(buildCount, equals(1));

      // Now update the selected item
      await controller
          .updatePublic((s) => s.copyWith(items: {'key': 'changed'}));
      await tester.pump();

      // Should rebuild
      expect(buildCount, equals(2));
      expect(find.text('Value: changed'), findsOneWidget);

      controller.dispose();
    });
  });

  group('Command Debounce', () {
    test('debounces rapid invocations and only executes the final intent',
        () async {
      final searchCommand = DebouncedSearchCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(searchCommand);

      // Dispatch 3 intents rapidly within 50ms window
      unawaited(controller.dispatch(const DebounceIntent('f')));
      unawaited(controller.dispatch(const DebounceIntent('fl')));
      unawaited(controller.dispatch(const DebounceIntent('flutter')));

      // Immediately, none should have executed yet
      expect(searchCommand.executedQueries, isEmpty);

      // Wait for debounce duration to elapse
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // Only the last query executed!
      expect(searchCommand.executedQueries, equals(['flutter']));
      expect(controller.state.logs, equals(['searched_flutter']));

      controller.dispose();
    });

    test('Keyed debounce scopes timers per key independently', () async {
      final keyedCommand = KeyedDebouncedCommand();
      final controller = CommanderControllerImpl(const ItemState());
      controller.bindPublic(keyedCommand);

      // Tab A
      unawaited(
          controller.dispatch(const KeyedDebounceIntent('tabA', 'queryA1')));
      unawaited(
          controller.dispatch(const KeyedDebounceIntent('tabA', 'queryA2')));

      // Tab B
      unawaited(
          controller.dispatch(const KeyedDebounceIntent('tabB', 'queryB1')));
      unawaited(
          controller.dispatch(const KeyedDebounceIntent('tabB', 'queryB2')));

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(
          keyedCommand.executed, containsAll(['tabA:queryA2', 'tabB:queryB2']));
      expect(keyedCommand.executed, isNot(contains('tabA:queryA1')));
      expect(keyedCommand.executed, isNot(contains('tabB:queryB1')));

      controller.dispose();
    });
  });

  group('Global CommanderObserver', () {
    test(
        'observes lifecycle, executions, states, effects, errors, and disposal',
        () async {
      final observer = TestObserver();
      Commander.observer = observer;

      expect(observer.createdCount, equals(0));

      final controller = ErrorHandlingController();
      expect(observer.createdCount, equals(1));

      // Dispatch failing intent handled by ErrorHandlingController
      await controller.dispatch(const FailingIntent('Observer check'));
      await Future<void>.delayed(Duration.zero);

      expect(observer.beforeExecuteCount, equals(1));
      expect(observer.errorCount, equals(1));
      expect(observer.effectCount, equals(1));
      expect(observer.afterExecuteCount, equals(1));

      controller.dispose();
      expect(observer.disposedCount, equals(1));

      Commander.observer = null;
    });
  });
}

// Helper test controller to expose protected members for testing
class CommanderControllerImpl
    extends CommanderController<ItemState, ItemEffect> {
  CommanderControllerImpl(super.initialState);

  void bindPublic<I extends CommandIntent>(
      Command<I, ItemState, ItemEffect> command) {
    bind(command);
  }

  void registerInlineCustom<I extends CommandIntent>(
    FutureOr<void> Function(CommandScope<ItemState, ItemEffect> scope, I intent)
        handler, {
    ExecutionPolicy policy = ExecutionPolicy.concurrent,
    Object? Function(I intent)? concurrencyKey,
  }) {
    on<I>(handler, policy: policy, concurrencyKey: concurrencyKey);
  }

  Future<void> updatePublic(ItemState Function(ItemState current) reducer) {
    return _handleUpdateStatePublic(reducer);
  }

  Future<void> _handleUpdateStatePublic(
      ItemState Function(ItemState current) reducer) async {
    on<InternalUpdateIntent>((scope, intent) {
      scope.updateState(reducer);
    });
    await dispatch(const InternalUpdateIntent());
  }
}

class InternalUpdateIntent extends CommandIntent {
  const InternalUpdateIntent();
}
