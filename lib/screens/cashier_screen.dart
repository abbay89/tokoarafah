import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/receipt_service.dart';
import '../widgets/cart_widgets.dart';
import '../theme.dart';
import 'printer_select_screen.dart';

class CashierScreen extends StatefulWidget {
  final ApiService api;
  const CashierScreen({super.key, required this.api});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final List<CartItem> _cart = [];
  bool _scanning = false;
  bool _busy = false;
  String? _lastBarcode;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  final TextEditingController _manualBarcodeController = TextEditingController();
  Map<String, dynamic>? _lastTransaction;

  int get _total => _cart.fold(0, (sum, e) => sum + e.subtotal);

  bool _isDuplicateScan(String barcode) {
    final now = DateTime.now();
    if (_lastBarcode == barcode && now.difference(_lastScanAt).inMilliseconds < 2000) {
      return true;
    }
    _lastBarcode = barcode;
    _lastScanAt = now;
    return false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _announce(String name, int price) async {
    try {
      await widget.api.announceItem(name, price);
    } catch (e) {
      _snack('Barang masuk, tapi suara gagal: $e');
    }
  }

  Future<void> _handleBarcode(String raw) async {
    final barcode = raw.trim();
    if (barcode.isEmpty || _isDuplicateScan(barcode)) return;

    final existingIndex = _cart.indexWhere((e) => e.barcode == barcode);
    if (existingIndex >= 0) {
      setState(() => _cart[existingIndex].qty++);
      final item = _cart[existingIndex];
      await _announce(item.name, item.price);
      return;
    }

    setState(() => _busy = true);
    try {
      final product = await widget.api.getProduct(barcode);
      if (!mounted) return;

      if (product != null && product.price != null) {
        final name = product.name ?? barcode;
        setState(() => _cart.add(CartItem(
              barcode: product.barcode,
              name: name,
              price: product.price!,
            )));
        await _announce(name, product.price!);
        return;
      }

      if (product != null) {
        _showPriceDialog(product);
        return;
      }

      await _handleUnknownBarcode(barcode);
    } catch (e) {
      _snack('Gagal memuat barang: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleUnknownBarcode(String barcode) async {
    SearchSuggestResult? suggestion;
    try {
      suggestion = await widget.api.searchSuggest(barcode: barcode);
    } catch (_) {
      // Tetap tampilkan form manual kalau internet sedang tidak tersedia.
    }
    if (!mounted) return;
    _showNewProductDialog(barcode, suggestion);
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
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Harga (Rp)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final price = int.tryParse(priceController.text.trim());
              if (price == null || price <= 0) {
                _snack('Harga harus lebih dari 0');
                return;
              }
              try {
                await widget.api.updateProduct(product.barcode, price: price);
              } catch (e) {
                _snack('Gagal menyimpan harga: $e');
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              final name = product.name ?? product.barcode;
              setState(() => _cart.add(CartItem(
                    barcode: product.barcode,
                    name: name,
                    price: price,
                  )));
              await _announce(name, price);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showNewProductDialog(String barcode, SearchSuggestResult? suggestion) {
    final nameController = TextEditingController(text: suggestion?.name ?? '');
    final priceController = TextEditingController(
      text: suggestion?.recommendedPrice?.toString() ?? '',
    );
    final sourceText = suggestion == null
        ? 'Tidak bisa mengambil saran. Isi nama dan harga manual.'
        : suggestion.estimated
            ? 'Nama saran dari internet. Harga masih estimasi, silakan ubah.'
            : 'Saran nama & harga dari ${suggestion.source ?? "internet"}. Silakan cek dulu.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barang Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: TextEditingController(text: barcode),
                decoration: const InputDecoration(labelText: 'Barcode'),
                readOnly: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama Barang'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga (Rp)'),
              ),
              const SizedBox(height: 10),
              Text(
                sourceText,
                style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final price = int.tryParse(priceController.text.trim());
              if (name.isEmpty) {
                _snack('Nama barang belum diisi');
                return;
              }
              if (price == null || price <= 0) {
                _snack('Harga harus lebih dari 0');
                return;
              }

              try {
                await widget.api.createProduct(barcode, name: name, price: price);
              } catch (e) {
                // Kalau sudah pernah tersimpan (mis. dua kali scan), update saja.
                try {
                  await widget.api.updateProduct(barcode, name: name, price: price);
                } catch (_) {
                  _snack('Gagal menyimpan barang: $e');
                  return;
                }
              }

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() => _cart.add(CartItem(
                    barcode: barcode,
                    name: name,
                    price: price,
                  )));
              await _announce(name, price);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.checkout(_cart);
      if (!mounted) return;
      final total = result['total'] is int
          ? result['total'] as int
          : int.tryParse(result['total']?.toString() ?? '') ?? 0;
      final txId = result['transaction_id'] is int
          ? result['transaction_id'] as int
          : int.tryParse(result['transaction_id']?.toString() ?? '') ?? 0;

      _lastTransaction = {
        'transaction_id': txId,
        'total': total,
        'created_at': result['created_at'] ?? DateTime.now().toString(),
        'items': List<Map<String, dynamic>>.from(_cart.map((e) => {
          'barcode': e.barcode,
          'name': e.name,
          'price': e.price,
          'qty': e.qty,
        })),
      };

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pembayaran Selesai'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total: ${formatRupiah(total)}'),
              const SizedBox(height: 12),
              Text('ID Transaksi: #$txId'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showReceiptOptions();
              },
              child: const Text('Cetak/Unduh Resi'),
            ),
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
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showReceiptOptions() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resi Transaksi'),
        content: const Text('Pilih opsi untuk resi transaksi ini:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _downloadReceipt();
            },
            child: const Text('Unduh Resi (PDF)'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _printReceiptBluetooth();
            },
            child: const Text('Cetak Bluetooth'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadReceipt() async {
    if (_lastTransaction == null) return;
    setState(() => _busy = true);
    try {
      final tx = _lastTransaction!;
      final items = (tx['items'] as List)
          .map((e) => CartItem(
                barcode: e['barcode'],
                name: e['name'],
                price: e['price'],
                qty: e['qty'],
              ))
          .toList();
      final pdfBytes = await ReceiptService.generateReceiptPdf(
        transactionId: tx['transaction_id'],
        createdAt: DateTime.parse(tx['created_at']),
        items: items,
        total: tx['total'],
      );
      final fileName = 'resi_${tx['transaction_id']}.pdf';
      final path = await ReceiptService.saveReceiptToDownloads(
        pdfBytes: pdfBytes,
        fileName: fileName,
      );
      if (!mounted) return;
      if (path == null) {
        _snack('Gagal menyimpan resi: izin penyimpanan tidak diberikan');
        return;
      }
      await ReceiptService.openReceipt(path);
      _snack('Resi disimpan: $path');
    } catch (e) {
      _snack('Gagal unduh resi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printReceiptBluetooth() async {
    if (_lastTransaction == null) return;
    final prefs = await SharedPreferences.getInstance();
    final macAddress = prefs.getString('printer_mac');

    if (macAddress == null || macAddress.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PrinterSelectScreen(onPrinterSelected: () {
            _printReceiptBluetooth();
          }),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final tx = _lastTransaction!;
      final items = (tx['items'] as List)
          .map((e) => CartItem(
                barcode: e['barcode'],
                name: e['name'],
                price: e['price'],
                qty: e['qty'],
              ))
          .toList();
      final success = await ReceiptService.printReceiptBluetooth(
        macAddress: macAddress,
        deviceName: 'Printer Tersimpan',
        transactionId: tx['transaction_id'],
        createdAt: DateTime.parse(tx['created_at']),
        items: items,
        total: tx['total'],
      );
      if (!mounted) return;
      _snack(success ? 'Resi dicetak' : 'Gagal mencetak resi');
    } catch (e) {
      _snack('Gagal cetak: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitManualBarcode() {
    final value = _manualBarcodeController.text.trim();
    if (value.isEmpty) return;
    _manualBarcodeController.clear();
    _handleBarcode(value);
  }

  Widget _buildScanner() {
    return Container(
      height: 220,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.trim().isNotEmpty) {
                  setState(() => _scanning = false);
                  _handleBarcode(value);
                  break;
                }
              }
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Arahkan kamera ke barcode',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _manualBarcodeController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitManualBarcode(),
              decoration: const InputDecoration(
                hintText: 'Ketik barcode manual',
                isDense: true,
                prefixIcon: Icon(Icons.keyboard),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _submitManualBarcode,
            child: const Text('Tambah'),
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
      body: Column(
        children: [
          if (_scanning) _buildScanner(),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
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
          _buildManualInput(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatRupiah(_total),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _cart.isEmpty || _busy ? null : _checkout,
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.secondary,
        onPressed: () => setState(() => _scanning = !_scanning),
        child: Icon(_scanning ? Icons.close : Icons.qr_code_scanner),
      ),
    );
  }

  @override
  void dispose() {
    _manualBarcodeController.dispose();
    super.dispose();
  }
}
