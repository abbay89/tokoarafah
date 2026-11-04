import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import '../models/models.dart';

class ReceiptService {
  static const String shopName = 'Toko Arafah';

  static Future<Uint8List> generateReceiptPdf({
    required int transactionId,
    required DateTime createdAt,
    required List<CartItem> items,
    required int total,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                shopName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Transaksi #$transactionId',
                style: pw.TextStyle(fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                createdAt.toString(),
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.center,
              ),
              pw.Divider(),
              pw.SizedBox(height: 4),
              ...items.map((item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${item.name} x${item.qty}', style: pw.TextStyle(fontSize: 11)),
                  pw.Text(formatRupiah(item.subtotal), style: pw.TextStyle(fontSize: 11)),
                ],
              )),
              pw.Divider(),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text(formatRupiah(total), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Terima kasih telah belanja',
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String formatRupiah(int? v) {
    final n = v ?? 0;
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp ${buf.toString()}';
  }

  static Future<String?> saveReceiptToDownloads({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      final manageStatus = await Permission.manageExternalStorage.request();
      if (!manageStatus.isGranted) {
        return null;
      }
    }

    final directory = await getDownloadsDirectory();
    final path = directory?.path;
    if (path == null) {
      final docsDir = await getApplicationDocumentsDirectory();
      final filePath = '${docsDir.path}/$fileName';
      await File(filePath).writeAsBytes(pdfBytes);
      return filePath;
    }

    final filePath = '$path/$fileName';
    await File(filePath).writeAsBytes(pdfBytes);
    return filePath;
  }

  static Future<void> openReceipt(String filePath) async {
    await OpenFilex.open(filePath);
  }

  static Future<List<BluetoothDevice>> getBondedPrinters() async {
    return await BlueThermalPrinter.instance.getBondedDevices();
  }

  static Future<bool> printReceiptBluetooth({
    required String macAddress,
    required String deviceName,
    required int transactionId,
    required DateTime createdAt,
    required List<CartItem> items,
    required int total,
  }) async {
    final printer = BlueThermalPrinter.instance;
    final device = BluetoothDevice(deviceName, macAddress);

    final connected = await printer.connect(device);
    if (connected != true) {
      return false;
    }

    try {
      await printer.printCustom(shopName, 2, 1);
      await printer.printCustom('Transaksi #$transactionId', 1, 1);
      await printer.printCustom(createdAt.toString(), 1, 1);
      await printer.printNewLine();

      await printer.printCustom(
        '${_padRight('Item', 16)}${'Qty'.padRight(6)}${'Total'.padRight(8)}',
        1,
        0,
      );
      await printer.printCustom('-' * 30, 1, 0);
      await printer.printNewLine();

      for (final item in items) {
        final name = item.name.length > 16
            ? item.name.substring(0, 16)
            : item.name.padRight(16);
        final qty = item.qty.toString().padRight(6);
        final price = formatRupiah(item.price).padRight(8);
        await printer.printCustom('$name$qty$price', 1, 0);
        await printer.printCustom(
          '${' ' * 8}x${item.qty} ${formatRupiah(item.subtotal)}',
          1,
          0,
        );
      }

      await printer.printCustom('-' * 30, 1, 0);
      await printer.printCustom(
        'Total: ${formatRupiah(total)}',
        1,
        2,
      );
      await printer.printNewLine();
      await printer.printNewLine();
      await printer.printCustom('Terima kasih telah belanja', 1, 1);
      await printer.printNewLine();
      await printer.printNewLine();
      await printer.paperCut();

      return true;
    } finally {
      await printer.disconnect();
    }
  }

  static String _padRight(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }
}
