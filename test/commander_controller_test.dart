import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterState {
  final int value;
  final String label;

  const CounterState({required this.value, required this.label});

  CounterState copyWith({int? value, String? label}) => CounterState(
        value: value ?? this.value,
        label: label ?? this.label,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterState &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          label == other.label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'CounterState(value: $value, label: $label)';
}

sealed class CounterEffect {
  const CounterEffect();
}

class ShowToastEffect extends CounterEffect {
  final String message;
  const ShowToastEffect(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShowToastEffect && runtimeType == other.runtimeType && message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ShowToastEffect(message: $message)';
}

class IncrementIntent extends Intent {
  final int amount;
  const IncrementIntent([this.amount = 1]);
}

class SetLabelIntent extends Intent {
  final String label;
  const SetLabelIntent(this.label);
}

class UnhandledIntent extends Intent {
  const UnhandledIntent();
}

class FailIntent extends Intent {
  const FailIntent();
}

class IncrementCommand extends Command<IncrementIntent, CounterState, CounterEffect> {
  @override
  Future<void> execute(
    CommandScope<CounterState, CounterEffect> scope,
    IncrementIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(value: s.value + intent.amount));
    scope.emitSideEffect(ShowToastEffect('Incremented by ${intent.amount}'));
  }
}

class FailingCommand extends Command<FailIntent, CounterState, CounterEffect> {
  @override
  Future<void> execute(
    CommandScope<CounterState, CounterEffect> scope,
    FailIntent intent,
  ) async {
    throw Exception('Simulated failure');
  }
}

class TestController extends CommanderController<CounterState, CounterEffect> {
  TestController({super.interceptors})
      : super(const CounterState(value: 0, label: 'initial')) {
    bind(IncrementCommand());
    bind(FailingCommand());

    // Inline DSL
    on<SetLabelIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(label: intent.label));
    });
  }
}

class MockInterceptor extends CommandInterceptor {
  final List<String> events = [];

  @override
  void onBeforeExecute(Command<dynamic, dynamic, dynamic> command, Intent intent) {
    events.add('before_${intent.runtimeType}');
  }

  @override
  void onAfterExecute(Command<dynamic, dynamic, dynamic> command, Intent intent) {
    events.add('after_${intent.runtimeType}');
  }

  @override
  void onStateChanged(dynamic oldState, dynamic newState) {
    events.add('state_${newState.runtimeType}');
  }

  @override
  void onEffectEmitted(dynamic effect) {
    events.add('effect_${effect.runtimeType}');
  }

  @override
  void onError(
    Command<dynamic, dynamic, dynamic> command,
    Intent intent,
    Object error,
    StackTrace stackTrace,
  ) {
    events.add('error_${intent.runtimeType}');
  }
}

void main() {
  group('CommanderController', () {
    late TestController controller;
    late MockInterceptor interceptor;

    setUp(() {
      interceptor = MockInterceptor();
      controller = TestController(interceptors: [interceptor]);
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial state and value getters match', () {
      expect(controller.state.value, equals(0));
      expect(controller.value.value, equals(0));
      expect(controller.state.label, equals('initial'));
    });

    test('dispatching registered command updates state and emits effects', () async {
      final effects = <CounterEffect>[];
      final sub = controller.effects.listen(effects.add);

      var notified = 0;
      controller.addListener(() => notified++);

      await controller.dispatch(const IncrementIntent(5));

      expect(controller.state.value, equals(5));
      expect(notified, equals(1));
      expect(effects, [const ShowToastEffect('Incremented by 5')]);

      await sub.cancel();
    });

    test('inline on<I> handler mutates state without separate command class', () async {
      await controller.dispatch(const SetLabelIntent('updated_label'));
      expect(controller.state.label, equals('updated_label'));
    });

    test('dispatching unregistered intent throws UnregisteredIntentException', () async {
      expect(
        () => controller.dispatch(const UnhandledIntent()),
        throwsA(isA<UnregisteredIntentException>()),
      );
    });

    test('identical or equal state does not trigger notifyListeners', () async {
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.dispatch(const SetLabelIntent('initial'));

      expect(notified, equals(0));
    });

    test('interceptors receive complete lifecycle events', () async {
      await controller.dispatch(const IncrementIntent(1));

      expect(interceptor.events, containsAllInOrder([
        'before_IncrementIntent',
        'state_CounterState',
        'effect_ShowToastEffect',
        'after_IncrementIntent',
      ]));
    });

    test('failing command triggers interceptor onError and rethrows', () async {
      await expectLater(
        controller.dispatch(const FailIntent()),
        throwsA(isA<Exception>()),
      );

      expect(interceptor.events, contains('error_FailIntent'));
    });

    test('LoggingCommandInterceptor produces structured output format', () async {
      final logs = <String>[];
      final logger = LoggingCommandInterceptor(printFn: logs.add);
      controller.addInterceptor(logger);

      await controller.dispatch(const IncrementIntent(2));

      expect(
        logs.any((msg) => msg.contains('[flutter_commander] [Intent] IncrementIntent -> [Command] IncrementCommand')),
        isTrue,
      );
      expect(
        logs.any((msg) => msg.contains('[flutter_commander] [State] CounterState(value: 2, label: initial)')),
        isTrue,
      );
      expect(
        logs.any((msg) => msg.contains('[flutter_commander] [Effect] ShowToastEffect(message: Incremented by 2)')),
        isTrue,
      );
    });

    test('dispose marks controller as disposed and cleans up resources', () {
      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });
  });
}
