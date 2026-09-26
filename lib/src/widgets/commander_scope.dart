import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../commander/commander.dart';

/// Injects and manages the lifecycle of a [Commander] in the widget tree.
///
/// Supports automatic disposal, lazy/eager creation, and fine-grained selector
/// subscriptions via Flutter's [InheritedModel].
class CommanderScope<C extends Commander<dynamic, dynamic>>
    extends StatefulWidget {
  /// Factory to instantiate the commander.
  final C Function(BuildContext context)? create;

  /// Existing commander instance (will not be disposed automatically).
  final C? value;

  /// Child widget subtree.
  final Widget child;

  /// Whether to automatically call [Commander.dispose] when this scope
  /// is unmounted. Defaults to `true` when using [CommanderScope.new] with `create`.
  final bool autoDispose;

  /// Standard constructor creating and owning a [Commander].
  const CommanderScope({
    super.key,
    required C Function(BuildContext context) this.create,
    required this.child,
    this.autoDispose = true,
  }) : value = null;

  /// Constructor supplying an existing [Commander] instance.
  /// [autoDispose] defaults to `false` to avoid disposing shared commanders.
  const CommanderScope.value({
    super.key,
    required C this.value,
    required this.child,
    this.autoDispose = false,
  }) : create = null;

  /// Retrieves the nearest [Commander] of type [C] from the widget tree.
  ///
  /// Set [listen] to `true` if the calling widget should rebuild whenever the
  /// commander's state updates. Defaults to `false`.
  static C of<C extends Commander<dynamic, dynamic>>(
    BuildContext context, {
    bool listen = false,
  }) {
    if (listen) {
      final model =
          InheritedModel.inheritFrom<_CommanderInheritedModel<C>>(context);
      if (model == null) {
        throw FlutterError(
          'CommanderScope.of<$C>(listen: true) could not find a matching CommanderScope<$C>.\n'
          'Ensure the widget is wrapped within a CommanderScope<$C>.',
        );
      }
      return model.commander;
    } else {
      final element = context.getElementForInheritedWidgetOfExactType<
          _CommanderInheritedModel<C>>();
      final widget = element?.widget as _CommanderInheritedModel<C>?;
      if (widget == null) {
        throw FlutterError(
          'CommanderScope.of<$C>() could not find a matching CommanderScope<$C>.\n'
          'Ensure the widget is wrapped within a CommanderScope<$C>.',
        );
      }
      return widget.commander;
    }
  }

  /// Obtains the nearest [Commander] of type [C] and registers a dependency ONLY
  /// on the commander instance itself (rebuilding dependencies only if the commander
  /// instance changes, not on normal state mutations).
  static C dependOnCommander<C extends Commander<dynamic, dynamic>>(
    BuildContext context,
  ) {
    final model = InheritedModel.inheritFrom<_CommanderInheritedModel<C>>(
      context,
      aspect: const _CommanderInstanceAspect(),
    );
    if (model == null) {
      throw FlutterError(
        'CommanderScope.dependOnCommander<$C>() could not find a matching CommanderScope<$C>.\n'
        'Ensure the widget is wrapped within a CommanderScope<$C>.',
      );
    }
    return model.commander;
  }

  /// Subscribes to a specific slice [R] from commander [C].
  ///
  /// Supports zero-ceremony type inference:
  /// ```dart
  /// final title = CommanderScope.select(context, (AppCommander c) => c.state.title);
  /// ```
  /// Or with explicit type arguments:
  /// ```dart
  /// final title = CommanderScope.select<AppCommander, String>(context, (c) => c.state.title);
  /// ```
  ///
  /// For optimal aspect equality caching during frequent rebuilds, supply an [aspectKey]
  /// (e.g. `aspectKey: #itemCount` or `aspectKey: 'itemCount'`).
  ///
  /// Recommendation: For isolated UI subtrees, consider using [CommanderSelector]
  /// which connects via direct local listeners without InheritedModel aspect registration.
  static R select<C extends Commander<dynamic, dynamic>, R>(
    BuildContext context,
    R Function(C commander) selector, {
    Object? aspectKey,
  }) {
    // 1. Obtain commander without registering a full rebuild dependency
    final commander = of<C>(context, listen: false);
    final currentValue = selector(commander);

    // 2. Resolve slot-based aspect key if aspectKey is null
    final modelElement = context.getElementForInheritedWidgetOfExactType<
        _CommanderInheritedModel<C>>() as _CommanderInheritedModelElement<C>?;

    final resolvedKey =
        aspectKey ?? modelElement?.nextSlotKey(context as Element) ?? 0;

    // 3. Register fine-grained aspect dependency
    final aspect = _SelectorAspect<C, R>(
      selector: selector,
      lastValue: currentValue,
      aspectKey: resolvedKey,
    );
    InheritedModel.inheritFrom<_CommanderInheritedModel<C>>(context,
        aspect: aspect);

    return currentValue;
  }

  /// Subscribes to a specific slice [R] of state [S] from commander [C] directly.
  static R selectState<C extends Commander<S, dynamic>, S, R>(
    BuildContext context,
    R Function(S state) selector, {
    Object? aspectKey,
  }) {
    return select<C, R>(
      context,
      (commander) => selector(commander.state),
      aspectKey: aspectKey,
    );
  }

  @override
  State<CommanderScope<C>> createState() => _CommanderScopeState<C>();
}

