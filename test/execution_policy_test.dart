import 'dart:async';

import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test Controller State & Effects
class TestState {
  final List<String> logs;
  final int count;

  const TestState({this.logs = const [], this.count = 0});

  TestState copyWith({List<String>? logs, int? count}) => TestState(
        logs: logs ?? this.logs,
        count: count ?? this.count,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          logs.length == other.logs.length;

  @override
  int get hashCode => Object.hash(count, logs.length);
}

class TestEffect {
  final String message;
  const TestEffect(this.message);
}

// Intents
class DropIntent extends CommandIntent {
  final String id;
  const DropIntent(this.id);
}

class RestartIntent extends CommandIntent {
  final String query;
  const RestartIntent(this.query);
}

class QueueIntent extends CommandIntent {
  final int item;
  const QueueIntent(this.item);
}

class ConcurrentIntent extends CommandIntent {
  final int id;
  const ConcurrentIntent(this.id);
}

// Commands
class DropCommand extends Command<DropIntent, TestState, TestEffect> {
  final Completer<void> blocker = Completer<void>();
  int executionsStarted = 0;
  int executionsCompleted = 0;

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Future<void> execute(CommandScope<TestState, TestEffect> scope, DropIntent intent) async {
    executionsStarted++;
    await blocker.future;
    executionsCompleted++;
    scope.updateState((s) => s.copyWith(logs: [...s.logs, 'drop_${intent.id}']));
  }
}

class RestartCommand extends Command<RestartIntent, TestState, TestEffect> {
  final List<Completer<void>> stepCompleters = [];
  final List<String> startedQueries = [];
  final List<String> completedQueries = [];

  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  @override
  Future<void> execute(CommandScope<TestState, TestEffect> scope, RestartIntent intent) async {
    startedQueries.add(intent.query);
    final completer = Completer<void>();
    stepCompleters.add(completer);

    await completer.future;

    // Check cancellation
    if (scope.isCancelled) return;

    completedQueries.add(intent.query);
    scope.updateState((s) => s.copyWith(logs: [...s.logs, 'restart_${intent.query}']));
  }
}

class QueueCommand extends Command<QueueIntent, TestState, TestEffect> {
  final List<int> processedOrder = [];

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<TestState, TestEffect> scope, QueueIntent intent) async {
    // Add small async yield to simulate I/O
    await Future<void>.delayed(const Duration(milliseconds: 10));
    processedOrder.add(intent.item);
    scope.updateState((s) => s.copyWith(count: s.count + 1));
  }
}

class ConcurrentCommand extends Command<ConcurrentIntent, TestState, TestEffect> {
  int concurrentRunning = 0;
  int maxConcurrentSeen = 0;

  @override
  ExecutionPolicy get policy => ExecutionPolicy.concurrent;

  @override
  Future<void> execute(CommandScope<TestState, TestEffect> scope, ConcurrentIntent intent) async {
    concurrentRunning++;
    if (concurrentRunning > maxConcurrentSeen) {
      maxConcurrentSeen = concurrentRunning;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    concurrentRunning--;
  }
}

class ConcurrencyTestController extends CommanderController<TestState, TestEffect> {
  final DropCommand dropCommand;
  final RestartCommand restartCommand;
  final QueueCommand queueCommand;
  final ConcurrentCommand concurrentCommand;

  ConcurrencyTestController({
    required this.dropCommand,
    required this.restartCommand,
    required this.queueCommand,
    required this.concurrentCommand,
  }) : super(const TestState()) {
    bind(dropCommand);
    bind(restartCommand);
    bind(queueCommand);
    bind(concurrentCommand);
  }
}

void main() {
  group('ExecutionPolicy Concurrency', () {
    late DropCommand dropCommand;
    late RestartCommand restartCommand;
    late QueueCommand queueCommand;
    late ConcurrentCommand concurrentCommand;
    late ConcurrencyTestController controller;

    setUp(() {
      dropCommand = DropCommand();
      restartCommand = RestartCommand();
      queueCommand = QueueCommand();
      concurrentCommand = ConcurrentCommand();
      controller = ConcurrencyTestController(
        dropCommand: dropCommand,
        restartCommand: restartCommand,
        queueCommand: queueCommand,
        concurrentCommand: concurrentCommand,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('DROP: ignores secondary intents while first is running', () async {
      // Dispatch first intent (will block on completer)
      final future1 = controller.dispatch(const DropIntent('1'));
      expect(dropCommand.executionsStarted, equals(1));

      // Dispatch second and third while first is active
      final future2 = controller.dispatch(const DropIntent('2'));
      final future3 = controller.dispatch(const DropIntent('3'));

      // Both should have been dropped immediately
      expect(dropCommand.executionsStarted, equals(1));

      // Unblock first
      dropCommand.blocker.complete();
      await Future.wait([future1, future2, future3]);

      expect(dropCommand.executionsCompleted, equals(1));
      expect(controller.state.logs, equals(['drop_1']));
    });

    test('RESTART: cancels active execution and starts new one', () async {
      // Dispatch query A
      unawaited(controller.dispatch(const RestartIntent('flutter')));
      expect(restartCommand.startedQueries, equals(['flutter']));

      // Dispatch query B immediately (restarts)
      unawaited(controller.dispatch(const RestartIntent('flutter_commander')));
      expect(restartCommand.startedQueries, equals(['flutter', 'flutter_commander']));

      // Complete the first query's step (it was cancelled so it should NOT record complete)
      restartCommand.stepCompleters[0].complete();
      // Complete second query's step
      restartCommand.stepCompleters[1].complete();

      // Allow microtasks to resolve
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(restartCommand.completedQueries, equals(['flutter_commander']));
      expect(controller.state.logs, equals(['restart_flutter_commander']));
    });

    test('QUEUE: executes sequentially in FIFO order', () async {
      final f1 = controller.dispatch(const QueueIntent(1));
      final f2 = controller.dispatch(const QueueIntent(2));
      final f3 = controller.dispatch(const QueueIntent(3));

      await Future.wait([f1, f2, f3]);

      expect(queueCommand.processedOrder, equals([1, 2, 3]));
      expect(controller.state.count, equals(3));
    });

    test('CONCURRENT: runs invocations simultaneously without blocking', () async {
      final f1 = controller.dispatch(const ConcurrentIntent(1));
      final f2 = controller.dispatch(const ConcurrentIntent(2));
      final f3 = controller.dispatch(const ConcurrentIntent(3));

      await Future.wait([f1, f2, f3]);

      expect(concurrentCommand.maxConcurrentSeen, greaterThanOrEqualTo(2));
    });
  });
}
