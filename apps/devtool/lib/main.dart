import 'package:flutter/material.dart';

import 'src/home_page.dart';

/// Vynic Unlocker — signs developer unlock tokens for the POS.
///
/// This never ships to a customer. It signs the unlock tokens that open the
/// developer half of the POS admin panel, and it is useless without the private
/// key file it reads at startup.
void main() {
  runApp(const VynicUnlockerApp());
}

class VynicUnlockerApp extends StatelessWidget {
  const VynicUnlockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vynic Unlocker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B5DD3),
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.comfortable,
      ),
      home: const DevToolHomePage(),
    );
  }
}
