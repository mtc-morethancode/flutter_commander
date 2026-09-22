import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_commander_example/src/core/models/order.dart';
import 'package:flutter_commander_example/src/core/services/payment_service.dart';
import 'package:flutter_commander_example/src/features/shop/commands/checkout_command.dart';
import 'package:flutter_commander_example/src/features/shop/controller/shop_effect.dart';
import 'package:flutter_commander_example/src/features/shop/controller/shop_state.dart';
import 'package:flutter_commander_example/src/features/shop/intents/shop_intents.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePaymentService implements PaymentService {
  @override
  Future<OrderConfirmation> processPayment({required double amount}) async {
    return OrderConfirmation(
      orderId: 'TEST-1234',
      totalAmount: amount,
      timestamp: DateTime(2026, 1, 1),
    );
  }
}

void main() {
  group('CheckoutCommand Unit Tests', () {
    test('declares ExecutionPolicy.drop to prevent duplicate submissions', () {
      final command = CheckoutCommand(FakePaymentService());
      expect(command.policy, equals(ExecutionPolicy.drop));
    });

    test(
        'updates state to loading, clears cart on success, and emits OrderConfirmedEffect',
        () async {
      final fakeService = FakePaymentService();
      final command = CheckoutCommand(fakeService);

      // Given initial cart with 2 items
      const initialState = ShopState(cartItemCount: 2);
      final testScope = TestCommandScope<ShopState, ShopEffect>(initialState);

      // When executing checkout
      await command.execute(testScope, const CheckoutIntent());

      // Then verify deterministic state transitions
      expect(testScope.states.length, equals(2));
      expect(testScope.states[0].isCheckingOut, isTrue);
      expect(testScope.states[1].isCheckingOut, isFalse);
      expect(testScope.states[1].cartItemCount, equals(0));

      // And verify emitted side effects
      expect(testScope.effects.length, equals(1));
      final effect = testScope.effects.first as OrderConfirmedEffect;
      expect(effect.confirmation.orderId, equals('TEST-1234'));
      expect(effect.confirmation.totalAmount, equals(998.0));
    });

    test('does nothing if cart is already empty', () async {
      final command = CheckoutCommand(FakePaymentService());
      const initialState = ShopState(cartItemCount: 0);
      final testScope = TestCommandScope<ShopState, ShopEffect>(initialState);

      await command.execute(testScope, const CheckoutIntent());

      expect(testScope.states, isEmpty);
      expect(testScope.effects, isEmpty);
    });
  });
}
