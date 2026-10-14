## 1.1.0

* **CI/CD & Release Automation**:
  * Automated GitHub release creation upon merging release branches.
  * Automated `pub.dev` publishing pipeline using GitHub Actions OIDC trusted publishing.
  * Upgraded CI/CD GitHub Actions dependencies (`actions/checkout`, `actions/setup-node`, `actions/deploy-pages`, `actions/upload-pages-artifact`).
* **Community & Governance**:
  * Added comprehensive `CONTRIBUTING.md` guidelines and Pull Request template.
  * Added `CODE_OF_CONDUCT.md` and `SECURITY.md` policy files.
  * Added structured GitHub issue templates for bug reports and feature requests.
  * Configured `CODEOWNERS` for repository governance and required reviews.
  * Configured Dependabot for automated dependency updates across workflows and website packages.
  * Standardized official contact and security reporting emails to `mtc.morethancode@gmail.com`.
* **Documentation & Website**:
  * Updated documentation website dependencies (`astro`, `@astrojs/starlight`, `sharp`).
  * Updated canonical repository, contributing, and license links.

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
  * Enterprise crash isolation: Uncaught exceptions in third-party observers (Sentry, Crashlytics) are safely contained without interrupting command execution, state updates, or widget lifecycles.
  * Native **Flutter DevTools Timeline Profiling** (`TimelineTask`, `postEvent`) for visual execution bars and VM Service event tracking (zero overhead in release builds).
* **Production Hardening & Concurrency Safety**:
  * Complete concurrency token cleanup guaranteeing zero memory or token leaks if a command throws synchronously under `DROP` or `RESTART` policies.
  * Async error symmetry in `Commander.dispatch`: Synchronous and asynchronous command failures return uniform catchable Futures with unhandled zone error suppression.
  * `CommandScope` cooperative cancellation utilities: `isCancelled`, `throwIfCancelled()`, `withCancellation()`, `runCancellable()`, `sleep()`, `listen()`, `forEach()`, and `attach()`.
* **Widgets & Flutter Integration**:
  * `CommanderScope`: InheritedWidget lifecycle manager with automatic disposal and multi-selector slot isolation.
  * `CommanderView`: Unified screen base widget with reactive state access, mounted effect handling, route buffering, and rebuild filtering (`shouldRebuild`).
  * `CommanderBuilder`: Selector-based rebuild optimization.
  * `CommanderSelector`: Declarative slice selector with stable aspect equality.
  * `CommanderStateBuilder`: Simplified full-state builder.
  * `CommanderListener`: Dedicated side-effect listener with active route gating.
  * `CommanderBuildContextX`: Clean extensions (`context.commander`, `context.dispatch`, `context.selectState`, `context.select`).
