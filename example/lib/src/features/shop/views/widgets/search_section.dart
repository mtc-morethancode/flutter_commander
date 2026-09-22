import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import '../../../../core/models/product.dart';
import '../../controller/shop_commander.dart';
import '../../controller/shop_state.dart';
import '../../intents/shop_intents.dart';

/// Product search bar showcasing [ExecutionPolicy.restart].
class SearchSection extends StatelessWidget {
  const SearchSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live Search (ExecutionPolicy.RESTART)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  tooltip: 'Parallel Refresh (CONCURRENT)',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context
                        .dispatch<ShopCommander>(const RefreshCatalogIntent());
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Type to search (e.g. Mac, Pixel, iPad)...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (text) {
                context.dispatch<ShopCommander>(SearchProductsIntent(text));
                context.dispatch<ShopCommander>(
                    TrackAnalyticsIntent('search:$text'));
              },
            ),
            const SizedBox(height: 8),
            // Rebuilds only when searching flag or search results change
            CommanderSelector<ShopCommander, ShopState, (bool, List<Product>)>(
              select: (s) => (s.isSearching, s.searchResults),
              builder: (context, slice) {
                final (isSearching, results) = slice;
                if (isSearching) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (results.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No products matched your search.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: results
                      .map((product) => ListTile(
                            leading:
                                const Icon(Icons.devices, color: Colors.indigo),
                            title: Text(product.title),
                            subtitle: Text(product.category),
                            trailing: Text(
                              '\$${product.price.toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
