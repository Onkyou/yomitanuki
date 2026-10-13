import 'package:flutter/material.dart';

/// Shown for a route name this build does not provide, instead of the
/// framework's "could not find a generator" assertion.
class MissingRouteView extends StatelessWidget {
  const MissingRouteView({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The "$name" screen is not available in this build.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
