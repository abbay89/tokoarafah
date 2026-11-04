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
      if (!mounted) return;
      setState(() => _products = list);
    } catch (e) {
      _snack('Gagal memuat barang: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showProductDialog({Product? product}) {
    final isEdit = product != null;
    final barcodeController = TextEditingController(text: product?.barcode ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product?.price?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Ubah Barang' : 'Tambah Barang'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: barcodeController,
                readOnly: isEdit,
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
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final barcode = barcodeController.text.trim();
              final name = nameController.text.trim();
              final price = int.tryParse(priceController.text.trim());
              if (!isEdit && barcode.isEmpty) {
                _snack('Barcode belum diisi');
                return;
              }
              if (name.isEmpty) {
                _snack('Nama barang belum diisi');
                return;
              }
              if (price == null || price <= 0) {
                _snack('Harga harus lebih dari 0');
                return;
              }
              try {
                if (isEdit) {
                  await widget.api.updateProduct(product.barcode, name: name, price: price);
                } else {
                  await widget.api.createProduct(barcode, name: name, price: price);
                }
              } catch (e) {
                _snack('Gagal menyimpan: $e');
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Barang?'),
        content: Text('${product.name ?? product.barcode} akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warn),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteProduct(product.barcode);
      _load();
    } catch (e) {
      _snack('Gagal menghapus: $e');
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
      appBar: AppBar(
        title: const Text('Barang'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textDark,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Cari nama/barcode',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _load,
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _products.length,
                      itemBuilder: (ctx, i) {
                        final p = _products[i];
                        return ListTile(
                          title: Text(p.name ?? p.barcode),
                          subtitle: Text(
                            '${p.barcode}  '
                            '${p.price == null ? "Harga belum diisi" : formatRupiah(p.price)}',
                          ),
                          onTap: () => _showProductDialog(product: p),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.warn),
                            onPressed: () => _delete(p),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => _showProductDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
