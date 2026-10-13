import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomitanuki/data/repositories/shared_preferences_settings_repository.dart';
import 'package:yomitanuki/data/services/anki/url_launcher_anki_exporter.dart';
import 'package:yomitanuki/data/services/camera/camera_frame_source.dart';
import 'package:yomitanuki/data/services/camera/camera_preview_view.dart';
import 'package:yomitanuki/data/services/dictionary/bundled_dictionary_asset.dart';
import 'package:yomitanuki/data/services/dictionary/lazy_dictionary.dart';
import 'package:yomitanuki/data/services/ort/lazy_inference.dart';
import 'package:yomitanuki/data/services/photo/image_picker_photo_picker.dart';
import 'package:yomitanuki/domain/ports/anki_exporter.dart';
import 'package:yomitanuki/domain/ports/dictionary.dart';
import 'package:yomitanuki/domain/ports/frame_source.dart';
import 'package:yomitanuki/domain/ports/ocr_engine.dart';
import 'package:yomitanuki/domain/ports/photo_picker.dart';
import 'package:yomitanuki/domain/ports/settings_repository.dart';
import 'package:yomitanuki/domain/ports/text_detector.dart';
import 'package:yomitanuki/ui/about/view/about_view.dart';
import 'package:yomitanuki/ui/core/theme.dart';
import 'package:yomitanuki/ui/core/view/missing_route_view.dart';
import 'package:yomitanuki/ui/reader/view/reader_view.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_view_model.dart';
import 'package:yomitanuki/ui/settings/view/settings_view.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

void main() {
  runApp(YomitanukiApp(dependencies: AppDependencies.production()));
}

/// The composition root's bag: the ports, the photo picker, and the camera
/// adapter's preview widget. Tests pass fakes; [production] wires the real
/// adapters (every port has one since WP2b).
class AppDependencies {
  const AppDependencies({
    required this.frameSource,
    required this.cameraPreview,
    required this.photoPicker,
    required this.detector,
    required this.ocr,
    required this.dictionary,
    required this.anki,
    required this.settingsRepository,
  });

  /// Real adapters: camera and photo (WP4), detector and OCR (WP2b, created
  /// on first use: the first detection pays the model copy and the CoreML
  /// compile), dictionary (WP3), Anki export and settings (WP5).
  factory AppDependencies.production() {
    final camera = CameraFrameSource();
    final inference = LazyInference.production();
    return AppDependencies(
      frameSource: camera,
      cameraPreview: (_) => CameraPreviewView(source: camera),
      photoPicker: ImagePickerPhotoPicker(),
      detector: inference.detector,
      ocr: inference.ocr,
      dictionary: LazyDictionary(asset: BundledDictionaryAsset()),
      anki: UrlLauncherAnkiExporter(),
      settingsRepository: SharedPreferencesSettingsRepository(
        SharedPreferencesAsync(),
      ),
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
  final SettingsRepository settingsRepository;
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

  /// Routes a later work package adds on top of `about` and `settings`.
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
    settings: widget.dependencies.settingsRepository,
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
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => ReaderView(
          viewModel: _reader,
          cameraPreview: widget.dependencies.cameraPreview(context),
        ),
      ),
      routes: {
        AboutView.routeName: (_) => const AboutView(),
        // A fresh view model per visit: the screen loads on open and saves
        // on every edit (WP5 D5.7); nothing is kept between visits.
        'settings': (_) => SettingsView(
          viewModel: SettingsViewModel(
            repository: widget.dependencies.settingsRepository,
          ),
        ),
        ...widget.routes,
      },
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => MissingRouteView(name: settings.name ?? '?'),
      ),
    );
  }
}
