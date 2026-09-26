import 'dart:async';

import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test Models
class HardeningState {
  final int count;
  final String text;

  const HardeningState({required this.count, required this.text});

  factory HardeningState.initial() =>
      const HardeningState(count: 0, text: 'init');

  HardeningState copyWith({int? count, String? text}) => HardeningState(
        count: count ?? this.count,
        text: text ?? this.text,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HardeningState && count == other.count && text == other.text;

  @override
  int get hashCode => Object.hash(count, text);

  @override
  String toString() => 'HardeningState($count, $text)';
}

class HardeningEffect {
  final String message;
  const HardeningEffect(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HardeningEffect && message == other.message;

  @override
  int get hashCode => message.hashCode;
}

class SyncDropFailIntent extends CommandIntent {
  const SyncDropFailIntent();
}

class SyncRestartFailIntent extends CommandIntent {
  const SyncRestartFailIntent();
}

class SyncDropSuccessIntent extends CommandIntent {
  const SyncDropSuccessIntent();
}

class SyncRestartSuccessIntent extends CommandIntent {
  const SyncRestartSuccessIntent();
}

class SyncDropCommand
    extends Command<SyncDropFailIntent, HardeningState, HardeningEffect> {
  bool shouldFail = true;

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  void execute(CommandScope<HardeningState, HardeningEffect> scope,
      SyncDropFailIntent intent) {
    if (shouldFail) {
      throw StateError('Sync drop failure');
    }
    scope.updateState((s) => s.copyWith(count: s.count + 1));
  }
}

class SyncRestartCommand
    extends Command<SyncRestartFailIntent, HardeningState, HardeningEffect> {
  bool shouldFail = true;

  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  @override
  void execute(CommandScope<HardeningState, HardeningEffect> scope,
      SyncRestartFailIntent intent) {
    if (shouldFail) {
      throw StateError('Sync restart failure');
    }
    scope.updateState((s) => s.copyWith(count: s.count + 1));
  }
}

class HardeningCommander extends Commander<HardeningState, HardeningEffect> {
  final dropCmd = SyncDropCommand();
  final restartCmd = SyncRestartCommand();
  final List<Object> absorbedErrors = [];

  HardeningCommander() : super(HardeningState.initial()) {
    bind(dropCmd);
    bind(restartCmd);
  }

  void testEmitSideEffect(HardeningEffect effect) => emitSideEffect(effect);

  @override
  void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
    absorbedErrors.add(error);
    // Don't rethrow to test absorbed error path
  }
}

void main() {
  group('Production Hardening: Concurrency Error Cleanup & Token Leaks', () {
    test(
        '_runDrop cleans up active token when synchronous command throws an error',
        () async {
      final commander = HardeningCommander();

      // 1. Dispatch synchronous command that throws
      commander.dropCmd.shouldFail = true;
      await commander.dispatch(const SyncDropFailIntent());

      expect(commander.absorbedErrors.length, equals(1));
      expect(commander.absorbedErrors.first, isA<StateError>());

      // 2. Dispatch subsequent command on the same drop key.
      // If active tokens were leaked, this invocation would be mistakenly dropped!
      commander.dropCmd.shouldFail = false;
      await commander.dispatch(const SyncDropFailIntent());

      expect(commander.state.count, equals(1));
      commander.dispose();
    });

    test(
        '_runRestart cleans up active token when synchronous command throws an error',
        () async {
      final commander = HardeningCommander();

      // 1. Dispatch synchronous command that throws
      commander.restartCmd.shouldFail = true;
      await commander.dispatch(const SyncRestartFailIntent());

      expect(commander.absorbedErrors.length, equals(1));
      expect(commander.absorbedErrors.first, isA<StateError>());

      // 2. Dispatch subsequent command on the same restart key.
      commander.restartCmd.shouldFail = false;
      await commander.dispatch(const SyncRestartFailIntent());

      expect(commander.state.count, equals(1));
      commander.dispose();
    });
  });

  group('Production Hardening: TestCommandScope Parity with Commander', () {
    test(
        'updateState drops identical state reference (prevents in-place mutation false positives)',
        () {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      // Returning identical state reference must NOT record
      testScope.updateState((s) => s);
      expect(testScope.states, isEmpty);
      expect(testScope.state, equals(HardeningState.initial()));

      // Returning equal state instance must NOT record
      testScope
          .updateState((s) => HardeningState(count: s.count, text: s.text));
      expect(testScope.states, isEmpty);

      // Returning fresh mutated state MUST record
      testScope.updateState((s) => s.copyWith(count: 42));
      expect(testScope.states.length, equals(1));
      expect(testScope.state.count, equals(42));
    });

    test('initialState returns the exact seeded instance', () {
      final initial = HardeningState.initial();
      final testScope =
          TestCommandScope<HardeningState, HardeningEffect>(initial);

      expect(identical(testScope.initialState, initial), isTrue);
    });

    test('sleep delays and supports cancellation abort', () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      // Normal sleep completion
      await testScope.sleep(const Duration(milliseconds: 10));

      // Cancelled sleep abort
      final sleepFuture = testScope.sleep(const Duration(seconds: 5));
      testScope.cancel('User aborted sleep');

      expect(
        () => sleepFuture,
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('User aborted sleep'),
        )),
      );
    });

