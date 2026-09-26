# Native State Persistence (`SavedStateMixin` & `SavedStateStore`) 💾

Inspired by native mobile state preservation (Android Jetpack's `SavedStateHandle` and Flutter's `StateRestoration`), `flutter_commander` provides seamless state persistence without coupling to any specific database (Hive, SharedPreferences, Isar, SQLite, or FlutterSecureStorage).

---

## 1. Agnostic Storage Contract (`SavedStateStore`)

Implement the minimal 3-method interface or use the built-in `InMemorySavedStateStore`:

```dart
// Example: Plug in Hive in ~15 lines without extra commander plugins
class HiveSavedStateStore implements SavedStateStore {
  final Box<dynamic> _box;
  HiveSavedStateStore(this._box);

  @override
  Map<String, dynamic>? read(String key) {
    final data = _box.get(key);
    return data != null ? Map<String, dynamic>.from(data as Map) : null;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    await _box.put(key, data);
  }

  @override
  Future<void> delete(String key) async {
    await _box.delete(key);
  }
}
```

---

## 2. Setup Global Store in `main()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox('commander_storage');

  // Configure global default store:
  SavedStateStore.defaultStore = HiveSavedStateStore(box);

  runApp(const MyApp());
}
```

---

## 3. Automatic Persistence with `SavedStateMixin`

Simply mix `SavedStateMixin` onto your `Commander`. It automatically saves on every state change and restores state on startup:

```dart
class CartCommander extends Commander<CartState, CartEffect>
    with SavedStateMixin<CartState, CartEffect> {
  CartCommander() : super(const CartState()) {
    // 1. Zero-Flicker Synchronous Restoration:
    // Because in-memory boxes are pre-warmed, state restores synchronously with 0 frame flicker!
    restoreStateSync();
  }

  @override
  String get savedStateKey => 'cart_state';

  @override
  Map<String, dynamic> stateToJson(CartState state) => state.toJson();

  @override
  CartState stateFromJson(Map<String, dynamic> json) => CartState.fromJson(json);

  // 2. Optional: Throttle rapid state updates to save battery and disk I/O
  @override
  Duration? get persistDebounce => const Duration(milliseconds: 100);
}
```

---

## 4. Key Persistence Features

* **Zero-Flicker Startup**: `restoreStateSync()` restores the state during construction, eliminating flash-of-initial-content.
* **Background Async Fallback**: If using asynchronous disk engines (like `FlutterSecureStorage`), state restores in the background via `await commander.savedStateReady;`.
* **State Clearing**: Call `await commander.clearSavedState();` on user logout or session reset.
* **Granular Key-Value Handle**: For persisting individual fields independently, use `SavedStateHandle(key: 'user_draft')`.
