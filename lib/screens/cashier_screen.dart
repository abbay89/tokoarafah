import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/big_icon_button.dart';
import '../widgets/cart_widgets.dart';
import '../theme.dart';

class CashierScreen extends StatefulWidget {
  final ApiService api;
  const CashierScreen({super.key, required this.api});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final List<CartItem> _cart = [];
  bool _scanning = false;
  bool _processingBarcode = false;
  String _barcodeInput = '';
  final TextEditingController _barcodeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  int get _total => _cart.fold(0, (sum, e) => sum + e.subtotal);

  @override
  void dispose() {
    _processingBarcode = false;
    _scannerController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    final existing = _cart.where((e) => e.barcode == barcode).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty++);
      return;
    }
    final product = await widget.api.getProduct(barcode);
    if (product != null && product.price != null) {
      setState(() => _cart.add(CartItem(barcode: barcode, name: product.name ?? barcode, price: product.price!)));
      widget.api.speak('${product.name ?? barcode} dimasukkan ke keranjang');
      return;
    }
    if (product != null) {
      _showPriceDialog(product);
      return;
    }
    _showNewProductDialog(barcode);
  }

  void _showPriceDialog(Product product) {
    final priceController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.name ?? product.barcode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Harga belum diisi. Masukkan harga:'),
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
              final p = int.tryParse(priceController.text.trim());
              await widget.api.updateProduct(product.barcode, price: p);
              Navigator.pop(ctx);
              setState(() => _cart.add(CartItem(barcode: product.barcode, name: product.name ?? product.barcode, price: p ?? 0)));
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showNewProductDialog(String barcode) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barang Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: TextEditingController(text: barcode), decoration: const InputDecoration(labelText: 'Barcode'), readOnly: true),
            const SizedBox(height: 12),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Barang')),
            const SizedBox(height: 12),
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final price = int.tryParse(priceController.text.trim());
              await widget.api.createProduct(barcode, name: name.isEmpty ? null : name, price: price);
              Navigator.pop(ctx);
              setState(() => _cart.add(CartItem(barcode: barcode, name: name.isEmpty ? barcode : name, price: price ?? 0)));
              widget.api.speak('${name.isEmpty ? barcode : name} dimasukkan ke keranjang');
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final result = await widget.api.checkout(_cart);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran Selesai'),
        content: Text('Total: ${formatRupiah(result['total'])}'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _cart.clear());
            },
            child: const Text('Transaksi Baru'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toko Arafah - Kasir'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textDark,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _cart.isEmpty
                    ? const EmptyCart()
                    : ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (ctx, i) => CartItemTile(
                          item: _cart[i],
                          onAdd: () => setState(() => _cart[i].qty++),
                          onRemove: () => setState(() {
                            if (_cart[i].qty > 1) _cart[i].qty--;
                            else _cart.removeAt(i);
                          }),
                          onDelete: () => setState(() => _cart.removeAt(i)),
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(formatRupiah(_total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _cart.isEmpty ? null : _checkout,
                            child: const Text('Bayar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_scanning)
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) {
                        if (_processingBarcode) return;
                        final List<Barcode> barcodes = capture.barcodes;
                        final code = barcodes.first.rawValue ?? '';
                        if (code.isNotEmpty && mounted) {
                          _processingBarcode = true;
                          setState(() => _scanning = false);
                          _handleBarcode(code).then((_) => _processingBarcode = false);
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _scanning = false),
                        tooltip: 'Tutup pemindaian',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.secondary,
        onPressed: () => setState(() => _scanning = !_scanning),
        child: Icon(_scanning ? Icons.close : Icons.qr_code_scanner),
      ),
    );
  }
}