    test('attach registers cancellation callback that executes on cancel', () {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      var cleanedUp = false;
      final detach = testScope.attach(() {
        cleanedUp = true;
      });

      expect(cleanedUp, isFalse);
      testScope.cancel();
      expect(cleanedUp, isTrue);

      // Detaching after cancellation is a safe no-op
      detach();
    });

    test('throwIfCancelled behaves according to cancellation state', () {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      expect(() => testScope.throwIfCancelled(), returnsNormally);

      testScope.cancel('Token halted');
      expect(
        () => testScope.throwIfCancelled(),
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Token halted'),
        )),
      );
    });

    test('runCancellable executes synchronous and asynchronous tasks',
        () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      // Synchronous
      final syncResult = testScope.runCancellable(() => 123);
      expect(await syncResult, equals(123));

      // Asynchronous
      final asyncResult = testScope.runCancellable(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 'done';
      });
      expect(await asyncResult, equals('done'));

      // Cancelled
      testScope.cancel();
      expect(
        () => testScope.runCancellable(() => 456),
        throwsA(isA<CancellationException>()),
      );
    });

    test('race and withCancellation race futures against token', () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      final result = await testScope.withCancellation(Future.value('fast'));
      expect(result, equals('fast'));

      final slow = Completer<String>();
      final raceFuture = testScope.race(slow.future);
      testScope.cancel('Race cancelled');

      expect(
        () => raceFuture,
        throwsA(isA<CancellationException>()),
      );
    });

    test('listen receives stream events and detaches on onDone', () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      final controller = StreamController<int>();
      final received = <int>[];
      var doneCalled = false;

      testScope.listen<int>(
        controller.stream,
        onData: received.add,
        onDone: () => doneCalled = true,
      );

      controller.add(1);
      controller.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, equals([1, 2]));

      await controller.close();
      await Future<void>.delayed(Duration.zero);
      expect(doneCalled, isTrue);
    });

    test('forEach completes on stream close and supports errors', () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      final stream = Stream<int>.fromIterable([10, 20, 30]);
      final items = <int>[];

      await testScope.forEach<int>(
        stream,
        onData: items.add,
      );

      expect(items, equals([10, 20, 30]));
    });
  });

  group('Production Hardening: CancellationToken Edge Cases', () {
    test('CancellationToken.timeout triggers automatically', () async {
      final token = CancellationToken.timeout(
        const Duration(milliseconds: 20),
        message: 'Timed out!',
      );

      expect(token.isCancelled, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(token.isCancelled, isTrue);
      expect(token.cancellationReason, equals('Timed out!'));
    });

    test(
        'CancellationToken.combine cancels when child of already cancelled token',
        () {
      final token1 = CancellationToken()..cancel('Already cancelled');
      final token2 = CancellationToken();

      final combined = CancellationToken.combine([token1, token2]);
      expect(combined.isCancelled, isTrue);
      expect(combined.cancellationReason, equals('Already cancelled'));
    });

    test(
        'CancellationToken.combine cancels when any parent cancels and detaches',
        () {
      final token1 = CancellationToken();
      final token2 = CancellationToken();

      final combined = CancellationToken.combine([token1, token2]);
      expect(combined.isCancelled, isFalse);

      token2.cancel('Token 2 died');
      expect(combined.isCancelled, isTrue);
      expect(combined.cancellationReason, equals('Token 2 died'));
    });

    test('sleep throws immediately if token is already cancelled', () {
      final token = CancellationToken()..cancel('Pre-cancelled');
      expect(
        () => token.sleep(const Duration(seconds: 1)),
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Pre-cancelled'),
        )),
      );
    });

    test('forEach returns immediately if token is already cancelled', () async {
      final token = CancellationToken()..cancel();
      var executed = false;
      await token.forEach<int>(
        Stream.value(1),
        onData: (_) => executed = true,
      );
      expect(executed, isFalse);
    });

    test('forEach propagates stream error when onError handler is omitted',
        () async {
      final token = CancellationToken();
      final controller = StreamController<int>();

      final future = token.forEach<int>(
        controller.stream,
        onData: (_) {},
      );

      controller.addError(Exception('Stream error'));

      expect(() => future, throwsA(isA<Exception>()));
    });
  });

  group('Production Hardening: SavedStateHandle Edge Cases', () {
    test('restoreSync with non-map data returns false cleanly', () {
      final handle = SavedStateHandle(
        key: 'non_map_key',
        initialData: {'foo': 'bar'},
      );

      expect(handle.get<String>('foo'), equals('bar'));
      expect(handle.containsKey('foo'), isTrue);
      expect(handle.containsKey('missing'), isFalse);
      expect(handle.toString(), contains('non_map_key'));

      final removed = handle.remove<String>('foo');
      expect(removed, equals('bar'));
      expect(handle.containsKey('foo'), isFalse);
    });

    test('clear with async delete store and throwing store write', () async {
      final store = _ThrowingAsyncStore();
      final handle = SavedStateHandle(
        key: 'throwing_key',
        store: store,
      );

      // set triggers _persist where store.write throws
      handle.set('key1', 'val1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // clear triggers store.delete which is an async future
      handle.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(handle.toMap(), isEmpty);
    });
  });

  group('Production Hardening: CancellationToken.none & Observer Defaults', () {
    test(
        'CancellationToken.none behaves as an active non-cancellable singleton',
        () async {
      final none = CancellationToken.none;

      expect(none.isCancelled, isFalse);
      expect(none.cancellationReason, isNull);
      expect(() => none.throwIfCancelled(), returnsNormally);

      none.cancel('Try cancel');
      expect(none.isCancelled, isFalse);

      var callbackRan = false;
      none.onCancelled(() => callbackRan = true);
      expect(callbackRan, isFalse);

      final detach = none.attach(() {});
      detach();

      expect(await none.race(Future.value('fast')), equals('fast'));
      expect(
          await none.withCancellation(Future.value('fast2')), equals('fast2'));
      expect(await none.runCancellable(() => 777), equals(777));
      await none.sleep(const Duration(milliseconds: 5));

      final collected = <int>[];
      await none.forEach<int>(Stream.fromIterable([1, 2]),
          onData: collected.add);
      expect(collected, equals([1, 2]));
    });

    test(
        'CommanderObserver default methods can be invoked safely without throwing',
        () {
      const observer = _DefaultEmptyObserver();

      expect(
        () => observer.onStateChanged(null, 1, 2),
        returnsNormally,
      );
      expect(
        () => observer.onEffectEmitted(null, 'effect'),
        returnsNormally,
      );
      expect(
        () => observer.onError(
            null, null, null, Exception('test'), StackTrace.empty),
        returnsNormally,
      );
    });

    test('TestCommandScope.listen onError supports single and two arguments',
        () async {
      final testScope = TestCommandScope<HardeningState, HardeningEffect>(
        HardeningState.initial(),
      );

      final controller1 = StreamController<int>();
      Object? singleArgError;
      testScope.listen<int>(
        controller1.stream,
        onError: (Object e) => singleArgError = e,
      );
      controller1.addError(Exception('single arg'));
      await Future<void>.delayed(Duration.zero);
      expect(singleArgError, isA<Exception>());

      final controller2 = StreamController<int>();
      Object? twoArgError;
      StackTrace? twoArgStack;
      testScope.listen<int>(
        controller2.stream,
        onError: (Object e, StackTrace st) {
          twoArgError = e;
          twoArgStack = st;
        },
      );
      controller2.addError(Exception('two args'));
      await Future<void>.delayed(Duration.zero);
      expect(twoArgError, isA<Exception>());
      expect(twoArgStack, isNotNull);
    });
  });

  group('Production Hardening: ControlledCommandScope runtime helpers', () {
    test(
        'ControlledCommandScope provides isCancelled, withCancellation, runCancellable, and listen',
        () async {
      final commander = _ControlledScopeCommander();
      await commander.dispatch(const ControlledScopeIntent());
      expect(commander.state.count, equals(888));
      commander.dispose();
    });
  });

  group('Production Hardening: Observer Isolation & Dispatch Error Symmetry',
      () {
    test(
        'Faulty CommanderObserver does NOT crash Commander execution, state updates, or disposal',
        () async {
      final prevObserver = Commander.observer;
      Commander.observer = _ThrowingObserver();

      try {
        // 1. Creation survives throwing observer
        final commander = HardeningCommander();

        // 2. State update & listeners survive throwing observer
        var notified = 0;
        commander.addListener(() => notified++);

        // 3. Side effects survive throwing observer
        final effects = <HardeningEffect>[];
        commander.effects.listen(effects.add);

        // 4. Command execution survives throwing observer
        commander.dropCmd.shouldFail = false;
        await commander.dispatch(const SyncDropFailIntent());

        expect(commander.state.count, equals(1));
        expect(notified, equals(1));

        // 5. Emitting side effect directly
        commander.testEmitSideEffect(const HardeningEffect('hello'));
        await Future<void>.delayed(Duration.zero);
        expect(effects, equals([const HardeningEffect('hello')]));

        // 6. Error reporting survives throwing observer
        commander.dropCmd.shouldFail = true;
        await commander.dispatch(const SyncDropFailIntent());
        expect(commander.absorbedErrors.length, equals(1));

        // 7. Disposal survives throwing observer
        expect(() => commander.dispose(), returnsNormally);
      } finally {
        Commander.observer = prevObserver;
      }
    });

    test('Synchronous command failure in dispatch returns a catchable Future',
        () async {
      final commander = HardeningSyncThrowCommander();

      // Can be caught via expect throwsA
      expect(
        commander.dispatch(const SyncThrowIntent()),
        throwsA(isA<StateError>()),
      );

      // Can be caught via catchError
      var caught = false;
      await commander.dispatch(const SyncThrowIntent()).catchError((e) {
        caught = true;
      });
      expect(caught, isTrue);

      commander.dispose();
    });
  });
}

