# flutter_commander 🚀

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://pub.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0+-0175C2.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage](https://img.shields.io/badge/coverage-97.8%25-brightgreen.svg)]()

**Enterprise MVI + Command Pattern architecture for Flutter.**

`flutter_commander` brings decoupled enterprise-grade state management to Flutter without code generation, without god-classes, and with declarative concurrency control built directly into each use-case.

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

```dart
class CheckoutIntent extends Intent {
  const CheckoutIntent();
}

class IncrementIntent extends Intent {
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
                CommanderBuilder<CartController, CartState, int>(
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
                CommanderBuilder<CartController, CartState, bool>(
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

Add `LoggingCommandInterceptor` to log structured traces:

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

Create custom interceptors by extending `CommandInterceptor` to send analytics or crash metrics to Sentry, Firebase Crashlytics, or Datadog.

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
