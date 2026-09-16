import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_builder.dart';
import 'commander_listener.dart';

/// Combines [CommanderListener] and [CommanderBuilder] into a single unified widget.
///
/// Handles both side-effect execution and reactive UI rebuilding with selectors.
class CommanderConsumer<C extends CommanderController<S, E>, S, E, R>
    extends StatelessWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

  /// Selector mapping full state [S] to selected slice [R].
  final R Function(S state)? select;

  /// Callback executed when an effect is emitted.
  final void Function(BuildContext context, E effect) onEffect;

  /// Optional filter for side-effect execution.
  final bool Function(E effect)? listenWhen;

  /// Widget builder function invoked with the selected [R] value.
  final Widget Function(BuildContext context, R value) builder;

  /// Optional condition to control rebuilding.
  final bool Function(R previous, R current)? buildWhen;

  /// Creates a [CommanderConsumer].
  const CommanderConsumer({
    super.key,
    this.controller,
    this.select,
    required this.onEffect,
    this.listenWhen,
    required this.builder,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return CommanderListener<C, E>(
      controller: controller,
      onEffect: onEffect,
      listenWhen: listenWhen,
      child: CommanderBuilder<C, S, R>(
        controller: controller,
        select: select,
        buildWhen: buildWhen,
        builder: builder,
      ),
    );
  }
}
