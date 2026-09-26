import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_commander/src/commander/command_registry.dart';
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
      other is ShowToastEffect &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ShowToastEffect(message: $message)';
}

class IncrementIntent extends CommandIntent {
  final int amount;
  const IncrementIntent([this.amount = 1]);
}

class SpecialIncrementIntent extends IncrementIntent {
  const SpecialIncrementIntent([super.amount = 1]);
}

class SetLabelIntent extends CommandIntent {
  final String label;
  const SetLabelIntent(this.label);
}

class UnhandledIntent extends CommandIntent {
  const UnhandledIntent();
}

class FailIntent extends CommandIntent {
  const FailIntent();
}

class IncrementCommand
    extends Command<IncrementIntent, CounterState, CounterEffect> {
  @override
  Future<void> execute(
    CommandScope<CounterState, CounterEffect> scope,
    IncrementIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(value: s.value + intent.amount));
    scope.emitSideEffect(ShowToastEffect('Incremented by ${intent.amount}'));
  }
}

class SpecialIncrementCommand
    extends Command<SpecialIncrementIntent, CounterState, CounterEffect> {
  @override
  Future<void> execute(
    CommandScope<CounterState, CounterEffect> scope,
    SpecialIncrementIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(value: s.value + intent.amount * 2));
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

class TestCommander extends Commander<CounterState, CounterEffect> {
  TestCommander({super.interceptors})
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
  void onBeforeExecute(
      Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {
    events.add('before_${intent.runtimeType}');
  }

  @override
  void onAfterExecute(
      Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {
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
    CommandIntent intent,
    Object error,
    StackTrace stackTrace,
  ) {
    events.add('error_${intent.runtimeType}');
  }
}

void main() {
  group('Commander', () {
    late TestCommander commander;
    late MockInterceptor interceptor;

    setUp(() {
      interceptor = MockInterceptor();
      commander = TestCommander(interceptors: [interceptor]);
    });

    tearDown(() {
      commander.dispose();
    });

    test('initial state and value getters match', () {
      expect(commander.state.value, equals(0));
      expect(commander.value.value, equals(0));
      expect(commander.state.label, equals('initial'));
    });

    test('dispatching registered command updates state and emits effects',
        () async {
      final effects = <CounterEffect>[];
      final sub = commander.effects.listen(effects.add);

      var notified = 0;
      commander.addListener(() => notified++);

      await commander.dispatch(const IncrementIntent(5));

      expect(commander.state.value, equals(5));
      expect(notified, equals(1));
      expect(effects, [const ShowToastEffect('Incremented by 5')]);

      await sub.cancel();
    });

    test('inline on<I> handler mutates state without separate command class',
        () async {
      await commander.dispatch(const SetLabelIntent('updated_label'));
      expect(commander.state.label, equals('updated_label'));
    });

    test('dispatching unregistered intent throws UnregisteredIntentException',
        () async {
      expect(
        () => commander.dispatch(const UnhandledIntent()),
        throwsA(isA<UnregisteredIntentException>()),
      );
    });

    test('identical or equal state does not trigger notifyListeners', () async {
      var notified = 0;
      commander.addListener(() => notified++);

      await commander.dispatch(const SetLabelIntent('initial'));

      expect(notified, equals(0));
    });

    test('interceptors receive complete lifecycle events', () async {
      await commander.dispatch(const IncrementIntent(1));

      expect(
          interceptor.events,
          containsAllInOrder([
            'before_IncrementIntent',
            'state_CounterState',
            'effect_ShowToastEffect',
            'after_IncrementIntent',
          ]));
    });

    test('failing command triggers interceptor onError and rethrows', () async {
      await expectLater(
        commander.dispatch(const FailIntent()),
        throwsA(isA<Exception>()),
      );

      expect(interceptor.events, contains('error_FailIntent'));
    });

    test('LoggingCommandInterceptor produces structured output format',
        () async {
      final logs = <String>[];
      final logger = LoggingCommandInterceptor(printFn: logs.add);
      commander.addInterceptor(logger);

      await commander.dispatch(const IncrementIntent(2));

      expect(
        logs.any((msg) => msg.contains(
            '[flutter_commander] [Intent] IncrementIntent -> [Command] IncrementCommand')),
        isTrue,
      );
      expect(
        logs.any((msg) => msg.contains(
            '[flutter_commander] [State] CounterState(value: 2, label: initial)')),
        isTrue,
      );
      expect(
        logs.any((msg) => msg.contains(
            '[flutter_commander] [Effect] ShowToastEffect(message: Incremented by 2)')),
        isTrue,
      );
    });

    test('dispose marks commander as disposed and cleans up resources', () {
      commander.dispose();
      expect(commander.isDisposed, isTrue);
    });

    test('cold-start side effects are buffered and replayed on first listen',
        () async {
      final freshCommander = TestCommander();

      // Emit effect while NO listener is connected
      await freshCommander.dispatch(const IncrementIntent(5));

      // Now attach listener
      final received = <CounterEffect>[];
      final sub = freshCommander.effects.listen(received.add);

      // Wait for microtask flush
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(
        received.first,
        equals(const ShowToastEffect('Incremented by 5')),
      );

      // Subsequent effects while listener is active are received immediately
      await freshCommander.dispatch(const IncrementIntent(1));
      expect(received, hasLength(2));
      expect(
        received.last,
        equals(const ShowToastEffect('Incremented by 1')),
      );

      await sub.cancel();
      freshCommander.dispose();
    });

    test('cold-start buffer clears pending effects on dispose', () async {
      final freshCommander = TestCommander();
      await freshCommander.dispatch(const IncrementIntent(5));
      freshCommander.dispose();

      final received = <CounterEffect>[];
      final sub = freshCommander.effects.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test(
        'CommandRegistry caches polymorphic resolution for O(1) subsequent lookups',
        () {
      final registry = CommandRegistry<CounterState, CounterEffect>();
      final cmd = IncrementCommand();
      registry.register<IncrementIntent>(cmd);

      // First lookup performs match and caches
      final first = registry.find(const IncrementIntent(1));
      expect(identical(first, cmd), isTrue);

      // Second lookup hits exact cache
      final second = registry.find(const IncrementIntent(2));
      expect(identical(second, cmd), isTrue);
    });

    test(
        'CommandRegistry re-registration clears stale polymorphic cache and replaces previous entry',
        () {
      final registry = CommandRegistry<CounterState, CounterEffect>();
      final cmd1 = IncrementCommand();
      final cmd2 = IncrementCommand();

      registry.register<IncrementIntent>(cmd1);

      // Polymorphically resolve SpecialIncrementIntent and cache it
      final firstLookup = registry.find(const SpecialIncrementIntent(1));
      expect(identical(firstLookup, cmd1), isTrue);

      // Re-register IncrementIntent with cmd2 (e.g. test mock or hot reload)
      registry.register<IncrementIntent>(cmd2);

      // Stale cache must be purged; SpecialIncrementIntent must now resolve to cmd2
      final secondLookup = registry.find(const SpecialIncrementIntent(1));
      expect(identical(secondLookup, cmd2), isTrue);

      // Direct exact match must also resolve to cmd2
      final directLookup = registry.find(const IncrementIntent(1));
      expect(identical(directLookup, cmd2), isTrue);
    });

    test(
        'Registering specific subtype command overrides previously cached parent polymorphic lookup',
        () {
      final registry = CommandRegistry<CounterState, CounterEffect>();
      final parentCmd = IncrementCommand();
      final specificCmd = SpecialIncrementCommand();

      registry.register<IncrementIntent>(parentCmd);

      // Resolve SpecialIncrementIntent using parent command and cache it
      final cachedLookup = registry.find(const SpecialIncrementIntent(1));
      expect(identical(cachedLookup, parentCmd), isTrue);

      // Now register specific command for SpecialIncrementIntent
      registry.register<SpecialIncrementIntent>(specificCmd);

      // Cache must be invalidated, resolving to specific command
      final overrideLookup = registry.find(const SpecialIncrementIntent(1));
      expect(identical(overrideLookup, specificCmd), isTrue);

      // Parent intent still resolves to parent command
      final parentLookup = registry.find(const IncrementIntent(1));
      expect(identical(parentLookup, parentCmd), isTrue);
    });
  });
}
