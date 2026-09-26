# flutter_commander_example 🛒

A complete real-world enterprise Flutter application demonstrating the architectural patterns, concurrency controls, and ergonomic UI integration of **`flutter_commander`**.

---

## 🌟 What This Example Demonstrates

1. **Unidirectional MVI Flow:** Strict separation of `ShopIntent` ➔ `ShopCommander` ➔ `ShopState` & `ShopEffect`.
2. **Declarative Concurrency Policies:**
   * **`ExecutionPolicy.drop` (`CheckoutCommand`):** Double-tap protection preventing accidental duplicate payment transactions.
   * **`ExecutionPolicy.restart` + `debounce` (`SearchProductsCommand`):** Type-ahead product search with 300ms debounce and cooperative request cancellation via `CancellationToken`.
   * **`ExecutionPolicy.queue` (`TrackAnalyticsCommand`):** Strict sequential FIFO processing for telemetry and analytics logging.
   * **`ExecutionPolicy.concurrent` (`RefreshCatalogCommand`):** Non-blocking parallel data fetching.
3. **Keyed Concurrency (`concurrencyKey`):** Independent concurrency tracking per query or product ID.
4. **First-Class One-Shot SideEffects:** Modal dialogs, SnackBars, and navigation via `ShopEffect` (`OrderConfirmedEffect`, `ShowSnackbarEffect`) with cold-start buffering.
5. **Ergonomic UI with `CommanderView`:** Zero nested builder pyramids (`onEffect`, `shouldRebuild`, and `build` unified in one widget).
6. **Optimized Sub-Widget Rebuilds (`context.select`):** Granular slice subscriptions for badges and counters with zero generic ceremony.
7. **Comprehensive Two-Tier Testing:**
   * High-level orchestrator verification with `commanderTest` (`example/test/commander/shop_commander_test.dart`).
   * Isolated, widget-free, synchronous unit tests with `TestCommandScope` (`example/test/commands/`).
   * Full widget interaction tests (`example/test/widget_test.dart`).

---

## 🚀 Running the Example

From the root of this project:

```bash
cd example
flutter pub get
flutter run
```

---

## 🧪 Running the Tests

To run the full suite of example tests (orchestrator, isolated commands, and widgets):

```bash
cd example
flutter test
```
