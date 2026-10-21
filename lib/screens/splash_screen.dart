import 'dart:async';
import 'package:flutter/material.dart';

import 'live_camera_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _detailsFade;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.82, curve: Curves.easeOut),
    );

    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.82, curve: Curves.easeOutBack),
      ),
    );

    _detailsFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();

    _navigationTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LiveCameraScreen(),
          transitionDuration: const Duration(milliseconds: 550),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1220),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF122B3A),
              Color(0xFF0A1220),
              Color(0xFF10172C),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -100,
              right: -100,
              child: _GlowOrb(size: 290, color: Color(0x2459D6C8)),
            ),
            const Positioned(
              bottom: -125,
              left: -110,
              child: _GlowOrb(size: 330, color: Color(0x1E829BFF)),
            ),
            Positioned(
              top: size.height * 0.19,
              left: -70,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.045),
                    width: 1.2,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          26,
                          compact ? 20 : 30,
                          26,
                          compact ? 18 : 28,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeTransition(
                              opacity: _fade,
                              child: ScaleTransition(
                                scale: _scale,
                                child: _LogoEmblem(size: compact ? 158 : 188),
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 32),
                            FadeTransition(
                              opacity: _detailsFade,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF59D6C8).withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: const Color(0xFF59D6C8).withValues(alpha: 0.23),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 15,
                                          color: Color(0xFF8CE9DE),
                                        ),
                                        SizedBox(width: 7),
                                        Text(
                                          'AI-POWERED ACCESSIBILITY',
                                          style: TextStyle(
                                            color: Color(0xFF9DECE3),
                                            fontSize: 10,
                                            letterSpacing: 1.45,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  const Text(
                                    'SightToSound',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFF5F8FF),
                                      fontSize: 34,
                                      height: 1.08,
                                      letterSpacing: -0.9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'From sight to sound.\nFrom sound to freedom.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFC7D3E5),
                                      fontSize: 16,
                                      height: 1.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 26 : 36),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _FeaturePill(
                                        icon: Icons.hearing_rounded,
                                        label: 'Listen',
                                      ),
                                      SizedBox(width: 9),
                                      _FeaturePill(
                                        icon: Icons.translate_rounded,
                                        label: 'Understand',
                                      ),
                                      SizedBox(width: 9),
                                      _FeaturePill(
                                        icon: Icons.accessibility_new_rounded,
                                        label: 'Explore',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: compact ? 28 : 42),
                            FadeTransition(
                              opacity: _detailsFade,
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.6,
                                      color: const Color(0xFF59D6C8),
                                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                                    ),
                                  ),
                                  const SizedBox(height: 13),
                                  const Text(
                                    'Getting things ready for you',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFAAB9CF),
                                      fontSize: 12,
                                      letterSpacing: 0.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Container(
                                    width: 42,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF59D6C8).withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(20),
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoEmblem extends StatelessWidget {
  const _LogoEmblem({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF59D6C8).withValues(alpha: 0.16),
                width: 1.2,
              ),
            ),
          ),
          Container(
            width: size * 0.88,
            height: size * 0.88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF59D6C8).withValues(alpha: 0.055),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Container(
            width: size * 0.72,
            height: size * 0.72,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF15283A),
              border: Border.all(
                color: const Color(0xFF7FE4D8).withValues(alpha: 0.72),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3359D6C8),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF173A4A),
                  child: Icon(
                    Icons.visibility_rounded,
                    size: 66,
                    color: Color(0xFF7FE4D8),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: size * 0.12,
            top: size * 0.18,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF8CE9DE),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0A1220), width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF7FE4D8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD0D9E8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