class _CommanderScopeState<C extends Commander<dynamic, dynamic>>
    extends State<CommanderScope<C>> {
  late C _commander;

  @override
  void initState() {
    super.initState();
    if (widget.create != null) {
      _commander = widget.create!(context);
    } else {
      _commander = widget.value!;
    }
    _commander.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(CommanderScope<C> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      oldWidget.value?.removeListener(_onStateChanged);
      _commander = widget.value!;
      _commander.addListener(_onStateChanged);
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

  void _onStateChanged() {
    _safeSetState(() {});
  }

  @override
  void dispose() {
    _commander.removeListener(_onStateChanged);
    if (widget.autoDispose) {
      _commander.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CommanderInheritedModel<C>(
      commander: _commander,
      state: _commander.state,
      child: widget.child,
    );
  }
}

class _CommanderInheritedModel<C extends Commander<dynamic, dynamic>>
    extends InheritedModel<_Aspect> {
  final C commander;
  final dynamic state;

  const _CommanderInheritedModel({
    super.key,
    required this.commander,
    required this.state,
    required super.child,
  });

  @override
  InheritedModelElement<_Aspect> createElement() =>
      _CommanderInheritedModelElement<C>(this);

  @override
  bool updateShouldNotify(_CommanderInheritedModel<C> oldWidget) {
    return !identical(state, oldWidget.state) && state != oldWidget.state;
  }

  @override
  bool updateShouldNotifyDependent(
    _CommanderInheritedModel<C> oldWidget,
    Set<_Aspect> dependencies,
  ) {
    if (!identical(commander, oldWidget.commander)) {
      return true;
    }

    if (dependencies.isEmpty) {
      return true;
    }

    for (final aspect in dependencies) {
      if (aspect.hasChanged(commander, oldWidget.state, state)) {
        return true;
      }
    }

    return false;
  }
}

class _CommanderInheritedModelElement<C extends Commander<dynamic, dynamic>>
    extends InheritedModelElement<_Aspect> {
  _CommanderInheritedModelElement(_CommanderInheritedModel<C> super.widget);

  final Map<Element, Set<_Aspect>> _managedDependencies = {};
  final Map<Element, int> _elementSlotCounters = {};

  Object nextSlotKey(Element dependent) {
    final slot = _elementSlotCounters[dependent] ?? 0;
    _elementSlotCounters[dependent] = slot + 1;
    if (_elementSlotCounters.length == 1 && slot == 0) {
      scheduleMicrotask(() {
        _elementSlotCounters.clear();
      });
    }
    return _SlotAspectKey(slot);
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    final Set<Object?>? existing = getDependencies(dependent) as Set<Object?>?;
    if (existing != null && existing.isEmpty) {
      return;
    }

    if (aspect == null) {
      _managedDependencies.remove(dependent);
      _elementSlotCounters.remove(dependent);
      setDependencies(dependent, HashSet<_Aspect>());
      return;
    }

    assert(aspect is _Aspect);
    final managed = _managedDependencies.putIfAbsent(dependent, () {
      final set = <_Aspect>{};
      setDependencies(dependent, set);
      return set;
    });

    if (aspect is _Aspect) {
      // Replace existing equivalent aspect so the function closure and cached value are refreshed
      // without accumulating duplicate aspects in memory across widget rebuilds.
      managed.remove(aspect);
      managed.add(aspect);
    }
  }

  @override
  void removeDependent(Element dependent) {
    _managedDependencies.remove(dependent);
    _elementSlotCounters.remove(dependent);
    super.removeDependent(dependent);
  }
}

abstract class _Aspect {
  bool hasChanged(dynamic commander, dynamic oldState, dynamic newState);
}

class _CommanderInstanceAspect implements _Aspect {
  const _CommanderInstanceAspect();

  @override
  bool hasChanged(dynamic commander, dynamic oldState, dynamic newState) =>
      false;
}

class _SlotAspectKey {
  final int slot;
  const _SlotAspectKey(this.slot);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _SlotAspectKey && slot == other.slot;

  @override
  int get hashCode => slot.hashCode;

  @override
  String toString() => '_SlotAspectKey($slot)';
}

class _SelectorAspect<C extends Commander<dynamic, dynamic>, R>
    implements _Aspect {
  final R Function(C commander) selector;
  R lastValue;
  final Object aspectKey;

  _SelectorAspect({
    required this.selector,
    required this.lastValue,
    required this.aspectKey,
  });

  @override
  bool hasChanged(dynamic commander, dynamic oldState, dynamic newState) {
    if (commander is! C) return true;
    final newValue = selector(commander);
    final changed = !identical(lastValue, newValue) && lastValue != newValue;
    if (changed) {
      lastValue = newValue;
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _SelectorAspect<C, R>) return false;
    return aspectKey == other.aspectKey;
  }

  @override
  int get hashCode => Object.hash(C, R, aspectKey);
}