class ControlledScopeIntent extends CommandIntent {
  const ControlledScopeIntent();
}

class ControlledScopeCommand
    extends Command<ControlledScopeIntent, HardeningState, HardeningEffect> {
  @override
  Future<void> execute(CommandScope<HardeningState, HardeningEffect> scope,
      ControlledScopeIntent intent) async {
    expect(scope.isCancelled, isFalse);
    scope.throwIfCancelled();

    final v1 = await scope.withCancellation(Future.value('ok'));
    expect(v1, equals('ok'));

    final v2 = await scope.runCancellable(() => 999);
    expect(v2, equals(999));

    final controller = StreamController<int>();
    final collected = <int>[];
    Object? caughtErr;
    var done = false;

    scope.listen<int>(
      controller.stream,
      onData: collected.add,
      onError: (Object err) => caughtErr = err,
      onDone: () => done = true,
    );

    controller.add(10);
    controller.addError(Exception('stream err'));
    await Future<void>.delayed(Duration.zero);
    await controller.close();
    await Future<void>.delayed(Duration.zero);

    expect(collected, equals([10]));
    expect(caughtErr, isA<Exception>());
    expect(done, isTrue);

    // Two-arg error callback
    final controller2 = StreamController<int>();
    Object? twoArgErr;
    StackTrace? twoArgSt;
    scope.listen<int>(
      controller2.stream,
      onError: (Object e, StackTrace st) {
        twoArgErr = e;
        twoArgSt = st;
      },
    );
    controller2.addError(Exception('two arg stream err'));
    await Future<void>.delayed(Duration.zero);
    await controller2.close();
    expect(twoArgErr, isA<Exception>());
    expect(twoArgSt, isNotNull);

    scope.updateState((s) => s.copyWith(count: 888));
  }
}

