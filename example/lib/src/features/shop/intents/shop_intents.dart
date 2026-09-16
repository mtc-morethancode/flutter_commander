import 'package:flutter_commander/flutter_commander.dart';

/// Sealed hierarchy of all user and system intents for the Shop feature.
sealed class ShopIntent extends Intent {
  const ShopIntent();
}

/// Triggered when the user enters or changes search terms.
final class SearchProductsIntent extends ShopIntent {
  final String query;
  const SearchProductsIntent(this.query);
}

/// Triggered when the user taps the checkout button.
final class CheckoutIntent extends ShopIntent {
  const CheckoutIntent();
}

/// Triggered when an analytics event needs to be tracked.
final class TrackAnalyticsIntent extends ShopIntent {
  final String event;
  const TrackAnalyticsIntent(this.event);
}

/// Triggered to asynchronously refresh the product catalog in parallel.
final class RefreshCatalogIntent extends ShopIntent {
  const RefreshCatalogIntent();
}

/// Triggered to toggle the VIP 15% discount switch.
final class ToggleVipDiscountIntent extends ShopIntent {
  const ToggleVipDiscountIntent();
}
