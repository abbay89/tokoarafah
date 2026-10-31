import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme.dart';

class CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shopping_bag, color: AppTheme.secondary),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('${formatRupiah(item.price)}  x${item.qty}  =  ${formatRupiah(item.subtotal)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove, color: AppTheme.warn),
              onPressed: onRemove,
            ),
            IconButton(
              icon: const Icon(Icons.add, color: AppTheme.accent),
              onPressed: onAdd,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.warn),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyCart extends StatelessWidget {
  const EmptyCart({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 80, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 16),
          const Text('Keranjang masih kosong', style: TextStyle(fontSize: 18, color: Color(0xFF888888))),
        ],
      ),
    );
  }
}
