import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.visibility_rounded, color: colors.primary),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SightToSound', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'AI SIGNBOARD READER',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF173A4A), Color(0xFF17233C)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF59D6C8).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.graphic_eq_rounded, size: 16, color: Color(0xFF59D6C8)),
                          SizedBox(width: 7),
                          Text(
                            'MADE FOR ACCESSIBILITY',
                            style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF8CE9DE)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'See a sign.\nHear what matters.',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 34,
                        color: Colors.white,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Understand nearby signboards with spoken guidance and simple, accessible controls.',
                      style: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFFD0D9E8)),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Icon(Icons.record_voice_over_rounded, size: 18, color: colors.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Voice-first • Multilingual • Easy to use',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text('Choose how to begin', style: theme.textTheme.titleLarge),
              const SizedBox(height: 7),
              Text(
                'Use your camera or select a photo you already have.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              _ActionTile(
                icon: Icons.center_focus_strong_rounded,
                title: 'Live camera',
                subtitle: 'Explore signs around you in real time',
                accent: colors.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.add_photo_alternate_rounded,
                title: 'Choose a photo',
                subtitle: 'Read and analyze a sign from your gallery',
                accent: colors.secondary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GalleryScreen()),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outline.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.accessibility_new_rounded, color: colors.primary, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Designed to be accessible', style: TextStyle(fontWeight: FontWeight.w750)),
                          SizedBox(height: 4),
                          Text(
                            'Use clear on-screen actions whenever voice commands are not convenient.',
                            style: TextStyle(color: Color(0xFFB8C4D8), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, size: 27, color: accent),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w750)),
                    const SizedBox(height: 5),
                    Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}