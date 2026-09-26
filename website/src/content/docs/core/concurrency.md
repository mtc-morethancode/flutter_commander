---
title: Declarative Concurrency Control
description: Master race conditions, double-tap prevention, live search debouncing, and keyed concurrency with ExecutionPolicy.
---

In modern Flutter applications, managing asynchronous race conditions, rapid button taps, debounced searches, and sequential queues often leads to brittle stream pipelines or bloated state machines.

`flutter_commander` solves concurrency declaratively at the use-case level using **`ExecutionPolicy`**.

---

## The Execution Policies

Each isolated `Command` declares its concurrency policy via the `policy` getter:

| Policy | Behavior | Typical Use Case |
| :--- | :--- | :--- |
| `ExecutionPolicy.drop` | If the command is currently executing, incoming intents of this type are **immediately ignored**. | **Checkout / Submit Buttons**: Prevents duplicate charges from double-tapping. |
| `ExecutionPolicy.restart` | Cooperatively cancels the active execution (via `CancellationToken`) and starts the new intent. | **Type-Ahead Live Search**: Cancels in-flight HTTP requests as the user types. |
| `ExecutionPolicy.queue` | Enqueues invocations in strict FIFO order, executing them sequentially one by one. | **Analytics / Audit Log**: Guarantees telemetry events are sent in exact chronological order. |
| `ExecutionPolicy.concurrent` | Executes all invocations in parallel without blocking or dropping. *(Default)* | **Independent Data Queries / Image Downloads**. |

---

## 1. `ExecutionPolicy.drop` (Double-Tap Prevention)

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

---

## 2. `ExecutionPolicy.restart` + `debounce` (Live Search)

Pairing `restart` with `debounce` creates a rock-solid type-ahead search with cooperative cancellation:

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
    // If the user types before 300ms or a new query arrives, 
    // the previous request is cancelled cooperatively via scope.cancellationToken
    final results = await _catalog.search(intent.query, token: scope.cancellationToken);
    
    // Check if cancelled before applying state:
    if (!scope.cancellationToken.isCancelled) {
      scope.updateState((s) => s.copyWith(searchResults: results));
    }
  }
}
```

---

## 3. Granular Keyed Concurrency (`concurrencyKey`)

By default, an `ExecutionPolicy` applies to all invocations of that command type. With `concurrencyKey`, you can isolate policies per entity (e.g. dropping duplicate taps on the **same product** while allowing different products in parallel):

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

---

## 4. `ExecutionPolicy.queue` (Ordered Telemetry Sync)

Guarantees sequential FIFO execution:

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
