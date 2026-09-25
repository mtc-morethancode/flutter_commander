import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Test State, Effects & Intents ---

class CounterState {
  final int count;
  final String note;

  const CounterState({this.count = 0, this.note = ''});

  CounterState copyWith({int? count, String? note}) => CounterState(
        count: count ?? this.count,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {'count': count, 'note': note};

  factory CounterState.fromJson(Map<String, dynamic> json) => CounterState(
        count: json['count'] as int? ?? 0,
        note: json['note'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterState &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          note == other.note;

  @override
  int get hashCode => count.hashCode ^ note.hashCode;
}

sealed class CounterEffect {
  const CounterEffect();
}

class IncrementIntent extends CommandIntent {
  const IncrementIntent();
}

class SetNoteIntent extends CommandIntent {
  final String note;
  const SetNoteIntent(this.note);
}

// --- Test Commanders with SavedStateMixin ---

class SyncCounterCommander extends Commander<CounterState, CounterEffect>
    with SavedStateMixin<CounterState, CounterEffect> {
  final SavedStateStore? _customStore;

  SyncCounterCommander({SavedStateStore? store})
      : _customStore = store,
        super(const CounterState()) {
    bind(_IncrementCommand());
    on<SetNoteIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(note: intent.note));
    });
    restoreStateSync();
  }

  @override
  String get savedStateKey => 'sync_counter';

  @override
  SavedStateStore get savedStateStore =>
      _customStore ?? super.savedStateStore;

  @override
  Map<String, dynamic> stateToJson(CounterState state) => state.toJson();

  @override
  CounterState stateFromJson(Map<String, dynamic> json) =>
      CounterState.fromJson(json);
}

class AsyncCounterCommander extends Commander<CounterState, CounterEffect>
    with SavedStateMixin<CounterState, CounterEffect> {
  final SavedStateStore? _customStore;
  final Duration? _debounce;
  final List<Object> caughtErrors = [];

  AsyncCounterCommander({
    SavedStateStore? store,
    Duration? debounce,
  })  : _customStore = store,
        _debounce = debounce,
        super(const CounterState()) {
    bind(_IncrementCommand());
  }

  @override
  String get savedStateKey => 'async_counter';

  @override
  Duration? get persistDebounce => _debounce;

  @override
  SavedStateStore get savedStateStore =>
      _customStore ?? super.savedStateStore;

  @override
  Map<String, dynamic> stateToJson(CounterState state) => state.toJson();

  @override
  CounterState stateFromJson(Map<String, dynamic> json) =>
      CounterState.fromJson(json);

  @override
  void onSavedStateError(Object error, StackTrace stackTrace) {
    caughtErrors.add(error);
    super.onSavedStateError(error, stackTrace);
  }
}

class _IncrementCommand
    extends Command<IncrementIntent, CounterState, CounterEffect> {
  @override
  Future<void> execute(
    CommandScope<CounterState, CounterEffect> scope,
    IncrementIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(count: s.count + 1));
  }
}

// --- Async Mock Store ---

class DelayedSavedStateStore implements SavedStateStore {
  final Map<String, Map<String, dynamic>> _storage = {};
  final Duration delay;
  int writeCount = 0;
  bool shouldThrowOnRead = false;
  bool shouldThrowOnWrite = false;

  DelayedSavedStateStore({this.delay = const Duration(milliseconds: 20)});

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    await Future<void>.delayed(delay);
    if (shouldThrowOnRead) throw Exception('Disk read error');
    final val = _storage[key];
    return val != null ? Map<String, dynamic>.from(val) : null;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    await Future<void>.delayed(delay);
    if (shouldThrowOnWrite) throw Exception('Disk write error');
    writeCount++;
    _storage[key] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> delete(String key) async {
    await Future<void>.delayed(delay);
    _storage.remove(key);
  }
}

