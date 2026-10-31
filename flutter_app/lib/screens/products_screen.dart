import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ProductsScreen extends StatefulWidget {
  final ApiService api;
  const ProductsScreen({super.key, required this.api});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = [];
  bool _loading = false;
  final TextEditingController _search = TextEditingController();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listProducts(search: _search.text.trim());
      setState(() => _products = list);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barang'), backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textDark),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Cari nama/barcode'),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _products.length,
                    itemBuilder: (ctx, i) {
                      final p = _products[i];
                      return ListTile(
                        title: Text(p.name ?? p.barcode),
                        subtitle: Text('${p.barcode}  ${p.price == null ? "Harga belum diisi" : formatRupiah(p.price)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.warn),
                          onPressed: () async {
                            await widget.api.deleteProduct(p.barcode);
                            _load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
