import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_scope.dart';

/// Listens exclusively to one-shot side effect emissions of type [E] from a [CommanderController]
/// without rebuilding the widget tree.
///
/// Ideal for navigation, showing SnackBar messages, alerts, and modal dialogs.
///
/// Example:
/// ```dart
/// CommanderListener<OrderController, OrderEffect>(
///   onEffect: (context, effect) {
///     switch (effect) {
///       case NavigateToConfirmationEffect():
///         Navigator.of(context).pushNamed('/confirmation');
///       case ShowErrorSnackbarEffect(:final message):
///         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
///     }
///   },
///   child: const OrderFormView(),
/// )
/// ```
class CommanderListener<C extends CommanderController<dynamic, E>, E>
    extends StatefulWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

  /// Callback executed whenever an effect is emitted.
  final void Function(BuildContext context, E effect) onEffect;

  /// Optional filter to condition which effects trigger [onEffect].
  final bool Function(E effect)? listenWhen;

  /// Child widget.
  final Widget child;

  /// Creates a [CommanderListener].
  const CommanderListener({
    super.key,
    this.controller,
    required this.onEffect,
    this.listenWhen,
    required this.child,
  });

  @override
  State<CommanderListener<C, E>> createState() =>
      _CommanderListenerState<C, E>();
}

class _CommanderListenerState<C extends CommanderController<dynamic, E>, E>
    extends State<CommanderListener<C, E>> {
  C? _controller;
  StreamSubscription<E>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(CommanderListener<C, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _subscribe();
    }
  }

  void _subscribe() {
    final controller =
        widget.controller ?? CommanderScope.of<C>(context, listen: false);
    if (_controller == controller) return;

    _subscription?.cancel();
    _controller = controller;

    _subscription = _controller!.effects.listen((effect) {
      if (!mounted) return;
      if (widget.listenWhen != null && !widget.listenWhen!(effect)) {
        return;
      }
      widget.onEffect(context, effect);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
