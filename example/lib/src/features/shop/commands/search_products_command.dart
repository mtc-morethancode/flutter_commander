import 'package:flutter_commander/flutter_commander.dart';

import '../../../core/services/catalog_service.dart';
import '../commander/shop_effect.dart';
import '../commander/shop_state.dart';
import '../intents/shop_intents.dart';

/// Handles live product queries with [ExecutionPolicy.restart].
///
/// If the user types rapidly, previous in-flight queries are automatically
/// cancelled cooperatively via [CommandScope.cancellationToken], ensuring only
/// the latest query mutates presentation state.
class SearchProductsCommand
    extends Command<SearchProductsIntent, ShopState, ShopEffect> {
  final CatalogService _catalogService;

  SearchProductsCommand(this._catalogService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.restart;

  @override
  Future<void> execute(
    CommandScope<ShopState, ShopEffect> scope,
    SearchProductsIntent intent,
  ) async {
    final query = intent.query.trim();

    scope.updateState((s) => s.copyWith(
          searchQuery: query,
          isSearching: query.isNotEmpty,
        ));

    if (query.isEmpty) {
      scope.updateState((s) => s.copyWith(
            searchResults: const [],
            isSearching: false,
          ));
      return;
    }

    // Call service with cooperative cancellation check
    final results = await _catalogService.searchProducts(query);

    // If cancelled during network latency, do not mutate state
    if (scope.isCancelled) return;

    scope.updateState((s) => s.copyWith(
          searchResults: results,
          isSearching: false,
        ));
  }
}
