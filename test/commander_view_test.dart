import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test Models
class TestState {
  final int count;
  final String title;

  const TestState({required this.count, required this.title});

  TestState copyWith({int? count, String? title}) => TestState(
        count: count ?? this.count,
        title: title ?? this.title,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          title == other.title;

  @override
  int get hashCode => Object.hash(count, title);
}

sealed class TestEffect {
  const TestEffect();
}

class ToastEffect extends TestEffect {
  final String message;
  const ToastEffect(this.message);
}

class SilentEffect extends TestEffect {
  const SilentEffect();
}

class IncrementIntent extends CommandIntent {
  const IncrementIntent();
}

class SetTitleIntent extends CommandIntent {
  final String title;
  const SetTitleIntent(this.title);
}

class TriggerToastIntent extends CommandIntent {
  final String message;
  const TriggerToastIntent(this.message);
}

class TriggerSilentIntent extends CommandIntent {
  const TriggerSilentIntent();
}

class NoopIntent extends CommandIntent {
  const NoopIntent();
}

class TestCommander extends Commander<TestState, TestEffect> {
  TestCommander({int initialCount = 0, String initialTitle = 'Default'})
      : super(TestState(count: initialCount, title: initialTitle)) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });

    on<NoopIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith());
    });

    on<SetTitleIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(title: intent.title));
    });

    on<TriggerToastIntent>((scope, intent) {
      scope.emitSideEffect(ToastEffect(intent.message));
    });

    on<TriggerSilentIntent>((scope, intent) {
      scope.emitSideEffect(const SilentEffect());
    });
  }
}

// Sample CommanderView subclass for testing
class CounterPageView
    extends CommanderView<TestCommander, TestState, TestEffect> {
  final void Function(BuildContext context, TestEffect effect)? onEffectCallback;
  final bool Function(TestEffect effect)? listenWhenCallback;
  final bool Function(TestState previous, TestState current)?
      shouldRebuildCallback;
  final void Function(int buildCount)? onBuilt;

  const CounterPageView({
    super.key,
    super.commander,
    this.onEffectCallback,
    this.listenWhenCallback,
    this.shouldRebuildCallback,
    this.onBuilt,
  });

  @override
  void onEffect(BuildContext context, TestEffect effect) {
    onEffectCallback?.call(context, effect);
  }

  @override
  bool listenWhen(TestEffect effect) {
    if (listenWhenCallback != null) {
      return listenWhenCallback!(effect);
    }
    return super.listenWhen(effect);
  }

  @override
  bool shouldRebuild(TestState previous, TestState current) {
    if (shouldRebuildCallback != null) {
      return shouldRebuildCallback!(previous, current);
    }
    return super.shouldRebuild(previous, current);
  }

  @override
  Widget build(BuildContext context, TestState state) {
    onBuilt?.call(state.count);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Text('Title: ${state.title}'),
          Text('Count: ${state.count}'),
          ElevatedButton(
            onPressed: () => dispatch(context, const IncrementIntent()),
            child: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}

class DefaultEffectView
    extends CommanderView<TestCommander, TestState, TestEffect> {
  const DefaultEffectView({super.key, super.commander});

  @override
  Widget build(BuildContext context, TestState state) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('Count: ${state.count}'),
    );
  }
}

