import 'dart:math';
import 'package:flutter/material.dart';
import 'map_select.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _flickerController;
  late Animation<double> _pulseAnim;
  late Animation<double> _flickerAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat(reverse: true);
    _flickerAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      _flickerController,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background with zombie atmosphere
          CustomPaint(
            painter: _MenuBackgroundPainter(),
            size: Size.infinite,
          ),
          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title
                AnimatedBuilder(
                  animation: _flickerAnim,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _flickerAnim.value,
                      child: Column(
                        children: [
                          Text(
                            'UNDEAD',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: Colors.red[700],
                              letterSpacing: 12,
                              shadows: [
                                Shadow(
                                  color: Colors.red.withAlpha(150),
                                  blurRadius: 20,
                                ),
                                const Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                  offset: Offset(3, 3),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'SIEGE',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[300],
                              letterSpacing: 20,
                              shadows: [
                                Shadow(
                                  color: Colors.red.withAlpha(100),
                                  blurRadius: 15,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 60),
                // Play button
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnim.value,
                      child: _MenuButton(
                        text: 'PLAY',
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  const MapSelectScreen(),
                              transitionsBuilder: (_, anim, __, child) {
                                return FadeTransition(
                                  opacity: anim,
                                  child: child,
                                );
                              },
                              transitionDuration:
                                  const Duration(milliseconds: 500),
                            ),
                          );
                        },
                        color: Colors.red[800]!,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _MenuButton(
                  text: 'CONTROLS',
                  onTap: () => _showControls(context),
                  color: Colors.grey[800]!,
                ),
              ],
            ),
          ),
          // Version text
          Positioned(
            bottom: 16,
            right: 16,
            child: Text(
              'v1.0.0',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showControls(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'CONTROLS',
          style: TextStyle(
            color: Colors.red[400],
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _controlRow('MOVE', 'WASD / Arrow Keys'),
            _controlRow('AIM', 'Mouse / Touch Drag'),
            _controlRow('SHOOT', 'Left Click / Shoot Btn'),
            _controlRow('RELOAD', 'R / Reload Btn'),
            _controlRow('KNIFE', 'V / Knife Btn'),
            _controlRow('SWITCH WEAPON', 'Q / Swap Btn'),
            _controlRow('INTERACT', 'F / Interact Btn'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _controlRow(String action, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(action,
              style: TextStyle(
                  color: Colors.grey[300], fontWeight: FontWeight.bold)),
          const SizedBox(width: 20),
          Text(key, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final Color color;

  const _MenuButton({
    required this.text,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          decoration: BoxDecoration(
            color: color.withAlpha(200),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(80),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dark gradient background
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1a0000),
        const Color(0xFF0a0a0a),
        const Color(0xFF0d0000),
      ],
    );
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // Draw some atmospheric scratches/blood spatters
    final rng = Random(42);
    final scratchPaint = Paint()
      ..color = const Color(0x15FF0000)
      ..strokeWidth = 2;

    for (int i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final len = rng.nextDouble() * 100 + 20;
      final angle = rng.nextDouble() * pi;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + cos(angle) * len, y + sin(angle) * len),
        scratchPaint,
      );
    }

    // Vignette effect
    final vignette = RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        Colors.transparent,
        Colors.black.withAlpha(180),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = vignette.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
