import 'package:flutter_commander/testing.dart';
import 'package:flutter_commander_example/src/core/models/order.dart';
import 'package:flutter_commander_example/src/core/models/product.dart';
import 'package:flutter_commander_example/src/core/services/analytics_service.dart';
import 'package:flutter_commander_example/src/core/services/catalog_service.dart';
import 'package:flutter_commander_example/src/core/services/payment_service.dart';
import 'package:flutter_commander_example/src/features/shop/commander/shop_commander.dart';
import 'package:flutter_commander_example/src/features/shop/commander/shop_effect.dart';
import 'package:flutter_commander_example/src/features/shop/commander/shop_state.dart';
import 'package:flutter_commander_example/src/features/shop/intents/shop_intents.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePaymentService implements PaymentService {
  @override
  Future<OrderConfirmation> processPayment({required double amount}) async {
    return OrderConfirmation(
      orderId: 'ORD-9999',
      totalAmount: amount,
      timestamp: DateTime(2026, 1, 1),
    );
  }
}

class FakeCatalogService extends CatalogService {
  @override
  Future<List<Product>> searchProducts(String query) async {
    return const [];
  }
}

class FakeAnalyticsService extends AnalyticsService {
  @override
  Future<String> recordEvent(String eventName) async {
    return 'LOGGED: $eventName';
  }
}

void main() {
  group('ShopCommander Orchestrator Tests with commanderTest', () {
    late CatalogService catalogService;
    late PaymentService paymentService;
    late AnalyticsService analyticsService;

    ShopCommander buildCommander() => ShopCommander(
          catalogService: catalogService,
          paymentService: paymentService,
          analyticsService: analyticsService,
        );

    setUp(() {
      catalogService = FakeCatalogService();
      paymentService = FakePaymentService();
      analyticsService = FakeAnalyticsService();
    });

    commanderTest<ShopCommander, ShopState, ShopEffect>(
      'toggles VIP discount, updates state, and emits ShowSnackbarEffect',
      build: buildCommander,
      act: (commander) => commander.dispatch(const ToggleVipDiscountIntent()),
      expectStates: () => [
        const ShopState(hasVipDiscount: true),
      ],
      expectEffects: () => [
        const ShowSnackbarEffect('VIP 15% discount applied!'),
      ],
      verify: (commander) {
        expect(commander.state.hasVipDiscount, isTrue);
      },
    );

    commanderTest<ShopCommander, ShopState, ShopEffect>(
      'processes checkout from seeded state, clearing cart and emitting confirmation',
      build: buildCommander,
      seed: () => const ShopState(cartItemCount: 3),
      act: (commander) => commander.dispatch(const CheckoutIntent()),
      expectStates: () => [
        const ShopState(cartItemCount: 3, isCheckingOut: true),
        const ShopState(cartItemCount: 0, isCheckingOut: false),
      ],
      expectEffects: () => [
        isA<OrderConfirmedEffect>().having(
          (e) => e.confirmation.orderId,
          'orderId',
          'ORD-9999',
        ),
      ],
      verify: (commander) {
        expect(commander.state.cartItemCount, 0);
        expect(commander.state.isCheckingOut, isFalse);
      },
    );

    commanderTest<ShopCommander, ShopState, ShopEffect>(
      'empty cart checkout does not transition state or emit effects',
      build: buildCommander,
      seed: () => const ShopState(cartItemCount: 0),
      act: (commander) => commander.dispatch(const CheckoutIntent()),
      expectStates: () => <ShopState>[],
      expectEffects: () => <ShopEffect>[],
    );
  });
}
