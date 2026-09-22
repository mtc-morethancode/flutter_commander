import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_builder.dart';

/// Rebuilds widget subtrees reactively based on a [CommanderController]'s full state [S].
///
/// A simplified alternative to [CommanderBuilder] that requires only 2 generic type parameters
/// (`C` and `S`) instead of 3, avoiding the need to specify the state type twice.
///
/// Example:
/// ```dart
/// CommanderStateBuilder<CartController, CartState>(
///   builder: (context, state) => Text('Items: ${state.count}'),
/// )
/// ```
class CommanderStateBuilder<C extends CommanderController<S, dynamic>, S>
    extends StatelessWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

  /// Widget builder function invoked with the full current [S] state.
  final Widget Function(BuildContext context, S state) builder;

  /// Optional condition to control whether [builder] should be called on state changes.
  final bool Function(S previous, S current)? buildWhen;

  /// Creates a [CommanderStateBuilder].
  const CommanderStateBuilder({
    super.key,
    this.controller,
    required this.builder,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return CommanderBuilder<C, S, S>(
      controller: controller,
      builder: builder,
      buildWhen: buildWhen,
    );
  }
}
