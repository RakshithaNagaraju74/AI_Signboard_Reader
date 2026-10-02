import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signboard_reader/models/sign_model.dart';
import 'package:signboard_reader/services/tts_service.dart';
import 'package:signboard_reader/widgets/sign_card.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final signModel = Provider.of<SignModel>(context);
    final detections = signModel.detections;
    final imagePath = signModel.lastImagePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: () async {
              for (var detection in detections) {
                await TTSService().speak(
                  signModel.getSpokenDescription(detection),
                );
                await Future.delayed(const Duration(milliseconds: 500));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (imagePath.isNotEmpty)
            Container(
              height: 250,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.error),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Found ${detections.length} sign${detections.length > 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: detections.isEmpty
                ? const Center(
                    child: Text('No signs detected in this image'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: detections.length,
                    itemBuilder: (context, index) {
                      return SignCard(
                        detection: detections[index],
                        spokenText: signModel.getSpokenDescription(
                          detections[index],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context);
        },
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    );
  }
}