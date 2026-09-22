import '../models/product.dart';

/// Simulated remote catalog repository.
class CatalogService {
  static const List<Product> _mockCatalog = [
    Product(
        id: 'p1',
        title: 'MacBook Pro M3 Max 16"',
        price: 3499.0,
        category: 'Laptops'),
    Product(
        id: 'p2',
        title: 'Google Pixel 9 Pro XL',
        price: 1099.0,
        category: 'Smartphones'),
    Product(
        id: 'p3',
        title: 'iPad Pro 13-inch M4 OLED',
        price: 1299.0,
        category: 'Tablets'),
    Product(
        id: 'p4',
        title: 'Sony WH-1000XM5 Wireless Headphones',
        price: 399.0,
        category: 'Audio'),
    Product(
        id: 'p5',
        title: 'Dell UltraSharp 32" 4K Thunderbolt Hub',
        price: 899.0,
        category: 'Monitors'),
    Product(
        id: 'p6',
        title: 'Keychron Q1 Pro Mechanical Keyboard',
        price: 199.0,
        category: 'Accessories'),
    Product(
        id: 'p7',
        title: 'Logitech MX Master 3S Wireless Mouse',
        price: 99.0,
        category: 'Accessories'),
  ];

  /// Performs simulated type-ahead product searches with network latency.
  Future<List<Product>> searchProducts(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    return _mockCatalog
        .where((p) =>
            p.title.toLowerCase().contains(trimmed) ||
            p.category.toLowerCase().contains(trimmed))
        .toList();
  }

  /// Fetches featured products.
  Future<List<Product>> fetchFeatured() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _mockCatalog.take(3).toList();
  }
}
