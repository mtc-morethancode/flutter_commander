# 🔄 Migration Guide: From BLoC & Riverpod to `flutter_commander`

> **Designed for both Human Developers and AI Coding Assistants (Cursor, Copilot, Claude, ChatGPT, Antigravity).**

This guide provides deterministic mapping rules, architectural equivalences, and side-by-side code comparisons to migrate existing state management solutions to **`flutter_commander`**.

---

## 🤖 AI Agent Migration Prompt (Copy & Paste into your AI Assistant)

If you are using Cursor, GitHub Copilot, Claude, ChatGPT, or Antigravity to migrate your codebase, paste the following prompt into your assistant:

```markdown
You are an expert Flutter architect specializing in MVI and unidirectional data flow.
Your task is to refactor the provided feature from [flutter_bloc / flutter_riverpod] to `flutter_commander`.

Follow these strict migration rules from doc/migration_guide.md:
1. DOMAIN LAYER:
   - Convert all events or notifier methods into immutable `CommandIntent` subclasses.
   - Separate persistent presentation data into an immutable `State` class.
   - Extract ephemeral events (navigation, SnackBars, dialogs, toasts) out of the state into a `sealed class` of one-shot `SideEffect`s. Never store navigation or error message flags in State.

2. COMMAND & BUSINESS LOGIC:
   - Replace complex asynchronous operations with isolated `Command<Intent, State, Effect>` classes.
   - Assign the appropriate `ExecutionPolicy`:
     * Use `ExecutionPolicy.drop` for payment/checkout/submit buttons (double-tap protection).
     * Use `ExecutionPolicy.restart` (+ optional `debounce`) for live search/type-ahead filters.
     * Use `ExecutionPolicy.queue` for analytics, event logging, or strict FIFO sync.
     * Use `ExecutionPolicy.concurrent` for independent, non-conflicting parallel operations.
   - For trivial UI mutations (e.g. toggles, tab switches), use the inline DSL `on<Intent>((scope, intent) => ...)` inside the `Commander`.

3. ORCHESTRATOR:
   - Define a `class [Feature]Commander extends Commander<[Feature]State, [Feature]Effect>`.
   - Register commands using `bind(MyCommand(...))` in the constructor.
   - Implement `onError` if centralized telemetry (e.g. Crashlytics/Sentry) is needed.

4. UI LAYER:
   - Replace Provider/BlocProvider with `CommanderScope<[Feature]Commander>`.
   - Replace state builders/selectors with `CommanderSelector` or `CommanderStateBuilder`.
   - Replace listeners/snackbars with `CommanderListener<[Feature]Commander, [Feature]Effect>`.
   - Replace event dispatches or notifier method calls with `context.dispatch<[Feature]Commander>(MyIntent())`.
   - If using `BuildContext` reads inside `build()`, use `context.select<[Feature]Commander, State, Slice>((s) => s.slice)`.

5. TESTING:
   - Replace blocTest or ProviderContainer mocks with `TestCommandScope<State, Effect>`.
   - Execute commands directly: `await command.execute(testScope, intent)`.
   - Assert with synchronous expectations: `expect(testScope.states, [...])` and `expect(testScope.effects, [...])`.
```

---

