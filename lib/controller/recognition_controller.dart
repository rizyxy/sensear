import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:get/get.dart';
import 'dart:io';
import 'dart:async';

class SoundModel {
  Interpreter? _interpreter;
  static const int SAMPLE_RATE = 16000;
  static const int CHUNK_DURATION_MS = 200;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter =
          await Interpreter.fromAsset('assets/model.tflite', options: options);

      // Print model input and output shapes for debugging
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print("Model input shape: $inputShape");
      print("Model output shape: $outputShape");

      print("Model loaded successfully");
    } catch (e) {
      print("Error loading model: $e");
      rethrow;
    }
  }

  Future<List<double>?> recognizeSound(Uint8List audioData) async {
    if (_interpreter == null) {
      throw StateError("Interpreter is not loaded.");
    }

    try {
      // Get actual input and output shapes from the model
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      // Process input data
      final processedData = _preprocessAudio(audioData, inputShape);

      // Create output tensor with correct shape [1, 2]
      // The model expects a 2D array with shape [1, 2]
      var outputBuffer = List.generate(
          outputShape[0], (_) => List<double>.filled(outputShape[1], 0.0));

      // Run inference
      _interpreter!.run(processedData, outputBuffer);

      // Flatten the output to return
      return outputBuffer[
          0]; // Return just the inner array since we only have one batch
    } catch (e) {
      print("Error during inference: $e");
      return null;
    }
  }

  List<List<double>> _preprocessAudio(
      Uint8List audioData, List<int> inputShape) {
    // Convert bytes to float array normalized between -1 and 1
    final List<double> floatData = audioData.map((byte) {
      return (byte - 128) / 128.0;
    }).toList();

    // Reshape the data to match the input shape [1, N]
    // Where N is the number of audio samples expected by the model
    final requiredLength =
        inputShape[1]; // Get the required length from input shape

    // Pad or truncate to match required length
    if (floatData.length < requiredLength) {
      floatData
          .addAll(List<double>.filled(requiredLength - floatData.length, 0));
    } else if (floatData.length > requiredLength) {
      floatData.length = requiredLength;
    }

    // Return as 2D array with shape [1, N]
    return [floatData];
  }

  String formatOutput(List<double> output) {
    // Assuming binary classification (e.g., [probability_class_0, probability_class_1])
    final maxIndex = output.indexOf(output.reduce((a, b) => a > b ? a : b));
    final probability = output[maxIndex] * 100;
    return "Class $maxIndex (${probability.toStringAsFixed(2)}%)";
  }

  Future<void> close() async {
    _interpreter?.close();
  }
}

class RecognitionController extends GetxController {
  final _listening = false.obs;
  final recognitionOutput = ''.obs;
  final recordingStatus = "Not Recording".obs;

  FlutterSoundRecorder? _audioRecorder;
  final SoundModel _soundModel = SoundModel();
  StreamSubscription? _recordingSubscription;

  bool get isListening => _listening.value;

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await checkAudioPermission();
      await _initRecorder();
      await _soundModel.loadModel();
    } catch (e) {
      print("Initialization error: $e");
      // Handle initialization error appropriately
    }
  }

  Future<void> checkAudioPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw StateError('Microphone permission is required');
    }
  }

  Future<void> _initRecorder() async {
    _audioRecorder = FlutterSoundRecorder();
    await _audioRecorder!.openRecorder();
    await _audioRecorder!.setSubscriptionDuration(
      const Duration(milliseconds: SoundModel.CHUNK_DURATION_MS),
    );
  }

  Future<void> toggleListening() async {
    try {
      _listening.value = !_listening.value;

      if (_listening.value) {
        await _startRecording();
      } else {
        await _stopRecording();
      }
    } catch (e) {
      _listening.value = false;
      print("Error toggling recording: $e");
      // Handle error appropriately
    }
  }

  Future<void> _startRecording() async {
    recordingStatus.value = "Recording...";

    final recordingDataController = StreamController<Uint8List>();

    await _audioRecorder!.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: SoundModel.SAMPLE_RATE,
    );

    _recordingSubscription = recordingDataController.stream.listen(
      (Uint8List data) async {
        if (data.isNotEmpty) {
          final result = await _soundModel.recognizeSound(data);
          if (result != null) {
            recognitionOutput.value = _formatRecognitionResult(result);
          }
        }
      },
      onError: (error) {
        print("Recording error: $error");
        toggleListening(); // Stop recording on error
      },
    );
  }

// Function name: _formatRecognitionResult
// Input: List<double> result - Array of confidence scores [doorbell, vehicle horn]
// Output: String describing which sound was detected and its confidence level
  String _formatRecognitionResult(List<double> result) {
    // Find index of highest confidence score (0 = doorbell, 1 = vehicle horn)
    final maxIndex = result.indexOf(result.reduce((a, b) => a > b ? a : b));

    // Convert index to category name
    final category = maxIndex == 0 ? "doorbell" : "vehicle horn";

    // Return formatted string with category name and confidence percentage
    return "Detected sound category: $category (${(result[maxIndex] * 100).toStringAsFixed(2)}%)";
  }

  Future<void> _stopRecording() async {
    await _recordingSubscription?.cancel();
    await _audioRecorder!.stopRecorder();
    recordingStatus.value = "Not Recording";
  }

  @override
  Future<void> onClose() async {
    await _stopRecording();
    await _audioRecorder?.closeRecorder();
    await _soundModel.close();
    super.onClose();
  }
}
