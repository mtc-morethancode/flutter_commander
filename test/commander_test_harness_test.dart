import 'package:flutter_commander/testing.dart';
import 'package:flutter_test/flutter_test.dart';

// Test State
class HarnessCounterState {
  final int count;
  final String status;

  const HarnessCounterState({required this.count, required this.status});

  HarnessCounterState copyWith({int? count, String? status}) =>
      HarnessCounterState(
        count: count ?? this.count,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HarnessCounterState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          status == other.status;

  @override
  int get hashCode => Object.hash(count, status);

  @override
  String toString() => 'HarnessCounterState(count: $count, status: $status)';
}

// Test Effects
sealed class HarnessEffect {
  const HarnessEffect();
}

class AlertEffect extends HarnessEffect {
  final String message;
  const AlertEffect(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertEffect &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'AlertEffect($message)';
}

// Test Intents
class IncrementCountIntent extends CommandIntent {
  final int amount;
  const IncrementCountIntent([this.amount = 1]);
}

class MultiStepIntent extends CommandIntent {
  const MultiStepIntent();
}

class DebouncedIntent extends CommandIntent {
  final int value;
  const DebouncedIntent(this.value);
}

class FailingIntent extends CommandIntent {
  const FailingIntent();
}

class CustomTestException implements Exception {
  final String message;
  const CustomTestException(this.message);

  @override
  String toString() => 'CustomTestException: $message';
}

// Test Commander
class HarnessCommander extends Commander<HarnessCounterState, HarnessEffect> {
  HarnessCommander({
    super.interceptors,
    HarnessCounterState? initialState,
  }) : super(
          initialState ?? const HarnessCounterState(count: 0, status: 'idle'),
        ) {
    on<IncrementCountIntent>((scope, intent) {
      scope.updateState(
        (s) =>
            s.copyWith(count: s.count + intent.amount, status: 'incremented'),
      );
      scope.emitSideEffect(AlertEffect('Count is now ${scope.state.count}'));
    });

    on<MultiStepIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(status: 'step1'));
      scope.updateState((s) => s.copyWith(status: 'step2'));
      scope.updateState((s) => s.copyWith(status: 'done'));
    });

    on<DebouncedIntent>(
      (scope, intent) {
        scope.updateState(
          (s) => s.copyWith(count: intent.value, status: 'debounced'),
        );
      },
      debounce: const Duration(milliseconds: 50),
    );

    on<FailingIntent>((scope, intent) {
      throw const CustomTestException('Planned failure');
    });
  }
}

void main() {
  group('commanderTest declarative harness', () {
    final lifecycleEvents = <String>[];
    HarnessCommander? lastCommander;

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'records synchronous state transitions and emitted side effects',
      setUp: () => lifecycleEvents.add('setUp'),
      build: () {
        lifecycleEvents.add('build');
        final c = HarnessCommander();
        lastCommander = c;
        return c;
      },
      act: (commander) {
        lifecycleEvents.add('act');
        commander.dispatch(const IncrementCountIntent(2));
      },
      expectStates: () => [
        const HarnessCounterState(count: 2, status: 'incremented'),
      ],
      expectEffects: () => [
        const AlertEffect('Count is now 2'),
      ],
      verify: (commander) {
        lifecycleEvents.add('verify');
        expect(commander.state.count, 2);
      },
      tearDown: (commander) {
        lifecycleEvents.add('tearDown');
      },
    );

    test('verifies lifecycle execution order and automatic disposal', () {
      expect(lifecycleEvents, ['setUp', 'build', 'act', 'verify', 'tearDown']);
      expect(lastCommander, isNotNull);
      expect(lastCommander!.isDisposed, isTrue);
    });

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'supports "expect" as an alias for "expectStates"',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const IncrementCountIntent(5)),
      expect: () => [
        const HarnessCounterState(count: 5, status: 'incremented'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'seeds state prior to act execution without recording seed in emissions',
      build: () => HarnessCommander(),
      seed: () => const HarnessCounterState(count: 50, status: 'seeded'),
      act: (commander) => commander.dispatch(const IncrementCountIntent(5)),
      expectStates: () => [
        const HarnessCounterState(count: 55, status: 'incremented'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'records multiple sequential state updates from multi-step commands',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const MultiStepIntent()),
      expectStates: () => [
        const HarnessCounterState(count: 0, status: 'step1'),
        const HarnessCounterState(count: 0, status: 'step2'),
        const HarnessCounterState(count: 0, status: 'done'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'skips N state emissions when skip is specified',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const MultiStepIntent()),
      skip: 2,
      expectStates: () => [
        const HarnessCounterState(count: 0, status: 'done'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'supports wait parameter for asynchronous/debounced commands',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const DebouncedIntent(42)),
      wait: const Duration(milliseconds: 80),
      expectStates: () => [
        const HarnessCounterState(count: 42, status: 'debounced'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'captures expected errors declaratively via errors callback',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const FailingIntent()),
      errors: () => [
        isA<CustomTestException>(),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'allows asserting side effects only with no state assertions',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const IncrementCountIntent(10)),
      expectEffects: () => [
        const AlertEffect('Count is now 10'),
      ],
    );

    commanderTest<HarnessCommander, HarnessCounterState, HarnessEffect>(
      'skipped test flag works as expected',
      build: () => HarnessCommander(),
      act: (commander) => commander.dispatch(const IncrementCountIntent(1)),
      skipTest: true,
      expectStates: () => [
        const HarnessCounterState(count: 999, status: 'never_reached'),
      ],
    );
  });
}
