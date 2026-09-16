import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';

/// Injects and manages the lifecycle of a [CommanderController] in the widget tree.
///
/// Supports automatic disposal, lazy/eager creation, and fine-grained selector
/// subscriptions via Flutter's [InheritedModel].
class CommanderScope<C extends CommanderController<dynamic, dynamic>> extends StatefulWidget {
  /// Factory to instantiate the controller.
  final C Function(BuildContext context)? create;

  /// Existing controller instance (will not be disposed automatically).
  final C? value;

  /// Child widget subtree.
  final Widget child;

  /// Whether to automatically call [CommanderController.dispose] when this scope
  /// is unmounted. Defaults to `true` when using [CommanderScope.new] with `create`.
  final bool autoDispose;

  /// Standard constructor creating and owning a [CommanderController].
  const CommanderScope({
    super.key,
    required C Function(BuildContext context) this.create,
    required this.child,
    this.autoDispose = true,
  }) : value = null;

  /// Constructor supplying an existing [CommanderController] instance.
  /// [autoDispose] defaults to `false` to avoid disposing shared controllers.
  const CommanderScope.value({
    super.key,
    required C this.value,
    required this.child,
    this.autoDispose = false,
  }) : create = null;

  /// Retrieves the nearest [CommanderController] of type [C] from the widget tree.
  ///
  /// Set [listen] to `true` if the calling widget should rebuild whenever the
  /// controller's state updates. Defaults to `false`.
  static C of<C extends CommanderController<dynamic, dynamic>>(
    BuildContext context, {
    bool listen = false,
  }) {
    if (listen) {
      final model = InheritedModel.inheritFrom<_CommanderInheritedModel<C>>(context);
      if (model == null) {
        throw FlutterError(
          'CommanderScope.of<$C>(listen: true) could not find a matching CommanderScope<$C>.\n'
          'Ensure the widget is wrapped within a CommanderScope<$C>.',
        );
      }
      return model.controller;
    } else {
      final element =
          context.getElementForInheritedWidgetOfExactType<_CommanderInheritedModel<C>>();
      final widget = element?.widget as _CommanderInheritedModel<C>?;
      if (widget == null) {
        throw FlutterError(
          'CommanderScope.of<$C>() could not find a matching CommanderScope<$C>.\n'
          'Ensure the widget is wrapped within a CommanderScope<$C>.',
        );
      }
      return widget.controller;
    }
  }

  /// Subscribes to a specific slice [R] of state [S] from controller [C].
  ///
  /// The calling widget will only rebuild when the value returned by [selector]
  /// changes (using equality `!=`).
  static R select<C extends CommanderController<S, dynamic>, S, R>(
    BuildContext context,
    R Function(S state) selector,
  ) {
    // 1. Obtain controller without registering a full rebuild dependency
    final controller = of<C>(context, listen: false) as CommanderController<S, dynamic>;
    final currentValue = selector(controller.state);

    // 2. Register fine-grained aspect dependency
    final aspect = _SelectorAspect<S, R>(selector, currentValue);
    InheritedModel.inheritFrom<_CommanderInheritedModel<C>>(context, aspect: aspect);

    return currentValue;
  }

  @override
  State<CommanderScope<C>> createState() => _CommanderScopeState<C>();
}

class _CommanderScopeState<C extends CommanderController<dynamic, dynamic>>
    extends State<CommanderScope<C>> {
  late C _controller;
  bool _createdInternally = false;

  @override
  void initState() {
    super.initState();
    if (widget.create != null) {
      _controller = widget.create!(context);
      _createdInternally = true;
    } else {
      _controller = widget.value!;
    }
    _controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(CommanderScope<C> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      oldWidget.value?.removeListener(_onStateChanged);
      _controller = widget.value!;
      _controller.addListener(_onStateChanged);
    }
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    if (_createdInternally || widget.autoDispose) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CommanderInheritedModel<C>(
      controller: _controller,
      state: _controller.state,
      child: widget.child,
    );
  }
}

class _CommanderInheritedModel<C extends CommanderController<dynamic, dynamic>>
    extends InheritedModel<_Aspect> {
  final C controller;
  final dynamic state;

  const _CommanderInheritedModel({
    super.key,
    required this.controller,
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_CommanderInheritedModel<C> oldWidget) {
    return !identical(state, oldWidget.state) && state != oldWidget.state;
  }

  @override
  bool updateShouldNotifyDependent(
    _CommanderInheritedModel<C> oldWidget,
    Set<_Aspect> dependencies,
  ) {
    if (dependencies.isEmpty) {
      return true;
    }

    for (final aspect in dependencies) {
      if (aspect.hasChanged(oldWidget.state, state)) {
        return true;
      }
    }

    return false;
  }
}

abstract class _Aspect {
  bool hasChanged(dynamic oldState, dynamic newState);
}

class _SelectorAspect<S, R> implements _Aspect {
  final R Function(S state) selector;
  final R lastValue;

  _SelectorAspect(this.selector, this.lastValue);

  @override
  bool hasChanged(dynamic oldState, dynamic newState) {
    if (oldState is! S || newState is! S) return true;
    final oldValue = selector(oldState);
    final newValue = selector(newState);
    return !identical(oldValue, newValue) && oldValue != newValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SelectorAspect &&
          runtimeType == other.runtimeType &&
          selector == other.selector;

  @override
  int get hashCode => selector.hashCode;
}
