import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_commander/src/commander/command_registry.dart';
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
  Future<void> execute(
      CommandScope<DummyState, DummyEffect> scope, BaseIntent intent) async {
    scope.updateState((s) => DummyState(s.count + 1));
  }
}

class QueuedSlowCommand
    extends Command<QueuedSlowIntent, DummyState, DummyEffect> {
  final Completer<void> completer = Completer<void>();

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<DummyState, DummyEffect> scope,
      QueuedSlowIntent intent) async {
    await completer.future;
  }
}

class DummyCommander extends Commander<DummyState, DummyEffect> {
  DummyCommander() : super(const DummyState(0)) {
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
      expect(
          () => interceptor.onStateChanged(
              const DummyState(0), const DummyState(1)),
          returnsNormally);
      expect(() => interceptor.onEffectEmitted(const DummyEffect()),
          returnsNormally);
      expect(
        () => interceptor.onError(cmd, intent, Exception(), StackTrace.current),
        returnsNormally,
      );
    });

    test('removeInterceptor removes registered interceptor', () async {
      final commander = DummyCommander();
      var logged = 0;
      final logger = LoggingCommandInterceptor(printFn: (_) => logged++);

      commander.addInterceptor(logger);
      await commander.dispatch(const DerivedIntent());
      expect(logged, greaterThan(0));

      final prevLogged = logged;
      commander.removeInterceptor(logger);
      await commander.dispatch(const DerivedIntent());
      expect(logged, equals(prevLogged));

      commander.dispose();
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

    test('CommandRegistry polymorphic subtype resolution and contains check',
        () async {
      final commander = DummyCommander();
      // BaseIntentCommand is registered for BaseIntent, DerivedIntent extends BaseIntent
      await commander.dispatch(const DerivedIntent());
      expect(commander.state.count, equals(1));
      commander.dispose();
    });

    test('Queue cancellation upon commander disposal when items are pending',
        () async {
      final commander = DummyCommander();

      // Dispatch 2 queued intents
      unawaited(
          commander.dispatch(const QueuedSlowIntent()).catchError((_) {}));
      final f2 = commander.dispatch(const QueuedSlowIntent());

      final expectation =
          expectLater(f2, throwsA(isA<CancellationException>()));

      // Dispose while queue is blocked
      commander.dispose();

      // Wait for expectation
      await expectation;

      // Cleanup
      final slowCmd = BaseIntentCommand();
      expect(slowCmd.policy, equals(ExecutionPolicy.concurrent));
    });

    testWidgets('CommanderScope.of with listen: true finds and rebuilds',
        (tester) async {
      final commander = DummyCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyCommander>.value(
            value: commander,
            child: Builder(
              builder: (context) {
                final c =
                    CommanderScope.of<DummyCommander>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      await commander.dispatch(const DerivedIntent());
      await tester.pump();

      expect(find.text('Count: 1'), findsOneWidget);
      commander.dispose();
    });

    testWidgets('CommanderScope.of throws FlutterError when scope not found',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                () => CommanderScope.of<DummyCommander>(context, listen: false),
                throwsA(isA<FlutterError>()),
              );
              expect(
                () => CommanderScope.of<DummyCommander>(context, listen: true),
                throwsA(isA<FlutterError>()),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('CommanderScope didUpdateWidget updates commander listener',
        (tester) async {
      final commanderA = DummyCommander();
      final commanderB = DummyCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyCommander>.value(
            value: commanderA,
            child: Builder(
              builder: (context) {
                final c =
                    CommanderScope.of<DummyCommander>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      // Swap commander
      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DummyCommander>.value(
            value: commanderB,
            child: Builder(
              builder: (context) {
                final c =
                    CommanderScope.of<DummyCommander>(context, listen: true);
                return Text('Count: ${c.state.count}');
              },
            ),
          ),
        ),
      );

      await commanderB.dispatch(const DerivedIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      commanderA.dispose();
      commanderB.dispose();
    });

    testWidgets('CommanderBuilder didUpdateWidget updates commander instance',
        (tester) async {
      final commander1 = DummyCommander();
      final commander2 = DummyCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderBuilder<DummyCommander, DummyState, int>(
            commander: commander1,
            select: (s) => s.count,
            builder: (context, count) => Text('Count: $count'),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderBuilder<DummyCommander, DummyState, int>(
            commander: commander2,
            select: (s) => s.count,
            builder: (context, count) => Text('Count: $count'),
          ),
        ),
      );

      await commander2.dispatch(const DerivedIntent());
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      commander1.dispose();
      commander2.dispose();
    });

    testWidgets('CommanderListener didUpdateWidget updates commander instance',
        (tester) async {
      final commander1 = DummyCommander();
      final commander2 = DummyCommander();
      var received = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderListener<DummyCommander, DummyEffect>(
            commander: commander1,
            onEffect: (context, effect) => received++,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderListener<DummyCommander, DummyEffect>(
            commander: commander2,
            onEffect: (context, effect) => received++,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      commander1.dispose();
      commander2.dispose();
    });

    test(
        'Additional edge cases: contains, isDisposed, TestCommandScope initialState, InlineCommand toString',
        () {
      final registry = CommandRegistry<DummyState, DummyEffect>();
      registry.registerInline<DerivedIntent>((scope, intent) {});
      expect(registry.contains<DerivedIntent>(), isTrue);
      final inlineCmd = registry.find(const DerivedIntent());
      expect(inlineCmd.toString(), contains('InlineCommand'));

      final testScope =
          TestCommandScope<DummyState, DummyEffect>(const DummyState(42));
      expect(testScope.initialState, equals(const DummyState(42)));

      final commander = DummyCommander();
      expect(commander.isDisposed, isFalse);
      commander.dispose();
      expect(commander.isDisposed, isTrue);
    });

    test('Queue processing handles command error gracefully', () async {
      final commander = CommanderWithFailingQueue();
      await expectLater(
        commander.dispatch(const QueuedFailingIntent()),
        throwsA(isA<Exception>()),
      );
      commander.dispose();
    });
  });
}

class QueuedFailingIntent extends CommandIntent {
  const QueuedFailingIntent();
}

class QueuedFailingCommand
    extends Command<QueuedFailingIntent, DummyState, DummyEffect> {
  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<DummyState, DummyEffect> scope,
      QueuedFailingIntent intent) async {
    throw Exception('Queue error test');
  }
}

class CommanderWithFailingQueue extends Commander<DummyState, DummyEffect> {
  CommanderWithFailingQueue() : super(const DummyState(0)) {
    bind(QueuedFailingCommand());
  }
}
