class Product {
  final String barcode;
  final String? name;
  final int? price;
  final String? createdAt;
  final String? updatedAt;

  Product({
    required this.barcode,
    this.name,
    this.price,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> j) {
    return Product(
      barcode: (j['barcode'] ?? '').toString(),
      name: j['name']?.toString(),
      price: j['price'] is int ? j['price'] as int : (j['price'] == null ? null : int.tryParse(j['price'].toString())),
      createdAt: j['created_at']?.toString(),
      updatedAt: j['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'price': price,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class CartItem {
  final String barcode;
  final String name;
  final int price;
  int qty;

  CartItem({
    required this.barcode,
    required this.name,
    required this.price,
    this.qty = 1,
  });

  int get subtotal => price * qty;
}

class Transaction {
  final int id;
  final int total;
  final String createdAt;
  final List<TransactionItem> items;

  Transaction({
    required this.id,
    required this.total,
    required this.createdAt,
    required this.items,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] ?? 0,
        total: j['total'] ?? 0,
        createdAt: j['created_at'] ?? '',
        items: (j['items'] as List? ?? [])
            .map((e) => TransactionItem.fromJson(e))
            .toList(),
      );
}

class TransactionItem {
  final int id;
  final int transactionId;
  final String barcode;
  final String name;
  final int price;
  final int qty;

  TransactionItem({
    required this.id,
    required this.transactionId,
    required this.barcode,
    required this.name,
    required this.price,
    required this.qty,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
        id: j['id'] ?? 0,
        transactionId: j['transaction_id'] ?? 0,
        barcode: j['barcode'] ?? '',
        name: j['name'] ?? '',
        price: j['price'] ?? 0,
        qty: j['qty'] ?? 0,
      );
}

class PriceSuggestion {
  final String source;
  final String title;
  final String price;

  PriceSuggestion({required this.source, required this.title, required this.price});
}

class SearchSuggestResult {
  final String? barcode;
  final String? name;
  final List<PriceSuggestion> priceSuggestions;
  final int? recommendedPrice;
  final bool cached;

  SearchSuggestResult({
    this.barcode,
    this.name,
    this.priceSuggestions = const [],
    this.recommendedPrice,
    this.cached = false,
  });
}