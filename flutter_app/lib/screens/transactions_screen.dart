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
      setState(() => _tx = list);
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
      appBar: AppBar(title: const Text('Riwayat'), backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textDark),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
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
    );
  }
}
