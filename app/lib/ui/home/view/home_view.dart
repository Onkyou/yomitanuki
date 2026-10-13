import 'package:flutter/material.dart';

/// Placeholder home screen. The reader UI (PLAN.md WP4) replaces its body.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Yomitanuki')));
  }
}
