import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sensear_app/controller/recognition_controller.dart';

class HomePage extends StatelessWidget {
  final RecognitionController controller = Get.put(RecognitionController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sound Recognition')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display recording status
            Obx(() => Text(
                  controller.recordingStatus.value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                )),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => controller.toggleListening(),
              child: Obx(() => Text(
                    controller.isListening
                        ? 'Stop Listening'
                        : 'Start Listening',
                    style: TextStyle(fontSize: 18),
                  )),
            ),
            SizedBox(height: 20),
            Obx(() => Text(
                  controller.recognitionOutput.value,
                  textAlign: TextAlign.center,
                )),
          ],
        ),
      ),
    );
  }
}
