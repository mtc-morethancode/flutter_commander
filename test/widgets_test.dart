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

class AppController extends CommanderController<AppState, AppEffect> {
  AppController() : super(const AppState(count: 0, title: 'App')) {
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
    testWidgets('CommanderScope provides controller and auto-disposes', (tester) async {
      late AppController capturedController;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>(
            create: (context) => AppController(),
            child: Builder(
              builder: (context) {
                capturedController = context.commander<AppController>();
                return Text('Count: ${capturedController.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);
      expect(capturedController.isDisposed, isFalse);

      // Unmount the scope
      await tester.pumpWidget(const SizedBox.shrink());
      expect(capturedController.isDisposed, isTrue);
    });

    testWidgets('CommanderScope.value does not dispose shared controller', (tester) async {
      final sharedController = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: sharedController,
            child: Builder(
              builder: (context) => Text('Count: ${context.commander<AppController>().state.count}'),
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);
      expect(sharedController.isDisposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(sharedController.isDisposed, isFalse);

      sharedController.dispose();
    });

    testWidgets('CommanderBuilder with select only rebuilds when selected slice changes',
        (tester) async {
      final controller = AppController();
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderBuilder<AppController, AppState, int>(
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
      await controller.dispatch(const SetTitleIntent('New Title'));
      await tester.pump();

      // Builder should NOT have rebuilt
      expect(buildCount, equals(1));

      // Mutate selected field (count)
      await controller.dispatch(const IncIntent());
      await tester.pump();

      expect(find.text('Rendered count: 1'), findsOneWidget);
      expect(buildCount, equals(2));

      controller.dispose();
    });

    testWidgets('CommanderBuilder respects buildWhen condition', (tester) async {
      final controller = AppController();
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderBuilder<AppController, AppState, int>(
              select: (state) => state.count,
              buildWhen: (prev, curr) => curr % 2 == 0, // only rebuild on even numbers
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
      await controller.dispatch(const IncIntent());
      await tester.pump();
      expect(buildCount, equals(1));
      expect(find.text('Even count: 0'), findsOneWidget);

      // Count becomes 2 (even) -> rebuild
      await controller.dispatch(const IncIntent());
      await tester.pump();
      expect(buildCount, equals(2));
      expect(find.text('Even count: 2'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('CommanderListener handles side effects without rebuilding child', (tester) async {
      final controller = AppController();
      final receivedEffects = <String>[];
      var childBuildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderListener<AppController, AppEffect>(
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

      await controller.dispatch(const NotifyEffectIntent('Effect 1'));
      await tester.pump();

      expect(receivedEffects, equals(['Effect 1']));
      // Child widget must NOT have rebuilt
      expect(childBuildCount, equals(1));

      controller.dispose();
    });

    testWidgets('CommanderConsumer combines builder and listener seamlessly', (tester) async {
      final controller = AppController();
      final receivedEffects = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderConsumer<AppController, AppState, AppEffect, int>(
              select: (state) => state.count,
              onEffect: (context, effect) {
                receivedEffects.add(effect.snackbarText);
              },
              builder: (context, count) => Text('Consumer Count: $count'),
            ),
          ),
        ),
      );

      expect(find.text('Consumer Count: 0'), findsOneWidget);

      await controller.dispatch(const NotifyEffectIntent('Toast'));
      await tester.pump();
      expect(receivedEffects, equals(['Toast']));

      await controller.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Consumer Count: 1'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('CommanderStateBuilder renders full state with only 2 generic types', (tester) async {
      final controller = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderStateBuilder<AppController, AppState>(
              builder: (context, state) => Text('State Count: ${state.count} - ${state.title}'),
            ),
          ),
        ),
      );

      expect(find.text('State Count: 0 - App'), findsOneWidget);

      await controller.dispatch(const IncIntent());
      await tester.pump();

      expect(find.text('State Count: 1 - App'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('CommanderSelector renders slice and only rebuilds when slice changes', (tester) async {
      final controller = AppController();
      int buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderSelector<AppController, AppState, int>(
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
      await controller.dispatch(const SetTitleIntent('New Title'));
      await tester.pump();
      expect(buildCount, equals(1));

      // Change count: should rebuild
      await controller.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Selector Count: 1'), findsOneWidget);
      expect(buildCount, equals(2));

      controller.dispose();
    });

    testWidgets('CommanderStateConsumer combines listener and full-state builder with 3 generics', (tester) async {
      final controller = AppController();
      final List<String> receivedEffects = [];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: CommanderStateConsumer<AppController, AppState, AppEffect>(
              onEffect: (context, effect) {
                receivedEffects.add(effect.snackbarText);
              },
              builder: (context, state) => Text('StateConsumer: ${state.count}'),
            ),
          ),
        ),
      );

      expect(find.text('StateConsumer: 0'), findsOneWidget);

      await controller.dispatch(const NotifyEffectIntent('StateConsumer Toast'));
      await tester.pump();
      expect(receivedEffects, equals(['StateConsumer Toast']));

      await controller.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('StateConsumer: 1'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('CommanderBuilder correctly unsubscribes when controller changes from inherited to explicit', (tester) async {
      final controller1 = AppController();
      final controller2 = AppController();

      Widget buildHarness({AppController? explicitController}) {
        return MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller1,
            child: CommanderStateBuilder<AppController, AppState>(
              controller: explicitController,
              builder: (context, state) => Text('Count: ${state.count}'),
            ),
          ),
        );
      }

      // 1. Initially uses inherited controller1
      await tester.pumpWidget(buildHarness(explicitController: null));
      expect(find.text('Count: 0'), findsOneWidget);

      // 2. Switch to explicit controller2
      await tester.pumpWidget(buildHarness(explicitController: controller2));
      expect(find.text('Count: 0'), findsOneWidget);

      // Mutate controller1: builder should NOT update because it's now listening to controller2
      await controller1.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 0'), findsOneWidget);

      // Mutate controller2: builder SHOULD update
      await controller2.dispatch(const IncIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      controller1.dispose();
      controller2.dispose();
    });

    testWidgets('CommanderBuildContextX context.dispatch and context.select work', (tester) async {
      final controller = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<AppController>.value(
            value: controller,
            child: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) {
                      final title = context.select<AppController, AppState, String>(
                        (state) => state.title,
                      );
                      return Text('Title: $title');
                    },
                  ),
                  Builder(
                    builder: (context) {
                      return ElevatedButton(
                        onPressed: () {
                          context.dispatch<AppController>(const SetTitleIntent('Updated!'));
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

      controller.dispose();
    });
  });
}
