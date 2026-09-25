# 🔄 Migration Guides: Migrating to `flutter_commander`

> **Comprehensive guides designed for both Human Developers and AI Coding Assistants (Cursor, Copilot, Claude, ChatGPT, Antigravity).**

Welcome! If you are migrating an existing Flutter project from another state management framework to **`flutter_commander`**, we provide dedicated, specialized guides tailored to the paradigms of each framework:

---

## 🎯 Select Your Migration Guide

### 📦 [Migrating from BLoC (`flutter_bloc`) ➔ `flutter_commander`](migration_from_bloc.md)
*Deconstruct monolithic god-blocs, replace `bloc_concurrency` (RxDart) with native `ExecutionPolicy`, eliminate ghost side-effects, replace nested `BlocConsumer`/`BlocListener`/`BlocBuilder` with `CommanderView`, and adopt synchronous `TestCommandScope`.*

### 🌊 [Migrating from Riverpod (`flutter_riverpod`) ➔ `flutter_commander`](migration_from_riverpod.md)
*Transition from global provider declarations to scoped lifecycles (`CommanderScope`), gain first-class one-shot side-effect streams (`SideEffect`), replace `ConsumerWidget` and `WidgetRef` boilerplate with `CommanderView` and `context.select`, and simplify asynchronous testing.*

---

## 💡 Universal MVI Core Principles

No matter which library you are migrating from, `flutter_commander` follows four core principles:

1. **State is Exclusively Presentation Data**:
   - `State` must only store long-lived data needed to render UI widgets.
   - Ephemeral events (navigation, SnackBars, modal alerts) belong in the dedicated `SideEffect` broadcast channel (`emitSideEffect(...)`).

2. **One Command = One Use Case**:
   - Complex business logic lives in standalone `Command<Intent, State, Effect>` classes.
   - Trivial UI-only mutations (such as tab toggles) can be defined quickly using the inline DSL: `on<MyIntent>((scope, intent) => ...)`.

3. **Concurrency is Declarative**:
   - Control race conditions directly on each Command using `ExecutionPolicy` (`drop`, `restart`, `queue`, `concurrent`) and optional `debounce` or `concurrencyKey`. No external stream operators required.

4. **Zero-Boilerplate UI**:
   - Use `CommanderView<C, S, E>` to handle state rendering (`build`), one-shot effects (`onEffect`), and rebuild filtering (`shouldRebuild`) in a single widget with zero nested pyramids.
