import 'package:flutter/material.dart';

/// Placeholder home screen; the reader UI replaces its body.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Yomitanuki')));
  }
}
