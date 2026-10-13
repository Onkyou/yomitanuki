part of 'ort.dart';

/// CoreML `ModelFormat`. WP0 C3: `NeuralNetwork` reaches the ANE for the
/// detector; `MLProgram` lands on the GPU and cannot compile the OCR encoder.
enum CoreMlModelFormat {
  neuralNetwork('NeuralNetwork'),
  mlProgram('MLProgram');

  const CoreMlModelFormat(this.key);

  /// The value ORT expects for the `ModelFormat` provider option.
  final String key;
}

/// CoreML `MLComputeUnits`. D0.10 uses [cpuAndNeuralEngine] so a GPU fallback
/// cannot hide an ANE rejection.
enum CoreMlComputeUnits {
  cpuOnly('CPUOnly'),
  cpuAndNeuralEngine('CPUAndNeuralEngine'),
  cpuAndGpu('CPUAndGPU'),
  all('ALL');

  const CoreMlComputeUnits(this.key);

  final String key;
}

/// Options for the CoreML execution provider, passed to ORT through the
/// string-keyed `SessionOptionsAppendExecutionProvider("CoreML", ...)` API.
/// Defaults are WP0 D0.10; [modelCacheDirectory] must be an existing,
/// writable directory (the compiled model is cached there; compiling took
/// 1.8 s per session on an M2).
class CoreMlOptions {
  const CoreMlOptions({
    required this.modelCacheDirectory,
    this.modelFormat = CoreMlModelFormat.neuralNetwork,
    this.computeUnits = CoreMlComputeUnits.cpuAndNeuralEngine,
  });

  final String modelCacheDirectory;
  final CoreMlModelFormat modelFormat;
  final CoreMlComputeUnits computeUnits;

  /// The provider option keys and values exactly as handed to ORT.
  Map<String, String> get providerOptions => {
    'ModelFormat': modelFormat.key,
    'MLComputeUnits': computeUnits.key,
    'ModelCacheDirectory': modelCacheDirectory,
  };
}
