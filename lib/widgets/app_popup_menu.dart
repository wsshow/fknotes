import 'package:flutter/material.dart';

import '../app.dart';

class AppPopupMenuItem<T> extends PopupMenuItem<T> {
  const AppPopupMenuItem({
    super.key,
    super.value,
    super.enabled = true,
    required super.child,
  }) : super(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12));

  AppPopupMenuItem.action({
    super.key,
    super.value,
    super.enabled = true,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) : super(
         height: 44,
         padding: const EdgeInsets.symmetric(horizontal: 12),
         child: AppPopupMenuRow(
           icon: icon,
           label: label,
           destructive: destructive,
         ),
       );
}

class AppPopupMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const AppPopupMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.coral : null;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
