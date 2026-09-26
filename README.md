# flutter_commander 🚀

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://pub.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0+-0175C2.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage](https://img.shields.io/badge/coverage-98.4%25-brightgreen.svg)]()

**Enterprise MVI + Command Pattern architecture for Flutter.**

`flutter_commander` brings decoupled, highly testable, enterprise-grade state management to Flutter without code generation, without bloated controllers, and with declarative concurrency control built directly into each use case.

```bash
flutter pub add flutter_commander
```

---

## ✨ Why `flutter_commander`?

* 🎯 **Atomic Single-Responsibility Commands:** Break complex business domains into isolated, reusable `Command` classes. Each action owns its logic, dependencies, and execution rules.
* ⚡ **Declarative Concurrency Control:** Solve race conditions, double-tap prevention, debounced live search, and sequential queues natively using `ExecutionPolicy` with zero stream boilerplate.
* 🔔 **First-Class One-Shot SideEffects:** Handle dialogs, SnackBars, and navigation via a dedicated broadcast channel with automatic cold-start FIFO buffering and mounted-context verification.
* 🧼 **Ergonomic UI with `CommanderView`:** Say goodbye to nested builder pyramids. Render state, listen to effects, and filter rebuilds in a single clean widget.
* 🧩 **Composable Mixins:** Add zero-flicker state persistence (`SavedStateMixin`) and comprehensive undo/redo time-travel (`UndoRedoMixin`) via idiomatic Dart 3 mixins.
* 🧪 **Two-Tier Testing (Declarative & Atomic):** Test entire orchestrators with `commanderTest` (declarative states, side-effects, seeding, and auto-disposal) or test isolated commands with `TestCommandScope`—100% deterministic and streamless.
* 🚫 **Zero Code Generation:** 100% pure Dart 3. Instant compilation, crystal-clear stack traces, and maximum developer velocity.

---

## ⚡ 3-Minute Quickstart

Here is the complete unidirectional MVI flow in a single, self-contained 50-line snippet using **`CommanderView`**:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

// 1. Presentation State & One-Shot SideEffect
class CounterState {
  final int count;
  const CounterState([this.count = 0]);
}

sealed class CounterEffect { const CounterEffect(); }
class ShowToastEffect extends CounterEffect {
  final String message;
  const ShowToastEffect(this.message);
}

// 2. Intent
class IncrementIntent extends CommandIntent { const IncrementIntent(); }

// 3. Commander Orchestrator (Inline DSL)
class CounterCommander extends Commander<CounterState, CounterEffect> {
  CounterCommander() : super(const CounterState()) {
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => CounterState(s.count + 1));
      if (state.count % 5 == 0) {
        scope.emitSideEffect(ShowToastEffect('Milestone reached: ${state.count}!'));
      }
    });
  }
}

// 4. Reactive UI with CommanderView (Zero nested builders!)
class CounterPage extends CommanderView<CounterCommander, CounterState, CounterEffect> {
  const CounterPage({super.key});

  @override
  void onEffect(BuildContext context, CounterEffect effect) {
    if (effect is ShowToastEffect) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(effect.message)));
    }
  }

  @override
  Widget build(BuildContext context, CounterState state) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commander Counter')),
      body: Center(
        child: Text('Count: ${state.count}', style: const TextStyle(fontSize: 32)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.dispatch<CounterCommander>(const IncrementIntent()),
        child: const Icon(Icons.add),
      ),
    );
  }
}

void main() {
  runApp(
    MaterialApp(
      home: CommanderScope<CounterCommander>(
        create: (_) => CounterCommander(),
        child: const CounterPage(),
      ),
    ),
  );
}
```

That's it! Strict unidirectional flow, persistent presentation state, first-class one-shot side effects, and clean, declarative UI with zero nesting.

---

## 📖 Deep Dive: Complete Architecture Showcase

Below is the complete architectural guide using a single, cohesive application domain: **An E-Commerce Store & Checkout App**.

```
[ User Interaction ] ───> [ CommandIntent ]
                                │
                                ▼
                       [ CommandRunner ]
                 (ExecutionPolicy Concurrency)
                                │
                                ▼
                            [ Command ]
                     (Isolated Single Use-Case)
                            /        \
                           /          \
                          ▼            ▼
                      [ State ]   [ SideEffect ]
                     (Persistent)    (One-Shot)