class _ControlledScopeCommander
    extends Commander<HardeningState, HardeningEffect> {
  _ControlledScopeCommander() : super(HardeningState.initial()) {
    bind(ControlledScopeCommand());
  }
}

class _DefaultEmptyObserver extends CommanderObserver {
  const _DefaultEmptyObserver();
}

class _ThrowingAsyncStore implements SavedStateStore {
  @override
  Map<String, dynamic>? read(String key) => null;

  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    throw Exception('Disk write failed');
  }

  @override
  Future<void> delete(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class SyncThrowIntent extends CommandIntent {
  const SyncThrowIntent();
}

class SyncThrowCommand
    extends Command<SyncThrowIntent, HardeningState, HardeningEffect> {
  @override
  void execute(CommandScope<HardeningState, HardeningEffect> scope,
      SyncThrowIntent intent) {
    throw StateError('Sync command error');
  }
}

class HardeningSyncThrowCommander
    extends Commander<HardeningState, HardeningEffect> {
  HardeningSyncThrowCommander() : super(HardeningState.initial()) {
    bind(SyncThrowCommand());
  }
}

class _ThrowingObserver extends CommanderObserver {
  @override
  void onCommanderCreated(Commander<dynamic, dynamic> commander) =>
      throw StateError('fail created');

  @override
  void onBeforeExecute(Commander<dynamic, dynamic>? commander,
          Command<dynamic, dynamic, dynamic> command, CommandIntent intent) =>
      throw StateError('fail before');

  @override
  void onAfterExecute(Commander<dynamic, dynamic>? commander,
          Command<dynamic, dynamic, dynamic> command, CommandIntent intent) =>
      throw StateError('fail after');

  @override
  void onStateChanged(Commander<dynamic, dynamic>? commander, dynamic oldState,
          dynamic newState) =>
      throw StateError('fail state');

  @override
  void onEffectEmitted(
          Commander<dynamic, dynamic>? commander, dynamic effect) =>
      throw StateError('fail effect');

  @override
  void onError(
          Commander<dynamic, dynamic>? commander,
          Command<dynamic, dynamic, dynamic>? command,
          CommandIntent? intent,
          Object error,
          StackTrace stackTrace) =>
      throw StateError('fail observer onError');

  @override
  void onCommanderDisposed(Commander<dynamic, dynamic> commander) =>
      throw StateError('fail disposed');
}
