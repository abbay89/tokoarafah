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
        onPressed: _showAddProductDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddProductDialog() {
    final barcodeController = TextEditingController();
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Barang'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: barcodeController,
              decoration: const InputDecoration(labelText: 'Barcode'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama Barang'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Harga (Rp)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final barcode = barcodeController.text.trim();
              final name = nameController.text.trim();
              final price = int.tryParse(priceController.text.trim());
              if (barcode.isEmpty) return;
              try {
                await widget.api.createProduct(barcode, name: name.isEmpty ? null : name, price: price);
                if (!mounted) return;
                Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Gagal tambah barang: $e')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