```

---

### 1. Domain: State, SideEffects & Intents

In `flutter_commander`, state holds exclusively persistent presentation data. Ephemeral events such as navigation, SnackBars, and modal dialogs travel through a dedicated broadcast channel of **SideEffects**:

```dart
// Immutable Presentation State
class CartState {
  final List<String> items;
  final List<String> searchResults;
  final bool isCheckingOut;
  final bool isVip;

  const CartState({
    this.items = const [],
    this.searchResults = const [],
    this.isCheckingOut = false,
    this.isVip = false,
  });

  int get itemCount => items.length;

  CartState copyWith({
    List<String>? items,
    List<String>? searchResults,
    bool? isCheckingOut,
    bool? isVip,
  }) => CartState(
    items: items ?? this.items,
    searchResults: searchResults ?? this.searchResults,
    isCheckingOut: isCheckingOut ?? this.isCheckingOut,
    isVip: isVip ?? this.isVip,
  );
}

// One-Shot SideEffects (SnackBars, Navigation, Dialogs)
sealed class CartEffect {
  const CartEffect();
}

class ShowToastEffect extends CartEffect {
  final String message;
  const ShowToastEffect(this.message);
}

class OrderConfirmedEffect extends CartEffect {
  final String orderId;
  const OrderConfirmedEffect(this.orderId);
}

// User & System Intents
class AddToCartIntent extends CommandIntent {
  final String productId;
  const AddToCartIntent(this.productId);
}

class SearchProductsIntent extends CommandIntent {
  final String query;
  const SearchProductsIntent(this.query);
}

class CheckoutIntent extends CommandIntent {
  const CheckoutIntent();
}

class TrackAnalyticsIntent extends CommandIntent {
  final String event;
  const TrackAnalyticsIntent(this.event);
}

class ToggleVipIntent extends CommandIntent {
  const ToggleVipIntent();
}
```

---

### 2. Declarative Concurrency Policies (`ExecutionPolicy`)

Each isolated operation lives in its own dedicated `Command` class with an explicit `ExecutionPolicy`. This eliminates race conditions natively and declaratively:

| Policy | Behavior in the Store App | Typical Use Case |
| :--- | :--- | :--- |
| `ExecutionPolicy.drop` | If the command is running, incoming intents of this type are **immediately ignored**. | **Checkout**: Prevents duplicate charges from double-tapping the pay button. |
| `ExecutionPolicy.restart` | Cooperatively cancels active execution (via `CancellationToken`) and starts the new intent. | **Live Search**: Cancels in-flight HTTP requests as the user continues typing. |
| `ExecutionPolicy.queue` | Enqueues invocations in strict FIFO order, executing them sequentially one by one. | **Analytics / Audit Log**: Guarantees telemetry events are sent in exact chronological order. |
| `ExecutionPolicy.concurrent` | Executes all invocations in parallel without blocking or dropping. | **Asset Downloading / Independent Queries**. |

#### A. `ExecutionPolicy.drop` (Double-Tap Prevention on Checkout)

```dart
class CheckoutCommand extends Command<CheckoutIntent, CartState, CartEffect> {
  final PaymentService _paymentService;
  CheckoutCommand(this._paymentService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Future<void> execute(CommandScope<CartState, CartEffect> scope, CheckoutIntent intent) async {
    scope.updateState((s) => s.copyWith(isCheckingOut: true));
    try {
      final orderId = await _paymentService.pay(scope.state.items);
      scope.updateState((s) => s.copyWith(isCheckingOut: false, items: const []));
      scope.emitSideEffect(OrderConfirmedEffect(orderId));
    } catch (e) {
      scope.updateState((s) => s.copyWith(isCheckingOut: false));
      scope.emitSideEffect(ShowToastEffect('Payment failed: $e'));
    }
  }
}
```

#### B. `ExecutionPolicy.restart` + `debounce` (Type-Ahead Live Product Search)

```dart
class SearchProductsCommand extends Command<SearchIntent, CartState, CartEffect> {
  final CatalogService _catalog;
  SearchProductsCommand(this._catalog);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  // Wait for 300ms of user typing inactivity before firing:
  @override
  Duration? get debounce => const Duration(milliseconds: 300);

