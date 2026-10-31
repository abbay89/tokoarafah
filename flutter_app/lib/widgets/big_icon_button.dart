import 'package:flutter/material.dart';
import 'package:tokasrafah_kasir/theme.dart';

class BigIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const BigIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: c.withOpacity(0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              child: Icon(icon, size: 36, color: c),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
      ],
    );
  }
}
