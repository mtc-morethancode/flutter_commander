# 🔄 Migration Guide: From BLoC to `flutter_commander`

> **Designed for both Human Developers and AI Coding Assistants (Cursor, Copilot, Claude, ChatGPT, Antigravity).**

This guide provides deterministic mapping rules, architectural equivalences, and side-by-side code comparisons to migrate from **`flutter_bloc`** to **`flutter_commander`**.

---

## 🤖 AI Agent Migration Prompt (Copy & Paste into your AI Assistant)

If you are using Cursor, GitHub Copilot, Claude, ChatGPT, or Antigravity to migrate your BLoC codebase, paste the following prompt into your assistant:

```markdown
You are an expert Flutter architect specializing in MVI and unidirectional data flow.
Your task is to refactor the provided BLoC feature from `flutter_bloc` to `flutter_commander`.

Follow these strict migration rules:
1. DOMAIN LAYER:
   - Convert all `BlocEvent` classes into immutable `CommandIntent` subclasses.
   - Separate persistent presentation data into an immutable `State` class.
   - Extract ephemeral events (navigation, SnackBars, dialogs, toasts, one-off alerts) out of the state into a `sealed class` of one-shot `SideEffect`s. Never store navigation or error flags in State.

2. COMMAND & BUSINESS LOGIC:
   - Replace complex asynchronous operations with isolated `Command<Intent, State, Effect>` classes.
   - Replace RxDart/bloc_concurrency transformers with native `ExecutionPolicy`:
     * Use `ExecutionPolicy.drop` for payment/checkout/submit buttons (double-tap protection, replaces `droppable()`).
     * Use `ExecutionPolicy.restart` (+ optional `debounce`) for live search/type-ahead filters (replaces `restartable()`).
     * Use `ExecutionPolicy.queue` for analytics, event logging, or strict FIFO sync (replaces `sequential()`).
     * Use `ExecutionPolicy.concurrent` for independent, non-conflicting parallel operations.
   - For trivial UI mutations (e.g. toggles, tab switches), use the inline DSL `on<Intent>((scope, intent) => ...)` inside the `Commander`.

3. ORCHESTRATOR:
   - Define a `class [Feature]Commander extends Commander<[Feature]State, [Feature]Effect>`.
   - Register commands using `bind(MyCommand(...))` in the constructor.
   - Implement `onError` if centralized error telemetry (e.g. Crashlytics/Sentry) is needed.

4. UI LAYER:
   - Replace `BlocProvider` with `CommanderScope<[Feature]Commander>`.
   - Replace `BlocConsumer` or nested `BlocListener` + `BlocBuilder` with `CommanderView<[Feature]Commander, State, Effect>`.
   - Replace `buildWhen` with `shouldRebuild(previous, current)`.
   - Put one-shot UI logic (SnackBars, dialogs, route navigation) inside `onEffect: (context, effect)`. Note that `CommanderView` automatically validates that the widget is mounted before executing `onEffect`.
   - Replace `context.read<Bloc>().add(Event())` with `context.dispatch<[Feature]Commander>(Intent())`.
   - For granular sub-tree rebuilding, use `CommanderSelector` or `context.select(([Feature]Commander c) => c.state.slice)`.

5. TESTING:
   - Replace `blocTest` stream mocks with `TestCommandScope<State, Effect>`.
   - Execute commands directly: `await command.execute(testScope, intent)`.
   - Assert with synchronous expectations: `expect(testScope.states, [...])` and `expect(testScope.effects, [...])`.
```

---

