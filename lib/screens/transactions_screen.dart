import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme.dart';

class TransactionsScreen extends StatefulWidget {
  final ApiService api;
  const TransactionsScreen({super.key, required this.api});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> _tx = [];
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.getTransactions();
      if (!mounted) return;
      setState(() => _tx = list);
    } catch (e) {
      if (!mounted) return;
      _snack('Gagal memuat riwayat: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat'), backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textDark),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                  itemCount: _tx.length,
                  itemBuilder: (ctx, i) {
                    final t = _tx[i];
                    return Card(
                      child: ExpansionTile(
                        title: Text('Transaksi #${t.id}'),
                        subtitle: Text('${t.createdAt}  •  ${formatRupiah(t.total)}'),
                        children: t.items
                            .map((e) => ListTile(
                                  title: Text(e.name),
                                  subtitle: Text('${formatRupiah(e.price)} x${e.qty}'),
                                  trailing: Text(formatRupiah(e.price * e.qty)),
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),
            ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
