import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import '../services/receipt_service.dart';
import '../theme.dart';

class PrinterSelectScreen extends StatefulWidget {
  final VoidCallback onPrinterSelected;
  const PrinterSelectScreen({super.key, required this.onPrinterSelected});

  @override
  State<PrinterSelectScreen> createState() => _PrinterSelectScreenState();
}

class _PrinterSelectScreenState extends State<PrinterSelectScreen> {
  final List<BluetoothDevice> _devices = [];
  bool _loading = false;
  bool _busy = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBondedDevices() async {
    setState(() {
      _loading = true;
      _devices.clear();
    });

    try {
      final devices = await ReceiptService.getBondedPrinters();
      if (!mounted) return;
      setState(() {
        _devices.addAll(devices);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memindai printer Bluetooth: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBondedDevices();
  }

  Future<void> _selectPrinter(BluetoothDevice device) async {
    setState(() => _busy = true);
    try {
      final printer = BlueThermalPrinter.instance;
      final connected = await printer.connect(device);
      await printer.disconnect();

      if (connected != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat terhubung ke printer')),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_mac', device.address ?? '');
      if (!mounted) return;
      widget.onPrinterSelected();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan printer: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Printer Bluetooth'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textDark,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading || _busy ? null : _loadBondedDevices,
                    child: const Text('Muat Ulang Perangkat'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('Belum ada printer Bluetooth yang terpair'))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final d = _devices[i];
                      return ListTile(
                        leading: const Icon(Icons.print),
                        title: Text(d.name ?? 'Printer Tidak Dikenal'),
                        subtitle: Text(d.address ?? 'Tanpa alamat'),
                        trailing: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: _busy ? null : () => _selectPrinter(d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
