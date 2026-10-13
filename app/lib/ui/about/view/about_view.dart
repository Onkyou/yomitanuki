import 'package:flutter/material.dart';

/// Attribution for the data and models the app ships with. The EDRDG
/// licence requires this screen (PLAN.md section 1); the licence texts are
/// placeholders until the dictionary (WP3) and model (WP2) assets land.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const routeName = 'about';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About Yomitanuki')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Yomitanuki reads physical manga with the camera: bubbles are '
            'boxed live, tapped bubbles are read on the device, words are '
            'looked up offline, and a tap sends a card to AnkiMobile. '
            'Nothing leaves the phone.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Text('Data and models', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Attribution(
            title: 'JMdict and KANJIDIC2',
            body:
                'The dictionary files are the property of the Electronic '
                'Dictionary Research and Development Group (EDRDG) and are '
                'used in conformance with the Group\'s licence '
                '(Creative Commons Attribution-ShareAlike 4.0). '
                'Built from the jmdict-simplified releases.',
          ),
          const _Attribution(
            title: 'manga-ocr',
            body:
                'Text recognition uses kha-white/manga-ocr, '
                'Apache License 2.0.',
          ),
          const _Attribution(
            title: 'comic-text-detector',
            body:
                'Bubble detection uses dmMaze/comic-text-detector, '
                'GNU General Public License v3.0. This is a personal '
                'build and is not distributed.',
          ),
          const _Attribution(
            title: 'Deinflection rules',
            body:
                'Derived from the Yomitan project, '
                'GNU General Public License v3.0.',
          ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
