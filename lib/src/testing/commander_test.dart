// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:matcher/expect.dart' as test_package;
import 'package:meta/meta.dart';
import 'package:test_api/scaffolding.dart' as test_package;

import '../commander/commander.dart';

/// A declarative test harness for testing [Commander] orchestrators.
///
/// [commanderTest] simplifies testing [Commander] instances by managing
/// lifecycle, state collection, side-effect recording, error handling, and teardown
/// in an expressive, declarative manner similar to `blocTest`.
///
/// ### Example: Testing States and Effects
/// ```dart
/// commanderTest<CounterCommander, CounterState, CounterEffect>(
///   'emits [1] and ShowToastEffect when IncrementIntent is dispatched',
///   build: () => CounterCommander(),
///   act: (commander) => commander.dispatch(const IncrementIntent(1)),
///   expectStates: () => [
///     const CounterState(value: 1),
///   ],
///   expectEffects: () => [
///     const ShowToastEffect('Incremented by 1'),
///   ],
/// );
/// ```
///
/// ### Example: Seeding State
/// ```dart
/// commanderTest<CounterCommander, CounterState, CounterEffect>(
///   'increments correctly from a seeded state',
///   build: () => CounterCommander(),
///   seed: () => const CounterState(value: 99),
///   act: (commander) => commander.dispatch(const IncrementIntent(1)),
///   expectStates: () => [
///     const CounterState(value: 100),
///   ],
/// );
/// ```
///
/// ### Example: Expecting Errors
/// ```dart
/// commanderTest<CounterCommander, CounterState, CounterEffect>(
///   'captures exception when FailingIntent is dispatched',
///   build: () => CounterCommander(),
///   act: (commander) => commander.dispatch(const FailIntent()),
///   errors: () => [isA<Exception>()],
/// );
/// ```
@isTest
void commanderTest<C extends Commander<S, E>, S, E>(
  String description, {
  FutureOr<void> Function()? setUp,
  required FutureOr<C> Function() build,
  FutureOr<S> Function()? seed,
  FutureOr<void> Function(C commander)? act,
  Duration? wait,
  int skip = 0,
  dynamic Function()? expect,
  dynamic Function()? expectStates,
  dynamic Function()? expectEffects,
  dynamic Function()? errors,
  FutureOr<void> Function(C commander)? verify,
  FutureOr<void> Function(C commander)? tearDown,
  dynamic tags,
  dynamic skipTest,
  test_package.Timeout? timeout,
}) {
  assert(
    expect == null || expectStates == null,
    'Cannot provide both "expect" and "expectStates". Use either "expectStates" or "expect".',
  );

  test_package.test(
    description,
    () async {
      await setUp?.call();

      C? commander;
      StreamSubscription<E>? effectSubscription;
      final states = <S>[];
      final effects = <E>[];
      final unhandledErrors = <Object>[];

      try {
        commander = await build();

        if (seed != null) {
          final seededState = await seed();
          commander.testSeed(seededState);
        }

        final targetCommander = commander;
        targetCommander.addListener(() {
          states.add(targetCommander.state);
        });

        effectSubscription = targetCommander.effects.listen(effects.add);

        await runZonedGuarded(
          () async {
            try {
              await act?.call(targetCommander);
            } catch (error) {
              unhandledErrors.add(error);
            }
          },
          (error, stackTrace) {
            unhandledErrors.add(error);
          },
        );

        if (wait != null) {
          await Future<void>.delayed(wait);
        } else {
          await Future<void>.delayed(Duration.zero);
        }

        // If errors are not expected, fail fast on unhandled errors before assertions
        if (errors == null && unhandledErrors.isNotEmpty) {
          final first = unhandledErrors.first;
          throw first;
        }

        // 1. Verify state transitions
        final expectedStatesFn = expectStates ?? expect;
        if (expectedStatesFn != null) {
          var recordedStates = states;
          if (skip > 0) {
            recordedStates = recordedStates.skip(skip).toList();
          }
          final dynamic expected = expectedStatesFn();
          test_package.expect(recordedStates, expected);
        }

        // 2. Verify emitted side-effects
        if (expectEffects != null) {
          final dynamic expectedEffects = expectEffects();
          test_package.expect(effects, expectedEffects);
        }

        // 3. Verify expected errors
        if (errors != null) {
          final dynamic expectedErrors = errors();
          test_package.expect(unhandledErrors, expectedErrors);
        }

        // 4. Verification callback (e.g. mocktail / mockito verifications)
        await verify?.call(targetCommander);
      } finally {
        if (commander != null) {
          try {
            await tearDown?.call(commander);
          } finally {
            await effectSubscription?.cancel();
            if (!commander.isDisposed) {
              commander.dispose();
            }
          }
        }
      }
    },
    tags: tags,
    skip: skipTest,
    timeout: timeout,
  );
}
