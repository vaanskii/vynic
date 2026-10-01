import 'package:flutter/material.dart';
import '../services/menu/menu_client_compatibility.dart';

/// Visible on every POS route after an explicit Cloud compatibility refusal.
/// Offline connectivity failures never produce this state or erase local data.
class MenuUpdateRequired extends StatelessWidget {
  const MenuUpdateRequired({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: MenuClientCompatibility.updateRequired,
    builder: (context, message, _) => Column(
      children: [
        if (message != null)
          Material(
            color: const Color(0xff7f1d1d),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}