void main() {
  group('CommanderView', () {
    testWidgets('default onEffect does nothing and does not crash',
        (tester) async {
      final commander = TestCommander();

      await tester.pumpWidget(
        DefaultEffectView(commander: commander),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      await commander.dispatch(const TriggerToastIntent('Ignored'));
      await tester.pump();

      expect(find.text('Count: 0'), findsOneWidget);
      commander.dispose();
    });
    testWidgets('renders initial state and responds to state changes',
        (tester) async {
      final commander = TestCommander();
      var buildCount = 0;

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: CounterPageView(
            onBuilt: (_) => buildCount++,
          ),
        ),
      );

      expect(find.text('Title: Default'), findsOneWidget);
      expect(find.text('Count: 0'), findsOneWidget);
      expect(buildCount, equals(1));

      // Dispatch increment
      await commander.dispatch(const IncrementIntent());
      await tester.pump();

      expect(find.text('Count: 1'), findsOneWidget);
      expect(buildCount, equals(2));

      // Emitting the exact same state should NOT trigger a rebuild
      await commander.dispatch(const NoopIntent());
      await tester.pump();

      expect(buildCount, equals(2));

      commander.dispose();
    });

    testWidgets(
        'respects shouldRebuild filter to conditionally prevent rebuilds',
        (tester) async {
      final commander = TestCommander();
      var buildCount = 0;

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: CounterPageView(
            onBuilt: (_) => buildCount++,
            // Only rebuild when title changes, ignore count mutations
            shouldRebuildCallback: (prev, curr) => prev.title != curr.title,
          ),
        ),
      );

      expect(buildCount, equals(1));
      expect(find.text('Count: 0'), findsOneWidget);
      expect(find.text('Title: Default'), findsOneWidget);

      // Increment count -> shouldRebuild returns false -> no rebuild!
      await commander.dispatch(const IncrementIntent());
      await tester.pump();

      expect(buildCount, equals(1));
      expect(find.text('Count: 0'), findsOneWidget);

      // Update title -> shouldRebuild returns true -> rebuilds!
      await commander.dispatch(const SetTitleIntent('Updated Title'));
      await tester.pump();

      expect(buildCount, equals(2));
      expect(find.text('Title: Updated Title'), findsOneWidget);
      expect(find.text('Count: 1'), findsOneWidget);

      commander.dispose();
    });

    testWidgets('receives side effects without rebuilding the view',
        (tester) async {
      final commander = TestCommander();
      var buildCount = 0;
      final receivedEffects = <String>[];

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: CounterPageView(
            onBuilt: (_) => buildCount++,
            onEffectCallback: (context, effect) {
              if (effect is ToastEffect) {
                receivedEffects.add(effect.message);
              }
            },
          ),
        ),
      );

      expect(buildCount, equals(1));
      expect(receivedEffects, isEmpty);

      // Trigger side-effect
      await commander.dispatch(const TriggerToastIntent('Hello Toast!'));
      await tester.pump();

      expect(receivedEffects, equals(['Hello Toast!']));
      // UI must NOT have rebuilt
      expect(buildCount, equals(1));

      commander.dispose();
    });

    testWidgets('respects listenWhen filter for side effects', (tester) async {
      final commander = TestCommander();
      final receivedEffects = <String>[];

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: CounterPageView(
            listenWhenCallback: (effect) => effect is ToastEffect,
            onEffectCallback: (context, effect) {
              if (effect is ToastEffect) {
                receivedEffects.add(effect.message);
              } else if (effect is SilentEffect) {
                receivedEffects.add('Silent');
              }
            },
          ),
        ),
      );

      // Trigger filtered effect (SilentEffect should be rejected by listenWhen)
      await commander.dispatch(const TriggerSilentIntent());
      await tester.pump();
      expect(receivedEffects, isEmpty);

      // Trigger accepted effect
      await commander.dispatch(const TriggerToastIntent('Accepted'));
      await tester.pump();
      expect(receivedEffects, equals(['Accepted']));

      commander.dispose();
    });

    testWidgets('dispatch helper method sends intents correctly',
        (tester) async {
      final commander = TestCommander();

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: const CounterPageView(),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      // Tap the increment button which uses dispatch(context, intent)
      await tester.tap(find.text('Increment'));
      await tester.pump();

      expect(find.text('Count: 1'), findsOneWidget);

      commander.dispose();
    });

    testWidgets('works with explicitly provided commander in constructor',
        (tester) async {
      final explicitCommander = TestCommander(initialCount: 42);

      await tester.pumpWidget(
        CounterPageView(
          commander: explicitCommander,
        ),
      );

      expect(find.text('Count: 42'), findsOneWidget);

      await tester.tap(find.text('Increment'));
      await tester.pump();

      expect(find.text('Count: 43'), findsOneWidget);

      explicitCommander.dispose();
    });

    testWidgets('updates subscription when didUpdateWidget changes commander',
        (tester) async {
      final commanderA = TestCommander(initialCount: 10, initialTitle: 'A');
      final commanderB = TestCommander(initialCount: 20, initialTitle: 'B');

      await tester.pumpWidget(
        CounterPageView(commander: commanderA),
      );

      expect(find.text('Title: A'), findsOneWidget);
      expect(find.text('Count: 10'), findsOneWidget);

      // Update widget with commanderB
      await tester.pumpWidget(
        CounterPageView(commander: commanderB),
      );

      expect(find.text('Title: B'), findsOneWidget);
      expect(find.text('Count: 20'), findsOneWidget);

      // Verify commanderA is unobserved
      await commanderA.dispatch(const IncrementIntent());
      await tester.pump();
      expect(find.text('Count: 20'), findsOneWidget);

      // Verify commanderB updates the view
      await commanderB.dispatch(const IncrementIntent());
      await tester.pump();
      expect(find.text('Count: 21'), findsOneWidget);

      commanderA.dispose();
      commanderB.dispose();
    });

    testWidgets(
        'CommanderView resubscribes when inherited commander instance changes',
        (tester) async {
      final commanderA = TestCommander(initialCount: 10, initialTitle: 'A');
      final commanderB = TestCommander(initialCount: 20, initialTitle: 'B');

      Widget buildTree(TestCommander commander) {
        return CommanderScope<TestCommander>.value(
          value: commander,
          child: const CounterPageView(),
        );
      }

      await tester.pumpWidget(buildTree(commanderA));
      expect(find.text('Title: A'), findsOneWidget);
      expect(find.text('Count: 10'), findsOneWidget);

      // Swap inherited commander
      await tester.pumpWidget(buildTree(commanderB));
      expect(find.text('Title: B'), findsOneWidget);
      expect(find.text('Count: 20'), findsOneWidget);

      // Mutate commanderA -> view should NOT update
      await commanderA.dispatch(const IncrementIntent());
      await tester.pump();
      expect(find.text('Count: 20'), findsOneWidget);

      // Mutate commanderB -> view SHOULD update
      await commanderB.dispatch(const IncrementIntent());
      await tester.pump();
      expect(find.text('Count: 21'), findsOneWidget);

      commanderA.dispose();
      commanderB.dispose();
    });

    testWidgets('commanderOf helper returns the bound commander',
        (tester) async {
      final commander = TestCommander();
      late TestCommander resolved;

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: Builder(
            builder: (context) {
              const view = CounterPageView();
              resolved = view.commanderOf(context);
              return view;
            },
          ),
        ),
      );

      expect(resolved, same(commander));
      commander.dispose();
    });

    testWidgets('unsubscribes and cleans up on unmount', (tester) async {
      final commander = TestCommander();
      var buildCount = 0;
      var effectCount = 0;

      await tester.pumpWidget(
        CommanderScope<TestCommander>.value(
          value: commander,
          child: CounterPageView(
            onBuilt: (_) => buildCount++,
            onEffectCallback: (_, __) => effectCount++,
          ),
        ),
      );

      expect(buildCount, equals(1));

      // Unmount view
      await tester.pumpWidget(const SizedBox.shrink());

      // Dispatch after unmount should not trigger any callback or error
      await commander.dispatch(const IncrementIntent());
      await commander.dispatch(const TriggerToastIntent('After unmount'));
      await tester.pump();

      expect(buildCount, equals(1));
      expect(effectCount, equals(0));

      commander.dispose();
    });
  });
}
