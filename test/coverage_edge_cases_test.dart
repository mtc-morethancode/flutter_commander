import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_commander/src/controller/command_registry.dart';
import 'package:flutter_test/flutter_test.dart';

// Test domain
class DummyState {
  final int count;
  const DummyState(this.count);
}

class DummyEffect {
  const DummyEffect();
}

abstract class BaseIntent extends CommandIntent {
  const BaseIntent();
}

class DerivedIntent extends BaseIntent {
  const DerivedIntent();
}

class QueuedSlowIntent extends CommandIntent {
  const QueuedSlowIntent();
}

class BaseIntentCommand extends Command<BaseIntent, DummyState, DummyEffect> {
  @override
  Future<void> execute(CommandScope<DummyState, DummyEffect> scope, BaseIntent intent) async {
    scope.updateState((s) => DummyState(s.count + 1));
  }
}

class QueuedSlowCommand extends Command<QueuedSlowIntent, DummyState, DummyEffect> {
  final Completer<void> completer = Completer<void>();

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<DummyState, DummyEffect> scope, QueuedSlowIntent intent) async {
    await completer.future;
  }
}

class DummyController extends CommanderController<DummyState, DummyEffect> {
  DummyController() : super(const DummyState(0)) {
    bind(BaseIntentCommand());
    bind(QueuedSlowCommand());
  }
}

class DefaultInterceptor extends CommandInterceptor {
  const DefaultInterceptor();
}

