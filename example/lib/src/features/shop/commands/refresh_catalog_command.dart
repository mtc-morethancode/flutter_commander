import 'package:flutter_commander/flutter_commander.dart';

import '../../../core/services/catalog_service.dart';
import '../controller/shop_effect.dart';
import '../controller/shop_state.dart';
import '../intents/shop_intents.dart';

/// Handles refreshing featured products in parallel with [ExecutionPolicy.concurrent].
class RefreshCatalogCommand
    extends Command<RefreshCatalogIntent, ShopState, ShopEffect> {
  final CatalogService _catalogService;

  RefreshCatalogCommand(this._catalogService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.concurrent;

  @override
  Future<void> execute(
    CommandScope<ShopState, ShopEffect> scope,
    RefreshCatalogIntent intent,
  ) async {
    scope.updateState((s) => s.copyWith(isRefreshing: true));

    final featured = await _catalogService.fetchFeatured();

    scope.updateState((s) => s.copyWith(
          featuredProducts: featured,
          isRefreshing: false,
        ));
    scope.emitSideEffect(
        const ShowSnackbarEffect('Catalog refreshed successfully!'));
  }
}
