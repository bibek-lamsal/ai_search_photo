import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class CLIPService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobileclip_b_datacompdr_lt_last.tflite',
        options: options,
      );
      _isolateInterpreter = await IsolateInterpreter.create(address: _interpreter!.address);
      _isInitialized = true;
    } catch (e) {
      debugPrint("Error loading CLIP model: $e");
      _isInitialized = false;
    }
  }

  // Pre-process image for CLIP (1 x 3 x 224 x 224)
  static Float32List _preprocessImageTask(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return Float32List(0);

      final resized = img.copyResize(image, 
        width: 224, 
        height: 224, 
        interpolation: img.Interpolation.linear
      );
      
      final input = Float32List(1 * 3 * 224 * 224);
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);
          input[0 * 224 * 224 + y * 224 + x] = (pixel.r / 255.0 - 0.48145466) / 0.26862954;
          input[1 * 224 * 224 + y * 224 + x] = (pixel.g / 255.0 - 0.4578275) / 0.26130258;
          input[2 * 224 * 224 + y * 224 + x] = (pixel.b / 255.0 - 0.40821073) / 0.27577711;
        }
      }
      return input;
    } catch (e) {
      debugPrint("Error preprocessing image: $e");
      return Float32List(0);
    }
  }

  static Int32List _tokenizeTask(String text) {
    final tokens = Int32List(77);
    const startToken = 49406;
    const endToken = 49407;

    tokens[0] = startToken;
    final bytes = text.toLowerCase().codeUnits;
    int i = 0;
    for (; i < bytes.length && i < 75; i++) {
      tokens[i + 1] = bytes[i];
    }
    tokens[i + 1] = endToken;
    return tokens;
  }

  Future<List<double>> generateImageEmbedding(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return generateImageEmbeddingFromBytes(bytes);
  }

  Future<List<double>> generateImageEmbeddingFromBytes(Uint8List bytes) async {
    await init();
    if (!_isInitialized || _isolateInterpreter == null) return [];

    final inputData = await compute(_preprocessImageTask, bytes);
    if (inputData.isEmpty) return [];

    final inputImage = inputData.reshape([1, 3, 224, 224]);
    final inputText = Int32List(77).reshape([1, 77]);
    
    final inputs = [inputImage, inputText];
    final outputBuffer = Float32List(512).reshape([1, 512]);
    final outputs = {0: outputBuffer};

    try {
      await _isolateInterpreter!.runForMultipleInputs(inputs, outputs);
      return List<double>.from(outputBuffer[0]);
    } catch (e) {
      debugPrint("Error running CLIP model for image: $e");
      return [];
    }
  }

  Future<List<double>> generateTextEmbedding(String text) async {
    await init();
    if (!_isInitialized || _isolateInterpreter == null) return [];

    final inputImage = Float32List(1 * 3 * 224 * 224).reshape([1, 3, 224, 224]);
    final inputText = _tokenizeTask(text).reshape([1, 77]);

    final inputs = [inputImage, inputText];
    final outputBuffer = Float32List(512).reshape([1, 512]);
    final outputs = {0: outputBuffer};

    try {
      await _isolateInterpreter!.runForMultipleInputs(inputs, outputs);
      return List<double>.from(outputBuffer[0]);
    } catch (e) {
      debugPrint("Error running CLIP model for text: $e");
      return [];
    }
  }
  
  void dispose() {
    _isolateInterpreter?.close();
    _interpreter?.close();
  }
}