## 📑 Table of Contents
1. [Architectural Overview: Why Migrate?](#architectural-overview-why-migrate)
2. [Concept Mapping Table](#concept-mapping-table)
3. [Step-by-Step Code Translation](#step-by-step-code-translation)
   * [Step 1: Events ➔ CommandIntents](#step-1-events--commandintents)
   * [Step 2: Clean State & Ephemeral SideEffects](#step-2-clean-state--ephemeral-sideeffects)
   * [Step 3: Decompose the God-Bloc into Standalone Commands](#step-3-decompose-the-god-bloc-into-standalone-commands)
   * [Step 4: Orchestrate with Commander](#step-4-orchestrate-with-commander)
   * [Step 5: UI Layer Migration (`BlocConsumer` ➔ `CommanderView`)](#step-5-ui-layer-migration-blocconsumer--commanderview)
4. [Replacing `bloc_concurrency` (RxDart) with Native `ExecutionPolicy`](#replacing-bloc_concurrency-rxdart-with-native-executionpolicy)
5. [Testing: `blocTest` ➔ `TestCommandScope`](#testing-bloctest--testcommandscope)
6. [Migration Checklist](#migration-checklist)

---

## Architectural Overview: Why Migrate?

While BLoC popularized unidirectional data flow in Flutter, enterprise production codebases frequently hit these pain points:

1. **The God-Bloc Anti-Pattern**: As features grow, a single BLoC class often balloons to 500–1500 lines, handling dozens of events and multiple repository dependencies in one monolithic file.
2. **RxDart Complexity for Concurrency**: Solving simple race conditions (like debouncing a search or dropping duplicate payment clicks) requires adding `bloc_concurrency` and writing custom RxDart stream transformers.
3. **Ghost Side-Effects**: Because BLoC only has `State`, developers store transient flags like `errorMessage` or `navigateToHome: true` in the state. When the widget tree rebuilds (e.g. on keyboard open or screen rotation), SnackBars and navigations re-trigger unintentionally.
4. **Widget Nesting Pyramid**: Handling state rebuilds and side-effects often produces ugly nesting: `BlocProvider` > `BlocListener` > `BlocBuilder` > `Scaffold`.

**`flutter_commander` solves every one of these problems:**
- **1 Command = 1 Use Case** (Single Responsibility Principle).
- **Native `ExecutionPolicy`** (`drop`, `restart`, `queue`, `concurrent`) with zero external stream libraries.
- **First-class `SideEffect` channel** (one-shot broadcast stream; never pollutes state).
- **`CommanderView`**: A single, clean widget that handles state building, side effects, and intent dispatch with zero nested pyramids.
- **Cold-Start Side Effect Buffering**: Side effects emitted during initialization are buffered until UI listeners mount, so toasts and route redirects are never lost.

---

## Concept Mapping Table

| `flutter_bloc` | `flutter_commander` | Key Architectural Advantage |
| :--- | :--- | :--- |
| `BlocEvent` | `CommandIntent` | Same immutable intent model. |
| `Bloc<Event, State>` | `Commander<State, Effect>` | Eliminates god-blocs by delegating use cases to standalone `Command` classes. |
| `on<Event>((event, emit) async { ... })` | `bind(MyCommand())` or `on<Intent>((scope, intent) => ...)` | Single Responsibility Principle: 1 Command = 1 Use Case. |
| `bloc_concurrency` (`droppable()`, `restartable()`, `sequential()`) | `ExecutionPolicy` (`drop`, `restart`, `queue`, `concurrent`) | **Zero RxDart dependency**. Declarative concurrency built into each Command. |
| Ephemeral flags in State (`errorMessage`, `orderSuccess: true`) | `emitSideEffect(MyEffect())` | **Pure MVI**: Side-effects travel on a dedicated broadcast stream; no ghost effects on widget rebuild. |
| `BlocProvider` / `MultiBlocProvider` | `CommanderScope` | Scoped lifecycle with automatic disposal and inherited commander swapping safety. |
| `BlocBuilder` | `CommanderStateBuilder` / `CommanderBuilder` | Granular reactive rebuilds. |
| `BlocSelector` | `CommanderSelector` / `context.select` | Targeted rebuilds based on value equality (`==`). |
| `BlocListener` | `CommanderListener` | Dedicated listener strictly for one-shot effects (with auto mounted check). |
| `BlocConsumer` / Nested Listener+Builder | `CommanderView` | **Zero nesting**: Provides `state`, `onEffect`, and `shouldRebuild` in one unified widget. |
| `buildWhen: (prev, curr) => ...` | `shouldRebuild: (prev, curr) => ...` | Granular rebuild filtering without boilerplate. |
| `context.read<B>().add(Event())` | `context.dispatch<C>(Intent())` | Fire-and-forget intention dispatch. |
| `blocTest` | `TestCommandScope` | **Synchronous & deterministic testing** without async stream delays, fake timers, or pump delays. |

---

## Step-by-Step Code Translation

### Step 1: Events ➔ CommandIntents

BLoC events map directly to `CommandIntent`s. Make them immutable with `const` constructors:

```dart
// ❌ BEFORE (BLoC)
abstract class CartEvent {}
class AddItemEvent extends CartEvent { final String item; AddItemEvent(this.item); }
class CheckoutEvent extends CartEvent {}
class SearchEvent extends CartEvent { final String query; SearchEvent(this.query); }

// ✅ AFTER (Commander)
class AddItemIntent extends CommandIntent { final String item; const AddItemIntent(this.item); }
class CheckoutIntent extends CommandIntent { const CheckoutIntent(); }
class SearchIntent extends CommandIntent { final String query; const SearchIntent(this.query); }
```

---

### Step 2: Clean State & Ephemeral SideEffects

Stop storing transient errors, toasts, and navigation flags inside your presentation state.

```dart
// ❌ BEFORE (BLoC: Ghost SnackBar & Ghost Navigation Anti-Pattern)
class CartState {
  final List<String> items;
  final bool isCheckingOut;
  final String? errorMessage;  // ⚠️ Re-shows SnackBar when keyboard opens or screen rotates!
  final bool orderSuccess;     // ⚠️ Navigates again if widget rebuilds!

  const CartState({
    this.items = const [],
    this.isCheckingOut = false,
    this.errorMessage,
    this.orderSuccess = false,
  });

  CartState copyWith({
    List<String>? items,
    bool? isCheckingOut,
    String? errorMessage,
    bool? orderSuccess,
  }) => ...;
}

// ✅ AFTER (Commander: Clean MVI separation)

// 1. Persistent Presentation State ONLY:
class CartState {
  final List<String> items;
  final bool isCheckingOut;

  const CartState({this.items = const [], this.isCheckingOut = false});

  CartState copyWith({List<String>? items, bool? isCheckingOut}) => CartState(
    items: items ?? this.items,
    isCheckingOut: isCheckingOut ?? this.isCheckingOut,
  );
}

// 2. Ephemeral One-Shot SideEffects (SnackBars, Navigation, Modals):
sealed class CartEffect { const CartEffect(); }
class ShowToastEffect extends CartEffect { final String message; const ShowToastEffect(this.message); }
class OrderSuccessEffect extends CartEffect { final String orderId; const OrderSuccessEffect(this.orderId); }
```

---

### Step 3: Decompose the God-Bloc into Standalone Commands

Instead of packing payment, search, and checkout logic into one huge BLoC file, each complex use-case becomes an isolated `Command`.

```dart
// ❌ BEFORE (BLoC: Everything crammed into one giant class)
class CartBloc extends Bloc<CartEvent, CartState> {
  final PaymentService paymentService;
  final CatalogService catalogService;

  CartBloc(this.paymentService, this.catalogService) : super(const CartState()) {
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
    }, transformer: droppable()); // Requires bloc_concurrency package

    on<SearchEvent>((event, emit) async {
      final results = await catalogService.search(event.query);
      emit(state.copyWith(items: results));
    }, transformer: restartable()); // Requires bloc_concurrency package
  }
}
```

```dart
// ✅ AFTER (Commander: Isolated, Single-Responsibility Command)
class CheckoutCommand extends Command<CheckoutIntent, CartState, CartEffect> {
  final PaymentService _paymentService;
  CheckoutCommand(this._paymentService);

  // Declarative double-tap protection built right in:
  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

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

### Step 4: Orchestrate with Commander

The `Commander` acts as a lean orchestrator. It binds formal commands and provides an inline DSL for simple UI state changes:

```dart
class CartCommander extends Commander<CartState, CartEffect> {
  CartCommander({
    required PaymentService paymentService,
    required CatalogService catalogService,
  }) : super(const CartState()) {
    // 1. Bind formal isolated use cases
    bind(CheckoutCommand(paymentService));
    bind(SearchProductsCommand(catalogService));

    // 2. Inline DSL for quick UI-only mutations
    on<AddItemIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(items: [...s.items, intent.item]));
      scope.emitSideEffect(const ShowToastEffect('Item added to cart!'));
    });
  }

  @override
  void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
    // Centralized crash reporting / telemetry
    debugPrint('Command failed: $intent with $error');
  }
}
```

---

### Step 5: UI Layer Migration (`BlocConsumer` ➔ `CommanderView`)

In BLoC, combining state building and side effects requires `BlocConsumer` or nesting `BlocListener` and `BlocBuilder`. With `flutter_commander`, **`CommanderView`** simplifies this into a single, clean class.

#### Before (BLoC):
```dart
BlocProvider(
  create: (context) => CartBloc(PaymentService(), CatalogService()),
  child: BlocConsumer<CartBloc, CartState>(
    listenWhen: (prev, curr) => curr.errorMessage != null || curr.orderSuccess,
    listener: (context, state) {
      if (state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
      }
      if (state.orderSuccess) {
        Navigator.of(context).pushNamed('/order-success');
      }
    },
    buildWhen: (prev, curr) => prev.items != curr.items || prev.isCheckingOut != curr.isCheckingOut,
    builder: (context, state) {
      return Scaffold(
        appBar: AppBar(title: Text('Cart (${state.items.length})')),
        body: state.isCheckingOut
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: state.items.length,
                itemBuilder: (context, index) => ListTile(title: Text(state.items[index])),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.read<CartBloc>().add(CheckoutEvent()),
          child: const Icon(Icons.payment),
        ),
      );
    },
  ),
)
```

#### After (Commander):
```dart
// Wrap with CommanderScope at the route or screen root:
CommanderScope<CartCommander>(
  create: (context) => CartCommander(
    paymentService: PaymentService(),
    catalogService: CatalogService(),
  ),
  child: const CartPage(),
)

// The Page extends CommanderView: Zero nested pyramids!
class CartPage extends CommanderView<CartCommander, CartState, CartEffect> {
  const CartPage({super.key});

  // Replaces buildWhen: Optional fine-grained rebuild filter
  @override
  bool shouldRebuild(CartState previous, CartState current) {
    return previous.items != current.items || previous.isCheckingOut != current.isCheckingOut;
  }

  // Replaces BlocListener: One-shot side-effects (safe & auto-validated for mounted context)
  @override
  void onEffect(BuildContext context, CartEffect effect) {
    switch (effect) {
      case ShowToastEffect(:final message):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      case OrderSuccessEffect(:final orderId):
        Navigator.of(context).pushNamed('/order-success/$orderId');
    }
  }

  // Clean build method with direct state access
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

## Replacing `bloc_concurrency` (RxDart) with Native `ExecutionPolicy`

In BLoC, concurrency requires the external `bloc_concurrency` package and RxDart transformers. In `flutter_commander`, concurrency is a built-in first-class property of every `Command`:

| In BLoC (`bloc_concurrency`) | In `flutter_commander` | How it works |
| :--- | :--- | :--- |
| `transformer: droppable()` | `ExecutionPolicy.drop` | Ignores subsequent incoming intents while the current execution is in-flight. |
| `transformer: restartable()` | `ExecutionPolicy.restart` | Cooperatively cancels active execution via `CancellationToken` and begins the new one. |
| `transformer: sequential()` | `ExecutionPolicy.queue` | Strict FIFO execution queue. |
| `transformer: concurrent()` | `ExecutionPolicy.concurrent` | Executes in parallel without blocking. |
| RxDart `debounceTime(300ms)` | `@override Duration get debounce => const Duration(milliseconds: 300);` | Native debounce timer before triggering. |
| Not supported out-of-the-box | `@override Object? concurrencyKey(intent) => intent.itemId;` | **Keyed Concurrency**: Scopes concurrency policies per entity ID independently. |

---

## Testing: `blocTest` ➔ `TestCommandScope`

In BLoC, unit testing requires `blocTest`, which runs asynchronously against stream emissions and often requires flaky timer delays. In `flutter_commander`, commands are tested **synchronously, deterministically, and with zero stream mocking**:

```dart
// ❌ BEFORE (BLoC: Flaky stream delays & stream expectations)
blocTest<CartBloc, CartState>(
  'emits isCheckingOut and success when checkout succeeds',
  build: () => CartBloc(MockPaymentService(), MockCatalogService()),
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

## Migration Checklist

- [ ] **Extract Ephemeral Flags from State**: Remove `errorMessage`, `isLoading`, `isSuccess`, or `navigationRoute` from your `State` classes and move them to sealed `SideEffect` classes.
- [ ] **Convert `BlocEvent` to `CommandIntent`**: Create immutable `CommandIntent` classes with `const` constructors.
- [ ] **Break Down Large BLoCs into `Command`s**: Put complex asynchronous logic into standalone `Command` classes.
- [ ] **Replace RxDart Transformers**: Use `ExecutionPolicy.drop` for buttons/payments, `ExecutionPolicy.restart` + `debounce` for search.
- [ ] **Migrate UI to `CommanderView`**: Replace nested `BlocConsumer` / `BlocListener` / `BlocBuilder` with `CommanderView`.
- [ ] **Replace `buildWhen` with `shouldRebuild`**: If you used `buildWhen` in `BlocBuilder`, override `shouldRebuild` in `CommanderView`.
- [ ] **Switch Tests to `TestCommandScope`**: Replace `blocTest` with fast, deterministic tests using `TestCommandScope`.