  @override
  Future<void> execute(CommandScope<CartState, CartEffect> scope, SearchIntent intent) async {
    // If the user types before 300ms or a new query arrives, the previous request is cancelled cooperatively
    final results = await _catalog.search(intent.query, token: scope.cancellationToken);
    scope.updateState((s) => s.copyWith(searchResults: results));
  }
}
```

#### C. Granular Keyed Concurrency (`concurrencyKey`)

Isolate policies per entity (e.g. dropping duplicate taps on the **same product** while allowing different products in parallel):

```dart
class AddToCartCommand extends Command<AddToCartIntent, CartState, CartEffect> {
  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  // Concurrency policy is isolated per product ID:
  @override
  Object? concurrencyKey(AddToCartIntent intent) => intent.productId;

  @override
  Future<void> execute(CommandScope<CartState, CartEffect> scope, AddToCartIntent intent) async {
    await Future.delayed(const Duration(milliseconds: 200));
    scope.updateState((s) => s.copyWith(items: [...s.items, intent.productId]));
    scope.emitSideEffect(ShowToastEffect('Product ${intent.productId} added'));
  }
}
```

#### D. `ExecutionPolicy.queue` (Ordered Telemetry Sync)

```dart
class TrackAnalyticsCommand extends Command<TrackAnalyticsIntent, CartState, CartEffect> {
  final AnalyticsService _analytics;
  TrackAnalyticsCommand(this._analytics);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(CommandScope<CartState, CartEffect> scope, TrackAnalyticsIntent intent) async {
    await _analytics.logEvent(intent.event);
  }
}
```

---

### 3. Orchestrating with the Commander (`CartCommander`)

The commander binds formal commands via `bind()` and handles quick UI state mutations using the **Inline DSL** `on<I>()`:

```dart
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander({
    required PaymentService paymentService,
    required CatalogService catalogService,
    required AnalyticsService analyticsService,
  }) : super(
         const CartState(),
         interceptors: const [LoggingCommandInterceptor()],
       ) {
    // 1. Register formal decoupled commands
    bind(CheckoutCommand(paymentService));
    bind(SearchProductsCommand(catalogService));
    bind(AddToCartCommand());
    bind(TrackAnalyticsCommand(analyticsService));

    // 2. Inline DSL for rapid UI-only mutations
    on<ToggleVipIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(isVip: !s.isVip));
    });
  }

  // Resilient centralized error boundary:
  @override
  void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
    emitSideEffect(ShowToastEffect('An unexpected error occurred: $error'));
  }
}
```

---

### 4. Reactive Flutter UI Integration

#### 🧩 Widget Selection Guide

| Widget / Extension | Purpose | Generics | Rebuilds On |
| :--- | :--- | :---: | :--- |
| `CommanderScope<C>` | Provide and manage the lifecycle of a `Commander` in the widget tree | 1 (`C`) | Commander instance swap |
| `CommanderView<C, S, E>` | **Recommended for screens & features**: Combines state reactivity, side-effects, intent dispatch, and rebuild filtering with zero nested builders | 3 (`C, S, E`) | State mutation (or via `shouldRebuild`) |
| `context.select((C c) => c.state.slice)` | **Recommended for sub-widgets**: Read and subscribe to a granular slice directly inside `build()` with zero-ceremony type inference | 0 (or 2: `C, R`) | Value equality (`==`) of slice |
| `CommanderSelector<C, S, R>` | Declarative widget alternative to isolate rebuilds to a sub-tree based on slice `R` | 3 (`C, S, R`) | Value equality (`==`) of `R` |
| `CommanderStateBuilder<C, S>` | Rebuild an isolated child sub-tree when full state updates (without side effects) | 2 (`C, S`) | Any state mutation (or via `buildWhen`) |
| `CommanderListener<C, E>` | Standalone side-effect execution (navigation, dialogs, toasts) with optional `bufferWhileInactive` | 2 (`C, E`) | Never (side-effects stream only) |
| `context.dispatch<C>(intent)` | Dispatch an intent from any `BuildContext` | 1 (`C`) | Never (fire-and-forget) |

> **🚀 The Modern DX Choice: `CommanderView`**
>
> Instead of nesting listeners and builders, use `CommanderView`. It handles the lifecycle, executes one-shot side-effects via `onEffect`, passes `state` directly into `build(context, state)`, and provides an optional `shouldRebuild(previous, current)` hook for fine-grained rebuild filtering. For surgical sub-widget rebuilds, pair it with Flutter's native `Builder` + `context.select`.

> **💡 Architecture Best Practice: Screen-Level vs. Sub-Widget Reactivity**
>
> - **Screen / Feature Root:** Extend `CommanderView<C, S, E>` as the root of your screen or feature view. It automatically handles one-shot side effects via `onEffect`, provides direct access to `state` in `build(context, state)`, enforces mounted-context checks, and eliminates nested listener/builder pyramids.
> - **Granular Sub-Widgets:** For high-frequency or isolated elements (e.g. cart badges, item counters, status pills), extract them into dedicated widgets and use **`context.select((CartCommander c) => c.state.itemCount)`** (or **`CommanderSelector`**). This ensures that state changes to individual properties only rebuild those specific sub-widgets rather than the entire screen, with zero generic type boilerplate.
> - **Headless / Dialog Listeners:** Use **`CommanderListener<C, E>`** only when an isolated component (e.g. an alert dialog, bottom sheet, or non-screen service widget) needs to react to side effects without rendering UI based on state. Supports `bufferWhileInactive: true` for delayed delivery upon route reactivation.

#### Store Page Implementation (`CartPage` with `CommanderView`)

```dart
// Provided at the screen route:
CommanderScope<CartCommander>(
  create: (context) => CartCommander(
    paymentService: PaymentService(),
    catalogService: CatalogService(),
    analyticsService: AnalyticsService(),
  ),
  child: const CartPage(),
);

