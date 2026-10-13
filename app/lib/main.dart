import 'package:flutter/material.dart';
import 'package:yomitanuki/ui/home/view/home_view.dart';

void main() {
  runApp(const YomitanukiApp());
}

/// Root widget: theme and navigation live here, feature screens under `ui/`.
class YomitanukiApp extends StatelessWidget {
  const YomitanukiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yomitanuki',
      theme: ThemeData(colorSchemeSeed: Colors.brown),
      home: const HomeView(),
    );
  }
}
