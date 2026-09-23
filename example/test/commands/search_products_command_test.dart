import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_commander_example/src/core/models/product.dart';
import 'package:flutter_commander_example/src/core/services/catalog_service.dart';
import 'package:flutter_commander_example/src/features/shop/commands/search_products_command.dart';
import 'package:flutter_commander_example/src/features/shop/commander/shop_effect.dart';
import 'package:flutter_commander_example/src/features/shop/commander/shop_state.dart';
import 'package:flutter_commander_example/src/features/shop/intents/shop_intents.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCatalogService implements CatalogService {
  @override
  Future<List<Product>> searchProducts(String query) async {
    return [
      const Product(
          id: 'p1', title: 'MacBook Pro', price: 2000, category: 'Laptops'),
    ];
  }

  @override
  Future<List<Product>> fetchFeatured() async => const [];
}

void main() {
  group('SearchProductsCommand Unit Tests', () {
    test('declares ExecutionPolicy.restart for live search', () {
      final command = SearchProductsCommand(FakeCatalogService());
      expect(command.policy, equals(ExecutionPolicy.restart));
    });

    test('clears results immediately when query is empty', () async {
      final command = SearchProductsCommand(FakeCatalogService());
      final testScope = TestCommandScope<ShopState, ShopEffect>(
        const ShopState(searchResults: [
          Product(id: 'p1', title: 'MacBook', price: 2000, category: 'Laptops'),
        ]),
      );

      await command.execute(testScope, const SearchProductsIntent(''));

      expect(testScope.states.last.searchResults, isEmpty);
      expect(testScope.states.last.isSearching, isFalse);
    });

    test('populates search results upon successful query', () async {
      final command = SearchProductsCommand(FakeCatalogService());
      final testScope =
          TestCommandScope<ShopState, ShopEffect>(const ShopState());

      await command.execute(testScope, const SearchProductsIntent('Mac'));

      expect(testScope.states.length, equals(2));
      expect(testScope.states[0].isSearching, isTrue);
      expect(testScope.states[1].isSearching, isFalse);
      expect(testScope.states[1].searchResults.length, equals(1));
      expect(
          testScope.states[1].searchResults.first.title, equals('MacBook Pro'));
    });

    test('cooperative cancellation prevents state mutation when cancelled',
        () async {
      final command = SearchProductsCommand(FakeCatalogService());
      final testScope =
          TestCommandScope<ShopState, ShopEffect>(const ShopState());

      // Simulate mid-execution cancellation
      testScope.cancel();

      await command.execute(testScope, const SearchProductsIntent('Mac'));

      // Cancelled scope suppresses updateState
      expect(testScope.states, isEmpty);
    });
  });
}
