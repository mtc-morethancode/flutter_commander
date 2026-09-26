import 'dart:async';

import 'package:flutter/foundation.dart';

import '../commander/commander.dart';
import 'saved_state_store.dart';

/// A mixin that adds automatic state persistence and restoration to a [Commander],
/// inspired by native mobile saved state restoration architectures.
///
/// Features:
/// - Works with any [SavedStateStore] implementation (SharedPreferences, Hive, SQLite, etc.).
/// - Supports both synchronous restoration (e.g. from in-memory cache) and async restoration.
/// - Automatic state persistence on every state transition.
/// - Optional write debouncing via [persistDebounce] to prevent high-frequency disk I/O.
/// - Safe error handling via [onSavedStateError] (never crashes your UI).
///
/// Example:
/// ```dart
/// class CounterCommander extends Commander<CounterState, CounterEffect>
///     with SavedStateMixin<CounterState, CounterEffect> {
///   CounterCommander() : super(const CounterState()) {
///     restoreStateSync(); // Optional: restore synchronously if store is sync
///   }
///
///   @override
///   String get savedStateKey => 'counter_state';
///
///   @override
///   Map<String, dynamic> stateToJson(CounterState state) => {'count': state.count};
///
///   @override
///   CounterState stateFromJson(Map<String, dynamic> json) =>
///       CounterState(count: json['count'] as int? ?? 0);
/// }
/// ```
mixin SavedStateMixin<S, E> on Commander<S, E> {
  /// The unique storage key for this commander's state.
  String get savedStateKey;

  /// Serializes [state] into a JSON-encodable map.
  Map<String, dynamic> stateToJson(S state);

  /// Deserializes [json] back into state instance [S].
  S stateFromJson(Map<String, dynamic> json);

  /// The store used to persist state.
  ///
  /// Defaults to [SavedStateStore.defaultStore]. Throws [StateError] if no store
  /// has been assigned globally or overridden in this commander.
  SavedStateStore get savedStateStore {
    final store = SavedStateStore.defaultStore;
    if (store == null) {
      throw StateError(
        'No SavedStateStore configured for $runtimeType ($savedStateKey). '
        'Assign a default store via SavedStateStore.defaultStore = MyStore() '
        'or override the savedStateStore getter on $runtimeType.',
      );
    }
    return store;
  }

  /// Optional debounce duration before writing state to persistent storage.
  ///
  /// Useful to throttle disk I/O when state updates rapidly (e.g. typing or counters).
  /// If `null` (default), writes happen immediately upon state update.
  Duration? get persistDebounce => null;

  Timer? _debounceTimer;
  bool _isRestoring = false;
  bool _isRestored = false;
  bool _isDirty = false;
  Completer<bool>? _restoreCompleter;

  /// Whether this commander's state has been restored from storage.
  bool get isRestored => _isRestored;

  /// Whether the state has been mutated in memory before or after restoration.
  bool get isDirty => _isDirty;

  /// A [Future] that completes with `true` when state restoration finishes successfully,
  /// or `false` if no saved state was found or an error occurred.
  Future<bool> get savedStateReady {
    if (_isRestored) return Future.value(true);
    if (_restoreCompleter != null) return _restoreCompleter!.future;
    _restoreCompleter = Completer<bool>();
    _initSavedState();
    return _restoreCompleter!.future;
  }

  @override
  void onInit() {
    super.onInit();
    // Schedule asynchronous restoration in the next microtask so that
    // subclass constructors and field initializers are completely finished.
    scheduleMicrotask(() {
      if (!_isRestored && !isDisposed) {
        unawaited(savedStateReady);
      }
    });
  }

  /// Attempts to restore state synchronously.
  ///
  /// Returns `true` if saved state was found and applied synchronously,
  /// or `false` otherwise.
  bool restoreStateSync() {
    if (_isRestored || isDisposed) return false;
    final store = savedStateStore;
    try {
      final data = store.read(savedStateKey);
      if (data is Map<String, dynamic>) {
        _isRestoring = true;
        try {
          final restored = stateFromJson(data);
          restoreState(restored);
          _isRestored = true;
          _isDirty = false;
          _restoreCompleter?.complete(true);
          return true;
        } finally {
          _isRestoring = false;
        }
      }
    } catch (e, stack) {
      onSavedStateError(e, stack);
    }
    return false;
  }

  /// Restores state asynchronously from [savedStateStore].
  Future<bool> restoreStateAsync() => savedStateReady;

  Future<void> _initSavedState() async {
    if (_isRestored || isDisposed) {
      if (!(_restoreCompleter?.isCompleted ?? true)) {
        _restoreCompleter?.complete(_isRestored);
      }
      return;
    }

    try {
      final store = savedStateStore;
      final result = store.read(savedStateKey);
      final json =
          result is Future<Map<String, dynamic>?> ? await result : result;

      if (json != null && !isDisposed) {
        final restored = stateFromJson(json);
        if (_isDirty) {
          // The state was already mutated in-flight by user actions before
          // the async storage read finished. Reconcile to avoid discarding fresh changes.
          final resolved = resolveRestorationConflict(restored, state);
          if (resolved != null && resolved != state) {
            _isRestoring = true;
            try {
              restoreState(resolved);
            } finally {
              _isRestoring = false;
            }
          }
          _schedulePersist(state);
        } else {
          _isRestoring = true;
          try {
            restoreState(restored);
          } finally {
            _isRestoring = false;
          }
        }
        _isRestored = true;
        if (!(_restoreCompleter?.isCompleted ?? true)) {
          _restoreCompleter?.complete(true);
        }
        return;
      }
    } catch (e, stack) {
      onSavedStateError(e, stack);
    }

    _isRestored = true;
    if (_isDirty && !isDisposed) {
      _schedulePersist(state);
    }
    if (!(_restoreCompleter?.isCompleted ?? true)) {
      _restoreCompleter?.complete(false);
    }
  }

  /// Hook called when asynchronous state restoration completes from storage, but
  /// the state was already mutated in-flight ([currentState]) by user actions
  /// or early commands before the storage read finished.
  ///
  /// By default, returns [currentState] to preserve the user's fresh in-memory changes
  /// rather than blindly overwriting them with stale data from disk.
  ///
  /// Subclasses can override this method to perform selective merging or conflict resolution.
  @protected
  S? resolveRestorationConflict(S diskState, S currentState) => currentState;

  @override
  void onStateChanged(S oldState, S newState) {
    super.onStateChanged(oldState, newState);
    if (!_isRestoring) {
      _isDirty = true;
    }
    if (!_isRestoring && !isDisposed && _isRestored) {
      _schedulePersist(newState);
    }
  }

  @override
  void onStateRestored(S oldState, S newState) {
    super.onStateRestored(oldState, newState);
    if (!_isRestoring && !isDisposed && _isRestored) {
      _isDirty = true;
      _schedulePersist(newState);
    }
  }

  void _schedulePersist(S state) {
    final debounce = persistDebounce;
    if (debounce != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        if (!isDisposed) {
          unawaited(_persist(state));
        }
      });
    } else {
      unawaited(_persist(state));
    }
  }

  Future<void> _persist(S state) async {
    try {
      final json = stateToJson(state);
      final result = savedStateStore.write(savedStateKey, json);
      if (result is Future) {
        await result;
      }
    } catch (e, stack) {
      onSavedStateError(e, stack);
    }
  }

  /// Forces an immediate synchronous/asynchronous persist of the current [state].
  Future<void> persistState() {
    _debounceTimer?.cancel();
    return _persist(state);
  }

  /// Deletes the persisted state from [savedStateStore].
  Future<void> clearSavedState() async {
    _debounceTimer?.cancel();
    _isDirty = false;
    try {
      final result = savedStateStore.delete(savedStateKey);
      if (result is Future) {
        await result;
      }
    } catch (e, stack) {
      onSavedStateError(e, stack);
    }
  }

  /// Hook invoked whenever a storage read, write, or deserialization error occurs.
  ///
  /// Subclasses can override this method to report errors to Firebase Crashlytics,
  /// Sentry, or custom telemetry services.
  @protected
  void onSavedStateError(Object error, StackTrace stackTrace) {
    assert(() {
      debugPrint(
        '[flutter_commander] [SavedStateError] in $runtimeType ($savedStateKey): $error\n$stackTrace',
      );
      return true;
    }());
  }

  @override
  void dispose() {
    if (_debounceTimer != null && _debounceTimer!.isActive) {
      _debounceTimer!.cancel();
      unawaited(_persist(state));
    }
    super.dispose();
  }
}