void main() {
  group('Coverage Edge Cases', () {
    test('CancellationException toString', () {
      const ex = CancellationException('Custom cancel');
      expect(ex.toString(), contains('Custom cancel'));
    });

    test('UnregisteredIntentException toString', () {
      const ex = UnregisteredIntentException(DerivedIntent());
      expect(ex.toString(), contains('UnregisteredIntentException'));
      expect(ex.toString(), contains('DerivedIntent'));
    });

    test('CommandInterceptor base class default empty methods', () {
      const interceptor = DefaultInterceptor();
      final cmd = BaseIntentCommand();
      const intent = DerivedIntent();

      expect(() => interceptor.onBeforeExecute(cmd, intent), returnsNormally);
      expect(() => interceptor.onAfterExecute(cmd, intent), returnsNormally);
      expect(() => interceptor.onStateChanged(const DummyState(0), const DummyState(1)), returnsNormally);
      expect(() => interceptor.onEffectEmitted(const DummyEffect()), returnsNormally);
      expect(
        () => interceptor.onError(cmd, intent, Exception(), StackTrace.current),
        returnsNormally,
      );
    });

    test('removeInterceptor removes registered interceptor', () async {
      final controller = DummyController();
      var logged = 0;
      final logger = LoggingCommandInterceptor(printFn: (_) => logged++);

      controller.addInterceptor(logger);
      await controller.dispatch(const DerivedIntent());
      expect(logged, greaterThan(0));

      final prevLogged = logged;
      controller.removeInterceptor(logger);
      await controller.dispatch(const DerivedIntent());
      expect(logged, equals(prevLogged));

      controller.dispose();
    });

    test('LoggingCommandInterceptor default print and error logging', () {
      const logger = LoggingCommandInterceptor(
        logStates: true,
        logEffects: true,
        logErrors: true,
      );

      // Testing error logging branch
      expect(
        () => logger.onError(
          BaseIntentCommand(),
          const DerivedIntent(),
          Exception('Boom'),
          StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('CommandRegistry polymorphic subtype resolution and contains check', () async {
      final controller = DummyController();
      // BaseIntentCommand is registered for BaseIntent, DerivedIntent extends BaseIntent
      await controller.dispatch(const DerivedIntent());
      expect(controller.state.count, equals(1));
      controller.dispose();
    });

    test('Queue cancellation upon controller disposal when items are pending', () async {
      final controller = DummyController();

      // Dispatch 2 queued intents
      unawaited(controller.dispatch(const QueuedSlowIntent()).catchError((_) {}));
      final f2 = controller.dispatch(const QueuedSlowIntent());

      final expectation = expectLater(f2, throwsA(isA<CancellationException>()));

      // Dispose while queue is blocked
      controller.dispose();

      // Wait for expectation
      await expectation;

      // Cleanup
      final slowCmd = BaseIntentCommand();
      expect(slowCmd.policy, equals(ExecutionPolicy.concurrent));
    });

    testWidgets('CommanderScope.of with listen: true finds and rebuilds', (tester) async {
      final controller = DummyController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyController>.value(
            value: controller,
            child: Builder(
              builder: (context) {
                final c = CommanderScope.of<DummyController>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      await controller.dispatch(const DerivedIntent());
      await tester.pump();

      expect(find.text('Count: 1'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('CommanderScope.of throws FlutterError when scope not found', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                () => CommanderScope.of<DummyController>(context, listen: false),
                throwsA(isA<FlutterError>()),
              );
              expect(
                () => CommanderScope.of<DummyController>(context, listen: true),
                throwsA(isA<FlutterError>()),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('CommanderScope didUpdateWidget updates controller listener', (tester) async {
      final controllerA = DummyController();
      final controllerB = DummyController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyController>.value(
            value: controllerA,
            child: Builder(
              builder: (context) {
                final c = CommanderScope.of<DummyController>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      // Swap controller
      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyController>.value(
            value: controllerB,
            child: Builder(
              builder: (context) {
                final c = CommanderScope.of<DummyController>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      await controllerB.dispatch(const DerivedIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      controllerA.dispose();
      controllerB.dispose();
    });

    testWidgets('CommanderBuilder didUpdateWidget updates controller instance', (tester) async {
      final controller1 = DummyController();
      final controller2 = DummyController();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderBuilder<DummyController, DummyState, int>(
            controller: controller1,
            select: (s) => s.count,
            builder: (context, count) => Text('Count: $count'),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderBuilder<DummyController, DummyState, int>(
            controller: controller2,
            select: (s) => s.count,
            builder: (context, count) => Text('Count: $count'),
          ),
        ),
      );

      await controller2.dispatch(const DerivedIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      controller1.dispose();
      controller2.dispose();
    });

    testWidgets('CommanderListener didUpdateWidget updates controller instance', (tester) async {
      final controller1 = DummyController();
      final controller2 = DummyController();
      var received = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderListener<DummyController, DummyEffect>(
            controller: controller1,
            onEffect: (context, effect) => received++,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderListener<DummyController, DummyEffect>(
            controller: controller2,
            onEffect: (context, effect) => received++,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      controller1.dispose();
      controller2.dispose();
    });

    test('Additional edge cases: contains, isDisposed, TestCommandScope initialState, InlineCommand toString', () {
      final registry = CommandRegistry<DummyState, DummyEffect>();
      registry.registerInline<DerivedIntent>((scope, intent) {});
      expect(registry.contains<DerivedIntent>(), isTrue);
      final inlineCmd = registry.find(const DerivedIntent());
      expect(inlineCmd.toString(), contains('InlineCommand'));

      final testScope = TestCommandScope<DummyState, DummyEffect>(const DummyState(42));
      expect(testScope.initialState, equals(const DummyState(42)));

      final controller = DummyController();
      expect(controller.isDisposed, isFalse);
      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });

    test('Queue processing handles command error gracefully', () async {
      final controller = CommanderControllerWithFailingQueue();
      await expectLater(
        controller.dispatch(const QueuedFailingIntent()),
        throwsA(isA<Exception>()),
      );
      controller.dispose();
    });
  });
}

class QueuedFailingIntent extends CommandIntent {
  const QueuedFailingIntent();
}

class QueuedFailingCommand extends Command<QueuedFailingIntent, DummyState, DummyEffect> {
  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<DummyState, DummyEffect> scope, QueuedFailingIntent intent) async {
    throw Exception('Queue error test');
  }
}

class CommanderControllerWithFailingQueue extends CommanderController<DummyState, DummyEffect> {
  CommanderControllerWithFailingQueue() : super(const DummyState(0)) {
    bind(QueuedFailingCommand());
  }
}
