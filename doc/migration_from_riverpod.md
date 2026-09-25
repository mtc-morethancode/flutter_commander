# 🔄 Migration Guide: From Riverpod to `flutter_commander`

> **Designed for both Human Developers and AI Coding Assistants (Cursor, Copilot, Claude, ChatGPT, Antigravity).**

This guide provides deterministic mapping rules, architectural equivalences, and side-by-side code comparisons to migrate from **`flutter_riverpod`** to **`flutter_commander`**.

---

## 🤖 AI Agent Migration Prompt (Copy & Paste into your AI Assistant)

If you are using Cursor, GitHub Copilot, Claude, ChatGPT, or Antigravity to migrate your Riverpod codebase, paste the following prompt into your assistant:

```markdown
You are an expert Flutter architect specializing in MVI and unidirectional data flow.
Your task is to refactor the provided Riverpod feature from `flutter_riverpod` to `flutter_commander`.

Follow these strict migration rules:
1. DOMAIN LAYER:
   - Convert all public Notifier methods into immutable `CommandIntent` subclasses.
   - Separate persistent presentation data into an immutable `State` class.
   - Extract ephemeral events (navigation, SnackBars, dialogs, toasts) out of the state into a `sealed class` of one-shot `SideEffect`s. Do not use state diffing or artificial flags to trigger side effects.

2. COMMAND & BUSINESS LOGIC:
   - Replace complex asynchronous operations with isolated `Command<Intent, State, Effect>` classes.
   - Assign the appropriate `ExecutionPolicy`:
     * Use `ExecutionPolicy.drop` for payment/checkout/submit operations (prevents duplicate requests).
     * Use `ExecutionPolicy.restart` (+ optional `debounce`) for search or type-ahead operations.
     * Use `ExecutionPolicy.queue` for analytics, logging, or sequential sync.
     * Use `ExecutionPolicy.concurrent` for independent parallel executions.
   - For simple UI state mutations, use the inline DSL `on<Intent>((scope, intent) => ...)` inside the `Commander`.

3. ORCHESTRATOR:
   - Replace global Notifier/AsyncNotifier classes with `class [Feature]Commander extends Commander<[Feature]State, [Feature]Effect>`.
   - Register commands using `bind(MyCommand(...))` in the constructor.
   - Implement `onError` if centralized error reporting is required.

4. UI LAYER:
   - Replace top-level global provider declarations with `CommanderScope<[Feature]Commander>`.
   - Replace `ConsumerWidget` or `ConsumerStatefulWidget` with standard `StatelessWidget` and `CommanderView<[Feature]Commander, State, Effect>`.
   - Move side-effect handling out of `ref.listen` and into `onEffect: (context, effect)`. Note that `CommanderView` automatically validates that the widget is mounted before executing `onEffect`.
   - Replace `ref.read(provider.notifier).myMethod()` with `context.dispatch<[Feature]Commander>(MyIntent())`.
   - Replace `ref.watch(provider.select((s) => s.slice))` with `context.select<[Feature]Commander, State, Slice>((s) => s.slice)` or `CommanderSelector`.

5. TESTING:
   - Replace `ProviderContainer` mocks with `TestCommandScope<State, Effect>`.
   - Execute commands directly: `await command.execute(testScope, intent)`.
   - Assert with synchronous expectations: `expect(testScope.states, [...])` and `expect(testScope.effects, [...])`.
```

---

