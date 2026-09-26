import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test domain models
class HardeningState {
  final int count;
  final String label;
  const HardeningState({required this.count, required this.label});

  HardeningState copyWith({int? count, String? label}) => HardeningState(
        count: count ?? this.count,
        label: label ?? this.label,
      );
}

class HardeningEffect {
  final String message;
  const HardeningEffect(this.message);
}

class SyncIncIntent extends CommandIntent {
  const SyncIncIntent();
}

class AsyncFailingIntent extends CommandIntent {
  final String errorMsg;
  const AsyncFailingIntent([this.errorMsg = 'Async command failure']);
}

class MutateLabelIntent extends CommandIntent {
  final String label;
  const MutateLabelIntent(this.label);
}

class HardeningCommander extends Commander<HardeningState, HardeningEffect> {
  HardeningCommander({super.interceptors})
      : super(const HardeningState(count: 0, label: 'initial')) {
    on<SyncIncIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });

    on<MutateLabelIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(label: intent.label));
    });

    on<AsyncFailingIntent>((scope, intent) async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      throw Exception(intent.errorMsg);
    });
  }
}

// Widget that dispatches synchronously inside initState
class WidgetDispatchingInInitState extends StatefulWidget {
  const WidgetDispatchingInInitState({super.key});

  @override
  State<WidgetDispatchingInInitState> createState() =>
      _WidgetDispatchingInInitStateState();
}

class _WidgetDispatchingInInitStateState
    extends State<WidgetDispatchingInInitState> {
  @override
  void initState() {
    super.initState();
    // Synchronously dispatch an intent that immediately mutates state via updateState
    context.dispatch<HardeningCommander>(const SyncIncIntent());
  }

  @override
  Widget build(BuildContext context) {
    final count = context.selectState<HardeningCommander, HardeningState, int>(
      (s) => s.count,
    );
    return Text('Count in initState: $count');
  }
}

// Widget testing context.select stability without aspectKey across rebuilds
class SelectorWidgetWithoutAspectKey extends StatelessWidget {
  final int parentTick;
  final VoidCallback onBuild;

  const SelectorWidgetWithoutAspectKey({
    super.key,
    required this.parentTick,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    onBuild();
    final count = context.selectState<HardeningCommander, HardeningState, int>(
      (s) => s.count,
    );
    return Text('Count: $count (parentTick: $parentTick)');
  }
}

class ParentRebuildTester extends StatefulWidget {
  final HardeningCommander commander;
  final VoidCallback onChildBuild;

  const ParentRebuildTester({
    super.key,
    required this.commander,
    required this.onChildBuild,
  });

  @override
  State<ParentRebuildTester> createState() => ParentRebuildTesterState();
}

class ParentRebuildTesterState extends State<ParentRebuildTester> {
  int tick = 0;
  void triggerParentRebuild() => setState(() => tick++);

  @override
  Widget build(BuildContext context) {
    return CommanderScope<HardeningCommander>.value(
      value: widget.commander,
      child: SelectorWidgetWithoutAspectKey(
        parentTick: tick,
        onBuild: widget.onChildBuild,
      ),
    );
  }
}

class CountingObserver extends CommanderObserver {
  int beforeCount = 0;
  int afterCount = 0;
  int errorCount = 0;