// The screen extends CommanderView: Zero nested pyramids!
class CartPage extends CommanderView<CartCommander, CartState, CartEffect> {
  const CartPage({super.key});

  // 1. One-shot side-effects (safe: automatically checks if context is mounted)
  @override
  void onEffect(BuildContext context, CartEffect effect) {
    switch (effect) {
      case ShowToastEffect(:final message):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      case OrderConfirmedEffect(:final orderId):
        Navigator.of(context).pushNamed('/order-success/$orderId');
    }
  }

  // 2. Optional fine-grained rebuild filtering
  @override
  bool shouldRebuild(CartState previous, CartState current) {
    return previous.items != current.items ||
        previous.searchResults != current.searchResults ||
        previous.isCheckingOut != current.isCheckingOut;
  }

  // 3. Clean build method with direct state access
  @override
  Widget build(BuildContext context, CartState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commander Store'),
        actions: const [CartBadge()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Live search field with 300ms debounce
            TextField(
              decoration: const InputDecoration(labelText: 'Search products'),
              onChanged: (query) => context.dispatch<CartCommander>(SearchProductsIntent(query)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: state.searchResults.length,
                itemBuilder: (context, index) {
                  final item = state.searchResults[index];
                  return ListTile(
                    title: Text(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: () => context.dispatch<CartCommander>(AddToCartIntent(item)),
                    ),
                  );
                },
              ),
            ),
            // Checkout button with double-tap protection
            ElevatedButton(
              onPressed: state.isCheckingOut
                  ? null
                  : () => context.dispatch<CartCommander>(const CheckoutIntent()),
              child: state.isCheckingOut
                  ? const CircularProgressIndicator.adaptive()
                  : const Text('Complete Purchase'),
            ),
          ],
        ),
      ),
    );
  }
}

// Extracted widget optimized with context.select:
class CartBadge extends StatelessWidget {
  const CartBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds ONLY when itemCount changes (zero generic boilerplate):
    final count = context.select((CartCommander c) => c.state.itemCount);

