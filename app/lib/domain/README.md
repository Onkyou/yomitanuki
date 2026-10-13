# domain

Plain models and the ports every adapter implements. Nothing in here imports Flutter
widgets, plugins or ONNX Runtime. Each port has exactly two kinds of implementation:
the real adapter under `lib/data/services/`, and a fake under `test/fakes/` used by
every test that is not the adapter's own.

| Port | Real adapter | Work package |
|---|---|---|
| `TextDetector` | ONNX Runtime, blocks-only detector graph | WP2 |
| `OcrEngine` | ONNX Runtime, manga-ocr encoder + greedy decoder | WP2 |
| `Dictionary` | SQLite (JMdict + KANJIDIC2) + deinflector | WP3 |
| `FrameSource` | `camera` plugin, BGRA8888 stream | WP4 |
| `AnkiExporter` | `anki://x-callback-url/addnote` via `url_launcher` | WP5 |
| `SettingsRepository` | `shared_preferences`, under `lib/data/repositories/` | WP5 |

Image data crosses every port as `BgraImage` (8-bit BGRA, the iOS camera's native
layout); the ONNX graphs consume it directly (WP0 D0.9), so no adapter resamples pixels.