## 📑 Table of Contents
1. [Architectural Overview: Why Migrate?](#architectural-overview-why-migrate)
2. [Concept Mapping Table](#concept-mapping-table)
3. [Step-by-Step Code Translation](#step-by-step-code-translation)
   * [Step 1: Notifier Methods ➔ CommandIntents](#step-1-notifier-methods--commandintents)
   * [Step 2: Clean State & One-Shot SideEffects](#step-2-clean-state--one-shot-sideeffects)
   * [Step 3: Standalone Commands with Declarative Concurrency](#step-3-standalone-commands-with-declarative-concurrency)
   * [Step 4: The Commander Orchestrator](#step-4-the-commander-orchestrator)
   * [Step 5: UI Migration (`ConsumerWidget` ➔ `CommanderView`)](#step-5-ui-migration-consumerwidget--commanderview)
4. [Solving Concurrency & Ephemeral Events without Workarounds](#solving-concurrency--ephemeral-events-without-workarounds)
5. [Testing: `ProviderContainer` ➔ `TestCommandScope`](#testing-providercontainer--testcommandscope)
6. [Migration Checklist](#migration-checklist)

---

## Architectural Overview: Why Migrate?

Riverpod is a popular reactive dependency and state management library, but developers frequently encounter hurdles in enterprise apps:

1. **Global Provider Pollution**: Riverpod encourages declaring providers as global top-level variables (`final myProvider = ...`). This makes multi-instance scoping (e.g. multiple tabs, master-detail lists, or scoped sub-flows) complex and unintuitive compared to Flutter's native widget tree hierarchy.
2. **Lack of First-Class One-Shot Side Effects**: Riverpod has no dedicated stream or channel for one-time events like SnackBars, dialogs, or navigation. Developers resort to anti-patterns: diffing state inside `ref.listen` in `build()`, or creating artificial wrapper states with IDs.
3. **Missing Concurrency Primitives**: Preventing double-taps on checkout or cancelling in-flight search queries requires manual boilerplate (holding `CancelToken` instances or tracking `bool _isExecuting`).
4. **Widget Boilerplate (`ConsumerWidget` & `WidgetRef`)**: Developers must replace standard `StatelessWidget` with `ConsumerWidget` or pass `WidgetRef` around, creating tight coupling to Riverpod across the UI.

**`flutter_commander` provides clean solutions:**
- **Scoped & Predictable Lifecycle**: Tied directly to the Flutter widget hierarchy via `CommanderScope`.
- **First-Class One-Shot SideEffects**: A dedicated broadcast channel with cold-start buffering guarantees toasts and navigation events are never lost or re-triggered on widget rebuild.
- **Built-in `ExecutionPolicy`**: `drop`, `restart`, `queue`, and `concurrent` without boilerplate.
- **`CommanderView`**: A unified widget combining state reactivity, side-effects, and intent dispatch without requiring special consumer widget wrappers.

---

## Concept Mapping Table

| `flutter_riverpod` | `flutter_commander` | Key Architectural Advantage |
| :--- | :--- | :--- |
| `Notifier<State>` / `AsyncNotifier<State>` | `Commander<State, Effect>` | Formal distinction between persistent state data and one-shot effects. |
| Public methods on Notifier (`notifier.pay()`) | `CommandIntent` dispatch | Decouples caller from implementation; easy to log, queue, or intercept. |
| Global top-level provider variables | Scoped or global `CommanderScope` | Prevents hidden global state; respects the Flutter widget tree lifecycle. |
| `ConsumerWidget` / `WidgetRef` everywhere | `CommanderView` or standard `StatelessWidget` | Zero widget boilerplate; no need to extend `ConsumerWidget`. |
| `ref.watch(provider.select(...))` | `CommanderSelector` / `context.select` | Targeted rebuilds based on value equality (`==`). |
| `ref.listen(provider, (prev, next) => ...)` | `CommanderView.onEffect` or `CommanderListener` | Listens to **real one-shot events**, avoiding awkward state diffing to show SnackBars. |
| Manual cancellation (`CancelToken`) | `scope.cancellationToken` + `ExecutionPolicy.restart` | Cooperative cancellation handled declaratively by the framework. |
| `ProviderContainer` testing | `TestCommandScope` | Fast, deterministic unit tests without container overrides. |

---

## Step-by-Step Code Translation

### Step 1: Notifier Methods ➔ CommandIntents

In Riverpod, UI components call methods directly on the notifier. In `flutter_commander`, interactions are represented as immutable `CommandIntent`s:

```dart
// ❌ BEFORE (Riverpod: Direct method invocation on Notifier)
class CartNotifier extends Notifier<CartState> {
  void addItem(String item) { ... }
  Future<void> checkout() async { ... }
  void search(String query) { ... }
}

// ✅ AFTER (Commander: Immutable Intents)
class AddItemIntent extends CommandIntent { final String item; const AddItemIntent(this.item); }
class CheckoutIntent extends CommandIntent { const CheckoutIntent(); }
class SearchIntent extends CommandIntent { final String query; const SearchIntent(this.query); }
```

---

### Step 2: Clean State & One-Shot SideEffects

In Riverpod, handling a SnackBar or navigation often requires storing transient error flags in the state or diffing `prev` and `next`:

```dart
// ❌ BEFORE (Riverpod: Ephemeral flags in State)
class CartState {
  final List<String> items;
  final bool isCheckingOut;
  final String? errorMessage; // ⚠️ Stored in state just to show a SnackBar!

  const CartState({this.items = const [], this.isCheckingOut = false, this.errorMessage});

  CartState copyWith({List<String>? items, bool? isCheckingOut, String? errorMessage}) => ...;
}

// ✅ AFTER (Commander: Pure State + Dedicated SideEffects)
class CartState {
  final List<String> items;
  final bool isCheckingOut;

  const CartState({this.items = const [], this.isCheckingOut = false});

  CartState copyWith({List<String>? items, bool? isCheckingOut}) => CartState(
    items: items ?? this.items,
    isCheckingOut: isCheckingOut ?? this.isCheckingOut,
  );
}

// Dedicated one-shot broadcast channel:
sealed class CartEffect { const CartEffect(); }
class ShowToastEffect extends CartEffect { final String message; const ShowToastEffect(this.message); }
class OrderSuccessEffect extends CartEffect { final String orderId; const OrderSuccessEffect(this.orderId); }
```

---

### Step 3: Standalone Commands with Declarative Concurrency

Instead of writing manual flags to prevent double-taps on checkout or managing timers for search debouncing, use isolated `Command` classes:

```dart
// ❌ BEFORE (Riverpod: Manual boolean guard & manual error handling)
class CartNotifier extends Notifier<CartState> {
  Future<void> checkout() async {
    if (state.isCheckingOut) return; // Manual double-tap guard

    state = state.copyWith(isCheckingOut: true);
    try {
      final orderId = await ref.read(paymentServiceProvider).pay(state.items);
      state = state.copyWith(isCheckingOut: false, items: []);
      // How do we navigate or show a SnackBar now?
    } catch (e) {
      state = state.copyWith(isCheckingOut: false, errorMessage: e.toString());
    }
  }
}

// ✅ AFTER (Commander: Declarative ExecutionPolicy.drop + Clean Effects)
class CheckoutCommand extends Command<CheckoutIntent, CartState, CartEffect> {
  final PaymentService _paymentService;
  CheckoutCommand(this._paymentService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop; // Native double-tap protection

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
```

---

### Step 4: The Commander Orchestrator

The `Commander` wires together formal commands and provides an inline DSL for simple UI state updates:

```dart
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander(PaymentService paymentService) : super(const CartState()) {
    // 1. Bind formal isolated use cases
    bind(CheckoutCommand(paymentService));

    // 2. Inline DSL for rapid UI-only mutations
    on<AddItemIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(items: [...s.items, intent.item]));
      scope.emitSideEffect(const ShowToastEffect('Item added!'));
    });
  }
}
```

---

### Step 5: UI Migration (`ConsumerWidget` ➔ `CommanderView`)

Say goodbye to `ConsumerWidget`, `WidgetRef`, and awkward `ref.listen` in `build()`. With `CommanderView`, your UI is clean, reactive, and self-contained:

#### Before (Riverpod):
```dart
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ Listening in build requires manual diffing:
    ref.listen<CartState>(cartNotifierProvider, (prev, next) {
      if (next.errorMessage != null && prev?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final state = ref.watch(cartNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Cart (${state.items.length})')),
      body: state.isCheckingOut
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) => ListTile(title: Text(state.items[index])),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(cartNotifierProvider.notifier).checkout(),
        child: const Icon(Icons.payment),
      ),
    );
  }
}
```

#### After (Commander):
```dart
// Provide scope at the screen or route root:
CommanderScope<CartCommander>(
  create: (context) => CartCommander(PaymentService()),
  child: const CartPage(),
)

// The Page extends CommanderView: Pure Flutter widget, zero Consumer boilerplate!
class CartPage extends CommanderView<CartCommander, CartState, CartEffect> {
  const CartPage({super.key});

  // Replaces ref.listen: dedicated one-shot effect handler with auto-mounted context check
  @override
  void onEffect(BuildContext context, CartEffect effect) {
    switch (effect) {
      case ShowToastEffect(:final message):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      case OrderSuccessEffect(:final orderId):
        Navigator.of(context).pushNamed('/order-success/$orderId');
    }
  }

  // Optional rebuild filter (replaces complex select diffs)
  @override
  bool shouldRebuild(CartState previous, CartState current) {
    return previous.items != current.items || previous.isCheckingOut != current.isCheckingOut;
  }

  @override
  Widget build(BuildContext context, CartState state) {
    return Scaffold(
      appBar: AppBar(title: Text('Cart (${state.items.length})')),
      body: state.isCheckingOut
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) => ListTile(title: Text(state.items[index])),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.dispatch<CartCommander>(const CheckoutIntent()),
        child: const Icon(Icons.payment),
      ),
    );
  }
}
```

---

## Solving Concurrency & Ephemeral Events without Workarounds

| Requirement | In Riverpod | In `flutter_commander` |
| :--- | :--- | :--- |
| **Prevent double-taps on submit** | Manual `bool _isSubmitting` flag in state | `ExecutionPolicy.drop` on `Command` |
| **Type-ahead search cancellation** | Manual `CancelToken` or timer management | `ExecutionPolicy.restart` + `debounce` |
| **Show SnackBar once** | Diff `prev` and `next` in `ref.listen` | `emitSideEffect(MyEffect())` |
| **Cold-start side effects** | Missed or lost if listener attaches late | Buffered automatically until UI mounts |
| **Granular sub-widget rebuilds** | `ref.watch(provider.select(...))` | `context.select<C, S, R>((s) => s.slice)` |

---

## Testing: `ProviderContainer` ➔ `TestCommandScope`

Testing a Riverpod notifier requires configuring a `ProviderContainer` with overrides and awaiting asynchronous microtasks. In `flutter_commander`, command logic is tested in isolation with **zero mock overhead**:

```dart
// ❌ BEFORE (Riverpod: ProviderContainer setup & overrides)
test('checkout updates state and clears cart', () async {
  final container = ProviderContainer(
    overrides: [
      paymentServiceProvider.overrideWithValue(MockPaymentService()),
    ],
  );
  addTearDown(container.dispose);

  await container.read(cartNotifierProvider.notifier).checkout();

  expect(container.read(cartNotifierProvider).items, isEmpty);
});

// ✅ AFTER (Commander: Pure synchronous & isolated testing)
test('CheckoutCommand processes payment and emits success effect', () async {
  final command = CheckoutCommand(MockPaymentService());
  final testScope = TestCommandScope<CartState, CartEffect>(
    const CartState(items: ['MacBook Pro']),
  );

  await command.execute(testScope, const CheckoutIntent());

  expect(testScope.states, [
    const CartState(items: ['MacBook Pro'], isCheckingOut: true),
    const CartState(items: [], isCheckingOut: false),
  ]);

  expect(testScope.effects, [
    const OrderSuccessEffect('ORD-123'),
  ]);
});
```

---

## Migration Checklist

- [ ] **Remove Global Provider Declarations**: Declare commanders inside `CommanderScope` widgets tied to the widget tree.
- [ ] **Convert Public Notifier Methods into `CommandIntent`s**: Decouple the UI triggers from business execution.
- [ ] **Separate One-Shot Effects**: Move SnackBars, toasts, and navigation from state variables to sealed `SideEffect` classes.
- [ ] **Adopt `ExecutionPolicy`**: Replace manual double-tap flags with `ExecutionPolicy.drop` and search debounce timers with `ExecutionPolicy.restart`.
- [ ] **Replace `ConsumerWidget` with `CommanderView`**: Remove `WidgetRef ref` parameters and implement `build(context, state)` and `onEffect(context, effect)`.
- [ ] **Migrate Tests to `TestCommandScope`**: Test commands directly without setting up container overrides.