    return Badge(
      label: Text('$count'),
      isLabelVisible: count > 0,
      child: const Icon(Icons.shopping_cart_outlined),
    );
  }
}
```

> **🛡️ Enterprise Reliability Built-In:**
>
> - **Cold-Start Effect Buffering**: Side effects emitted during commander construction or before the UI finishes mounting are stored in a 32-element FIFO buffer and flushed automatically as soon as the first listener attaches. You will never drop an initial error toast or auth redirect.
> - **Mounted Context Guard**: Both `CommanderView` and `CommanderListener` automatically verify `context.mounted` before invoking `onEffect`. Showing dialogs, SnackBars, or route transitions is safe by default even across async delays.
> - **Dynamic Scope Swapping**: `CommanderScope.dependOnCommander` tracks instance identity, ensuring immediate resubscription and rebuilds when swapping commander instances at runtime, even inside deeply nested `const` subtrees.

---

### 5. Native State Persistence (`SavedStateMixin` & `SavedStateStore`)

Inspired by native mobile state preservation (Android Jetpack's `SavedStateHandle` and Flutter's `StateRestoration`), `flutter_commander` provides seamless state persistence without coupling to any specific database (Hive, SharedPreferences, Isar, SQLite, or SecureStorage).

#### A. Agnostic Storage Contract (`SavedStateStore`)

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

#### B. Setup Global Store in `main()`

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

#### C. Automatic Persistence with `SavedStateMixin`

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

* **Zero-Flicker Startup**: `restoreStateSync()` restores the state during construction, eliminating flash-of-initial-content.
* **Background Async Fallback**: If using asynchronous disk engines (like `FlutterSecureStorage`), state restores in the background via `await commander.savedStateReady;`.
* **State Clearing**: Call `await commander.clearSavedState();` on user logout or session reset.
* **Granular Key-Value Handle**: For persisting individual fields independently, use `SavedStateHandle(key: 'user_draft')`.

---

### 6. Declarative & Atomic Testing (`commanderTest` & `TestCommandScope`)

`flutter_commander` provides a two-tier testing suite designed for unmatched developer velocity:

#### A. Orchestrator Testing (`commanderTest`)
For declarative, end-to-end unit testing of `Commander` instances with state sequences, side-effects, seeding, debounce waits, and mock verification (available from `package:flutter_commander/testing.dart`):

```dart
import 'package:flutter_commander/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  commanderTest<CartCommander, CartState, CartEffect>(
    'emits checkout state and OrderConfirmedEffect on checkout',
    build: () => CartCommander(mockPaymentService),
    seed: () => const CartState(items: ['MacBook Pro']),
    act: (commander) => commander.dispatch(const CheckoutIntent()),
    expectStates: () => [
      const CartState(items: ['MacBook Pro'], isCheckingOut: true),
      const CartState(items: [], isCheckingOut: false),
    ],
    expectEffects: () => [
      const OrderConfirmedEffect('ORD-777'),
    ],
    verify: (commander) {
      verify(() => mockPaymentService.pay(any())).called(1);
    },
  );
}
```

#### B. Atomic Command Testing (`TestCommandScope`)
For isolated, widget-free, stream-free testing of individual `Command` units with zero timers and synchronous execution:

```dart
test('CheckoutCommand processes payment, clears cart and emits confirmation', () async {
  final fakePayment = FakePaymentService(mockOrderId: 'ORD-777');
  final command = CheckoutCommand(fakePayment);

  // Initialize test harness with 2 items in cart
  final testScope = TestCommandScope<CartState, CartEffect>(
    const CartState(items: ['MacBook Pro', 'Mouse']),
  );

  // Execute the command directly
  await command.execute(testScope, const CheckoutIntent());

  // 1. Verify chronological state transitions:
  expect(testScope.states, [
    const CartState(items: ['MacBook Pro', 'Mouse'], isCheckingOut: true),
    const CartState(items: [], isCheckingOut: false),
  ]);

  // 2. Verify emitted one-shot side effects:
  expect(testScope.effects, [
    const OrderConfirmedEffect('ORD-777'),
  ]);
});
```

---

### 7. Observability & Global Telemetry

Monitor lifecycle events, executions, and crash reports across the entire app by registering a `CommanderObserver` in your `main()`:

```dart
void main() {
  Commander.observer = AppStoreObserver();
  runApp(const MyApp());
}

class AppStoreObserver extends CommanderObserver {
  @override
  void onCommanderCreated(Commander<dynamic, dynamic> commander) {
    debugPrint('[Lifecycle] Created: ${commander.runtimeType}');
  }

  @override
  void onStateChanged(
    Commander<dynamic, dynamic>? commander,
    dynamic oldState,
    dynamic newState,
  ) {
    debugPrint('[State] ${commander.runtimeType} -> $newState');
  }

