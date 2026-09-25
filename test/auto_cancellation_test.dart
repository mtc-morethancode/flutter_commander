import 'dart:async';

import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test domain models
class SearchState {
  final bool isLoading;
  final String query;
  final List<String> results;

  const SearchState({
    required this.isLoading,
    required this.query,
    required this.results,
  });

  factory SearchState.initial() => const SearchState(
        isLoading: false,
        query: '',
        results: [],
      );

  SearchState copyWith({
    bool? isLoading,
    String? query,
    List<String>? results,
  }) {
    return SearchState(
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
      results: results ?? this.results,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          isLoading == other.isLoading &&
          query == other.query &&
          results.length == other.results.length;

  @override
  int get hashCode => Object.hash(isLoading, query, results.length);
}

class SearchEffect {
  final String message;
  const SearchEffect(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchEffect && message == other.message;

  @override
  int get hashCode => message.hashCode;
}

class SearchIntent extends CommandIntent {
  final String query;
  const SearchIntent(this.query);
}

class SleepIntent extends CommandIntent {
  final Duration duration;
  const SleepIntent(this.duration);
}

class StreamIntent extends CommandIntent {
  const StreamIntent();
}

class MockSearchApi {
  final Map<String, Completer<List<String>>> inFlight = {};

  Future<List<String>> search(String query) {
    final completer = Completer<List<String>>();
    inFlight[query] = completer;
    return completer.future;
  }
}

class SearchCommander extends Commander<SearchState, SearchEffect> {
  final MockSearchApi api;
  final StreamController<int>? testStreamController;
  final List<String> cleanupCalls = [];
  final List<Object> caughtErrors = [];

  SearchCommander({
    required this.api,
    this.testStreamController,
  }) : super(SearchState.initial()) {
    // 1. Restartable search command using scope.race
    on<SearchIntent>(
      (scope, intent) async {
        scope.updateState((s) => s.copyWith(isLoading: true, query: intent.query));

        // Register custom resource cleanup
        final detach = scope.attach(() {
          cleanupCalls.add('aborted_${intent.query}');
        });

        final results = await scope.race(api.search(intent.query));
        detach();

        scope.updateState((s) => s.copyWith(isLoading: false, results: results));
        scope.emitSideEffect(SearchEffect('Found ${results.length} for ${intent.query}'));
      },
      policy: ExecutionPolicy.restart,
    );

    // 2. Sleep command using scope.sleep
    on<SleepIntent>(
      (scope, intent) async {
        scope.updateState((s) => s.copyWith(isLoading: true));
        await scope.sleep(intent.duration);
        scope.updateState((s) => s.copyWith(isLoading: false));
      },
      policy: ExecutionPolicy.restart,
    );

    // 3. Stream subscription command using scope.forEach
    if (testStreamController != null) {
      on<StreamIntent>(
        (scope, intent) async {
          await scope.forEach<int>(
            testStreamController!.stream,
            onData: (value) {
              scope.updateState(
                (s) => s.copyWith(results: [...s.results, 'item_$value']),
              );
            },
          );
        },
        policy: ExecutionPolicy.restart,
      );
    }
  }

  @override
  void onError(
    Object error,
    StackTrace stackTrace,
    CommandIntent intent,
  ) {
    caughtErrors.add(error);
    super.onError(error, stackTrace, intent);
  }
}

void main() {
  group('Auto-Cancellation Integration Tests', () {
    test('ExecutionPolicy.restart auto-aborts previous in-flight task via scope.race',
        () async {
      final api = MockSearchApi();
      final commander = SearchCommander(api: api);
      final effects = <SearchEffect>[];
      commander.effects.listen(effects.add);

      // 1. Dispatch first search: 'flutt'
      unawaited(commander.dispatch(const SearchIntent('flutt')));
      await Future<void>.delayed(Duration.zero);

      expect(commander.state.isLoading, isTrue);
      expect(commander.state.query, equals('flutt'));
      expect(api.inFlight.containsKey('flutt'), isTrue);

      // 2. Dispatch second search: 'flutter' before first completes
      unawaited(commander.dispatch(const SearchIntent('flutter')));
      await Future<void>.delayed(Duration.zero);

      expect(commander.state.query, equals('flutter'));
      expect(commander.cleanupCalls, contains('aborted_flutt'));

      // 3. Complete the first (cancelled) API call late in background
      api.inFlight['flutt']!.complete(['stale_1', 'stale_2']);
      await Future<void>.delayed(Duration.zero);

      // The stale response must NOT update state or emit side-effects
      expect(commander.state.results, isEmpty);
      expect(effects, isEmpty);

      // 4. Complete the second (active) API call
      api.inFlight['flutter']!.complete(['flutter_dev', 'flutter_docs']);
      await Future<void>.delayed(Duration.zero);

      // State is updated with fresh data
      expect(commander.state.isLoading, isFalse);
      expect(commander.state.results, equals(['flutter_dev', 'flutter_docs']));
      expect(effects, equals([const SearchEffect('Found 2 for flutter')]));

      // Cancellation must not be reported as an application error
      expect(commander.caughtErrors, isEmpty);

      commander.dispose();
    });

    test('commander.dispose() auto-cancels in-flight scope.sleep timers immediately',
        () async {
      final api = MockSearchApi();
      final commander = SearchCommander(api: api);

      unawaited(commander.dispatch(const SleepIntent(Duration(seconds: 5))));
      await Future<void>.delayed(Duration.zero);

      expect(commander.state.isLoading, isTrue);

      // Dispose commander while sleeping
      commander.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(commander.isDisposed, isTrue);
      expect(commander.caughtErrors, isEmpty);
    });

    test('scope.listen automatically unsubscribes on restart and dispose',
        () async {
      final api = MockSearchApi();
      final streamController = StreamController<int>.broadcast();
      final commander = SearchCommander(
        api: api,
        testStreamController: streamController,
      );

      // Start listening
      unawaited(commander.dispatch(const StreamIntent()));
      await Future<void>.delayed(Duration.zero);

      // Emit item 1 -> received
      streamController.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(commander.state.results, equals(['item_1']));

      // Restart the command (new subscription instance)
      unawaited(commander.dispatch(const StreamIntent()));
      await Future<void>.delayed(Duration.zero);

      // Emit item 2 -> only ONE listener should process it (previous was cancelled)
      streamController.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(commander.state.results, equals(['item_1', 'item_2']));

      // Dispose commander
      commander.dispose();
      await Future<void>.delayed(Duration.zero);

      // Emit item 3 after disposal -> must be ignored
      streamController.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(commander.state.results, equals(['item_1', 'item_2']));

      await streamController.close();
    });

    test('TestCommandScope supports unit testing cancellation helpers in isolation',
        () async {
      final scope = TestCommandScope<SearchState, SearchEffect>(
        SearchState.initial(),
      );

      var cleanupRan = false;
      scope.attach(() => cleanupRan = true);

      final apiCompleter = Completer<List<String>>();
      final raceFuture = scope.race(apiCompleter.future);

      expect(scope.isCancelled, isFalse);

      // Simulate cancellation in test
      scope.cancel('Test cancellation');

      expect(scope.isCancelled, isTrue);
      expect(cleanupRan, isTrue);
      expect(
        () => raceFuture,
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Test cancellation'),
        )),
      );

      // Attempting state update after cancellation is a no-op
      scope.updateState((s) => s.copyWith(isLoading: true));
      expect(scope.states, isEmpty);
    });
  });
}
