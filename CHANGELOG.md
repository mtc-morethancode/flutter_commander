## 1.0.0

* Initial official production release of `flutter_commander`.
* **Architecture**: Pure Dart 3 enterprise MVI + Command Pattern with strict unidirectional flow (`Intent -> Command -> State / SideEffect`).
* **Concurrency Policies**: Declarative `ExecutionPolicy` per command:
  * `DROP`: Discards incoming duplicate intents while active (double-tap protection).
  * `RESTART`: Cancels previous active tasks cooperatively via `CancellationToken` (autocomplete/search).
  * `QUEUE`: Sequentially processes intents in strict FIFO order (event queues, sync).
  * `CONCURRENT`: Runs tasks concurrently in parallel.
* **SideEffect Channel**: Formal broadcast stream for one-shot ephemeral events (navigation, SnackBars, dialogs).
* **Boilerplate Reduction**:
  * Type-safe registration via `bind(command)`.
  * Inline DSL for quick UI actions: `on<ToggleIntent>((scope, intent) => ...)`.
* **Observability**: `CommandInterceptor` interface and out-of-the-box `LoggingCommandInterceptor`.
* **Testing**: `TestCommandScope` harness for fast, widget-free, deterministic command unit testing.
* **Widgets & Flutter Integration**:
  * `CommanderScope`: InheritedWidget lifecycle manager.
  * `CommanderView`: Unified screen base widget with direct state access, effect handling, and zero nested builders.
  * `CommanderBuilder`: Selector-based rebuild optimization.
  * `CommanderSelector`: Declarative slice selector.
  * `CommanderStateBuilder`: Simplified full-state builder.
  * `CommanderListener`: Dedicated side-effect listener.
  * `CommanderBuildContextX`: Clean extensions (`context.commander`, `context.dispatch`, `context.select`).