  @override
  void onEffectEmitted(
    Commander<dynamic, dynamic>? commander,
    dynamic effect,
  ) {
    debugPrint('[Effect] ${commander.runtimeType} -> $effect');
  }

  @override
  void onError(
    Commander<dynamic, dynamic>? commander,
    Command<dynamic, dynamic, dynamic>? command,
    CommandIntent? intent,
    Object error,
    StackTrace stackTrace,
  ) {
    // Automatic crash reporting to Firebase Crashlytics or Sentry:
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}
```

#### Native Flutter DevTools Timeline Profiling

In debug and profile modes (`!kReleaseMode`), `flutter_commander` automatically emits native `dart:developer.TimelineTask` tracks and VM Service extension events:
* **Performance Timeline**: View exact execution bars in Flutter DevTools with policy, intent type, and concurrency key arguments.
* **Lifecycle Events**: Traces `intent_dropped` on duplicate drop-policy calls and `command_restarted` on cancellations.
* **Zero Release Overhead**: Timeline calls are guarded by `Commander.enableTimelineTracing = !kReleaseMode` and completely bypassed in release builds.

---

### 8. Composable Time-Travel & Undo / Redo (`UndoRedoMixin`)

Built on Dart 3's idiomatic mixin architecture, **`UndoRedoMixin<S, E>`** gives any `Commander` full history navigation and time-travel capabilities. Because it is a mixin rather than a rigid base class, it composes seamlessly with persistence (`SavedStateMixin`) and custom mixins with zero type conflicts.

#### A. Basic Mixin Usage

```dart
class CanvasCommander extends Commander<CanvasState, CanvasEffect>
    with UndoRedoMixin<CanvasState, CanvasEffect> {
  CanvasCommander() : super(const CanvasState.initial()) {
    on<DrawShapeIntent>((scope, intent) {
      scope.updateState((s) => s.addShape(intent.shape));
    });
  }

  // Optional: customize the history limit (defaults to 50, FIFO eviction)
  @override
  int get historyLimit => 25;

  // Optional: filter out transient / loading states from history
  @override
  bool shouldRecordState(CanvasState oldState, CanvasState newState) {
    return !newState.isDragging;
  }
}
```

#### B. Direct UI Invocation & Reactive Button States

Because `Commander` implements `Listenable`, button states dynamically update when `canUndo` and `canRedo` change:

```dart
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final commander = context.commander<CanvasCommander>();

    return ListenableBuilder(
      listenable: commander,
      builder: (context, _) {
        return Row(
          children: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: commander.canUndo ? commander.undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: commander.canRedo ? commander.redo : null,
              tooltip: 'Redo',
            ),
          ],
        );
      },
    );
  }
}
```

#### C. Intent-Driven Dispatch

`UndoRedoMixin` automatically registers handlers for `UndoIntent`, `RedoIntent`, and `ClearHistoryIntent`. Deeply nested widgets or keyboard shortcuts (e.g. `Ctrl+Z` / `Cmd+Z`) can trigger undo/redo declaratively without a direct reference to the commander:

```dart
// Undo 1 step:
context.dispatch<CanvasCommander>(const UndoIntent());

// Undo 3 steps at once:
context.dispatch<CanvasCommander>(const UndoIntent(3));

// Redo 1 step:
context.dispatch<CanvasCommander>(const RedoIntent());

// Clear history:
context.dispatch<CanvasCommander>(const ClearHistoryIntent());
```

---

## 📚 Ecosystem, Comparison & Migration

Whether you are evaluating architectural options for a new project or migrating an existing app, explore our dedicated guides:

* ⚖️ [**Detailed Architectural Comparison**](doc/comparison.md): An objective side-by-side matrix comparing `flutter_commander` with BLoC and Riverpod.
* 📦 [**Migrating from BLoC**](doc/migration_from_bloc.md): Step-by-step migration guide with AI prompts and side-by-side examples.
* 🌊 [**Migrating from Riverpod**](doc/migration_from_riverpod.md): Step-by-step migration guide from Riverpod providers to Commander.
* 📖 [**Universal Migration Guide**](doc/migration_guide.md): Universal MVI core principles and transition overview.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
