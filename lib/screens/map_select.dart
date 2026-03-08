import 'dart:math';
import 'package:flutter/material.dart';
import 'game_screen.dart';

class MapSelectScreen extends StatelessWidget {
  const MapSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1a0a00), Color(0xFF0a0a0a)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Header
                Text(
                  'SELECT MAP',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey[300],
                    letterSpacing: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 2,
                  color: Colors.red[800],
                ),
                const SizedBox(height: 30),
                // Maps
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Map 1 - Nacht Der Untoten (Playable)
                        _MapCard(
                          name: 'NACHT DER\nUNTOTEN',
                          subtitle: 'The Original Bunker',
                          locked: false,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) =>
                                    const GameScreen(mapKey: 'nacht_der_untoten'),
                                transitionsBuilder: (_, anim, __, child) {
                                  return FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  );
                                },
                                transitionDuration:
                                    const Duration(milliseconds: 800),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 30),
                        // Map 2 - Locked
                        _MapCard(
                          name: 'KINO DER\nTOTEN',
                          subtitle: 'Coming Soon',
                          locked: true,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'MAP LOCKED - Coming Soon',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                backgroundColor: Colors.red[900],
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Back button
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.grey),
                    label: Text(
                      'BACK',
                      style: TextStyle(
                        color: Colors.grey[500],
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool locked;
  final VoidCallback onTap;

  const _MapCard({
    required this.name,
    required this.subtitle,
    required this.locked,
    required this.onTap,
  });

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.locked
        ? Colors.grey[700]!
        : _hovering
            ? Colors.red[400]!
            : Colors.red[800]!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 220,
          height: 280,
          decoration: BoxDecoration(
            color: widget.locked
                ? Colors.grey[900]!.withAlpha(150)
                : _hovering
                    ? const Color(0xFF2a0a0a)
                    : const Color(0xFF1a0a0a),
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.locked
                ? []
                : [
                    BoxShadow(
                      color: Colors.red.withAlpha(_hovering ? 60 : 30),
                      blurRadius: _hovering ? 20 : 10,
                      spreadRadius: _hovering ? 4 : 2,
                    ),
                  ],
          ),
          child: Stack(
            children: [
              // Map preview (procedural)
              if (!widget.locked)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MapPreviewPainter(),
                  ),
                ),
              // Content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.locked)
                      Icon(
                        Icons.lock,
                        size: 48,
                        color: Colors.grey[600],
                      ),
                    if (widget.locked) const SizedBox(height: 12),
                    Text(
                      widget.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: widget.locked
                            ? Colors.grey[600]
                            : Colors.grey[200],
                        letterSpacing: 3,
                        height: 1.3,
                        shadows: widget.locked
                            ? []
                            : [
                                Shadow(
                                  color: Colors.red.withAlpha(100),
                                  blurRadius: 8,
                                ),
                              ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.locked
                            ? Colors.grey[700]
                            : Colors.grey[500],
                        letterSpacing: 2,
                      ),
                    ),
                    if (!widget.locked) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red[800]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SELECT',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
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

class _MapPreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(123);
    final paint = Paint()..color = const Color(0x0AFFFFFF);

    // Draw a simplified map layout
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final w = rng.nextDouble() * 40 + 10;
      final h = rng.nextDouble() * 40 + 10;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
