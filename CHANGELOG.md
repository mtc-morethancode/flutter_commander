## 1.0.0

* Initial official production release of `flutter_commander`.
* **Architecture**: Pure Dart 3 enterprise MVI + Command Pattern with strict unidirectional flow (`Intent -> Command -> State / SideEffect`).
* **Declarative Concurrency Policies**: Built-in `ExecutionPolicy` per command:
  * `DROP`: Discards incoming duplicate intents while active (double-tap and duplicate payment protection).
  * `RESTART`: Cooperatively cancels active tasks via `CancellationToken` (autocomplete and live search).
  * `QUEUE`: Sequentially processes intents in strict FIFO order (telemetry, audit trails, and sequential synchronization).
  * `CONCURRENT`: Runs tasks concurrently in parallel.
  * **Keyed Concurrency**: Scopes execution policies per entity ID via `concurrencyKey(intent)`.
  * **Native Debounce**: Declarative `debounce` duration per command.
* **First-Class One-Shot SideEffects**:
  * Dedicated broadcast channel for navigation, SnackBars, toasts, and dialogs.
  * Automatic cold-start FIFO buffering for initialization effects.
  * Route reactivation buffering (`bufferWhileInactive`) to prevent ghost effects while covered by pushed routes.
* **Two-Tier Testing Suite**:
  * `commanderTest`: High-level declarative testing harness for `Commander` orchestrators (states, effects, seed, error verification, auto-disposal) via `package:flutter_commander/testing.dart`.
  * `TestCommandScope`: Deterministic, synchronous, widget-free, and stream-free unit testing for isolated `Command`s.
* **Composable Mixins**:
  * `SavedStateMixin`: Synchronous zero-flicker state restoration + background async fallback with serialized write queue and debounce flush on disposal.
  * `UndoRedoMixin`: Full time-travel history navigation (undo, redo, clear history) with intent-driven commands and automatic persistence synchronization.
* **Observability & DevTools Profiling**:
  * `CommanderObserver` & `LoggingCommandInterceptor` for structured lifecycle and telemetry logging.
  * Native **Flutter DevTools Timeline Profiling** (`TimelineTask`, `postEvent`) for visual execution bars and VM Service event tracking (zero overhead in release builds).
* **Widgets & Flutter Integration**:
  * `CommanderScope`: InheritedWidget lifecycle manager with automatic disposal and multi-selector slot isolation.
  * `CommanderView`: Unified screen base widget with reactive state access, mounted effect handling, route buffering, and rebuild filtering (`shouldRebuild`).
  * `CommanderBuilder`: Selector-based rebuild optimization.
  * `CommanderSelector`: Declarative slice selector with stable aspect equality.
  * `CommanderStateBuilder`: Simplified full-state builder.
  * `CommanderListener`: Dedicated side-effect listener with active route gating.
  * `CommanderBuildContextX`: Clean extensions (`context.commander`, `context.dispatch`, `context.selectState`, `context.select`).
