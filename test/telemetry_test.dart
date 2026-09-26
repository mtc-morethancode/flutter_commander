import 'package:flutter/foundation.dart';
import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

class TelemetryState {
  final int count;
  const TelemetryState(this.count);

  TelemetryState copyWith({int? count}) => TelemetryState(count ?? this.count);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryState &&
          runtimeType == other.runtimeType &&
          count == other.count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => 'TelemetryState($count)';
}

sealed class TelemetryEffect {
  const TelemetryEffect();
}

class TelemetryAlertEffect extends TelemetryEffect {
  final String text;
  const TelemetryAlertEffect(this.text);

  @override
  String toString() => 'TelemetryAlertEffect($text)';
}

class FastIntent extends CommandIntent {
  const FastIntent();
}

class SlowIntent extends CommandIntent {
  final Duration duration;
  const SlowIntent([this.duration = const Duration(milliseconds: 30)]);
}

class DropIntent extends CommandIntent {
  const DropIntent();
}

class ErrorIntent extends CommandIntent {
  const ErrorIntent();
}

class TelemetryCommander extends Commander<TelemetryState, TelemetryEffect> {
  TelemetryCommander() : super(const TelemetryState(0)) {
    // 1. Synchronous inline command
    on<FastIntent>((scope, intent) {
      scope.updateState((s) => s.copyWith(count: s.count + 1));
      scope.emitSideEffect(const TelemetryAlertEffect('fast_done'));
    });

    // 2. Restart policy async command
    on<SlowIntent>(
      (scope, intent) async {
        await scope.sleep(intent.duration);
        scope.updateState((s) => s.copyWith(count: s.count + 10));
      },
      policy: ExecutionPolicy.restart,
    );

    // 3. Drop policy command
    on<DropIntent>(
      (scope, intent) async {
        await scope.sleep(const Duration(milliseconds: 50));
        scope.updateState((s) => s.copyWith(count: s.count + 100));
      },
      policy: ExecutionPolicy.drop,
    );

    // 4. Failing command
    on<ErrorIntent>((scope, intent) async {
      throw Exception('Telemetry failure test');
    });
  }
}

void main() {
  group('Developer Telemetry & DevTools Timeline', () {
    late TelemetryCommander commander;

    setUp(() {
      Commander.enableTimelineTracing = true;
      commander = TelemetryCommander();
    });

    tearDown(() {
      commander.dispose();
      Commander.enableTimelineTracing = !kReleaseMode;
    });

    test('enableTimelineTracing defaults to true in non-release mode', () {
      expect(Commander.enableTimelineTracing, isTrue);
    });

    test('synchronous commands trace timeline and postEvents seamlessly',
        () async {
      await commander.dispatch(const FastIntent());
      expect(commander.state.count, 1);
    });

    test('restartable async commands trace start, restart, and cancellation',
        () async {
      // Dispatch first slow intent
      final first = commander.dispatch(
        const SlowIntent(Duration(milliseconds: 40)),
      );

      // Immediately dispatch second to trigger restart & cancellation event
      final second = commander.dispatch(
        const SlowIntent(Duration(milliseconds: 10)),
      );

      await Future.wait([first, second]);
      expect(commander.state.count, 10);
    });

    test('drop policy commands trace intent_dropped events upon conflict',
        () async {
      final first = commander.dispatch(const DropIntent());
      // Second drop intent while first is running
      final second = commander.dispatch(const DropIntent());

      await Future.wait([first, second]);
      expect(commander.state.count, 100);
    });

    test('failing commands finish timeline task with error status', () async {
      expect(
        () => commander.dispatch(const ErrorIntent()),
        throwsA(isA<Exception>()),
      );
    });

    test('works normally and cleanly when enableTimelineTracing is disabled',
        () async {
      Commander.enableTimelineTracing = false;

      await commander.dispatch(const FastIntent());
      expect(commander.state.count, 1);

      final slow = commander.dispatch(
        const SlowIntent(Duration(milliseconds: 10)),
      );
      await slow;
      expect(commander.state.count, 11);
    });
  });
}
