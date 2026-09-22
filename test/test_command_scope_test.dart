import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

// Test domain models
class OrderState {
  final bool isLoading;
  final bool isSuccess;
  final String? orderId;

  const OrderState({
    required this.isLoading,
    required this.isSuccess,
    this.orderId,
  });

  factory OrderState.initial() => const OrderState(
        isLoading: false,
        isSuccess: false,
      );

  OrderState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? orderId,
  }) {
    return OrderState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      orderId: orderId ?? this.orderId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          isSuccess == other.isSuccess &&
          orderId == other.orderId;

  @override
  int get hashCode => Object.hash(isLoading, isSuccess, orderId);

  @override
  String toString() =>
      'OrderState(isLoading: $isLoading, isSuccess: $isSuccess, orderId: $orderId)';
}

sealed class OrderEffect {
  const OrderEffect();
}

class NavigateToConfirmationEffect extends OrderEffect {
  final String orderId;
  const NavigateToConfirmationEffect(this.orderId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigateToConfirmationEffect &&
          runtimeType == other.runtimeType &&
          orderId == other.orderId;

  @override
  int get hashCode => orderId.hashCode;

  @override
  String toString() => 'NavigateToConfirmationEffect(orderId: $orderId)';
}

class SubmitOrderIntent extends CommandIntent {
  final String orderId;
  const SubmitOrderIntent(this.orderId);
}

class SubmitOrderCommand
    extends Command<SubmitOrderIntent, OrderState, OrderEffect> {
  final Future<void> Function(String id)? onApiCall;

  SubmitOrderCommand({this.onApiCall});

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Future<void> execute(
    CommandScope<OrderState, OrderEffect> scope,
    SubmitOrderIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(isLoading: true));
    if (onApiCall != null) {
      await onApiCall!(intent.orderId);
    }
    scope.updateState((s) =>
        s.copyWith(isLoading: false, isSuccess: true, orderId: intent.orderId));
    scope.emitSideEffect(NavigateToConfirmationEffect(intent.orderId));
  }
}

void main() {
  group('TestCommandScope Harness', () {
    test('verifies atomic command execution exactly as specified', () async {
      final command = SubmitOrderCommand();
      final testScope =
          TestCommandScope<OrderState, OrderEffect>(OrderState.initial());

      await command.execute(testScope, const SubmitOrderIntent('id_123'));

      final expectedLoadingState =
          OrderState.initial().copyWith(isLoading: true);
      final expectedSuccessState = OrderState.initial().copyWith(
        isLoading: false,
        isSuccess: true,
        orderId: 'id_123',
      );
      const expectedNavEffect = NavigateToConfirmationEffect('id_123');

      expect(testScope.states, [expectedLoadingState, expectedSuccessState]);
      expect(testScope.effects, [expectedNavEffect]);
      expect(testScope.state, equals(expectedSuccessState));
      expect(testScope.history, [
        OrderState.initial(),
        expectedLoadingState,
        expectedSuccessState,
      ]);
    });

    test('cancellation suppresses state mutations and effect emissions', () {
      final testScope =
          TestCommandScope<OrderState, OrderEffect>(OrderState.initial());

      testScope.updateState((s) => s.copyWith(isLoading: true));
      expect(testScope.states.length, equals(1));

      testScope.cancel();
      expect(testScope.isCancelled, isTrue);

      testScope.updateState((s) => s.copyWith(isSuccess: true));
      testScope.emitSideEffect(const NavigateToConfirmationEffect('cancelled'));

      // No new state or effect added after cancel
      expect(testScope.states.length, equals(1));
      expect(testScope.effects, isEmpty);
    });

    test('reset() restores initial state and empties recorded collections', () {
      final testScope =
          TestCommandScope<OrderState, OrderEffect>(OrderState.initial());

      testScope.updateState((s) => s.copyWith(isLoading: true));
      testScope.emitSideEffect(const NavigateToConfirmationEffect('1'));

      expect(testScope.states, isNotEmpty);
      expect(testScope.effects, isNotEmpty);

      testScope.reset();

      expect(testScope.state, equals(OrderState.initial()));
      expect(testScope.states, isEmpty);
      expect(testScope.effects, isEmpty);
    });

    test('hasState and hasEffect helper predicates work', () {
      final testScope =
          TestCommandScope<OrderState, OrderEffect>(OrderState.initial());

      testScope.updateState((s) => s.copyWith(orderId: 'xyz'));
      testScope.emitSideEffect(const NavigateToConfirmationEffect('xyz'));

      expect(testScope.hasState((s) => s.orderId == 'xyz'), isTrue);
      expect(testScope.hasState((s) => s.orderId == 'abc'), isFalse);

      expect(
        testScope.hasEffect(
            (e) => e is NavigateToConfirmationEffect && e.orderId == 'xyz'),
        isTrue,
      );
      expect(
        testScope.hasEffect((e) =>
            e is NavigateToConfirmationEffect && e.orderId == 'nonexistent'),
        isFalse,
      );
    });
  });
}
