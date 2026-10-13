import 'package:flutter/material.dart';
import 'package:yomitanuki/data/services/camera/camera_frame_source.dart';
import 'package:yomitanuki/data/services/camera/camera_preview_view.dart';
import 'package:yomitanuki/data/services/photo/image_picker_photo_picker.dart';
import 'package:yomitanuki/data/services/photo/photo_picker.dart';
import 'package:yomitanuki/data/services/unavailable/unavailable_ports.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/ports/anki_exporter.dart';
import 'package:yomitanuki/domain/ports/dictionary.dart';
import 'package:yomitanuki/domain/ports/frame_source.dart';
import 'package:yomitanuki/domain/ports/ocr_engine.dart';
import 'package:yomitanuki/domain/ports/text_detector.dart';
import 'package:yomitanuki/ui/about/view/about_view.dart';
import 'package:yomitanuki/ui/reader/view/reader_view.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_view_model.dart';

void main() {
  runApp(YomitanukiApp(dependencies: AppDependencies.production()));
}

/// The composition root's bag: the five ports, the photo picker, and the
/// adapter's preview widget. Tests pass fakes; [production] wires the real
/// adapters this branch has and `Unavailable…` stand-ins for the rest.
class AppDependencies {
  const AppDependencies({
    required this.frameSource,
    required this.cameraPreview,
    required this.photoPicker,
    required this.detector,
    required this.ocr,
    required this.dictionary,
    required this.anki,
    this.ankiSettings = const AnkiSettings(),
  });

  /// Real adapters where this branch has them (camera, photo); the other
  /// four throw `NotWiredError` until WP2b (detector, OCR), WP3 (dictionary)
  /// and WP5 (Anki) replace them here.
  factory AppDependencies.production() {
    final camera = CameraFrameSource();
    return AppDependencies(
      frameSource: camera,
      cameraPreview: (_) => CameraPreviewView(source: camera),
      photoPicker: ImagePickerPhotoPicker(),
      detector: const UnavailableTextDetector(),
      ocr: const UnavailableOcrEngine(),
      dictionary: const UnavailableDictionary(),
      anki: const UnavailableAnkiExporter(),
    );
  }

  final FrameSource frameSource;

  /// Built by the camera adapter module, never by the domain.
  final WidgetBuilder cameraPreview;
  final PhotoPicker photoPicker;
  final TextDetector detector;
  final OcrEngine ocr;
  final Dictionary dictionary;
  final AnkiExporter anki;
  final AnkiSettings ankiSettings;
}

/// Root widget: theme and routes live here, feature screens under `ui/`.
/// Owns the reader view model for the app's lifetime.
class YomitanukiApp extends StatefulWidget {
  const YomitanukiApp({
    required this.dependencies,
    this.routes = const {},
    super.key,
  });

  final AppDependencies dependencies;

  /// Routes other work packages add (WP5: `settings`).
  final Map<String, WidgetBuilder> routes;

  @override
  State<YomitanukiApp> createState() => _YomitanukiAppState();
}

class _YomitanukiAppState extends State<YomitanukiApp> {
  late final ReaderViewModel _reader = ReaderViewModel(
    frameSource: widget.dependencies.frameSource,
    photoPicker: widget.dependencies.photoPicker,
    detector: widget.dependencies.detector,
    ocr: widget.dependencies.ocr,
    dictionary: widget.dependencies.dictionary,
    anki: widget.dependencies.anki,
    ankiSettings: widget.dependencies.ankiSettings,
  );

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yomitanuki',
      theme: ThemeData(colorSchemeSeed: Colors.brown),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.brown,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => ReaderView(
          viewModel: _reader,
          cameraPreview: widget.dependencies.cameraPreview(context),
        ),
      ),
      routes: {AboutView.routeName: (_) => const AboutView(), ...widget.routes},
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => MissingRouteView(name: settings.name ?? '?'),
      ),
    );
  }
}

/// Shown for a route name this build does not provide (e.g. `settings`
/// before WP5 lands), instead of the framework's assertion.
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
