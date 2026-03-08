import 'dart:math';
import 'dart:ui' hide TextStyle;
import 'package:flutter/painting.dart';
import '../models/game_state.dart';
import '../models/map_data.dart';
import '../models/weapon_data.dart';

class Raycaster {
  static const double fov = 66 * pi / 180; // 66 degrees in radians
  static const double maxDist = 30.0; // max render distance in tiles
  static const int stripWidth = 2; // render every 2 pixels for performance

  late List<double> _zBuffer;
  int _screenW = 0;

  void render(
    Canvas canvas,
    Size screenSize,
    PlayerState player,
    BuiltMap map,
    Set<String> openedDoors,
    List<ZombieState> zombies,
    List<SpawnPoint> spawns,
    List<WallWeaponState> wallWeapons,
    List<PerkState> perks,
    MysteryBoxState? mysteryBox,
    PackAPunchState? packAPunch,
    GameWeapon currentWeapon,
    double weaponBob,
    double muzzleFlashTimer,
    double shakeX,
    double shakeY,
  ) {
    _screenW = screenSize.width.toInt();
    _zBuffer = List.filled(_screenW, maxDist * tileSize);

    final px = player.x + player.width / 2;
    final py = player.y + player.height / 2;
    final pAngle = player.angle;

    canvas.save();
    canvas.translate(shakeX, shakeY);

    _renderCeilingFloor(canvas, screenSize);
    _renderWalls(canvas, screenSize, px, py, pAngle, map, openedDoors);
    _renderSprites(canvas, screenSize, px, py, pAngle, zombies, spawns,
        wallWeapons, perks, mysteryBox, packAPunch, openedDoors, map);
    _renderWeaponView(canvas, screenSize, currentWeapon, weaponBob, muzzleFlashTimer);

    canvas.restore();
  }

  void _renderCeilingFloor(Canvas canvas, Size size) {
    // Ceiling - dark grey gradient
    final ceilPaint = Paint();
    for (int y = 0; y < size.height ~/ 2; y++) {
      final t = y / (size.height / 2);
      final shade = (20 + t * 30).round().clamp(0, 255);
      ceilPaint.color = Color.fromARGB(255, shade ~/ 2, shade ~/ 2, shade);
      canvas.drawLine(
        Offset(0, y.toDouble()),
        Offset(size.width, y.toDouble()),
        ceilPaint,
      );
    }

    // Floor - dark brown/green gradient
    final floorPaint = Paint();
    for (int y = size.height ~/ 2; y < size.height.toInt(); y++) {
      final t = (y - size.height / 2) / (size.height / 2);
      final shade = (20 + t * 40).round().clamp(0, 255);
      floorPaint.color = Color.fromARGB(255, shade, shade ~/ 2 + 5, shade ~/ 3);
      canvas.drawLine(
        Offset(0, y.toDouble()),
        Offset(size.width, y.toDouble()),
        floorPaint,
      );
    }
  }

