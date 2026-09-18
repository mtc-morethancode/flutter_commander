# flutter_commander 🚀

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://pub.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0+-0175C2.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage](https://img.shields.io/badge/coverage-97.8%25-brightgreen.svg)]()

**Enterprise MVI + Command Pattern architecture for Flutter.**

`flutter_commander` brings decoupled enterprise-grade state management to Flutter without code generation, without god-classes, and with declarative concurrency control built directly into each use-case.

```bash
flutter pub add flutter_commander
```

---

## 🌟 Why flutter_commander?

In enterprise Flutter applications, traditional BLoC and Riverpod implementations frequently suffer from:
1. **God ViewModels / Blocs**: As features grow, a single Bloc/Notifier accumulates dozens of events, methods, and injected services, creating monolithic files that lead to constant merge conflicts across concurrent teams.
2. **Race Conditions & Fragile Debounce**: Handling double-tap submissions, search cancellations, or ordered sync queues often requires error-prone manual boilerplate (`rxdart` operators, debounce timers, or mutable flags).
3. **State Pollution**: Using presentation state for one-shot events (e.g., `state.showSuccessSnackbar == true`) leads to ugly hacks (`state.copyWith(showSuccessSnackbar: false)` or event consumption flags) that cause ghost re-triggers on screen rotation.
4. **Heavy Code Generation**: Relying on code generation slows down hot reload and compilation cycles.

### The Solution:

```
[ User Interaction ] ───> [ Intent ]
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

- **Strict Unidirectional Flow**: `Intent -> Command -> State / SideEffect`.
- **True Decoupling (SRP)**: Each complex operation lives in its own dedicated `Command` class with only the dependencies it actually needs. Multiple developers can work on the same screen concurrently without touching the same file.
- **Declarative Concurrency (`ExecutionPolicy`)**: Configure how each command behaves under rapid invocation (`DROP`, `RESTART`, `QUEUE`, `CONCURRENT`) without writing custom debounce or cancellation logic.
- **Dedicated SideEffect Channel**: One-shot events (Navigation, SnackBars, Dialogs) are emitted through a dedicated broadcast stream and consumed without rebuilding widgets.
- **Pure Dart 3**: Built on `sealed classes`, pattern matching, and strong typing. Zero code-gen required.

---

## ⚡ Concurrency Policies (ExecutionPolicy)

Every formal `Command` declares its own concurrency policy via `ExecutionPolicy`:

| Policy | Behavior | Typical Use Case |
| :--- | :--- | :--- |
| `ExecutionPolicy.drop` | If the command is running, new intents of this type are **immediately ignored**. | Double-tap prevention on checkout, login, or submit buttons. |
| `ExecutionPolicy.restart` | Cancels the active execution cooperatively via `CancellationToken` and runs the new intent immediately. | Type-ahead live search, autocomplete, tab switches. |
| `ExecutionPolicy.queue` | Enqueues invocations in strict FIFO order, executing them sequentially one after another. | Offline sync queues, analytics tracking, transactional writes. |
| `ExecutionPolicy.concurrent` | Executes all invocations in parallel without blocking or dropping. | Independent data fetching, multi-file downloading. |

### 🎯 Keyed Concurrency (Granular Concurrency per Item/Resource)

By default, policies apply globally across all instances of a `Command`. To apply policies **per item, user, or entity** (e.g., dropping duplicate taps for item `A` while still allowing item `B`), override `concurrencyKey`:

```dart
class DownloadFileCommand extends Command<DownloadIntent, FileState, FileEffect> {
  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  // Concurrency policy is isolated per file ID:
  @override
  Object? concurrencyKey(DownloadIntent intent) => intent.fileId;

  @override
  Future<void> execute(CommandScope<FileState, FileEffect> scope, DownloadIntent intent) async {
    // Downloading file A will NOT drop requests for file B!
  }
}
```

The inline DSL also supports `concurrencyKey`:
```dart
on<SyncItemIntent>(
  (scope, intent) async { ... },
  policy: ExecutionPolicy.queue,
  concurrencyKey: (intent) => intent.itemId, // Sequential FIFO per item!
);
```

### ⏱️ Declarative Debounce (Search & Rapid Input)

Prevent UI event flooding by adding a debounce duration directly to any `Command` or `on<I>()` handler. Combining `debounce` with `ExecutionPolicy.restart` provides rock-solid type-ahead search with zero RxDart boilerplate:

```dart
class SearchProductsCommand extends Command<SearchIntent, ShopState, ShopEffect> {
  // Restart cancels active HTTP requests when a new query arrives:
  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  // Wait 300ms of user typing inactivity before firing:
  @override
  Duration? get debounce => const Duration(milliseconds: 300);