  @override
  void onBeforeExecute(Commander<dynamic, dynamic>? commander,
      Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {
    beforeCount++;
  }

  @override
  void onAfterExecute(Commander<dynamic, dynamic>? commander,
      Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {
    afterCount++;
  }

  @override
  void onError(
      Commander<dynamic, dynamic>? commander,
      Command<dynamic, dynamic, dynamic>? command,
      CommandIntent? intent,
      Object error,
      StackTrace stackTrace) {
    errorCount++;
  }
}

void main() {
  group('Production Hardening & Bug Fixes', () {
    testWidgets(
        '1. Synchronous dispatch inside initState does not crash with "markNeedsBuild called during build"',
        (tester) async {
      final commander = HardeningCommander();

      // Mounting this widget would previously trigger a fatal exception in CommanderScope
      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<HardeningCommander>.value(
            value: commander,
            child: const WidgetDispatchingInInitState(),
          ),
        ),
      );

      // Verify that widget mounted and reflects the incremented count safely
      expect(find.text('Count in initState: 1'), findsOneWidget);
      expect(commander.state.count, equals(1));

      commander.dispose();
    });

    testWidgets(
        '2. context.select without aspectKey does not leak aspects in dependencies set across multiple rebuilds',
        (tester) async {
      final commander = HardeningCommander();
      var childBuildCount = 0;
      final parentKey = GlobalKey<ParentRebuildTesterState>();

      await tester.pumpWidget(
        MaterialApp(
          home: ParentRebuildTester(
            key: parentKey,
            commander: commander,
            onChildBuild: () => childBuildCount++,
          ),
        ),
      );

      expect(childBuildCount, equals(1));
      expect(find.text('Count: 0 (parentTick: 0)'), findsOneWidget);

      // Trigger 10 external rebuilds of the parent widget
      for (var i = 0; i < 10; i++) {
        parentKey.currentState!.triggerParentRebuild();
        await tester.pump();
      }

      expect(childBuildCount, equals(11));

      // Inspect InheritedModel dependencies for the child element
      final childElement =
          tester.element(find.byType(SelectorWidgetWithoutAspectKey));
      final inheritedElement = tester.element(
        find.byWidgetPredicate((w) =>
            w.runtimeType.toString().contains('_CommanderInheritedModel')),
      ) as InheritedModelElement;

      final dependencies =
          // ignore: invalid_use_of_protected_member
          inheritedElement.getDependencies(childElement) as Set?;

      // Must have exactly 1 dependency entry, not 11!
      expect(dependencies, isNotNull);
      expect(dependencies!.length, equals(1),
          reason:
              'Dependencies should be deduplicated by generic types <S, R> and not leak memory.');

      // Also verify that mutating an unrelated field does not rebuild the child
      final preUnrelatedBuilds = childBuildCount;
      await commander.dispatch(const MutateLabelIntent('updated_label'));
      await tester.pump();
      expect(childBuildCount, equals(preUnrelatedBuilds),
          reason: 'Child should not rebuild when unrelated slice changes');

      // And mutating the selected field DOES trigger a rebuild
      await commander.dispatch(const SyncIncIntent());
      await tester.pump();
      expect(childBuildCount, equals(preUnrelatedBuilds + 1));
      expect(find.text('Count: 1 (parentTick: 10)'), findsOneWidget);

      commander.dispose();
    });

    test(
        '3a. Fire-and-forget dispatch of failing async command does not trigger Unhandled Zone Crash',
        () async {
      final commander = HardeningCommander();

      Object? unhandledError;
      final spec = ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stackTrace) {
          unhandledError = error;
        },
      );

      await runZonedGuarded(() async {
        // Dispatched without await (fire-and-forget), simulating UI button clicks:
        // onPressed: () => context.dispatch(const AsyncFailingIntent())
        unawaited(commander.dispatch(const AsyncFailingIntent('Async crash')));

        // Wait for command to fail internally
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }, (error, stack) {
        unhandledError = error;
      }, zoneSpecification: spec);

      // Unhandled zone error must be null!
      expect(unhandledError, isNull,
          reason:
              'Commander dispatch must attach internal catch handler so fire-and-forget calls do not crash root Zone.');

      commander.dispose();
    });

    test(
        '3b. Explicitly awaited dispatch continues to propagate error normally',
        () async {
      final commander = HardeningCommander();

      // Callers that DO await must still receive the exception
      await expectLater(
        () => commander.dispatch(const AsyncFailingIntent('Awaited crash')),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Awaited crash'),
        )),
      );

      commander.dispose();
    });

    test(
        '3c. Telemetry onAfterExecute always executes via finally block even when _reportError throws',
        () async {
      final observer = CountingObserver();
      Commander.observer = observer;

      final commander = HardeningCommander();

      try {
        await commander.dispatch(const AsyncFailingIntent('Observe crash'));
      } catch (_) {
        // Expected rethrow from default onError
      }

      // Both onBeforeExecute and onAfterExecute MUST be balanced
      expect(observer.beforeCount, equals(1));
      expect(observer.errorCount, equals(1));
      expect(observer.afterCount, equals(1),
          reason:
              'onAfterExecute must always be called even when onError rethrows.');

      commander.dispose();
      Commander.observer = null;
    });
  });
}
