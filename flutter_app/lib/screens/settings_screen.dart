import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  const SettingsScreen({super.key, required this.api});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ctrl;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.api.baseUrl);
  }

  Future<void> _test() async {
    try {
      await widget.api.setBaseUrl(_ctrl.text.trim());
      final h = await widget.api.health();
      setState(() => _status = 'Koneksi berhasil: ${h['service']}');
    } catch (e) {
      setState(() => _status = 'Gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan'), backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textDark),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alamat Server STB', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(hintText: 'http://192.168.18.240:8000'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _test,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.wifi), SizedBox(width: 8), Text('Tes Koneksi')],
              ),
            ),
            const SizedBox(height: 12),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
