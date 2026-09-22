import 'package:flutter_commander/flutter_commander.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/payment_service.dart';
import '../commands/checkout_command.dart';
import '../commands/refresh_catalog_command.dart';
import '../commands/search_products_command.dart';
import '../commands/track_analytics_command.dart';
import '../intents/shop_intents.dart';
import 'shop_effect.dart';
import 'shop_state.dart';

/// Orchestrator for the Shop feature.
///
/// Binds isolated use-case commands with their injected services and policies,
/// and defines fast inline DSL handlers for simple UI mutations.
class ShopCommander extends Commander<ShopState, ShopEffect> {
  ShopCommander({
    required CatalogService catalogService,
    required PaymentService paymentService,
    required AnalyticsService analyticsService,
  }) : super(
          const ShopState(),
          interceptors: const [LoggingCommandInterceptor()],
        ) {
    // 1. Bind formal commands with explicit policies:
    bind(SearchProductsCommand(catalogService));
    bind(CheckoutCommand(paymentService));
    bind(TrackAnalyticsCommand(analyticsService));
    bind(RefreshCatalogCommand(catalogService));

    // 2. Inline DSL for fast UI mutations without creating separate classes:
    on<ToggleVipDiscountIntent>((scope, intent) {
      final updated = !scope.state.hasVipDiscount;
      scope.updateState((s) => s.copyWith(hasVipDiscount: updated));

      scope.emitSideEffect(
        ShowSnackbarEffect(
          updated ? 'VIP 15% discount applied!' : 'VIP discount removed.',
        ),
      );
    });
  }
}

/// Backward-compatible alias for [ShopCommander].
typedef ShopController = ShopCommander;