void main() {
  setUp(() {
    SavedStateStore.defaultStore = null;
  });

  group('InMemorySavedStateStore', () {
    test('writes, reads, deletes and dumps entries', () {
      final store = InMemorySavedStateStore();

      expect(store.read('test'), isNull);
      expect(store.keys, isEmpty);

      store.write('test', {'count': 42});
      expect(store.read('test'), equals({'count': 42}));
      expect(store.keys, contains('test'));

      final dumped = store.dump();
      expect(dumped['test'], equals({'count': 42}));

      store.delete('test');
      expect(store.read('test'), isNull);

      store.write('k1', {'a': 1});
      store.write('k2', {'b': 2});
      expect(store.keys.length, 2);

      store.clear();
      expect(store.keys, isEmpty);
    });

    test('defensive copies prevent accidental state mutation', () {
      final store = InMemorySavedStateStore();
      final data = {'score': 100};
      store.write('game', data);

      data['score'] = 999;
      expect(store.read('game')?['score'], 100);

      final readData = store.read('game')!;
      readData['score'] = 555;
      expect(store.read('game')?['score'], 100);
    });
  });

  group('SavedStateHandle', () {
    test('stores and restores key-values correctly', () {
      final store = InMemorySavedStateStore();
      final handle = SavedStateHandle(key: 'user_draft', store: store);

      expect(handle.get<String>('name'), isNull);
      expect(handle.containsKey('name'), isFalse);

      handle.set('name', 'Alice');
      handle.set('age', 30);

      expect(handle.get<String>('name'), 'Alice');
      expect(handle.get<int>('age'), 30);
      expect(handle.containsKey('age'), isTrue);
      expect(handle.toMap(), equals({'name': 'Alice', 'age': 30}));

      final removed = handle.remove<String>('name');
      expect(removed, 'Alice');
      expect(handle.containsKey('name'), isFalse);

      handle.clear();
      expect(handle.toMap(), isEmpty);
    });

    test('restores asynchronously from store', () async {
      final store = DelayedSavedStateStore();
      await store.write('session', {'token': 'jwt-12345'});

      final handle = SavedStateHandle(key: 'session', store: store);
      final restored = await handle.restoreAsync();

      expect(restored, isTrue);
      expect(handle.get<String>('token'), 'jwt-12345');
    });
  });

  group('SavedStateMixin - Synchronous Restoration', () {
    test('restores state synchronously when data exists', () {
      final store = InMemorySavedStateStore();
      store.write('sync_counter', {'count': 10, 'note': 'Restored'});

      final commander = SyncCounterCommander(store: store);
      expect(commander.isRestored, isTrue);
      expect(commander.state.count, 10);
      expect(commander.state.note, 'Restored');

      commander.dispose();
    });

    test('persists state update automatically', () async {
      final store = InMemorySavedStateStore();
      final commander = SyncCounterCommander(store: store);

      expect(commander.state.count, 0);

      await commander.dispatch(const IncrementIntent());
      expect(commander.state.count, 1);
      expect(store.read('sync_counter')?['count'], 1);

      await commander.dispatch(const SetNoteIntent('Shopping'));
      expect(commander.state.note, 'Shopping');
      expect(store.read('sync_counter')?['note'], 'Shopping');

      commander.dispose();
    });

    test('clearSavedState removes data from storage', () async {
      final store = InMemorySavedStateStore();
      final commander = SyncCounterCommander(store: store);

      await commander.dispatch(const IncrementIntent());
      expect(store.read('sync_counter'), isNotNull);

      await commander.clearSavedState();
      expect(store.read('sync_counter'), isNull);

      commander.dispose();
    });
  });

  group('SavedStateMixin - Asynchronous Restoration', () {
    test('restores state asynchronously via savedStateReady', () async {
      final store = DelayedSavedStateStore();
      await store.write('async_counter', {'count': 99, 'note': 'Async'});

      final commander = AsyncCounterCommander(store: store);
      expect(commander.isRestored, isFalse);
      expect(commander.state.count, 0); // starts with default

      final result = await commander.savedStateReady;
      expect(result, isTrue);
      expect(commander.isRestored, isTrue);
      expect(commander.state.count, 99);
      expect(commander.state.note, 'Async');

      commander.dispose();
    });

    test('automatic microtask triggers savedStateReady', () async {
      final store = DelayedSavedStateStore();
      await store.write('async_counter', {'count': 42});

      final commander = AsyncCounterCommander(store: store);

      // Wait for delayed store read to complete
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(commander.isRestored, isTrue);
      expect(commander.state.count, 42);

      commander.dispose();
    });

    test('debounces frequent state persist writes', () async {
      final store = DelayedSavedStateStore();
      final commander = AsyncCounterCommander(
        store: store,
        debounce: const Duration(milliseconds: 50),
      );

      // Dispatch 3 updates rapidly
      await commander.dispatch(const IncrementIntent());
      await commander.dispatch(const IncrementIntent());
      await commander.dispatch(const IncrementIntent());

      // Debounce window hasn't passed
      expect(store.writeCount, 0);

      // Wait for debounce duration and async write to finish
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(store.writeCount, 1);
      expect((await store.read('async_counter'))?['count'], 3);

      commander.dispose();
    });

    test('persistState forces immediate write bypassing debounce', () async {
      final store = DelayedSavedStateStore();
      final commander = AsyncCounterCommander(
        store: store,
        debounce: const Duration(milliseconds: 200),
      );

      await commander.dispatch(const IncrementIntent());
      expect(store.writeCount, 0);

      await commander.persistState();
      expect(store.writeCount, 1);
      expect((await store.read('async_counter'))?['count'], 1);

      commander.dispose();
    });
  });

  group('SavedStateMixin - Error Handling & Edge Cases', () {
    test('throws StateError when no store is configured', () {
      expect(
        () => SyncCounterCommander(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No SavedStateStore configured'),
        )),
      );
    });

    test('falls back to SavedStateStore.defaultStore if set', () {
      final defaultStore = InMemorySavedStateStore();
      SavedStateStore.defaultStore = defaultStore;
      defaultStore.write('sync_counter', {'count': 7});

      final commander = SyncCounterCommander();
      expect(commander.state.count, 7);

      commander.dispose();
    });

    test('onSavedStateError catches read and write failures safely', () async {
      final store = DelayedSavedStateStore();
      store.shouldThrowOnWrite = true;

      final commander = AsyncCounterCommander(store: store);
      await commander.dispatch(const IncrementIntent());

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(commander.caughtErrors, isNotEmpty);
      // Ensure commander still functions and state remains in memory
      expect(commander.state.count, 1);

      commander.dispose();
    });

    test('restoreState skips notification if restored state equals current', () {
      final store = InMemorySavedStateStore();
      store.write('sync_counter', {'count': 0, 'note': ''});

      var notificationCount = 0;
      final commander = SyncCounterCommander(store: store);
      commander.addListener(() => notificationCount++);

      // Restoring identical state does not notify listeners
      commander.restoreStateSync();
      expect(notificationCount, 0);

      commander.dispose();
    });
  });

  group('UI Integration with CommanderView', () {
    testWidgets('CommanderView renders restored state immediately',
        (tester) async {
      final store = InMemorySavedStateStore();
      store.write('sync_counter', {'count': 15, 'note': 'Cart Restored'});

      final commander = SyncCounterCommander(store: store);

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<SyncCounterCommander>.value(
            value: commander,
            child: const _TestView(),
          ),
        ),
      );

      expect(find.text('Count: 15'), findsOneWidget);
      expect(find.text('Note: Cart Restored'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Count: 16'), findsOneWidget);
      expect(store.read('sync_counter')?['count'], 16);
    });
  });
}

class _TestView
    extends CommanderView<SyncCounterCommander, CounterState, CounterEffect> {
  const _TestView();

  @override
  Widget build(BuildContext context, CounterState state) {
    return Column(
      children: [
        Text('Count: ${state.count}'),
        Text('Note: ${state.note}'),
        ElevatedButton(
          onPressed: () =>
              context.dispatch<SyncCounterCommander>(const IncrementIntent()),
          child: const Text('+1'),
        ),
      ],
    );
  }
}
