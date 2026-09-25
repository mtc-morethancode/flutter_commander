import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test domain models
class PersistState {
  final int count;
  final String note;
  const PersistState({required this.count, required this.note});

  PersistState copyWith({int? count, String? note}) => PersistState(
        count: count ?? this.count,
        note: note ?? this.note,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistState && count == other.count && note == other.note;

  @override
  int get hashCode => Object.hash(count, note);
}

class PersistEffect {
  final String message;
  const PersistEffect(this.message);
}

class IncPersistIntent extends CommandIntent {
  const IncPersistIntent();
}

class EmitEffectIntent extends CommandIntent {
  final String text;
  const EmitEffectIntent(this.text);
}

// Delayed async store to simulate disk latency
class DelayedAsyncStore implements SavedStateStore {
  final Map<String, Map<String, dynamic>> _storage = {};
  final Duration delay;

  DelayedAsyncStore([this.delay = const Duration(milliseconds: 30)]);

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    await Future<void>.delayed(delay);
    return _storage[key];
  }

  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    await Future<void>.delayed(delay);
    _storage[key] = data;
  }

  @override
  Future<void> delete(String key) async {
    await Future<void>.delayed(delay);
    _storage.remove(key);
  }
}

// Commander with default conflict resolution (keeps user in-flight state)
class DefaultConflictCommander extends Commander<PersistState, PersistEffect>
    with SavedStateMixin<PersistState, PersistEffect> {
  final SavedStateStore _store;

  DefaultConflictCommander(this._store)
      : super(const PersistState(count: 0, note: 'initial')) {
    on<IncPersistIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });
    on<EmitEffectIntent>((scope, intent) {
      scope.emitSideEffect(PersistEffect(intent.text));
    });
  }

  @override
  String get savedStateKey => 'default_conflict_key';

  @override
  SavedStateStore get savedStateStore => _store;

  @override
  Map<String, dynamic> stateToJson(PersistState state) =>
      {'count': state.count, 'note': state.note};

  @override
  PersistState stateFromJson(Map<String, dynamic> json) => PersistState(
        count: json['count'] as int? ?? 0,
        note: json['note'] as String? ?? '',
      );
}

// Commander with custom conflict resolution merging disk note with in-memory count
class MergingConflictCommander extends Commander<PersistState, PersistEffect>
    with SavedStateMixin<PersistState, PersistEffect> {
  final SavedStateStore _store;

  MergingConflictCommander(this._store)
      : super(const PersistState(count: 0, note: 'initial')) {
    on<IncPersistIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });
  }

  @override
  String get savedStateKey => 'merging_conflict_key';

  @override
  SavedStateStore get savedStateStore => _store;

  @override
  Map<String, dynamic> stateToJson(PersistState state) =>
      {'count': state.count, 'note': state.note};

  @override
  PersistState stateFromJson(Map<String, dynamic> json) => PersistState(
        count: json['count'] as int? ?? 0,
        note: json['note'] as String? ?? '',
      );

  @override
  PersistState resolveRestorationConflict(
      PersistState diskState, PersistState currentState) {
    // Preserve fresh user count but incorporate note from disk
    return currentState.copyWith(note: diskState.note);
  }
}

// Test views for active route ghost effect testing
class ScreenAView extends CommanderView<DefaultConflictCommander, PersistState,
    PersistEffect> {
  final List<String> receivedEffects;

  const ScreenAView({super.key, required this.receivedEffects});

  @override
  void onEffect(BuildContext context, PersistEffect effect) {
    receivedEffects.add('ScreenA: ${effect.message}');
  }

  @override
  Widget build(BuildContext context, PersistState state) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen A')),
      body: Center(
        child: ElevatedButton(
          key: const Key('btn_open_b'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScreenBView()),
            );
          },
          child: const Text('Go to Screen B'),
        ),
      ),
    );
  }
}

class ScreenBView extends StatelessWidget {
  const ScreenBView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen B')),
      body: const Center(child: Text('Screen B Content')),
    );
  }
}

