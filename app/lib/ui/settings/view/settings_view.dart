import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/anki_settings.dart';
import '../view_model/settings_view_model.dart';

/// The settings screen: Anki deck, note type and the six field names, each
/// saved as it is edited. WP4's `main.dart` registers it under the route
/// name `settings`; the reader opens it with `Navigator.pushNamed`.
class SettingsView extends StatefulWidget {
  const SettingsView({required this.viewModel, super.key});

  final SettingsViewModel viewModel;

  static const deckKey = ValueKey('settings.deck');
  static const noteTypeKey = ValueKey('settings.noteType');
  static Key fieldKey(AnkiField field) =>
      ValueKey('settings.field.${field.name}');

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _deck = TextEditingController();
  final _noteType = TextEditingController();
  final _fields = {
    for (final field in AnkiField.values) field: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_syncControllers);
    unawaited(widget.viewModel.load());
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_syncControllers);
    _deck.dispose();
    _noteType.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pushes view-model state into the controllers after a load or a reset.
  /// An edit typed into a controller already equals the state it produced,
  /// so this never moves the caret under the user's finger.
  void _syncControllers() {
    final s = widget.viewModel.settings;
    if (s == null) return;
    _set(_deck, s.deck);
    _set(_noteType, s.noteType);
    for (final MapEntry(key: field, value: c) in _fields.entries) {
      _set(c, s.fieldName(field));
    }
  }

  static void _set(TextEditingController c, String text) {
    if (c.text != text) c.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // In the app bar, not at the end of the list: always reachable,
          // keyboard up or not.
          TextButton(
            onPressed: () => unawaited(vm.resetToDefaults()),
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.settings == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = vm.error;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) _ErrorBanner(message: error),
              _Section(
                title: 'Anki',
                children: [
                  _Field(
                    fieldKey: SettingsView.deckKey,
                    controller: _deck,
                    label: 'Deck',
                    hint: 'Nested decks separated by ::',
                    onChanged: (v) => unawaited(vm.setDeck(v)),
                  ),
                  _Field(
                    fieldKey: SettingsView.noteTypeKey,
                    controller: _noteType,
                    label: 'Note type',
                    onChanged: (v) => unawaited(vm.setNoteType(v)),
                  ),
                ],
              ),
              _Section(
                title: 'Field names',
                subtitle: 'As the note type spells them in AnkiMobile.',
                children: [
                  for (final field in AnkiField.values)
                    _Field(
                      fieldKey: SettingsView.fieldKey(field),
                      controller: _fields[field]!,
                      label: _fieldLabels[field]!,
                      onChanged: (v) => unawaited(vm.setFieldName(field, v)),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

const _fieldLabels = {
  AnkiField.word: 'Word',
  AnkiField.reading: 'Reading',
  AnkiField.meaning: 'Meaning',
  AnkiField.example: 'Example (the OCR line)',
  AnkiField.exampleEn: 'Example, English',
  AnkiField.note: 'Note',
};

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.fieldKey,
    this.hint,
  });

  /// Identifies the [TextField] itself, for tests.
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: fieldKey,
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
