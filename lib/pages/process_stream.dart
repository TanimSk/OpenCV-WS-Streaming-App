import 'dart:async';
import 'package:fabric_defect_detector/utils/settings_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ProcessStream extends StatefulWidget {
  const ProcessStream({super.key});

  @override
  _ProcessStream createState() => _ProcessStream();
}

class _ProcessStream extends State<ProcessStream> {
  late WebSocketChannel _channel;
  final ValueNotifier<Uint8List?> _imageDataNotifier =
      ValueNotifier<Uint8List?>(null);
  Timer? retryTimer;
  late Map<String, dynamic> _settings;
  final SettingsPreferences _settingsPreferences = SettingsPreferences();
  bool _isDetectionStarted = false;
  int _defectionCount = 0;

  // Platform channel to communicate with native code
  static const platform = MethodChannel('opencv_processing');
  static const EventChannel _eventChannel =
      EventChannel('com.example.fabric_defect_detector/events');

  @override
  void initState() {
    super.initState();
    connectWebSocket();

    _eventChannel.receiveBroadcastStream().listen((event) {
      print("---------- Received event from native: $event ----------");
      setState(() async {
        _defectionCount = event as int;
        _settings["total_defection_count"] = _defectionCount;
        await _settingsPreferences.setSettings(_settings);
      });
    });
  }

  void connectWebSocket() async {
    try {
      _settings = await _settingsPreferences.getSettings();
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://${_settings["device_ip"]}'),
      );
      _channel.stream.listen(
        (data) {
          // Assuming image bytes received
          Uint8List imageData = data as Uint8List;
          // Process the image using OpenCV
          processFrame(imageData).then((processedImage) async {
            if (processedImage != null) {
              _imageDataNotifier.value = processedImage;
              // setState(() async {
              // _defectionCount =
              // await platform.invokeMethod('defectionCount') as int;
              // _settings["total_defection_count"] = _defectionCount;
              // _settingsPreferences.setSettings(_settings);
              // });
            }
          });
        },
        onError: (error) {
          print('WebSocket error: $error');
          retryConnection();
        },
        onDone: () {
          Navigator.pushReplacementNamed(context, '/home');
          print('WebSocket connection closed');
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
      retryTimer = Timer(const Duration(seconds: 2), connectWebSocket);
    }
  }

  // Process frame using OpenCV via platform channels
  Future<Uint8List?> processFrame(Uint8List? frame) async {
    try {
      return await platform.invokeMethod('processFrame', frame);
    } on PlatformException catch (e) {
      print("Failed to process frame: ${e.message}");
      return frame;
    }
  }

  void retryConnection() {
    retryTimer?.cancel();
    retryTimer = Timer(const Duration(seconds: 5), connectWebSocket);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Image Stream'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _channel.sink.close();
            Navigator.pushReplacementNamed(
                context, '/home'); // Navigate back when the button is pressed
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Add a horizontal slider
            Slider(
              value: _defectionCount.toDouble(),
              min: 0,
              max: 25, // Adjust the max value as needed
              divisions: 25,
              label: _defectionCount.toString(),
              onChanged: (double value) async {
                await platform.invokeMethod(
                  'setQCWait',
                  value.toInt(),
                );
              },
            ),
            const SizedBox(height: 10),
            Slider(
              value: _defectionCount.toDouble(),
              min: 0,
              max: 25, // Adjust the max value as needed
              divisions: 25,
              label: _defectionCount.toString(),
              onChanged: (double value) async {
                await platform.invokeMethod(
                  'setDefectWait',
                  value.toInt(),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              "Defects detected: $_defectionCount",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            ValueListenableBuilder<Uint8List?>(
              valueListenable: _imageDataNotifier,
              builder: (context, imageData, child) {
                if (imageData == null) {
                  return const CircularProgressIndicator();
                }
                return Image.memory(
                  imageData,
                  gaplessPlayback: true,
                  fit: BoxFit.cover,
                );
              },
            ),
            const SizedBox(height: 30),
            // Button is now outside the ValueListenableBuilder, so it won't rebuild unnecessarily
            ElevatedButton(
              onPressed: () async {
                _isDetectionStarted = !_isDetectionStarted;
                bool state = await platform.invokeMethod(
                  'startDetection',
                  _isDetectionStarted,
                );
                setState(() {
                  _isDetectionStarted = state;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4.0),
                ),
              ),
              child: Text(
                _isDetectionStarted ? "Stop detection" : "Start detection",
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channel.sink
        .close(); // Close the WebSocket connection when the widget is disposed
    retryTimer?.cancel();
    super.dispose();
  }
}
