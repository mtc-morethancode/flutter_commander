import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Domain model for multi-selector testing
class UserProfileState {
  final String firstName;
  final String lastName;
  final int age;

  const UserProfileState({
    required this.firstName,
    required this.lastName,
    required this.age,
  });

  UserProfileState copyWith({
    String? firstName,
    String? lastName,
    int? age,
  }) =>
      UserProfileState(
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        age: age ?? this.age,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileState &&
          firstName == other.firstName &&
          lastName == other.lastName &&
          age == other.age;

  @override
  int get hashCode => Object.hash(firstName, lastName, age);
}

class ChangeFirstNameIntent extends CommandIntent {
  final String firstName;
  const ChangeFirstNameIntent(this.firstName);
}

class ChangeLastNameIntent extends CommandIntent {
  final String lastName;
  const ChangeLastNameIntent(this.lastName);
}

class ChangeAgeIntent extends CommandIntent {
  final int age;
  const ChangeAgeIntent(this.age);
}

class UserProfileCommander extends Commander<UserProfileState, String> {
  UserProfileCommander()
      : super(const UserProfileState(
          firstName: 'John',
          lastName: 'Doe',
          age: 30,
        )) {
    on<ChangeFirstNameIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(firstName: intent.firstName));
    });
    on<ChangeLastNameIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(lastName: intent.lastName));
    });
    on<ChangeAgeIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(age: intent.age));
    });
  }
}

// Domain model for debounced persistence & undo/redo
class CounterPersistenceState {
  final int count;
  const CounterPersistenceState(this.count);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterPersistenceState && count == other.count;

  @override
  int get hashCode => count.hashCode;
}

class IncCounterIntent extends CommandIntent {
  const IncCounterIntent();
}

class DebouncedPersistenceCommander
    extends Commander<CounterPersistenceState, void>
    with SavedStateMixin<CounterPersistenceState, void> {
  final SavedStateStore _store;

  DebouncedPersistenceCommander(this._store)
      : super(const CounterPersistenceState(0)) {
    on<IncCounterIntent>((scope, intent) {
      scope.updateState((s) => CounterPersistenceState(s.count + 1));
    });
  }

  @override
  String get savedStateKey => 'debounced_key';

  @override
  SavedStateStore get savedStateStore => _store;

  @override
  Duration get persistDebounce => const Duration(milliseconds: 500);

  @override
  Map<String, dynamic> stateToJson(CounterPersistenceState state) =>
      {'count': state.count};

  @override
  CounterPersistenceState stateFromJson(Map<String, dynamic> json) =>
      CounterPersistenceState(json['count'] as int? ?? 0);
}

class UndoRedoPersistenceCommander
    extends Commander<CounterPersistenceState, void>
    with
        SavedStateMixin<CounterPersistenceState, void>,
        UndoRedoMixin<CounterPersistenceState, void> {
  final SavedStateStore _store;

  UndoRedoPersistenceCommander(this._store)
      : super(const CounterPersistenceState(0)) {
    on<IncCounterIntent>((scope, intent) {
      scope.updateState((s) => CounterPersistenceState(s.count + 1));
    });
  }

  @override
  String get savedStateKey => 'undo_redo_key';

  @override
  SavedStateStore get savedStateStore => _store;

  @override
  Map<String, dynamic> stateToJson(CounterPersistenceState state) =>
      {'count': state.count};

  @override
  CounterPersistenceState stateFromJson(Map<String, dynamic> json) =>
      CounterPersistenceState(json['count'] as int? ?? 0);
}

class BufferedEffectCommander extends Commander<int, String> {
  BufferedEffectCommander() : super(0) {
    on<ChangeAgeIntent>((scope, intent) {
      scope.emitSideEffect('Age: ${intent.age}');
    });
  }
}

