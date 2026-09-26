# Observability, Global Telemetry & DevTools Profiling 📊

`flutter_commander` provides built-in enterprise observability and deep integration with Flutter's developer tooling.

---

## 1. Global Lifecycle & Crash Reporting (`CommanderObserver`)

Monitor lifecycle events, executions, and crash reports across the entire app by registering a `CommanderObserver` in your `main()`:

```dart
void main() {
  Commander.observer = AppStoreObserver();
  runApp(const MyApp());
}

class AppStoreObserver extends CommanderObserver {
  @override
  void onCommanderCreated(Commander<dynamic, dynamic> commander) {
    debugPrint('[Lifecycle] Created: ${commander.runtimeType}');
  }

  @override
  void onStateChanged(
    Commander<dynamic, dynamic>? commander,
    dynamic oldState,
    dynamic newState,
  ) {
    debugPrint('[State] ${commander.runtimeType} -> $newState');
  }

  @override
  void onEffectEmitted(
    Commander<dynamic, dynamic>? commander,
    dynamic effect,
  ) {
    debugPrint('[Effect] ${commander.runtimeType} -> $effect');
  }

  @override
  void onError(
    Commander<dynamic, dynamic>? commander,
    Command<dynamic, dynamic, dynamic>? command,
    CommandIntent? intent,
    Object error,
    StackTrace stackTrace,
  ) {
    // Automatic crash reporting to Firebase Crashlytics or Sentry:
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}
```

---

## 2. Native Flutter DevTools Timeline Profiling

In debug and profile modes (`!kReleaseMode`), `flutter_commander` automatically emits native `dart:developer.TimelineTask` tracks and VM Service extension events:

* **Performance Timeline**: View exact execution bars in Flutter DevTools with policy, intent type, and concurrency key arguments.
* **Lifecycle Events**: Traces `intent_dropped` on duplicate drop-policy calls and `command_restarted` on cancellations.
* **Zero Release Overhead**: Timeline calls are guarded by `Commander.enableTimelineTracing = !kReleaseMode` and completely bypassed in release builds.

### How to Inspect in Flutter DevTools:

1. Run your Flutter app in debug or profile mode: `flutter run --profile`.
2. Open Flutter DevTools (from your IDE or terminal).
3. Navigate to the **Performance** tab.
4. Interact with your Commander features. You will see dedicated timeline events named `commander:execute`, `commander:dropped`, and `commander:restarted` with complete metadata.
