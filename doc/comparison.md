# ⚖️ Architectural Comparison: `flutter_commander` vs. BLoC vs. Riverpod

This document provides an objective, side-by-side technical comparison between **`flutter_commander`**, **BLoC (`flutter_bloc`)**, and **Riverpod (`flutter_riverpod`)** to help teams choose the right architectural pattern for their Flutter applications.

---

## 📊 Feature & Architecture Matrix

| Architectural Dimension | `flutter_commander` | BLoC (`flutter_bloc`) | Riverpod (`flutter_riverpod`) |
| :--- | :---: | :---: | :---: |
| **Architectural Pattern** | Model-View-Intent (MVI) + Command Pattern | BLoC (Business Logic Component) / Event-State | Provider / Reactive Dependency Injection |
| **Separation of Concerns** | Single-responsibility `Command` classes per use-case | Centralized Bloc class handling multiple events | StateNotifier / AsyncNotifier with multiple methods |
| **Concurrency Control** | **Declarative & Built-in** (`drop`, `restart`, `queue`, `concurrent`) + `debounce` & `concurrencyKey` | Requires external `bloc_concurrency` + RxDart transformers | Manual `CancelToken` handling or custom stream logic |
| **One-Shot Side Effects** | **First-class broadcast channel** (`SideEffect`) with cold-start FIFO buffering & mounted checks | State flags (`isLoading`, `hasError`) or external stream listeners | State flags or external callback subscriptions |
| **UI DX & Nesting** | **`CommanderView`**: Combines state rendering, side-effects, and rebuild filtering in one widget | Often requires nesting `BlocListener` + `BlocBuilder` (`BlocConsumer`) | Requires `ConsumerWidget` / `ref.watch` / `ref.listen` |
| **State Persistence** | Agnostic **`SavedStateMixin`** (zero-flicker sync + background async restoration) | Coupled to `hydrated_bloc` (requires subclassing `HydratedBloc`) | Manual notifier state serialization or custom caches |
| **Time-Travel (Undo/Redo)** | Composable **`UndoRedoMixin`** (combine with any mixin, intent-driven or direct) | `replay_bloc` (rigid base class inheritance) | Custom state history stack implementations |
| **Code Generation** | ❌ **None** (100% Pure Dart 3) | ❌ Optional | ⚠️ Recommended (`riverpod_generator`) |
| **Unit Testing DX** | **Deterministic & synchronous** with `TestCommandScope` (zero streams, zero pumps) | `blocTest` (asynchronous, relies on stream delay timings) | `ProviderContainer` with overrides and asynchronous mocks |
| **Dependency Injection** | Native widget-tree scoping (`CommanderScope`) or DI container agnostic | Native widget-tree scoping (`BlocProvider`) or DI agnostic | Global provider declarations with `ProviderScope` |

---

## 🎯 When to Choose `flutter_commander`

- **Enterprise & Domain-Driven Design (DDD):** Your application has complex business logic that benefits from isolating each use-case into a single, testable class (`Command`).
- **Rich User Interactions:** You frequently handle race conditions, rapid button taps (checkout/payments), type-ahead live search with debouncing, or ordered telemetry synchronization.
- **Clean UI Architecture:** You want clean presentation code without deeply nested builder widgets or error-prone state flags for one-shot events (toasts, dialogs, navigation).
- **Zero Build Fatigue:** You prefer 100% pure Dart 3 without code generation tools (`build_runner`) slowing down CI/CD and developer workflows.
- **Fast, Deterministic Tests:** You want business logic tests that run instantaneously in memory without stream-settling delays.

---

## 🔄 Migration Guides

For teams transitioning an existing codebase to `flutter_commander`:
* 📦 [**Migrating from BLoC**](migration_from_bloc.md)
* 🌊 [**Migrating from Riverpod**](migration_from_riverpod.md)
* 📖 [**Universal Migration Overview**](migration_guide.md)
