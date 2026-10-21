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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading results'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Read results aloud',
            icon: const Icon(Icons.volume_up_rounded),
            onPressed: detections.isEmpty
                ? null
                : () async {
                    for (var detection in detections) {
                      await TTSService().speak(
                        signModel.getSpokenDescription(detection),
                      );
                      await Future.delayed(const Duration(milliseconds: 500));
                    }
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF173A4A), Color(0xFF17233C)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF59D6C8).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.fact_check_rounded, color: Color(0xFF7FE4D8), size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detections.isEmpty
                                    ? 'No signs found yet'
                                    : '${detections.length} ${detections.length == 1 ? 'sign' : 'signs'} detected',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                detections.isEmpty
                                    ? 'Try a clearer photo with the sign fully visible.'
                                    : 'Your results are ready to review or hear aloud.',
                                style: const TextStyle(color: Color(0xFFD0D9E8), height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (imagePath.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Your image', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colors.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined, size: 36),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Detected signs', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      if (detections.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            '${detections.length} found',
                            style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (detections.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.outline.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded, size: 42, color: colors.onSurfaceVariant),
                          const SizedBox(height: 12),
                          const Text('Nothing detected in this image', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            'Move closer, improve the lighting, and try another photo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                          ),
                        ],
                      ),
                    )
                  else
                    ...detections.map(
                      (detection) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SignCard(
                          detection: detection,
                          spokenText: signModel.getSpokenDescription(detection),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}