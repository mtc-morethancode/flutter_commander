import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test Models
class AppState {
  final int count;
  final String title;
  const AppState({required this.count, required this.title});

  AppState copyWith({int? count, String? title}) => AppState(
        count: count ?? this.count,
        title: title ?? this.title,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          title == other.title;

  @override
  int get hashCode => Object.hash(count, title);
}

class AppEffect {
  final String snackbarText;
  const AppEffect(this.snackbarText);
}

class IncIntent extends CommandIntent {
  const IncIntent();
}

class SetTitleIntent extends CommandIntent {
  final String title;
  const SetTitleIntent(this.title);
}

class NotifyEffectIntent extends CommandIntent {
  final String message;
  const NotifyEffectIntent(this.message);
}

class AppCommander extends Commander<AppState, AppEffect> {
  AppCommander() : super(const AppState(count: 0, title: 'App')) {
    on<IncIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });

    on<SetTitleIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(title: intent.title));
    });

    on<NotifyEffectIntent>((scope, intent) {
      scope.emitSideEffect(AppEffect(intent.message));
    });
  }
}

void main() {
  group('Commander Widgets', () {
    testWidgets('CommanderScope provides commander and auto-disposes',
        (tester) async {
      late AppCommander capturedCommander;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>(
            create: (context) => AppCommander(),
            child: Builder(
              builder: (context) {
                capturedCommander = context.commander<AppCommander>();
                return Text('Count: ${capturedCommander.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);
      expect(capturedCommander.isDisposed, isFalse);

      // Unmount the scope
      await tester.pumpWidget(const SizedBox.shrink());
      expect(capturedCommander.isDisposed, isTrue);
    });

    testWidgets('CommanderScope.value does not dispose shared commander',
        (tester) async {
      final sharedCommander = AppCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: sharedCommander,
            child: Builder(
              builder: (context) => Text(
                  'Count: ${context.commander<AppCommander>().state.count}'),
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);
      expect(sharedCommander.isDisposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(sharedCommander.isDisposed, isFalse);

      sharedCommander.dispose();
    });

    testWidgets(
        'CommanderBuilder with select only rebuilds when selected slice changes',
        (tester) async {
      final commander = AppCommander();
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderBuilder<AppCommander, AppState, int>(
              select: (state) => state.count,
              builder: (context, count) {
                buildCount++;
                return Text('Rendered count: $count');
              },
            ),
          ),
        ),
      );

      expect(find.text('Rendered count: 0'), findsOneWidget);
      expect(buildCount, equals(1));

      // Mutate unrelated field (title)
      await commander.dispatch(const SetTitleIntent('New Title'));
      await tester.pump();

      // Builder should NOT have rebuilt
      expect(buildCount, equals(1));

      // Mutate selected field (count)
      await commander.dispatch(const IncIntent());
      await tester.pump();

      expect(find.text('Rendered count: 1'), findsOneWidget);
      expect(buildCount, equals(2));

      commander.dispose();
    });

    testWidgets('CommanderBuilder respects buildWhen condition',
        (tester) async {
      final commander = AppCommander();
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderBuilder<AppCommander, AppState, int>(
              select: (state) => state.count,
              buildWhen: (prev, curr) =>
                  curr % 2 == 0, // only rebuild on even numbers
              builder: (context, count) {
                buildCount++;
                return Text('Even count: $count');
              },
            ),
          ),
        ),
      );

      expect(find.text('Even count: 0'), findsOneWidget);
      expect(buildCount, equals(1));

      // Count becomes 1 (odd) -> skip rebuild
      await commander.dispatch(const IncIntent());
      await tester.pump();
      expect(buildCount, equals(1));
      expect(find.text('Even count: 0'), findsOneWidget);

      // Count becomes 2 (even) -> rebuild
      await commander.dispatch(const IncIntent());
      await tester.pump();
      expect(buildCount, equals(2));
      expect(find.text('Even count: 2'), findsOneWidget);

      commander.dispose();
    });

    testWidgets(
        'CommanderListener handles side effects without rebuilding child',
        (tester) async {
      final commander = AppCommander();
      final receivedEffects = <String>[];
      var childBuildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderListener<AppCommander, AppEffect>(
              onEffect: (context, effect) {
                receivedEffects.add(effect.snackbarText);
              },
              child: Builder(
                builder: (context) {
                  childBuildCount++;
                  return const Text('Static Child');
                },
              ),
            ),
          ),
        ),
      );

      expect(childBuildCount, equals(1));

      await commander.dispatch(const NotifyEffectIntent('Effect 1'));
      await tester.pump();

      expect(receivedEffects, equals(['Effect 1']));
      // Child widget must NOT have rebuilt
      expect(childBuildCount, equals(1));

      commander.dispose();
    });


    testWidgets(
        'CommanderStateBuilder renders full state with only 2 generic types',
        (tester) async {
      final commander = AppCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderStateBuilder<AppCommander, AppState>(
              builder: (context, state) =>
                  Text('State Count: ${state.count} - ${state.title}'),
            ),
          ),
        ),
      );

      expect(find.text('State Count: 0 - App'), findsOneWidget);

      await commander.dispatch(const IncIntent());
      await tester.pump();

      expect(find.text('State Count: 1 - App'), findsOneWidget);

      commander.dispose();
    });

    testWidgets(
        'CommanderSelector renders slice and only rebuilds when slice changes',
        (tester) async {
      final commander = AppCommander();
      int buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderSelector<AppCommander, AppState, int>(
              select: (state) => state.count,
              builder: (context, count) {
                buildCount++;
                return Text('Selector Count: $count');
              },
            ),
          ),
        ),
      );

      expect(find.text('Selector Count: 0'), findsOneWidget);
      expect(buildCount, equals(1));

      // Change title: count slice doesn't change, builder should NOT rebuild
      await commander.dispatch(const SetTitleIntent('New Title'));
      await tester.pump();
      expect(buildCount, equals(1));

      // Change count: should rebuild
      await commander.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Selector Count: 1'), findsOneWidget);
      expect(buildCount, equals(2));

      commander.dispose();
    });


    testWidgets(
        'CommanderBuilder correctly unsubscribes when commander changes from inherited to explicit',
        (tester) async {
      final commander1 = AppCommander();
      final commander2 = AppCommander();

      Widget buildHarness({AppCommander? explicitCommander}) {
        return MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander1,
            child: CommanderStateBuilder<AppCommander, AppState>(
              commander: explicitCommander,
              builder: (context, state) => Text('Count: ${state.count}'),
            ),
          ),
        );
      }

      // 1. Initially uses inherited commander1
      await tester.pumpWidget(buildHarness(explicitCommander: null));
      expect(find.text('Count: 0'), findsOneWidget);

      // 2. Switch to explicit commander2
      await tester.pumpWidget(buildHarness(explicitCommander: commander2));
      expect(find.text('Count: 0'), findsOneWidget);

      // Mutate commander1: builder should NOT update because it's now listening to commander2
      await commander1.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 0'), findsOneWidget);

      // Mutate commander2: builder SHOULD update
      await commander2.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      commander1.dispose();
      commander2.dispose();
    });

    testWidgets(
        'CommanderBuilder resubscribes when inherited commander instance changes',
        (tester) async {
      final commanderA = AppCommander();
      final commanderB = AppCommander();

      Widget buildTree(AppCommander commander) {
        return MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderStateBuilder<AppCommander, AppState>(
              builder: (context, state) => Text('Count: ${state.count}'),
            ),
          ),
        );
      }

      // 1. Initial render with commanderA
      await tester.pumpWidget(buildTree(commanderA));
      expect(find.text('Count: 0'), findsOneWidget);

      // 2. Swap to commanderB
      await tester.pumpWidget(buildTree(commanderB));
      expect(find.text('Count: 0'), findsOneWidget);

      // 3. Mutating commanderA should NOT update UI
      await commanderA.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 0'), findsOneWidget);

      // 4. Mutating commanderB SHOULD update UI
      await commanderB.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      commanderA.dispose();
      commanderB.dispose();
    });

    testWidgets(
        'CommanderListener resubscribes when inherited commander instance changes',
        (tester) async {
      final commanderA = AppCommander();
      final commanderB = AppCommander();
      final effects = <String>[];

      Widget buildTree(AppCommander commander) {
        return MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: CommanderListener<AppCommander, AppEffect>(
              onEffect: (context, effect) => effects.add(effect.snackbarText),
              child: const Text('Child'),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTree(commanderA));
      await tester.pumpWidget(buildTree(commanderB));

      // Emit on old commanderA: should NOT receive effect
      await commanderA.dispatch(const NotifyEffectIntent('from A'));
      await tester.pump();
      expect(effects, isEmpty);

      // Emit on new commanderB: SHOULD receive effect
      await commanderB.dispatch(const NotifyEffectIntent('from B'));
      await tester.pump();
      expect(effects, equals(['from B']));

      commanderA.dispose();
      commanderB.dispose();
    });

    testWidgets(
        'CommanderBuildContextX context.dispatch and context.select work',
        (tester) async {
      final commander = AppCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>.value(
            value: commander,
            child: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) {
                      final title =
                          context.select<AppCommander, AppState, String>(
                        (state) => state.title,
                      );
                      return Text('Title: $title');
                    },
                  ),
                  Builder(
                    builder: (context) {
                      return ElevatedButton(
                        onPressed: () {
                          context.dispatch<AppCommander>(
                              const SetTitleIntent('Updated!'));
                        },
                        child: const Text('Change Title'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Title: App'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Title: Updated!'), findsOneWidget);

      commander.dispose();
    });

    testWidgets(
        'CommanderScope with create and autoDispose: false does not dispose commander on unmount',
        (tester) async {
      final commander = AppCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppCommander>(
            create: (_) => commander,
            autoDispose: false,
            child: const Text('Content'),
          ),
        ),
      );

      expect(commander.isDisposed, isFalse);

      // Unmount CommanderScope
      await tester.pumpWidget(const SizedBox.shrink());

      expect(commander.isDisposed, isFalse);
      commander.dispose();
    });

    testWidgets(
        'CommanderBuilder didUpdateWidget updates displayed value when select callback changes',
        (tester) async {
      final commander = AppCommander();

      Widget buildHarness(String Function(AppState) selector) {
        return MaterialApp(
          home: CommanderBuilder<AppCommander, AppState, String>(
            commander: commander,
            select: selector,
            builder: (context, val) => Text('Val: $val'),
          ),
        );
      }

      await tester.pumpWidget(buildHarness((s) => 'Count: ${s.count}'));
      expect(find.text('Val: Count: 0'), findsOneWidget);

      // Change selector to title without changing state
      await tester.pumpWidget(buildHarness((s) => 'Title: ${s.title}'));
      expect(find.text('Val: Title: App'), findsOneWidget);

      commander.dispose();
    });
  });
}
