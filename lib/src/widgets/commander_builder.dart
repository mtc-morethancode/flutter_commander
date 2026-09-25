import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import 'commander_scope.dart';

/// Rebuilds widget subtrees reactively based on a [Commander]'s state.
///
/// Supports selector projections via [select] and conditional rebuild guards via [buildWhen].
///
/// Example with selector:
/// ```dart
/// CommanderBuilder<CartCommander, CartState, int>(
///   select: (state) => state.itemCount,
///   builder: (context, count) => Text('Items: $count'),
/// )
/// ```
///
/// Example with full state:
/// ```dart
/// CommanderBuilder<CartCommander, CartState, CartState>(
///   builder: (context, state) => Text('Total: ${state.total}'),
/// )
/// ```
class CommanderBuilder<C extends Commander<S, dynamic>, S, R>
    extends StatefulWidget {
  /// Optional commander instance. If omitted, resolved from the nearest [CommanderScope].
  final C? commander;

  /// Selector mapping full state [S] to selected slice [R].
  /// If null, [S] is cast to [R].
  final R Function(S state)? select;

  /// Widget builder function invoked with the selected [R] value.
  final Widget Function(BuildContext context, R value) builder;

  /// Optional condition to control whether [builder] should be called on value changes.
  final bool Function(R previous, R current)? buildWhen;

  /// Creates a [CommanderBuilder].
  const CommanderBuilder({
    super.key,
    this.commander,
    this.select,
    required this.builder,
    this.buildWhen,
  });

  @override
  State<CommanderBuilder<C, S, R>> createState() =>
      _CommanderBuilderState<C, S, R>();
}

class _CommanderBuilderState<C extends Commander<S, dynamic>, S, R>
    extends State<CommanderBuilder<C, S, R>> {
  C? _commander;
  late R _currentValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(CommanderBuilder<C, S, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commander != oldWidget.commander) {
      _subscribe();
    } else if (widget.commander == null) {
      final current = CommanderScope.of<C>(context, listen: false);
      if (_commander != current) {
        _subscribe();
      } else if (widget.select != oldWidget.select) {
        if (_commander != null) {
          _currentValue = _computeValue(_commander!.state);
        }
      }
    } else if (widget.select != oldWidget.select) {
      if (_commander != null) {
        _currentValue = _computeValue(_commander!.state);
      }
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(fn);
        }
      });
    } else {
      setState(fn);
    }
  }

  void _subscribe() {
    final commander =
        widget.commander ?? CommanderScope.dependOnCommander<C>(context);
    if (_commander == commander) return;

    final isInitial = _commander == null;
    _commander?.removeListener(_onStateChanged);
    _commander = commander;
    _commander!.addListener(_onStateChanged);
    _currentValue = _computeValue(_commander!.state);
    if (!isInitial && mounted) {
      _safeSetState(() {});
    }
  }

  R _computeValue(S state) {
    if (widget.select != null) {
      return widget.select!(state);
    }
    return state as R;
  }

  void _onStateChanged() {
    final commander = _commander;
    if (commander == null) return;

    final newValue = _computeValue(commander.state);
    final shouldRebuild = widget.buildWhen != null
        ? widget.buildWhen!(_currentValue, newValue)
        : !identical(_currentValue, newValue) && _currentValue != newValue;

    _currentValue = newValue;

    if (shouldRebuild && mounted) {
      _safeSetState(() {});
    }
  }

  @override
  void dispose() {
    _commander?.removeListener(_onStateChanged);
    _commander = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _currentValue);
  }
}
