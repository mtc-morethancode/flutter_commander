# flutter_commander 🚀

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://pub.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0+-0175C2.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage](https://img.shields.io/badge/coverage-98.4%25-brightgreen.svg)]()

**Enterprise MVI + Command Pattern architecture for Flutter.**

`flutter_commander` brings decoupled enterprise-grade state management to Flutter without code generation, without god-classes, and with declarative concurrency control built directly into each use-case.

```bash
flutter pub add flutter_commander
```

---

## ⚡ 3-Minute Quickstart

In a rush? Here is the entire unidirectional MVI flow in a single, self-contained 40-line snippet:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

// 1. State & One-Shot Effect
class CartState {
  final int count;
  const CartState({this.count = 0});
}
sealed class CartEffect { const CartEffect(); }
class ShowToastEffect extends CartEffect {
  final String message;
  const ShowToastEffect(this.message);
}

// 2. Intent
class AddItemIntent extends CommandIntent { const AddItemIntent(); }

// 3. Commander with Inline DSL or Command
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander() : super(const CartState()) {
    on<AddItemIntent>((scope, intent) {
      scope.updateState((s) => CartState(count: s.count + 1));
      scope.emitSideEffect(const ShowToastEffect('Item added to cart!'));
    });
  }
}

// 4. Reactive UI
class QuickstartApp extends StatelessWidget {
  const QuickstartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CommanderScope<CartCommander>(
      create: (_) => CartCommander(),
      child: CommanderListener<CartCommander, CartEffect>(
        onEffect: (context, effect) {
          if (effect is ShowToastEffect) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(effect.message)));
          }
        },
        child: Scaffold(
          body: Center(
            child: CommanderSelector<CartCommander, CartState, int>(
              select: (s) => s.count,
              builder: (context, count) => Text('Items: $count', style: const TextStyle(fontSize: 24)),
            ),
          ),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton(
              onPressed: () => context.dispatch<CartCommander>(const AddItemIntent()),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );
  }
}
```

That's it! Strict unidirectional flow, persistent presentation state, and decoupled one-shot side effects.

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

Each isolated operation lives in its own dedicated `Command` class with an explicit `ExecutionPolicy`. This eliminates race conditions with **zero RxDart boilerplate**:

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

> **💡 Note on Naming:** Your state & use-case orchestrators extend `Commander<S, E>` (e.g. `CartCommander`, `ShopCommander`). For teams that prefer controller terminology, `typedef CommanderController<S, E> = Commander<S, E>;` is available out-of-the-box.

---

### 4. Reactive Flutter UI Integration

#### 🧩 Widget Selection Guide

| Widget / Extension | Purpose | Generics | Rebuilds On |
| :--- | :--- | :---: | :--- |
| `CommanderStateBuilder<C, S>` | Rebuild when full state updates | 2 (`C, S`) | Any state mutation |
| `CommanderSelector<C, S, R>` | Rebuild **only** when projected slice `R` changes | 3 (`C, S, R`) | Value equality (`==`) of `R` |
| `CommanderListener<C, E>` | Execute one-shot side effects (navigation, dialogs, toasts) | 2 (`C, E`) | Never (side-effects stream only) |
| `CommanderStateConsumer<C, S, E>` | Combine full-state builder + side-effect listener | 3 (`C, S, E`) | Any state mutation |
| `CommanderConsumer<C, S, R, E>` | Combine slice selector + side-effect listener | 4 (`C, S, R, E`) | Value equality (`==`) of `R` |
| `context.select<C, S, R>(select)` | Read slice reactively directly inside `build()` | 3 (`C, S, R`) | Value equality (`==`) of `R` |
| `context.dispatch<C>(intent)` | Dispatch an intent from any `BuildContext` | 1 (`C`) | Never (fire-and-forget) |

> **💡 Best Practice: `CommanderListener` vs. `CommanderStateConsumer`**
>
> - **Golden Rule:** *Listen to effects high up in the widget tree, rebuild UI as deep and localized as possible.*
> - **Use `CommanderListener`** at the screen root (wrapping your `Scaffold`) when handling global side-effects (navigation, `SnackBar`, alerts). Pair it with localized `CommanderSelector` or `CommanderStateBuilder` widgets deeper in the tree so state changes never cause full-screen rebuilds.
> - **Use `CommanderStateConsumer`** when a self-contained, localized widget (like an isolated card, modal dialog, or bottom sheet) needs **both** to react to effects and rebuild its own UI, saving you from manually nesting a listener and builder.

#### Store Page Implementation (`CartPage`)

```dart
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommanderScope<CartCommander>(
      create: (context) => CartCommander(
        paymentService: PaymentService(),
        catalogService: CatalogService(),
        analyticsService: AnalyticsService(),
      ),
      child: CommanderListener<CartCommander, CartEffect>(
        onEffect: (context, effect) {
          switch (effect) {
            case ShowToastEffect(:final message):
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            case OrderConfirmedEffect(:final orderId):
              Navigator.of(context).pushNamed('/order-success/$orderId');
          }
        },
        child: Scaffold(
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
                // Rebuilds ONLY when search results update
                Expanded(
                  child: CommanderSelector<CartCommander, CartState, List<String>>(
                    select: (state) => state.searchResults,
                    builder: (context, results) {
                      return ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return ListTile(
                            title: Text(item),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_shopping_cart),
                              onPressed: () => context.dispatch<CartCommander>(AddToCartIntent(item)),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Checkout button with double-tap protection
                CommanderSelector<CartCommander, CartState, bool>(
                  select: (state) => state.isCheckingOut,
                  builder: (context, isCheckingOut) {
                    return ElevatedButton(
                      onPressed: isCheckingOut
                          ? null
                          : () => context.dispatch<CartCommander>(const CheckoutIntent()),
                      child: isCheckingOut
                          ? const CircularProgressIndicator.adaptive()
                          : const Text('Complete Purchase'),
                    );
                  },
                ),
              ],
            ),
          ),
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
    // Rebuilds ONLY when itemCount changes:
    final count = context.select<CartCommander, CartState, int>((s) => s.itemCount);

    return Badge(
      label: Text('$count'),
      isLabelVisible: count > 0,
      child: const Icon(Icons.shopping_cart_outlined),
    );
  }
}
```

---

### 5. Atomic Unit Testing with `TestCommandScope`

Unit testing in `flutter_commander` is deterministic, requires **zero widget pumping, zero streams, and zero timers**:

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

### 6. Observability & Global Telemetry

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

---

### 7. Architectural Comparison

| Feature | flutter_commander | BLoC | Riverpod |
| :--- | :---: | :---: | :---: |
| **Concurrency Control** | Declarative (`DROP`, `RESTART`, `QUEUE`, `CONCURRENT`) | Requires custom RxDart transformers | Manual cancel tokens |
| **Separation of Concerns** | Single-responsibility `Command` classes | Centralized Bloc with multiple event handlers | Notifiers with multiple methods |
| **One-Shot Effects Channel** | First-class `SideEffect` broadcast stream | State flags or external stream adapters | State flags or external streams |
| **Code Generation** | ❌ None (Pure Dart 3) | ❌ Optional | ⚠️ Recommended |
| **Business Logic Testing** | Atomic & synchronous via `TestCommandScope` | `blocTest` (async with stream delays) | `ProviderContainer` mocking |

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
