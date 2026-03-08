import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../components/zombie_game.dart';

class GameScreen extends StatefulWidget {
  final String mapKey;

  const GameScreen({super.key, required this.mapKey});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ZombieGame _game;

  @override
  void initState() {
    super.initState();
    _game = ZombieGame(
      mapKey: widget.mapKey,
      onGameOver: _showGameOver,
    );
  }

  void _showGameOver(int round, int kills, int points) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GameOverDialog(
        round: round,
        kills: kills,
        points: points,
        onRestart: () {
          Navigator.pop(ctx);
          setState(() {
            _game = ZombieGame(
              mapKey: widget.mapKey,
              onGameOver: _showGameOver,
            );
          });
        },
        onQuit: () {
          Navigator.pop(ctx);
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Desktop: mouse position for aiming, click to fire
          Listener(
            onPointerHover: (event) {
              _game.updateMousePosition(
                event.localPosition.dx,
                event.localPosition.dy,
              );
            },
            onPointerMove: (event) {
              _game.updateMousePosition(
                event.localPosition.dx,
                event.localPosition.dy,
              );
            },
            onPointerDown: (event) {
              if (event.buttons & 0x01 != 0) {
                _game.setFiring(true);
              }
              if (event.buttons & 0x02 != 0) {
                _game.onKnife();
              }
            },
            onPointerUp: (event) {
              _game.setFiring(false);
            },
            onPointerCancel: (event) {
              _game.setFiring(false);
            },
            child: GameWidget(game: _game),
          ),
          // Mobile controls overlay
          _MobileControls(game: _game),
        ],
      ),
    );
  }
}

class _GameOverDialog extends StatelessWidget {
  final int round;
  final int kills;
  final int points;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  const _GameOverDialog({
    required this.round,
    required this.kills,
    required this.points,
    required this.onRestart,
    required this.onQuit,
  });

  String _getCompliment() {
    if (round >= 30) return 'LEGENDARY SURVIVOR!';
    if (round >= 20) return 'ZOMBIE SLAYER!';
    if (round >= 15) return 'UNDEAD NIGHTMARE!';
    if (round >= 10) return 'IMPRESSIVE RUN!';
    if (round >= 7) return 'NOT BAD, SOLDIER.';
    if (round >= 5) return 'DECENT EFFORT.';
    if (round >= 3) return 'KEEP TRYING.';
    return 'BETTER LUCK NEXT TIME.';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: const Color(0xEE1a0a0a),
          border: Border.all(color: Colors.red[800]!, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withAlpha(60),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GAME OVER',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.red[600],
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getCompliment(),
              style: TextStyle(
                fontSize: 16,
                color: Colors.amber[400],
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 24),
            _statRow('ROUND', '$round'),
            _statRow('KILLS', '$kills'),
            _statRow('POINTS', '$points'),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _dialogButton('RESTART', Colors.red[800]!, onRestart),
                _dialogButton('QUIT', Colors.grey[800]!, onQuit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey[500],
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20)),
        ],
      ),
    );
  }

  Widget _dialogButton(String text, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(200),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}

class _MobileControls extends StatelessWidget {
  final ZombieGame game;

  const _MobileControls({required this.game});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Right half of screen = aim area (touch to aim)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: constraints.maxWidth / 2,
              child: _AimArea(game: game),
            ),

            // Left side - Movement joystick
            Positioned(
              left: 20,
              bottom: 20,
              child: _Joystick(
                size: 120,
                onMove: (dx, dy) {
                  game.setMobileMove(dx, dy);
                },
              ),
            ),

            // Top-right - FIRE button (index finger accessible)
            Positioned(
              right: 16,
              top: 16,
              child: _IconActionButton(
                icon: Icons.my_location,
                size: 64,
                color: Colors.red[700]!,
                onTapDown: () => game.setMobileFiring(true),
                onTapUp: () => game.setMobileFiring(false),
              ),
            ),

            // Left side - action buttons (vertical stack above joystick)
            Positioned(
              left: 160,
              bottom: 28,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reload
                  _IconActionButton(
                    icon: Icons.refresh,
                    size: 48,
                    color: Colors.blue[700]!,
                    onTap: () => game.onReloadPressed(),
                  ),
                  const SizedBox(width: 8),
                  // Switch weapon
                  _IconActionButton(
                    icon: Icons.swap_horiz,
                    size: 48,
                    color: Colors.purple[700]!,
                    onTap: () => game.onSwitchWeapon(),
                  ),
                  const SizedBox(width: 8),
                  // Interact
                  _IconActionButton(
                    icon: Icons.touch_app,
                    size: 48,
                    color: Colors.green[700]!,
                    onTap: () => game.onInteract(),
                  ),
                  const SizedBox(width: 8),
                  // Knife
                  _IconActionButton(
                    icon: Icons.content_cut,
                    size: 48,
                    color: Colors.orange[700]!,
                    onTap: () => game.onKnife(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Invisible area on right half of screen for touch-to-aim
class _AimArea extends StatelessWidget {
  final ZombieGame game;

  const _AimArea({required this.game});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) {
        // Send the global touch position as aiming target
        game.updateMousePosition(
          details.globalPosition.dx,
          details.globalPosition.dy,
        );
      },
      onPanStart: (details) {
        game.updateMousePosition(
          details.globalPosition.dx,
          details.globalPosition.dy,
        );
      },
    );
  }
}

class _Joystick extends StatefulWidget {
  final double size;
  final void Function(double dx, double dy) onMove;

  const _Joystick({required this.size, required this.onMove});

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  double _dx = 0, _dy = 0;

  void _updatePosition(Offset localPos) {
    final center = widget.size / 2;
    final dx = (localPos.dx - center) / center;
    final dy = (localPos.dy - center) / center;
    final dist = (dx * dx + dy * dy);
    if (dist > 1) {
      final scale = 1 / (dist > 0 ? dist : 1);
      _dx = dx * scale;
      _dy = dy * scale;
    } else {
      _dx = dx;
      _dy = dy;
    }
    widget.onMove(_dx, _dy);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _updatePosition(d.localPosition),
      onPanUpdate: (d) => _updatePosition(d.localPosition),
      onPanEnd: (_) {
        _dx = 0;
        _dy = 0;
        widget.onMove(0, 0);
        setState(() {});
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(20),
          border: Border.all(color: Colors.white.withAlpha(40), width: 2),
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(
              _dx * widget.size * 0.3,
              _dy * widget.size * 0.3,
            ),
            child: Container(
              width: widget.size * 0.4,
              height: widget.size * 0.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(60),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;

  const _IconActionButton({
    required this.icon,
    required this.size,
    required this.color,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onTapDown: onTapDown != null ? (_) => onTapDown!() : null,
      onTapUp: onTapUp != null ? (_) => onTapUp!() : null,
      onTapCancel: onTapUp,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: size > 56 ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: size <= 56 ? BorderRadius.circular(12) : null,
          color: color.withAlpha(120),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}
