import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_scope.dart';

/// Rebuilds widget subtrees reactively based on a [CommanderController]'s state.
///
/// Supports selector projections via [select] and conditional rebuild guards via [buildWhen].
///
/// Example with selector:
/// ```dart
/// CommanderBuilder<CartController, CartState, int>(
///   select: (state) => state.itemCount,
///   builder: (context, count) => Text('Items: $count'),
/// )
/// ```
///
/// Example with full state:
/// ```dart
/// CommanderBuilder<CartController, CartState, CartState>(
///   builder: (context, state) => Text('Total: ${state.total}'),
/// )
/// ```
class CommanderBuilder<C extends CommanderController<S, dynamic>, S, R>
    extends StatefulWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

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
    this.controller,
    this.select,
    required this.builder,
    this.buildWhen,
  });

  @override
  State<CommanderBuilder<C, S, R>> createState() => _CommanderBuilderState<C, S, R>();
}

class _CommanderBuilderState<C extends CommanderController<S, dynamic>, S, R>
    extends State<CommanderBuilder<C, S, R>> {
  C? _controller;
  late R _currentValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(CommanderBuilder<C, S, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _subscribe();
    }
  }

  void _subscribe() {
    final controller = widget.controller ?? CommanderScope.of<C>(context, listen: false);
    if (_controller == controller) return;

    _controller?.removeListener(_onStateChanged);
    _controller = controller;
    _controller!.addListener(_onStateChanged);
    _currentValue = _computeValue(_controller!.state);
  }

  R _computeValue(S state) {
    if (widget.select != null) {
      return widget.select!(state);
    }
    return state as R;
  }

  void _onStateChanged() {
    final controller = _controller;
    if (controller == null) return;

    final newValue = _computeValue(controller.state);
    final shouldRebuild = widget.buildWhen != null
        ? widget.buildWhen!(_currentValue, newValue)
        : !identical(_currentValue, newValue) && _currentValue != newValue;

    _currentValue = newValue;

    if (shouldRebuild && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onStateChanged);
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _currentValue);
  }
}
