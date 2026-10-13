import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An [AssetBundle] over an in-memory map of asset key to bytes, recording
/// every [load] so a test can assert what was (not) read.
class FakeAssetBundle extends AssetBundle {
  FakeAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  /// Every key passed to [load], in order.
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(bytes);
  }
}
