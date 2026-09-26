---
title: Overview & Quickstart
description: Get started with flutter_commander in 3 minutes.
---

## Installation

Add `flutter_commander` to your `pubspec.yaml` dependencies:

```bash
flutter pub add flutter_commander
```

Or manually:

```yaml
dependencies:
  flutter_commander: ^1.0.0
```

---

## 3-Minute Quickstart

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
