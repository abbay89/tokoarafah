import 'package:flutter/material.dart';
import 'package:tokasrafah_kasir/theme.dart';
import 'package:tokasrafah_kasir/services/api_service.dart';
import 'package:tokasrafah_kasir/screens/cashier_screen.dart';
import 'package:tokasrafah_kasir/screens/products_screen.dart';
import 'package:tokasrafah_kasir/screens/transactions_screen.dart';
import 'package:tokasrafah_kasir/screens/settings_screen.dart';
import 'package:tokasrafah_kasir/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = await ApiService.getSavedUrl();
  final api = ApiService(baseUrl: url);
  runApp(TokoArafahApp(api: api));
}

class TokoArafahApp extends StatelessWidget {
  final ApiService api;
  const TokoArafahApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toko Arafah Kasir',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(homeScreen: HomeShell(api: api)),
    );
  }
}

class HomeShell extends StatefulWidget {
  final ApiService api;
  const HomeShell({super.key, required this.api});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      CashierScreen(api: widget.api),
      ProductsScreen(api: widget.api),
      TransactionsScreen(api: widget.api),
      SettingsScreen(api: widget.api),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: const Color(0xFF888888),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Kasir'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Barang'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Riwayat'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}