  @override
  Future<void> execute(CommandScope<ShopState, ShopEffect> scope, SearchIntent intent) async {
    final results = await _api.search(intent.query, token: scope.cancellationToken);
    scope.updateState((s) => s.copyWith(results: results));
  }
}
```

Or quickly with the inline DSL:
```dart
on<FilterQueryIntent>(
  (scope, intent) async {
    final items = await api.filter(intent.query);
    scope.updateState((s) => s.copyWith(items: items));
  },
  policy: ExecutionPolicy.restart,
  debounce: const Duration(milliseconds: 250),
);
```

> **Note:** Debounce timers are automatically scoped per `concurrencyKey` and safely cancelled when the controller or widget scope is disposed.

---

## 🚀 Quickstart Guide

### 1. Define State and SideEffects

```dart
class CartState {
  final int count;
  final bool isCheckingOut;

  const CartState({this.count = 0, this.isCheckingOut = false});

  CartState copyWith({int? count, bool? isCheckingOut}) => CartState(
        count: count ?? this.count,
        isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      );
}

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
```

### 2. Define Intents

Use `CommandIntent` to avoid namespace collisions with Flutter's built-in `actions.dart` `Intent`:

```dart
class CheckoutIntent extends CommandIntent {
  const CheckoutIntent();
}

class IncrementIntent extends CommandIntent {
  const IncrementIntent();
}
```

### 3. Create Isolated Commands

```dart
class CheckoutCommand extends Command<CheckoutIntent, CartState, CartEffect> {
  final PaymentService _paymentService;
  CheckoutCommand(this._paymentService);

