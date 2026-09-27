<p align="center">
  <img src="https://raw.githubusercontent.com/mtc-morethancode/flutter_commander/main/doc/assets/logo.png" alt="flutter_commander logo" width="160" />
</p>

<h1 align="center">flutter_commander</h1>

<p align="center">
  <b>Enterprise MVI + Command Pattern architecture for Flutter.</b><br>
  Declarative concurrency, strict decoupling, one-shot side effects, and zero code generation.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_commander"><img src="https://img.shields.io/badge/pub-v1.0.0-blue.svg" alt="pub package" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.0+-0175C2.svg" alt="Dart SDK" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.10+-02569B.svg" alt="Flutter" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/coverage-96%25-brightgreen.svg" alt="Coverage" />
  <a href="https://mtc-morethancode.github.io/flutter_commander/"><img src="https://img.shields.io/badge/docs-GitHub_Pages-blue.svg" alt="Documentation" /></a>
</p>

---

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
* 🏛️ **Engineered for TDD, SDD & AI Pair-Programming:** Isolated command units and deterministic test contracts eliminate flakiness, making test-driven development and AI coding assistants fast and reliable.
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

## 🏛️ Engineering Excellence: TDD, SDD, XP & AI Pair-Programming

`flutter_commander` is intentionally built around battle-tested software engineering disciplines: **Test-Driven Development (TDD)**, **Spec-Driven Development (SDD)**, and **Extreme Programming (XP)**. This architectural clarity makes Commander remarkably intuitive for human engineering teams and highly effective when collaborating with modern AI coding agents.

```
   ┌────────────────────────────────────────────────────────┐
   │ 1. Spec-Driven Development (SDD)                       │
   │    Human / Architect writes formal commanderTest()     │
   └───────────────────────────┬────────────────────────────┘
                               │ Executable Contract (Red)
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 2. Test-Driven Development (TDD)                       │
   │    Developer or AI Agent implements Command (Green)    │
   └───────────────────────────┬────────────────────────────┘
                               │ Verified Execution
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 3. Extreme Programming (XP)                            │
   │    Rapid refactoring, small releases, zero side-effects│
   └────────────────────────────────────────────────────────┘
```

### 1. Spec-Driven Development (SDD): Executable Contracts
In traditional development, specifications are often written in static documentation that quickly drifts out of sync with the actual codebase. In SDD, **the specification is the test itself**.