void main() {
  group('Phase 1 Production Hardening', () {
    test(
        '1. SavedStateMixin protects in-flight user mutations from stale async disk restore',
        () async {
      final store = DelayedAsyncStore(const Duration(milliseconds: 30));
      // Pre-populate disk with count = 100
      await store
          .write('default_conflict_key', {'count': 100, 'note': 'saved'});

      // Create commander (starts at 0, schedules async read of 100)
      final commander = DefaultConflictCommander(store);
      expect(commander.isDirty, isFalse);

      // User interacts immediately (frame 0) before disk read finishes:
      await commander.dispatch(const IncPersistIntent());
      expect(commander.state.count, equals(1));
      expect(commander.isDirty, isTrue);

      // Wait for slow async disk restore to finish
      final success = await commander.savedStateReady;
      expect(success, isTrue);

      // Verify the user's fresh change was NOT discarded by stale disk state!
      expect(commander.state.count, equals(1),
          reason:
              'In-flight user mutation must not be overwritten by delayed disk restore.');

      commander.dispose();
    });

    test(
        '2. SavedStateMixin resolveRestorationConflict allows selective merging on conflict',
        () async {
      final store = DelayedAsyncStore(const Duration(milliseconds: 30));
      await store
          .write('merging_conflict_key', {'count': 88, 'note': 'disk_note'});

      final commander = MergingConflictCommander(store);

      // User increments count in memory before restore completes:
      await commander.dispatch(const IncPersistIntent());
      expect(commander.state.count, equals(1));
      expect(commander.state.note, equals('initial'));

      // Wait for restore to complete
      await commander.savedStateReady;

      // Merging hook preserved in-flight count (1) and merged disk note ('disk_note')
      expect(commander.state.count, equals(1));
      expect(commander.state.note, equals('disk_note'));

      commander.dispose();
    });

    testWidgets(
        '3. CommanderView with listenOnlyWhenActive skips ghost side-effects while covered by Navigator.push',
        (tester) async {
      final store = DelayedAsyncStore(Duration.zero);
      final commander = DefaultConflictCommander(store);
      final effectsLog = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DefaultConflictCommander>.value(
            value: commander,
            child: ScreenAView(receivedEffects: effectsLog),
          ),
        ),
      );

      expect(find.text('Screen A'), findsOneWidget);

      // Emit effect while Screen A is active: Screen A must receive it
      await commander.dispatch(const EmitEffectIntent('Effect 1'));
      await tester.pump();
      expect(effectsLog, equals(['ScreenA: Effect 1']));

      // Navigate to Screen B (Screen A is now covered in the backstack)
      await tester.tap(find.byKey(const Key('btn_open_b')));
      await tester.pumpAndSettle();

      expect(find.text('Screen B Content'), findsOneWidget);

      // Emit effect while Screen B is top-most and covering Screen A:
      // Screen A must IGNORE this effect (no ghost side-effects)!
      await commander.dispatch(const EmitEffectIntent('Effect 2 (Covered)'));
      await tester.pump();
      expect(effectsLog, equals(['ScreenA: Effect 1']),
          reason:
              'Covered Screen A must not receive side effects while inactive.');

      // Pop Screen B to return to Screen A
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.text('Screen A'), findsOneWidget);

      // Now Screen A is top-most again and receives new effects
      await commander.dispatch(const EmitEffectIntent('Effect 3 (Restored)'));
      await tester.pump();
      expect(
        effectsLog,
        equals(['ScreenA: Effect 1', 'ScreenA: Effect 3 (Restored)']),
      );

      commander.dispose();
    });

    testWidgets(
        '4. CommanderListener with listenOnlyWhenActive respects modal route activity',
        (tester) async {
      final store = DelayedAsyncStore(Duration.zero);
      final commander = DefaultConflictCommander(store);
      final listenerEffects = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CommanderScope<DefaultConflictCommander>.value(
            value: commander,
            child: Scaffold(
              body: CommanderListener<DefaultConflictCommander, PersistEffect>(
                listenOnlyWhenActive: true,
                onEffect: (ctx, e) => listenerEffects.add(e.message),
                child: Builder(
                  builder: (context) => ElevatedButton(
                    key: const Key('open_dialog'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Text('Modal Screen'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Top-most: receives effect
      await commander.dispatch(const EmitEffectIntent('Initial'));
      await tester.pump();
      expect(listenerEffects, equals(['Initial']));

      // Push route on top
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      expect(find.text('Modal Screen'), findsOneWidget);

      // While covered: ignored
      await commander.dispatch(const EmitEffectIntent('Ignored while covered'));
      await tester.pump();
      expect(listenerEffects, equals(['Initial']));

      // Pop route
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // Top-most again: receives effect
      await commander.dispatch(const EmitEffectIntent('Resumed'));
      await tester.pump();
      expect(listenerEffects, equals(['Initial', 'Resumed']));

      commander.dispose();
    });
  });
}
