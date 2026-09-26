---
title: Architecture & Core Concepts
description: Deep dive into unidirectional MVI flow, persistent presentation state, and CommanderView UI integration.
---

`flutter_commander` is built on a clean unidirectional **MVI (Model-View-Intent)** + **Command Pattern** architecture designed for Flutter applications that demand decoupling, strict predictability, and high maintainability.

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

## 1. Domain: State, SideEffects & Intents

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

## 2. Orchestrating with the Commander (`CartCommander`)

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

## 3. Reactive Flutter UI Integration

### Widget Selection Guide

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

### Architecture Best Practice: Screen-Level vs. Sub-Widget Reactivity

- **Screen / Feature Root:** Extend `CommanderView<C, S, E>` as the root of your screen or feature view. It automatically handles one-shot side effects via `onEffect`, provides direct access to `state` in `build(context, state)`, enforces mounted-context checks, and eliminates nested listener/builder pyramids.
- **Granular Sub-Widgets:** For high-frequency or isolated elements (e.g. cart badges, item counters, status pills), extract them into dedicated widgets and use **`context.select((CartCommander c) => c.state.itemCount)`** (or **`CommanderSelector`**). This ensures that state changes to individual properties only rebuild those specific sub-widgets rather than the entire screen, with zero generic type boilerplate.
- **Headless / Dialog Listeners:** Use **`CommanderListener<C, E>`** only when an isolated component (e.g. an alert dialog, bottom sheet, or non-screen service widget) needs to react to side effects without rendering UI based on state. Supports `bufferWhileInactive: true` for delayed delivery upon route reactivation.

### Store Page Implementation (`CartPage` with `CommanderView`)

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

---

## 4. Enterprise Reliability Built-In

* **Cold-Start Effect Buffering**: Side effects emitted during commander construction or before the UI finishes mounting are stored in a 32-element FIFO buffer and flushed automatically as soon as the first listener attaches. You will never drop an initial error toast or auth redirect.
* **Mounted Context Guard**: Both `CommanderView` and `CommanderListener` automatically verify `context.mounted` before invoking `onEffect`. Showing dialogs, SnackBars, or route transitions is safe by default even across async delays.
* **Dynamic Scope Swapping**: `CommanderScope.dependOnCommander` tracks instance identity, ensuring immediate resubscription and rebuilds when swapping commander instances at runtime, even inside deeply nested `const` subtrees.
