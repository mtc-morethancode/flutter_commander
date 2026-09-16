/// Product entity representing catalog items.
class Product {
  final String id;
  final String title;
  final double price;
  final String category;

  const Product({
    required this.id,
    required this.title,
    required this.price,
    required this.category,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Product(id: $id, title: $title, price: \$$price)';
}