  void _renderWalls(Canvas canvas, Size size, double px, double py,
      double pAngle, BuiltMap map, Set<String> openedDoors) {
    final halfFov = fov / 2;
    final numRays = _screenW ~/ stripWidth;

    for (int i = 0; i < numRays; i++) {
      final screenX = i * stripWidth;
      final rayAngle = pAngle - halfFov + (i / numRays) * fov;

      final result = _castRay(px, py, rayAngle, map, openedDoors);
      if (result == null) continue;

      // Fix fisheye with cos correction
      final correctedDist = result.distance * cos(rayAngle - pAngle);
      _zBuffer[screenX] = correctedDist;
      // Fill all columns this strip covers
      for (int s = 1; s < stripWidth && screenX + s < _screenW; s++) {
        _zBuffer[screenX + s] = correctedDist;
      }

      if (correctedDist <= 0) continue;

      final wallHeight = (tileSize * size.height / correctedDist).clamp(0.0, size.height * 3);
      final wallTop = (size.height - wallHeight) / 2;

      // Wall color based on type and side
      Color wallColor;
      switch (result.cellType) {
        case 1: // Wall
          wallColor = result.side == 0
              ? const Color(0xFF5A5A5A)
              : const Color(0xFF4A4A4A);
          break;
        case 2: // Door (closed)
          wallColor = result.side == 0
              ? const Color(0xFFB8860B)
              : const Color(0xFF8B6914);
          break;
        case 3: // Window/barricade
          wallColor = result.side == 0
              ? const Color(0xFF3A3A5A)
              : const Color(0xFF2A2A4A);
          break;
        default:
          wallColor = const Color(0xFF4A4A4A);
      }

      // Distance-based darkening (fog)
      final fogFactor = (1 - correctedDist / (maxDist * tileSize)).clamp(0.2, 1.0);
      final r = (wallColor.red * fogFactor).round();
      final g = (wallColor.green * fogFactor).round();
      final b = (wallColor.blue * fogFactor).round();
      wallColor = Color.fromARGB(255, r, g, b);

      canvas.drawRect(
        Rect.fromLTWH(screenX.toDouble(), wallTop, stripWidth.toDouble(), wallHeight),
        Paint()..color = wallColor,
      );

      // Draw boards on windows
      if (result.cellType == 3) {
        final boardColor = Color.fromARGB(
          255,
          (100 * fogFactor).round(),
          (70 * fogFactor).round(),
          (33 * fogFactor).round(),
        );
        final boardPaint = Paint()
          ..color = boardColor
          ..strokeWidth = max(1, (3 * tileSize / correctedDist));
        for (int b = 0; b < 3; b++) {
          final boardY = wallTop + wallHeight * (0.2 + b * 0.3);
          canvas.drawLine(
            Offset(screenX.toDouble(), boardY),
            Offset(screenX.toDouble() + stripWidth, boardY),
            boardPaint,
          );
        }
      }

      // Door frame detail
      if (result.cellType == 2) {
        final frameColor = Color.fromARGB(
          255,
          (218 * fogFactor).round(),
          (165 * fogFactor).round(),
          (32 * fogFactor).round(),
        );
        canvas.drawRect(
          Rect.fromLTWH(screenX.toDouble(), wallTop, stripWidth.toDouble(), 2),
          Paint()..color = frameColor,
        );
        canvas.drawRect(
          Rect.fromLTWH(screenX.toDouble(), wallTop + wallHeight - 2,
              stripWidth.toDouble(), 2),
          Paint()..color = frameColor,
        );
      }
    }
  }

  _RayResult? _castRay(double px, double py, double angle,
      BuiltMap map, Set<String> openedDoors) {
    final dirX = cos(angle);
    final dirY = sin(angle);

    // Current grid position
    int mapX = (px / tileSize).floor();
    int mapY = (py / tileSize).floor();

    // Length of ray from one x/y side to next
    final deltaDistX = dirX == 0 ? 1e30 : (1 / dirX).abs() * tileSize;
    final deltaDistY = dirY == 0 ? 1e30 : (1 / dirY).abs() * tileSize;

    int stepX, stepY;
    double sideDistX, sideDistY;

    if (dirX < 0) {
      stepX = -1;
      sideDistX = (px / tileSize - mapX) * deltaDistX;
    } else {
      stepX = 1;
      sideDistX = (mapX + 1.0 - px / tileSize) * deltaDistX;
    }
    if (dirY < 0) {
      stepY = -1;
      sideDistY = (py / tileSize - mapY) * deltaDistY;
    } else {
      stepY = 1;
      sideDistY = (mapY + 1.0 - py / tileSize) * deltaDistY;
    }

    // DDA
    int side = 0;
    for (int i = 0; i < (maxDist * 2).round(); i++) {
      if (sideDistX < sideDistY) {
        sideDistX += deltaDistX;
        mapX += stepX;
        side = 0;
      } else {
        sideDistY += deltaDistY;
        mapY += stepY;
        side = 1;
      }

      if (mapX < 0 || mapX >= map.info.width || mapY < 0 || mapY >= map.info.height) {
        break;
      }

      final cell = map.grid[mapY][mapX];
      if (cell == 1) {
        // Solid wall
        final dist = side == 0
            ? sideDistX - deltaDistX
            : sideDistY - deltaDistY;
        return _RayResult(distance: dist, side: side, cellType: 1,
            mapX: mapX, mapY: mapY);
      } else if (cell == 2) {
        // Check if door is open
        final isDoorOpen = map.doors
            .where((d) => (d.x / tileSize).floor() == mapX &&
                          (d.y / tileSize).floor() == mapY)
            .any((d) => d.open);
        if (!isDoorOpen) {
          final dist = side == 0
              ? sideDistX - deltaDistX
              : sideDistY - deltaDistY;
          return _RayResult(distance: dist, side: side, cellType: 2,
              mapX: mapX, mapY: mapY);
        }
      } else if (cell == 3) {
        // Window/barricade - always solid for rays
        final dist = side == 0
            ? sideDistX - deltaDistX
            : sideDistY - deltaDistY;
        return _RayResult(distance: dist, side: side, cellType: 3,
            mapX: mapX, mapY: mapY);
      }
    }
    return null;
  }

