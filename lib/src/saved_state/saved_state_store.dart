import 'dart:async';

/// An abstract storage contract for persisting and restoring state.
///
/// Implementations can wrap SharedPreferences, Hive, SQLite, Flutter Secure Storage,
/// or in-memory collections.
///
/// Methods return [FutureOr] to support both synchronous in-memory caches
/// and asynchronous storage engines.
abstract interface class SavedStateStore {
  /// The global default store used by `SavedStateMixin` and `SavedStateHandle`
  /// when no custom store is specified.
  static SavedStateStore? defaultStore;

  /// Reads stored state JSON for [key].
  ///
  /// Returns `null` if no data exists for [key].
  FutureOr<Map<String, dynamic>?> read(String key);

  /// Writes [data] to persistent storage under [key].
  FutureOr<void> write(String key, Map<String, dynamic> data);

  /// Deletes persisted state for [key].
  FutureOr<void> delete(String key);
}

/// An in-memory implementation of [SavedStateStore].
///
/// Ideal for unit tests, widget tests, or applications requiring
/// session-only state caching without third-party dependencies.
class InMemorySavedStateStore implements SavedStateStore {
  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Map<String, dynamic>? read(String key) {
    final entry = _storage[key];
    if (entry == null) return null;
    return Map<String, dynamic>.from(entry);
  }

  @override
  void write(String key, Map<String, dynamic> data) {
    _storage[key] = Map<String, dynamic>.from(data);
  }

  @override
  void delete(String key) {
    _storage.remove(key);
  }

  /// Clears all stored data.
  void clear() => _storage.clear();

  /// Returns all currently stored keys.
  Iterable<String> get keys => _storage.keys;

  /// Returns an unmodifiable snapshot of all stored entries.
  Map<String, Map<String, dynamic>> dump() =>
      Map<String, Map<String, dynamic>>.unmodifiable(_storage);
}