## 📑 Table of Contents
1. [Migrating from `flutter_bloc`](#1-migrating-from-flutter_bloc)
   * [Concept Mapping Table](#concept-mapping-table-bloc)
   * [Step-by-Step Code Translation (Bloc ➔ Commander)](#step-by-step-code-translation-bloc--commander)
   * [Replacing `bloc_concurrency` (RxDart) with Native `ExecutionPolicy`](#replacing-bloc_concurrency-rxdart-with-native-executionpolicy)
   * [Testing: `blocTest` ➔ `TestCommandScope`](#testing-bloctest--testcommandscope)
2. [Migrating from `flutter_riverpod`](#2-migrating-from-flutter_riverpod)
   * [Concept Mapping Table](#concept-mapping-table-riverpod)
   * [Step-by-Step Code Translation (Riverpod ➔ Commander)](#step-by-step-code-translation-riverpod--commander)
   * [Solving Concurrency & Side-Effects from Riverpod](#solving-concurrency--side-effects-from-riverpod)

---

## 1. Migrating from `flutter_bloc`

### Concept Mapping Table (BLoC)

| `flutter_bloc` | `flutter_commander` | Key Architectural Advantage |
| :--- | :--- | :--- |
| `BlocEvent` | `CommandIntent` | Same immutable intent model. |
| `Bloc<Event, State>` | `Commander<State, Effect>` | Eliminates god-blocs by delegating use cases to standalone `Command` classes. |
| `on<Event>((event, emit) async { ... })` | `bind(MyCommand())` or `on<Intent>((scope, intent) => ...)` | Single Responsibility Principle: 1 Command = 1 Use Case. |
| `bloc_concurrency` (`droppable()`, `restartable()`, `sequential()`) | `ExecutionPolicy` (`drop`, `restart`, `queue`, `concurrent`) | **Zero RxDart dependency**. Declarative concurrency built into each Command. |
| Ephemeral flags in State (`hasError`, `navigateToHome: true`) | `emitSideEffect(MyEffect())` | **Pure MVI**: Side-effects travel on a dedicated broadcast stream; no ghost effects on widget rebuild. |
| `BlocProvider` / `MultiBlocProvider` | `CommanderScope` | Scoped lifecycle with automatic disposal. |
| `BlocBuilder` | `CommanderStateBuilder` / `CommanderBuilder` | Granular reactive rebuilds. |
| `BlocSelector` | `CommanderSelector` / `context.select` | Targeted rebuilds based on value equality (`==`). |
| `BlocListener` | `CommanderListener` | Dedicated listener strictly for one-shot effects. |
| `BlocConsumer` | `CommanderStateConsumer` / `CommanderConsumer` | Combined state builder + effect listener. |
| `context.read<B>().add(Event())` | `context.dispatch<C>(Intent())` | Fire-and-forget intention dispatch. |
| `blocTest` | `TestCommandScope` | **Synchronous & deterministic testing** without async stream delays or timers. |

---

### Step-by-Step Code Translation (Bloc ➔ Commander)

#### Step 1: Events ➔ CommandIntents
```dart
// ❌ BEFORE (BLoC)
abstract class CartEvent {}
class AddItemEvent extends CartEvent { final String item; AddItemEvent(this.item); }
class CheckoutEvent extends CartEvent {}

// ✅ AFTER (Commander)
class AddItemIntent extends CommandIntent { final String item; const AddItemIntent(this.item); }
class CheckoutIntent extends CommandIntent { const CheckoutIntent(); }
```

#### Step 2: Separate Persistent State from Ephemeral Side-Effects
```dart
// ❌ BEFORE (BLoC Anti-Pattern: Mixing ephemeral navigation & error flags into persistent state)
class CartState {
  final List<String> items;
  final bool isCheckingOut;
  final String? errorMessage;      // ⚠️ Ghost SnackBar bug when widget rebuilds!
  final bool orderSuccess;         // ⚠️ Ghost Navigation bug on device rotation!
  ...
}

// ✅ AFTER (Commander: Clean MVI separation)
// 1. Persistent Presentation State ONLY:
class CartState {
  final List<String> items;
  final bool isCheckingOut;
  const CartState({this.items = const [], this.isCheckingOut = false});
  CartState copyWith({List<String>? items, bool? isCheckingOut}) => ...;
}

// 2. Ephemeral One-Shot SideEffects:
sealed class CartEffect { const CartEffect(); }
class ShowToastEffect extends CartEffect { final String message; const ShowToastEffect(this.message); }
class OrderSuccessEffect extends CartEffect { final String orderId; const OrderSuccessEffect(this.orderId); }
```

#### Step 3: Decompose the God-Bloc into Standalone Commands
```dart
// ❌ BEFORE (BLoC: God-class handling all use-cases in a single 500-line file)
class CartBloc extends Bloc<CartEvent, CartState> {
  final PaymentService paymentService;
  CartBloc(this.paymentService) : super(const CartState()) {
    on<AddItemEvent>((event, emit) {
      emit(state.copyWith(items: [...state.items, event.item]));
    });

    on<CheckoutEvent>((event, emit) async {
      emit(state.copyWith(isCheckingOut: true));
      try {
        final id = await paymentService.pay(state.items);
        emit(state.copyWith(isCheckingOut: false, orderSuccess: true));
      } catch (e) {
        emit(state.copyWith(isCheckingOut: false, errorMessage: e.toString()));
      }
    }, transformer: droppable()); // Requires package:bloc_concurrency
  }
}

// ✅ AFTER (Commander: Decoupled Command + Lean Commander Orchestrator)

// Dedicated Checkout Command (Single Responsibility & isolated testing):
class CheckoutCommand extends Command<CheckoutIntent, CartState, CartEffect> {
  final PaymentService _paymentService;
  CheckoutCommand(this._paymentService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop; // Built-in double-tap protection!

  @override
  Future<void> execute(CommandScope<CartState, CartEffect> scope, CheckoutIntent intent) async {
    scope.updateState((s) => s.copyWith(isCheckingOut: true));
    try {
      final orderId = await _paymentService.pay(scope.state.items);
      scope.updateState((s) => s.copyWith(isCheckingOut: false, items: const []));
      scope.emitSideEffect(OrderSuccessEffect(orderId));
    } catch (e) {
      scope.updateState((s) => s.copyWith(isCheckingOut: false));
      scope.emitSideEffect(ShowToastEffect('Payment failed: $e'));
    }
  }
}

// The Commander Orchestrator:
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander(PaymentService paymentService) : super(const CartState()) {
    // 1. Bind formal commands
    bind(CheckoutCommand(paymentService));

    // 2. Inline DSL for rapid UI-only mutations
    on<AddItemIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(items: [...s.items, intent.item]));
      scope.emitSideEffect(const ShowToastEffect('Item added!'));
    });
  }
}
```

#### Step 4: UI Widget Migration
```dart
// ❌ BEFORE (BLoC)
BlocProvider(
  create: (context) => CartBloc(PaymentService()),
  child: BlocListener<CartBloc, CartState>(
    listener: (context, state) {
      if (state.errorMessage != null) { ... }
      if (state.orderSuccess) { ... }
    },
    child: BlocSelector<CartBloc, CartState, int>(
      selector: (state) => state.items.length,
      builder: (context, count) {
        return ElevatedButton(
          onPressed: () => context.read<CartBloc>().add(CheckoutEvent()),
          child: Text('Checkout ($count)'),
        );
      },
    ),
  ),
)

// ✅ AFTER (Commander)
CommanderScope<CartCommander>(
  create: (context) => CartCommander(PaymentService()),
  child: CommanderListener<CartCommander, CartEffect>(
    onEffect: (context, effect) {
      switch (effect) {
        case ShowToastEffect(:final message):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        case OrderSuccessEffect(:final orderId):
          Navigator.of(context).pushNamed('/order/$orderId');
      }
    },
    child: CommanderSelector<CartCommander, CartState, int>(
      select: (state) => state.items.length,
      builder: (context, count) {
        return ElevatedButton(
          onPressed: () => context.dispatch<CartCommander>(const CheckoutIntent()),
          child: Text('Checkout ($count)'),
        );
      },
    ),
  ),
)
```

---

### Replacing `bloc_concurrency` (RxDart) with Native `ExecutionPolicy`

| In BLoC (`bloc_concurrency`) | In `flutter_commander` | How it works |
| :--- | :--- | :--- |
| `transformer: droppable()` | `ExecutionPolicy.drop` | Ignores secondary incoming intents while current task is in-flight. |
| `transformer: restartable()` | `ExecutionPolicy.restart` | Cancels in-flight task via `CancellationToken` and executes new intent. |
| `transformer: sequential()` | `ExecutionPolicy.queue` | Strict FIFO execution queue. |
| `transformer: concurrent()` | `ExecutionPolicy.concurrent` | Executes in parallel without blocking. |
| RxDart `debounceTime(300ms)` | `@override Duration get debounce => const Duration(milliseconds: 300);` | Native inactivity delay before triggering. |
| N/A (Difficult in BLoC) | `@override Object? concurrencyKey(intent) => intent.itemId;` | **Keyed Concurrency**: Scopes the policy per item ID independently. |

---

### Testing: `blocTest` ➔ `TestCommandScope`

In BLoC, tests require `blocTest`, which runs asynchronously over stream subscriptions. In `flutter_commander`, unit testing a command is **completely synchronous, deterministic, and widget-free**:

```dart
// ❌ BEFORE (BLoC)
blocTest<CartBloc, CartState>(
  'emits isCheckingOut and success',
  build: () => CartBloc(MockPaymentService()),
  act: (bloc) => bloc.add(CheckoutEvent()),
  wait: const Duration(milliseconds: 100), // Flaky timer wait
  expect: () => [
    CartState(isCheckingOut: true),
    CartState(isCheckingOut: false, orderSuccess: true),
  ],
);

// ✅ AFTER (Commander: Zero async wait, 100% deterministic)
test('CheckoutCommand processes payment and emits success effect', () async {
  final command = CheckoutCommand(MockPaymentService());
  final testScope = TestCommandScope<CartState, CartEffect>(
    const CartState(items: ['MacBook Pro']),
  );

  // Execute directly:
  await command.execute(testScope, const CheckoutIntent());

  // 1. Verify exact chronological state transitions:
  expect(testScope.states, [
    const CartState(items: ['MacBook Pro'], isCheckingOut: true),
    const CartState(items: [], isCheckingOut: false),
  ]);

  // 2. Verify emitted one-shot side-effects:
  expect(testScope.effects, [
    const OrderSuccessEffect('ORD-123'),
  ]);
});
```

---

## 2. Migrating from `flutter_riverpod`

### Concept Mapping Table (Riverpod)

| `flutter_riverpod` | `flutter_commander` | Key Architectural Advantage |
| :--- | :--- | :--- |
| `Notifier<State>` / `AsyncNotifier<State>` | `Commander<State, Effect>` | Formal distinction between state data and one-shot effects. |
| Public methods on Notifier (`notifier.pay()`) | `CommandIntent` dispatch | Decouples caller from implementation; easy to log, queue, or intercept. |
| Global top-level provider variables | Scoped or global `CommanderScope` | Prevents hidden global state; respects the Flutter widget tree lifecycle. |
| `ConsumerWidget` / `WidgetRef` everywhere | Standard `StatelessWidget` + `context.select` / `context.dispatch` | Zero widget boilerplate; no need to extend `ConsumerWidget`. |
| `ref.watch(provider.select(...))` | `CommanderSelector` / `context.select` | Targeted rebuilds based on value equality. |
| `ref.listen(provider, (prev, next) => ...)` | `CommanderListener<C, E>` | Listens to **real one-shot events**, avoiding awkward state diffing to show SnackBars. |
| Manual cancellation (`CancelToken`) | `scope.cancellationToken` + `ExecutionPolicy.restart` | Cooperative cancellation handled declaratively by the framework. |

---

### Step-by-Step Code Translation (Riverpod ➔ Commander)

#### Step 1: Notifier with Methods ➔ Commander with Intents & Commands
```dart
// ❌ BEFORE (Riverpod)
class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void addItem(String item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  Future<void> checkout() async {
    state = state.copyWith(isCheckingOut: true);
    try {
      final id = await ref.read(paymentServiceProvider).pay(state.items);
      state = state.copyWith(isCheckingOut: false, items: []);
      // ⚠️ How to show a SnackBar or navigate cleanly in Riverpod?
      // Requires storing a flag in state or using an auxiliary StateProvider!
    } catch (e) {
      state = state.copyWith(isCheckingOut: false);
    }
  }
}

// ✅ AFTER (Commander)
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander(PaymentService paymentService) : super(const CartState()) {
    bind(CheckoutCommand(paymentService));

    on<AddItemIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(items: [...s.items, intent.item]));
      scope.emitSideEffect(const ShowToastEffect('Item added!'));
    });
  }
}
```

#### Step 2: Widget Consumption (No `ConsumerWidget` required!)
```dart
// ❌ BEFORE (Riverpod: Requires ConsumerWidget & WidgetRef parameter)
class CartView extends ConsumerWidget {
  const CartView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listening to state changes for SnackBars requires diffing previous & next state:
    ref.listen<CartState>(cartProvider, (prev, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error')));
      }
    });

    final itemCount = ref.watch(cartProvider.select((s) => s.items.length));

    return ElevatedButton(
      onPressed: () => ref.read(cartProvider.notifier).checkout(),
      child: Text('Checkout ($itemCount)'),
    );
  }
}

// ✅ AFTER (Commander: Standard StatelessWidget with clean context extensions)
class CartView extends StatelessWidget {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. One-shot side-effect listener (SnackBars, Navigation)
    return CommanderListener<CartCommander, CartEffect>(
      onEffect: (context, effect) {
        if (effect is ShowToastEffect) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(effect.message)));
        }
      },
      // 2. Granular rebuild with context.select:
      child: Builder(
        builder: (context) {
          final count = context.select<CartCommander, CartState, int>((s) => s.items.length);

          return ElevatedButton(
            onPressed: () => context.dispatch<CartCommander>(const CheckoutIntent()),
            child: Text('Checkout ($count)'),
          );
        },
      ),
    );
  }
}
```

---

## 💡 Migration Best Practices & Checklist

- [ ] **Never put navigation or SnackBar flags in `State`**: Use `emitSideEffect(MyEffect())` and handle it in `CommanderListener`.
- [ ] **Eliminate Double-Taps**: Change submit and checkout buttons to `ExecutionPolicy.drop`.
- [ ] **Debounce Searches**: Use `ExecutionPolicy.restart` and `get debounce => const Duration(milliseconds: 300);`.
- [ ] **Keep States Immutable**: Always return a new instance from `updateState((s) => s.copyWith(...))`.
- [ ] **Test Units with `TestCommandScope`**: Don't mock streams, notifiers, or commanders for use-case testing—test `Command.execute()` directly.
