import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_listener.dart';
import 'commander_state_builder.dart';

/// Combines [CommanderListener] and [CommanderStateBuilder] into a single unified widget.
///
/// Designed for full-state consumption with side effects, requiring only 3 generic
/// parameters (`C`, `S`, `E`) instead of the 4 required by [CommanderConsumer].
///
/// Example:
/// ```dart
/// CommanderStateConsumer<OrderController, OrderState, OrderEffect>(
///   onEffect: (context, effect) { ... },
///   builder: (context, state) => Text(state.status),
/// )
/// ```
class CommanderStateConsumer<C extends CommanderController<S, E>, S, E>
    extends StatelessWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

  /// Callback executed when an effect is emitted.
  final void Function(BuildContext context, E effect) onEffect;

  /// Optional filter for side-effect execution.
  final bool Function(E effect)? listenWhen;

  /// Widget builder function invoked with the full current [S] state.
  final Widget Function(BuildContext context, S state) builder;

  /// Optional condition to control rebuilding.
  final bool Function(S previous, S current)? buildWhen;

  /// Creates a [CommanderStateConsumer].
  const CommanderStateConsumer({
    super.key,
    this.controller,
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
      child: CommanderStateBuilder<C, S>(
        controller: controller,
        buildWhen: buildWhen,
        builder: builder,
      ),
    );
  }
}