  // Prevent duplicate submissions while in-flight!
  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Future<void> execute(
    CommandScope<CartState, CartEffect> scope,
    CheckoutIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(isCheckingOut: true));
    try {
      final orderId = await _paymentService.pay();
      scope.updateState((s) => s.copyWith(isCheckingOut: false, count: 0));
      scope.emitSideEffect(OrderConfirmedEffect(orderId));
    } catch (e) {
      scope.updateState((s) => s.copyWith(isCheckingOut: false));
      scope.emitSideEffect(ShowToastEffect(e.toString()));
    }
  }
}
```

### 4. Wire the Controller

Use `bind` for formal commands, and the **Inline DSL** `on<I>` for quick UI state updates:

```dart
class CartController extends CommanderController<CartState, CartEffect> {
  CartController(PaymentService paymentService)
      : super(
          const CartState(),
          interceptors: const [LoggingCommandInterceptor()],
        ) {
    // 1. Formal commands with dependencies and policies:
    bind(CheckoutCommand(paymentService));

    // 2. Inline DSL for rapid, simple mutations:
    on<IncrementIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
    });
  }
}
```

### 5. Build Reactive Flutter UI

#### 🧩 Widget Selection Guide

| Widget / Extension | Purpose | Generics | Rebuilds On |
| :--- | :--- | :---: | :--- |
| `CommanderStateBuilder<C, S>` | Rebuild when entire state changes | 2 (`C, S`) | Any state mutation |
| `CommanderSelector<C, S, R>` | Rebuild only when a selected slice changes | 3 (`C, S, R`) | Selected slice equality (`==`) |
| `CommanderListener<C, E>` | Execute side effects (navigation, dialogs, toasts) | 2 (`C, E`) | Never (side effects stream only) |
| `CommanderStateConsumer<C, S, E>` | Combine full state builder + side effect listener | 3 (`C, S, E`) | Any state mutation |
| `CommanderConsumer<C, S, R, E>` | Combine slice selector + side effect listener | 4 (`C, S, R, E`) | Selected slice equality (`==`) |
| `context.select<C, R>(select)` | Read slice reactively directly inside `build()` | 2 (`C, R`) | Selected slice equality (`==`) |
| `context.dispatch<C>(intent)` | Dispatch an intent from any `BuildContext` | 1 (`C`) | Never (fire-and-forget) |

```dart
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommanderScope<CartController>(
      create: (context) => CartController(PaymentService()),
      child: CommanderListener<CartController, CartEffect>(
        onEffect: (context, effect) {
          switch (effect) {
            case ShowToastEffect(:final message):
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            case OrderConfirmedEffect(:final orderId):
              Navigator.of(context).pushNamed('/order/$orderId');
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Store')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Selector rebuild: Only rebuilds when count changes!
                CommanderSelector<CartController, CartState, int>(
                  select: (state) => state.count,
                  builder: (context, count) => Text('Items: $count', style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.dispatch<CartController>(const IncrementIntent()),
                  child: const Text('Add Item'),
                ),
                const SizedBox(height: 8),
                // Rebuilds only on isCheckingOut
                CommanderSelector<CartController, CartState, bool>(
                  select: (state) => state.isCheckingOut,
                  builder: (context, isCheckingOut) => ElevatedButton(
                    onPressed: isCheckingOut
                        ? null
                        : () => context.dispatch<CartController>(const CheckoutIntent()),
                    child: isCheckingOut
                        ? const CircularProgressIndicator.adaptive()
                        : const Text('Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 💡 Tip: In extracted widgets, read slices directly with context.select:
class CartBadge extends StatelessWidget {
  const CartBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds ONLY when count changes!
    final count = context.select<CartController, int>((s) => s.count);
    return Badge(label: Text('$count'), child: const Icon(Icons.shopping_cart));
  }
}
```

---

## 🧪 Atomic Testing with `TestCommandScope`

Testing in `flutter_commander` is deterministic and requires **zero mocks, zero streams, and zero widget pumping**:

```dart
test('CheckoutCommand updates state and emits confirmation effect', () async {
  final fakePaymentService = FakePaymentService();
  final command = CheckoutCommand(fakePaymentService);

  final testScope = TestCommandScope<CartState, CartEffect>(
    const CartState(count: 2),
  );

  await command.execute(testScope, const CheckoutIntent());

  // Assert chronological state transitions
  expect(testScope.states, [
    const CartState(count: 2, isCheckingOut: true),
    const CartState(count: 0, isCheckingOut: false),
  ]);

  // Assert emitted side-effects
  expect(testScope.effects, [
    const OrderConfirmedEffect('ORD-123'),
  ]);
});
```

---

## 🔍 Observability & Telemetry

### 🌐 Global `CommanderObserver`

Monitor lifecycle events, state mutations, effects, and errors across the **entire application** by registering a global `CommanderObserver` in your `main()` entrypoint:

```dart
void main() {
  Commander.observer = AppCommanderObserver();
  runApp(const MyApp());
}

class AppCommanderObserver extends CommanderObserver {
  @override
  void onControllerCreated(CommanderController<dynamic, dynamic> controller) {
    debugPrint('Created controller: ${controller.runtimeType}');
  }

  @override
  void onStateChanged(CommanderController<dynamic, dynamic> controller, dynamic oldState, dynamic newState) {
    debugPrint('${controller.runtimeType} -> State updated: $newState');
  }

  @override
  void onEffectEmitted(CommanderController<dynamic, dynamic> controller, dynamic effect) {
    debugPrint('${controller.runtimeType} -> Effect emitted: $effect');
  }

  @override
  void onError(
    CommanderController<dynamic, dynamic>? controller,
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
    Object error,
    StackTrace stackTrace,
  ) {
    // Send unhandled command exceptions to Firebase Crashlytics or Sentry:
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}
```

### 🧩 Per-Controller `CommandInterceptor`

Add `LoggingCommandInterceptor` (or custom interceptors) to individual controllers to log structured traces:

```dart
controller.addInterceptor(const LoggingCommandInterceptor());
```

Produces standard console logs:
```text
[flutter_commander] [Intent] CheckoutIntent -> [Command] CheckoutCommand (Policy: DROP)
[flutter_commander] [State] CartState(count: 2, isCheckingOut: true)
[flutter_commander] [Effect] OrderConfirmedEffect(orderId: ORD-9812)
[flutter_commander] [State] CartState(count: 0, isCheckingOut: false)
```

Create custom interceptors by extending `CommandInterceptor` to benchmark performance, audit events, or inject custom middleware.

---

## 🛡️ Resilient Error Handling

By default, unhandled command exceptions are rethrown so that tests and callers can detect them. To handle errors gracefully without crashing the UI, override `onError` in your controller and emit side-effects directly:

```dart
class CartController extends CommanderController<CartState, CartEffect> {
  CartController(...) : super(...) { ... }

  @override
  void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
    // 1. Report to telemetry:
    Crashlytics.instance.recordError(error, stackTrace);

    // 2. Emit an error toast or snackbar to the user:
    emitSideEffect(ShowToastEffect('An unexpected error occurred.'));

    // 3. Do not rethrow: the error is safely absorbed!
  }
}
```

---

## 📊 Architectural Comparison

| Feature | flutter_commander | BLoC | Riverpod |
| :--- | :---: | :---: | :---: |
| **Concurrency Control** | Declarative (`DROP`, `RESTART`, `QUEUE`, `CONCURRENT`) | Requires RxDart transformer boilerplate | Manual / cancel tokens |
| **Separation of Concerns** | Single-responsibility `Command` classes | Monolithic event handlers in Bloc | Monolithic Notifier methods |
| **One-Shot Effects** | First-class `SideEffect` stream | State flags or complex add-ons | State flags or external streams |
| **Code Generation** | ❌ None required | ❌ Optional | ⚠️ Required / Recommended |
| **Team Scalability** | High (Independent command files) | Low (Merge conflicts in Bloc) | Medium |
| **Testability** | Atomic via `TestCommandScope` | `blocTest` (requires stream delays) | `ProviderContainer` mocking |

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
