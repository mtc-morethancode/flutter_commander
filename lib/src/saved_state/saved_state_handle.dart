import 'dart:async';

import 'package:flutter/foundation.dart';

import 'saved_state_store.dart';

/// A key-value container for preserving and restoring granular state properties,
/// inspired by Android Jetpack's `SavedStateHandle`.
///
/// Can be used alongside or independently of `SavedStateMixin` to persist
/// specific parameters (e.g. filter query, scroll position, user drafts).
///
/// Example:
/// ```dart
/// final handle = SavedStateHandle(key: 'checkout_draft');
/// handle.set('promoCode', 'DISCOUNT20');
/// final promo = handle.get<String>('promoCode');
/// ```
class SavedStateHandle {
  /// The unique storage key for this handle.
  final String key;

  /// The storage engine backing this handle.
  final SavedStateStore store;

  final Map<String, dynamic> _data;
  Future<void> _writeQueue = Future<void>.value();

  /// Creates a [SavedStateHandle].
  ///
  /// If [store] is omitted, defaults to [SavedStateStore.defaultStore]
  /// or a new [InMemorySavedStateStore] if no default is configured.
  SavedStateHandle({
    required this.key,
    SavedStateStore? store,
    Map<String, dynamic>? initialData,
  })  : store =
            store ?? SavedStateStore.defaultStore ?? InMemorySavedStateStore(),
        _data =
            initialData != null ? Map<String, dynamic>.from(initialData) : {} {
    restoreSync();
  }

  /// Retrieves the value stored for [key], or `null` if not found.
  T? get<T>(String key) => _data[key] as T?;

  /// Stores [value] under [key] and asynchronously saves to [store].
  void set<T>(String key, T value) {
    _data[key] = value;
    _persist();
  }

  /// Whether this handle contains a value for [key].
  bool containsKey(String key) => _data.containsKey(key);

  /// Removes the value for [key] and updates persistent storage.
  T? remove<T>(String key) {
    final removed = _data.remove(key) as T?;
    _persist();
    return removed;
  }

  /// Clears all keys in this handle and deletes the stored entry from [store].
  void clear() {
    _data.clear();
    try {
      final result = store.delete(key);
      if (result is Future) {
        unawaited(result.catchError((_) {}));
      }
    } catch (_) {}
  }

  /// Restores state synchronously if [store] provides data synchronously.
  /// Returns `true` if state was found and loaded.
  bool restoreSync() {
    try {
      final result = store.read(key);
      if (result is Map<String, dynamic>) {
        _data.addAll(result);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Restores state asynchronously from [store].
  Future<bool> restoreAsync() async {
    try {
      final result = await store.read(key);
      if (result != null) {
        _data.addAll(result);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _persist() {
    final snapshot = Map<String, dynamic>.from(_data);
    _writeQueue = _writeQueue.then((_) async {
      try {
        final result = store.write(key, snapshot);
        if (result is Future) {
          await result;
        }
      } catch (e) {
        debugPrint(
            '[flutter_commander] [SavedStateHandle] write error on $key: $e');
      }
    });
  }

  /// Returns an unmodifiable view of all stored key-value pairs.
  Map<String, dynamic> toMap() => Map.unmodifiable(_data);

  @override
  String toString() => 'SavedStateHandle($key, $_data)';
}