Because [`commanderTest`](#a-orchestrator-testing-commandertest) declaratively describes the complete behavior of a use case, it acts as an unambiguous, machine-executable contract:

```dart
// The Specification Contract for a Checkout flow:
commanderTest<ShopCommander, ShopState, ShopEffect>(
  'Given an active cart, when checkout succeeds, transitions to loading then confirms order',
  build: () => ShopCommander(paymentService: mockPaymentService),
  seed: () => ShopState.cart(items: [itemA]),
  act: (commander) => commander.dispatch(const CheckoutIntent(cartId: '123')),
  expectStates: () => [
    const ShopState.loading(),
    const ShopState.orderConfirmed(orderId: 'ORD-777'),
  ],
  expectEffects: () => [
    const ShopEffect.showSnackBar('Order placed successfully!'),
  ],
);
```

### 2. Deterministic Test-Driven Development (TDD)
Commander provides a fast, predictable test harness designed to make the Red-Green-Refactor loop natural and enjoyable:
* **Red:** Write the `commanderTest` for a new feature. The test fails cleanly because the command or intent is not yet registered.
* **Green:** Implement the atomic `Command` class with the focused code required to satisfy the contract.
* **Refactor:** Optimize, clean up, or extract services with complete confidence. The test executes deterministically in milliseconds without artificial delays or flakiness.

### 3. Extreme Programming (XP) Values
* **Simplicity (KISS & YAGNI):** Commands are small, focused classes (typically 20–40 lines). Each action owns its logic, dependencies, and execution rules with zero hidden plumbing.
* **Rapid Feedback:** Unit tests run instantly. Real-time performance profiling is available out-of-the-box via Flutter DevTools Timeline.
* **Fearless Refactoring:** Because UI widgets only depend on `Intent` and `State`, you can rewrite or optimize a `Command` without touching any widget code.
* **Collective Ownership & Pair-Programming:** Standardized, single-responsibility files ensure that any team member—human or AI—can inspect, understand, and enhance any feature immediately.

### 4. Synergy with AI Coding Assistants (AI Pair-Programming)
When pair-programming with AI agents, Commander's modular structure solves three common friction points in AI-assisted development:

* 📉 **Token Efficiency (Zero Context Bloat):** LLMs perform best on concise, high-signal contexts. In Commander, an AI agent only needs to read the relevant `Intent`, its `Command`, and its test file (~50 lines total)—maximizing attention quality and eliminating context fatigue.
* 🎯 **Zero Accidental Regressions:** Because each use case is an isolated class, the AI agent **cannot accidentally break** other commands when adding or modifying functionality.
* 🤖 **Autonomous Red-Green-Refactor Loop:** You provide the `commanderTest` contract as the prompt. The AI agent implements the `Command`, runs `flutter test`, analyzes the deterministic failure output if any, self-corrects, and delivers a green, fully-verified feature.

---

## 📖 In-Depth Feature & Architecture Guides

Explore dedicated guides with comprehensive code showcases, real-world patterns, and best practices:

| Guide | Description |
| :--- | :--- |
| 🏛️ [**Architecture & Core Concepts**](doc/architecture.md) | Deep dive into MVI flow, presentation state, one-shot side effects, and `CommanderView` UI integration. |
| ⚡ [**Declarative Concurrency Control**](doc/concurrency.md) | Master `ExecutionPolicy` (`drop`, `restart`, `queue`, `concurrent`) and entity-level `concurrencyKey`. |
| 🧪 [**Two-Tier Testing Guide**](doc/testing.md) | End-to-end testing with `commanderTest` and isolated, synchronous testing with `TestCommandScope`. |
| 💾 [**State Persistence**](doc/saved_state.md) | Zero-flicker startup, `SavedStateMixin`, custom disk engines (Hive, SQLite, SecureStorage), and `SavedStateHandle`. |
| ⏪ [**Time-Travel & Undo/Redo**](doc/undo_redo.md) | Composable history navigation with `UndoRedoMixin`, reactive button states, and `UndoIntent`. |
| 📊 [**Observability & DevTools**](doc/telemetry.md) | Native Flutter DevTools Timeline profiling (`dart:developer`), lifecycle hooks, and global crash reporting. |

---

## 📚 Ecosystem, Comparison & Migration

Whether you are evaluating architectural options for a new project or migrating an existing app, explore our dedicated guides:

* ⚖️ [**Detailed Architectural Comparison**](doc/comparison.md): An objective side-by-side matrix comparing `flutter_commander` with BLoC and Riverpod.
* 📦 [**Migrating from BLoC**](doc/migration_from_bloc.md): Step-by-step migration guide with AI prompts and side-by-side examples.
* 🌊 [**Migrating from Riverpod**](doc/migration_from_riverpod.md): Step-by-step migration guide from Riverpod providers to Commander.
* 📖 [**Universal Migration Guide**](doc/migration_guide.md): Universal MVI core principles and transition overview.

---

## 🛒 Real-World Example App

Explore a complete, production-grade e-commerce application in the [`example`](example) directory:
* **`CheckoutCommand`**: Double-tap prevention via `ExecutionPolicy.drop`.
* **`SearchProductsCommand`**: Debounced type-ahead live search with cooperative cancellation via `ExecutionPolicy.restart`.
* **`TrackAnalyticsCommand`**: Sequential chronological audit logging via `ExecutionPolicy.queue`.
* **`ToggleVipDiscountIntent`**: Fast UI-only state mutations using the inline DSL `on<Intent>()`.
* **`CommanderView` UI**: Clean, non-nested view with mounted effect handling and `context.select` performance optimizations.
* **Testing Suite**: Declarative orchestrator tests (`commanderTest`) and synchronous atomic unit tests (`TestCommandScope`).

To run the example app locally:
```bash
cd example
flutter run
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