  void _renderSprites(
    Canvas canvas,
    Size size,
    double px,
    double py,
    double pAngle,
    List<ZombieState> zombies,
    List<SpawnPoint> spawns,
    List<WallWeaponState> wallWeapons,
    List<PerkState> perks,
    MysteryBoxState? mysteryBox,
    PackAPunchState? packAPunch,
    Set<String> openedDoors,
    BuiltMap map,
  ) {
    final sprites = <_SpriteInfo>[];
    final halfH = size.height / 2;

    // Zombies
    for (final z in zombies) {
      if (!z.alive && z.deathTimer <= 0) continue;
      final sx = z.x + z.width / 2;
      final sy = z.y + z.height / 2;
      final dist = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));
      if (dist < 5) continue;

      Color color;
      if (!z.alive) {
        color = Color.fromARGB((z.deathTimer.clamp(0, 1) * 255).round(), 58, 26, 10);
      } else {
        switch (z.type) {
          case 'brute': color = const Color(0xFF5A2D0C); break;
          case 'runner': color = const Color(0xFF4A5A2D); break;
          default: color = const Color(0xFF3D5A3D);
        }
      }

      sprites.add(_SpriteInfo(
        x: sx, y: sy, dist: dist,
        color: color, type: 'zombie',
        data: z,
        sizeMultiplier: z.type == 'brute' ? 1.3 : 1.0,
      ));
    }

    // Perk machines
    for (final perk in perks) {
      if (perk.requiresDoor != null && !openedDoors.contains(perk.requiresDoor)) continue;
      final sx = perk.x + 15;
      final sy = perk.y + 18;
      final dist = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));

      final perkColors = {
        'juggernog': const Color(0xFFFF4444),
        'speedcola': const Color(0xFF44FF44),
        'quickrevive': const Color(0xFF4444FF),
        'staminup': const Color(0xFFFFFF44),
        'doubletap': const Color(0xFFFF8800),
      };
      sprites.add(_SpriteInfo(
        x: sx, y: sy, dist: dist,
        color: perkColors[perk.perk] ?? const Color(0xFFFFFFFF),
        type: 'perk', sizeMultiplier: 1.0,
      ));
    }

    // Wall weapons
    for (final ww in wallWeapons) {
      if (ww.requiresDoor != null && !openedDoors.contains(ww.requiresDoor)) continue;
      final sx = ww.x + 30;
      final sy = ww.y + 15;
      final dist = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));
      final weaponDef = WeaponData.weapons[ww.weapon];
      sprites.add(_SpriteInfo(
        x: sx, y: sy, dist: dist,
        color: Color(weaponDef?.color ?? 0xFFFFFFFF),
        type: 'wallweapon', sizeMultiplier: 0.6,
      ));
    }

    // Mystery box
    if (mysteryBox != null) {
      if (mysteryBox.requiresDoor == null || openedDoors.contains(mysteryBox.requiresDoor)) {
        final sx = mysteryBox.x + 20;
        final sy = mysteryBox.y + 15;
        final dist = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));
        sprites.add(_SpriteInfo(
          x: sx, y: sy, dist: dist,
          color: const Color(0xFF0088FF),
          type: 'mysterybox', sizeMultiplier: 1.0,
        ));
      }
    }

    // Pack-a-Punch
    if (packAPunch != null) {
      if (packAPunch.requiresDoor == null || openedDoors.contains(packAPunch.requiresDoor)) {
        final sx = packAPunch.x + 20;
        final sy = packAPunch.y + 18;
        final dist = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));
        sprites.add(_SpriteInfo(
          x: sx, y: sy, dist: dist,
          color: const Color(0xFFBB00FF),
          type: 'packapunch', sizeMultiplier: 1.0,
        ));
      }
    }

    // Sort back-to-front
    sprites.sort((a, b) => b.dist.compareTo(a.dist));

    // Render each sprite
    for (final sprite in sprites) {
      final dx = sprite.x - px;
      final dy = sprite.y - py;

      // Calculate angle relative to player
      final spriteAngle = atan2(dy, dx) - pAngle;
      // Normalize to -pi..pi
      double normAngle = spriteAngle;
      while (normAngle > pi) normAngle -= 2 * pi;
      while (normAngle < -pi) normAngle += 2 * pi;

      // Check if within FOV (with some margin)
      if (normAngle.abs() > fov / 2 + 0.2) continue;

      // Screen X position
      final screenX = (size.width / 2) * (1 + normAngle / (fov / 2));

      // Sprite size based on distance
      final spriteHeight = (tileSize * size.height / sprite.dist * sprite.sizeMultiplier)
          .clamp(0.0, size.height * 2);
      final spriteWidth = spriteHeight * 0.6;
      final spriteTop = halfH - spriteHeight / 2;
      final spriteLeft = screenX - spriteWidth / 2;

      // Distance fog
      final fogFactor = (1 - sprite.dist / (maxDist * tileSize)).clamp(0.1, 1.0);

      // Z-buffer clipping (check center and edges)
      final centerCol = screenX.round().clamp(0, _screenW - 1);
      if (sprite.dist > _zBuffer[centerCol]) continue;

      final fogR = (sprite.color.red * fogFactor).round();
      final fogG = (sprite.color.green * fogFactor).round();
      final fogB = (sprite.color.blue * fogFactor).round();
      final fogAlpha = sprite.color.alpha;
      final fogColor = Color.fromARGB(fogAlpha, fogR, fogG, fogB);

      if (sprite.type == 'zombie') {
        _drawZombieSprite(canvas, spriteLeft, spriteTop, spriteWidth,
            spriteHeight, fogColor, sprite, fogFactor);
      } else {
        // Generic colored rectangle for items
        _drawItemSprite(canvas, spriteLeft, spriteTop, spriteWidth,
            spriteHeight, fogColor, sprite.type, fogFactor);
      }
    }
  }

  void _drawZombieSprite(Canvas canvas, double left, double top, double width,
      double height, Color color, _SpriteInfo sprite, double fog) {
    final z = sprite.data as ZombieState?;
    if (z == null) return;

    // Body
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.15, top + height * 0.1,
          width * 0.7, height * 0.8),
      Paint()..color = color,
    );

    // Arms
    final armWidth = width * 0.2;
    final armHeight = height * 0.15;
    final armY = top + height * 0.3;
    // Left arm
    canvas.drawRect(
      Rect.fromLTWH(left - armWidth * 0.5, armY, armWidth, armHeight),
      Paint()..color = color,
    );
    // Right arm
    canvas.drawRect(
      Rect.fromLTWH(left + width - armWidth * 0.5, armY, armWidth, armHeight),
      Paint()..color = color,
    );

    // Eyes
    final eyeColor = z.type == 'runner'
        ? Color.fromARGB(255, (255 * fog).round(), (255 * fog).round(), 0)
        : Color.fromARGB(255, (255 * fog).round(), 0, 0);
    final eyeSize = max(2.0, width * 0.12);
    final eyeY = top + height * 0.2;
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.3, eyeY, eyeSize, eyeSize),
      Paint()..color = eyeColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.55, eyeY, eyeSize, eyeSize),
      Paint()..color = eyeColor,
    );

    // Health bar (if damaged)
    if (z.alive && z.health < z.maxHealth) {
      final barW = width * 0.8;
      final barH = max(2.0, height * 0.03);
      final barLeft = left + (width - barW) / 2;
      final barTop = top - barH - 2;
      canvas.drawRect(
        Rect.fromLTWH(barLeft, barTop, barW, barH),
        Paint()..color = const Color(0xFF333333),
      );
      final ratio = z.health / z.maxHealth;
      canvas.drawRect(
        Rect.fromLTWH(barLeft, barTop, barW * ratio, barH),
        Paint()..color = ratio > 0.5 ? const Color(0xFFFF0000) : const Color(0xFFFF4500),
      );
    }
  }

  void _drawItemSprite(Canvas canvas, double left, double top, double width,
      double height, Color color, String type, double fog) {
    // Main body
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.1, top + height * 0.1,
          width * 0.8, height * 0.8),
      Paint()..color = color,
    );

    // Glow effect for special items
    if (type == 'mysterybox' || type == 'packapunch' || type == 'perk') {
      final glowAlpha = (sin(DateTime.now().millisecondsSinceEpoch * 0.004) * 30 + 50)
          .round().clamp(0, 255);
      canvas.drawRect(
        Rect.fromLTWH(left + width * 0.05, top + height * 0.05,
            width * 0.9, height * 0.9),
        Paint()
          ..color = color.withAlpha(glowAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _renderWeaponView(Canvas canvas, Size size, GameWeapon weapon,
      double weaponBob, double muzzleFlashTimer) {
    final weaponColor = Color(weapon.color);
    final centerX = size.width / 2;
    final bottomY = size.height;

    // Weapon bob from walking
    final bobX = sin(weaponBob) * 8;
    final bobY = cos(weaponBob * 2) * 4;

    // Gun body
    final gunW = 80.0;
    final gunH = 50.0;
    final gunX = centerX - gunW / 2 + bobX + 30;
    final gunY = bottomY - gunH - 20 + bobY;

    // Gun body (main rectangle)
    canvas.drawRect(
      Rect.fromLTWH(gunX, gunY, gunW, gunH),
      Paint()..color = weaponColor.withAlpha(220),
    );

    // Gun barrel
    canvas.drawRect(
      Rect.fromLTWH(gunX + gunW * 0.3, gunY - 25, gunW * 0.15, 30),
      Paint()..color = weaponColor,
    );

    // Handle
    canvas.drawRect(
      Rect.fromLTWH(gunX + gunW * 0.35, gunY + gunH, gunW * 0.3, 25),
      Paint()..color = const Color(0xFF333333),
    );

    // Pack-a-Punch glow
    if (weapon.isPaP) {
      canvas.drawRect(
        Rect.fromLTWH(gunX - 3, gunY - 28, gunW + 6, gunH + 58),
        Paint()
          ..color = weaponColor.withAlpha(80)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
      );
    }

    // Muzzle flash
    if (muzzleFlashTimer > 0) {
      final flashSize = 30.0 + muzzleFlashTimer * 50;
      final flashX = gunX + gunW * 0.35;
      final flashY = gunY - 25 - flashSize / 2;
      canvas.drawRect(
        Rect.fromLTWH(flashX, flashY, flashSize * 0.5, flashSize),
        Paint()..color = Color.fromARGB(
          (muzzleFlashTimer * 3 * 255).round().clamp(0, 255),
          255, 255, 100,
        ),
      );
    }

    // Reloading indicator
    if (weapon.reloading) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'RELOADING...',
          style: TextStyle(
            color: Color(0xFFFFFF00),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(
        centerX - textPainter.width / 2,
        gunY - 45,
      ));
    }
  }
}

class _RayResult {
  final double distance;
  final int side; // 0 = vertical wall hit (E/W), 1 = horizontal wall hit (N/S)
  final int cellType;
  final int mapX, mapY;

  _RayResult({
    required this.distance,
    required this.side,
    required this.cellType,
    required this.mapX,
    required this.mapY,
  });
}

class _SpriteInfo {
  final double x, y, dist;
  final Color color;
  final String type;
  final Object? data;
  final double sizeMultiplier;

  _SpriteInfo({
    required this.x,
    required this.y,
    required this.dist,
    required this.color,
    required this.type,
    this.data,
    this.sizeMultiplier = 1.0,
  });
}