class BufferViewTestWidget
    extends CommanderView<BufferedEffectCommander, int, String> {
  final List<String> receivedEffects;

  const BufferViewTestWidget({
    super.key,
    super.commander,
    required this.receivedEffects,
  });

  @override
  bool get listenOnlyWhenActive => true;

  @override
  bool get bufferWhileInactive => true;

  @override
  void onEffect(BuildContext context, String effect) {
    receivedEffects.add(effect);
  }

  @override
  Widget build(BuildContext context, int state) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Text('Screen A: $state'),
            ElevatedButton(
              key: const Key('open_screen_b'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Text('Screen B Modal Content'),
                    ),
                  ),
                );
              },
              child: const Text('Open B'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('Architectural Hardening - Sprint 1: Selection Ergonomics & Isolation',
      () {
    testWidgets(
        'Multiple context.select calls of the SAME return type in the SAME widget do NOT collide without aspectKey',
        (tester) async {
      final commander = UserProfileCommander();
      int buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<UserProfileCommander>.value(
            value: commander,
            child: Builder(
              builder: (context) {
                buildCount++;
                // Two selectors of the same slice type (String) without aspectKey
                final first = context
                    .select((UserProfileCommander c) => c.state.firstName);
                final last = context
                    .select((UserProfileCommander c) => c.state.lastName);
                return Text('$first $last');
              },
            ),
          ),
        ),
      );

      expect(find.text('John Doe'), findsOneWidget);
      expect(buildCount, equals(1));

      // 1. Mutate ONLY firstName: widget must rebuild and show updated first name
      await commander.dispatch(const ChangeFirstNameIntent('Jane'));
      await tester.pump();
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(buildCount, equals(2));

      // 2. Mutate ONLY lastName: widget must rebuild and show updated last name
      await commander.dispatch(const ChangeLastNameIntent('Smith'));
      await tester.pump();
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(buildCount, equals(3));

      // 3. Mutate unrelated property (age): widget must NOT rebuild
      await commander.dispatch(const ChangeAgeIntent(31));
      await tester.pump();
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(buildCount, equals(3));

      commander.dispose();
    });

    testWidgets(
        'context.selectState preserves 3-generic backward compatibility',
        (tester) async {
      final commander = UserProfileCommander();

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<UserProfileCommander>.value(
            value: commander,
            child: Builder(
              builder: (context) {
                final age = context.selectState<UserProfileCommander,
                    UserProfileState, int>((s) => s.age);
                return Text('Age: $age');
              },
            ),
          ),
        ),
      );

      expect(find.text('Age: 30'), findsOneWidget);

      await commander.dispatch(const ChangeAgeIntent(35));
      await tester.pump();
      expect(find.text('Age: 35'), findsOneWidget);

      commander.dispose();
    });
  });

  group(
      'Architectural Hardening - Sprint 2: Persistence & Lifecycle Synchronization',
      () {
    test('SavedStateMixin flushes pending debounced writes on dispose()',
        () async {
      final store = InMemorySavedStateStore();
      final commander = DebouncedPersistenceCommander(store);

      // Verify store empty initially
      expect(store.read('debounced_key'), isNull);

      // Mutate state (starts 500ms debounce timer)
      await commander.dispatch(const IncCounterIntent());
      expect(commander.state.count, equals(1));

      // Store is still null because 500ms debounce hasn't elapsed
      expect(store.read('debounced_key'), isNull);

      // Abruptly dispose commander (simulating screen pop/unmount)
      commander.dispose();

      // State MUST have been flushed to store!
      final saved = store.read('debounced_key');
      expect(saved, isNotNull);
      expect(saved!['count'], equals(1));
    });

    test(
        'SavedStateMixin automatically synchronizes disk when UndoRedoMixin reverts state',
        () async {
      final store = InMemorySavedStateStore();
      final commander = UndoRedoPersistenceCommander(store);

      // 1. Advance state: 0 -> 1 -> 2
      await commander.dispatch(const IncCounterIntent());
      await commander.dispatch(const IncCounterIntent());
      expect(commander.state.count, equals(2));

      // Store reflects current state (2)
      expect(store.read('undo_redo_key')!['count'], equals(2));

      // 2. Perform undo: in-memory state reverts to 1
      commander.undo();
      expect(commander.state.count, equals(1));

      // Store MUST be updated to reflect the undone state (1), not left stale at 2!
      final restoredFromDisk = store.read('undo_redo_key');
      expect(restoredFromDisk, isNotNull);
      expect(restoredFromDisk!['count'], equals(1));

      // 3. Perform redo: in-memory state returns to 2
      commander.redo();
      expect(commander.state.count, equals(2));
      expect(store.read('undo_redo_key')!['count'], equals(2));

      commander.dispose();
    });

    test(
        'SavedStateHandle serializes rapid concurrent async writes without corruption',
        () async {
      final store = InMemorySavedStateStore();
      final handle = SavedStateHandle(key: 'concurrent_handle', store: store);

      // Rapidly write 10 keys asynchronously
      for (var i = 1; i <= 10; i++) {
        handle.set('counter', i);
      }

      // Small delay to ensure all async chained writes complete
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final persisted = store.read('concurrent_handle');
      expect(persisted, isNotNull);
      expect(persisted!['counter'], equals(10));
    });
  });

  group('Architectural Hardening - Sprint 3: Route-Aware Side-Effect Buffering',
      () {
    testWidgets(
        'CommanderListener with bufferWhileInactive retains effects while covered and flushes on reactivation',
        (tester) async {
      final commander = BufferedEffectCommander();
      final receivedEffects = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<BufferedEffectCommander>.value(
            value: commander,
            child: Scaffold(
              body: CommanderListener<BufferedEffectCommander, String>(
                listenOnlyWhenActive: true,
                bufferWhileInactive: true,
                onEffect: (ctx, effect) => receivedEffects.add(effect),
                child: Builder(
                  builder: (context) => ElevatedButton(
                    key: const Key('open_modal'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Text('Modal Screen Content'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Initial effect delivered while active
      await commander.dispatch(const ChangeAgeIntent(20));
      await tester.pump();
      expect(receivedEffects, equals(['Age: 20']));

      // 2. Open modal screen (covering listener in backstack)
      await tester.tap(find.byKey(const Key('open_modal')));
      await tester.pumpAndSettle();
      expect(find.text('Modal Screen Content'), findsOneWidget);

      // 3. Emit effect while covered: listener must NOT execute yet (no ghost effect)
      await commander.dispatch(const ChangeAgeIntent(21));
      await tester.pump();
      expect(receivedEffects, equals(['Age: 20']));

      // 4. Pop modal screen (resuming Screen A)
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // Buffered effect MUST have flushed cleanly upon reactivation!
      expect(receivedEffects, equals(['Age: 20', 'Age: 21']));

      commander.dispose();
    });

    testWidgets(
        'CommanderView with bufferWhileInactive retains effects while covered and flushes on reactivation',
        (tester) async {
      final commander = BufferedEffectCommander();
      final effects = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<BufferedEffectCommander>.value(
            value: commander,
            child: BufferViewTestWidget(
              commander: commander,
              receivedEffects: effects,
            ),
          ),
        ),
      );

      expect(find.text('Screen A: 0'), findsOneWidget);

      // Open Screen B
      await tester.tap(find.byKey(const Key('open_screen_b')));
      await tester.pumpAndSettle();
      expect(find.text('Screen B Modal Content'), findsOneWidget);

      // Emit effect while inactive
      await commander.dispatch(const ChangeAgeIntent(99));
      await tester.pump();
      expect(effects, isEmpty);

      // Pop Screen B to reactivate Screen A
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // Effect must be delivered now that Screen A is top-most
      expect(effects, equals(['Age: 99']));

      commander.dispose();
    });
  });
}
