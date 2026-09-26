import 'package:flutter/foundation.dart';
import '../../../core/models/product.dart';

/// Immutable presentation state for the Shop feature.
class ShopState {
  final String searchQuery;
  final List<Product> searchResults;
  final List<Product> featuredProducts;
  final bool isSearching;
  final bool isCheckingOut;
  final bool isRefreshing;
  final bool hasVipDiscount;
  final List<String> analyticsLog;
  final int cartItemCount;

  const ShopState({
    this.searchQuery = '',
    this.searchResults = const [],
    this.featuredProducts = const [],
    this.isSearching = false,
    this.isCheckingOut = false,
    this.isRefreshing = false,
    this.hasVipDiscount = false,
    this.analyticsLog = const [],
    this.cartItemCount = 2,
  });

  /// Computed subtotal based on current cart items.
  double get subtotal => cartItemCount * 499.0;

  /// Active discount rate.
  double get discountRate => hasVipDiscount ? 0.15 : 0.0;

  /// Computed grand total after applicable discounts.
  double get total => subtotal * (1.0 - discountRate);

  ShopState copyWith({
    String? searchQuery,
    List<Product>? searchResults,
    List<Product>? featuredProducts,
    bool? isSearching,
    bool? isCheckingOut,
    bool? isRefreshing,
    bool? hasVipDiscount,
    List<String>? analyticsLog,
    int? cartItemCount,
  }) {
    return ShopState(
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      featuredProducts: featuredProducts ?? this.featuredProducts,
      isSearching: isSearching ?? this.isSearching,
      isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      hasVipDiscount: hasVipDiscount ?? this.hasVipDiscount,
      analyticsLog: analyticsLog ?? this.analyticsLog,
      cartItemCount: cartItemCount ?? this.cartItemCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopState &&
          runtimeType == other.runtimeType &&
          searchQuery == other.searchQuery &&
          isSearching == other.isSearching &&
          isCheckingOut == other.isCheckingOut &&
          isRefreshing == other.isRefreshing &&
          hasVipDiscount == other.hasVipDiscount &&
          cartItemCount == other.cartItemCount &&
          listEquals(searchResults, other.searchResults) &&
          listEquals(featuredProducts, other.featuredProducts) &&
          listEquals(analyticsLog, other.analyticsLog);

  @override
  int get hashCode => Object.hash(
        searchQuery,
        isSearching,
        isCheckingOut,
        isRefreshing,
        hasVipDiscount,
        cartItemCount,
        Object.hashAll(searchResults),
        Object.hashAll(featuredProducts),
        Object.hashAll(analyticsLog),
      );

  @override
  String toString() =>
      'ShopState(query: "$searchQuery", results: ${searchResults.length}, checkingOut: $isCheckingOut, vip: $hasVipDiscount)';
}
