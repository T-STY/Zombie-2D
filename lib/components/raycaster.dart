import 'dart:math';
import 'dart:ui' hide TextStyle;
import 'package:flutter/painting.dart';
import '../models/game_state.dart';
import '../models/map_data.dart';
import '../models/weapon_data.dart';

class Raycaster {
  static const double fov = 66 * pi / 180;
  static const double maxDist = 30.0;
  static const int stripWidth = 2;

  late List<double> _zBuffer;
  int _screenW = 0;
  double _time = 0;

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
    _time += 0.016; // approximate frame time

    final px = player.x + player.width / 2;
    final py = player.y + player.height / 2;
    final pAngle = player.angle;

    canvas.save();
    canvas.translate(shakeX, shakeY);

    _renderCeilingFloor(canvas, screenSize, pAngle);
    _renderWalls(canvas, screenSize, px, py, pAngle, map, openedDoors, spawns);
    _renderSprites(canvas, screenSize, px, py, pAngle, zombies, spawns,
        wallWeapons, perks, mysteryBox, packAPunch, openedDoors, map);
    _renderWeaponView(canvas, screenSize, currentWeapon, weaponBob, muzzleFlashTimer, player);

    canvas.restore();
  }

  void _renderCeilingFloor(Canvas canvas, Size size, double pAngle) {
    final halfH = size.height / 2;
    final w = size.width;

    // Ceiling - dark atmospheric gradient (just 2 large rects)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, halfH * 0.5),
      Paint()..color = const Color(0xFF080810),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, halfH * 0.5, w, halfH * 0.5),
      Paint()..color = const Color(0xFF0E1018),
    );

    // Floor - dark concrete with subtle gradient (3 bands)
    final floorBandH = halfH / 3;
    canvas.drawRect(
      Rect.fromLTWH(0, halfH, w, floorBandH),
      Paint()..color = const Color(0xFF1A1A18),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, halfH + floorBandH, w, floorBandH),
      Paint()..color = const Color(0xFF1E1D19),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, halfH + floorBandH * 2, w, floorBandH),
      Paint()..color = const Color(0xFF22211B),
    );

    // Fog at horizon line for atmosphere
    canvas.drawRect(
      Rect.fromLTWH(0, halfH - 6, w, 12),
      Paint()..color = const Color(0x22181820),
    );
  }

  void _renderWalls(Canvas canvas, Size size, double px, double py,
      double pAngle, BuiltMap map, Set<String> openedDoors, List<SpawnPoint> spawns) {
    final halfFov = fov / 2;
    final numRays = _screenW ~/ stripWidth;
    final halfH = size.height / 2;

    for (int i = 0; i < numRays; i++) {
      final screenX = i * stripWidth;
      final rayAngle = pAngle - halfFov + (i / numRays) * fov;

      final result = _castRay(px, py, rayAngle, map, openedDoors);
      if (result == null) continue;

      final correctedDist = result.distance * cos(rayAngle - pAngle);
      _zBuffer[screenX] = correctedDist;
      for (int s = 1; s < stripWidth && screenX + s < _screenW; s++) {
        _zBuffer[screenX + s] = correctedDist;
      }

      if (correctedDist <= 0) continue;

      final wallHeight = (tileSize * size.height / correctedDist).clamp(0.0, size.height * 3);
      final wallTop = halfH - wallHeight / 2;

      // Distance fog factor (exponential for more realism)
      final normalizedDist = correctedDist / (maxDist * tileSize);
      final fogFactor = exp(-normalizedDist * 3.0).clamp(0.08, 1.0);

      // Calculate texture coordinate for brick pattern
      final wallU = result.wallU;

      // Base wall colors with more variation
      _drawWallStrip(canvas, screenX.toDouble(), wallTop, wallHeight,
          result, fogFactor, wallU, spawns, size);
    }
  }

  void _drawWallStrip(Canvas canvas, double x, double top, double height,
      _RayResult result, double fog, double? wallU, List<SpawnPoint> spawns, Size screenSize) {

    // Base colors per wall type
    int baseR, baseG, baseB;
    switch (result.cellType) {
      case 1: // Concrete wall
        baseR = result.side == 0 ? 95 : 75;
        baseG = result.side == 0 ? 90 : 72;
        baseB = result.side == 0 ? 82 : 65;
        break;
      case 2: // Door (closed)
        baseR = result.side == 0 ? 140 : 115;
        baseG = result.side == 0 ? 85 : 70;
        baseB = result.side == 0 ? 25 : 20;
        break;
      case 3: // Window/barricade
        baseR = result.side == 0 ? 60 : 48;
        baseG = result.side == 0 ? 58 : 46;
        baseB = result.side == 0 ? 72 : 58;
        break;
      default:
        baseR = 70; baseG = 70; baseB = 65;
    }

    // Apply fog
    final r = (baseR * fog).round().clamp(0, 255);
    final g = (baseG * fog).round().clamp(0, 255);
    final b = (baseB * fog).round().clamp(0, 255);

    // Main wall strip
    canvas.drawRect(
      Rect.fromLTWH(x, top, stripWidth.toDouble(), height),
      Paint()..color = Color.fromARGB(255, r, g, b),
    );

    // Brick mortar lines (subtle horizontal lines for texture)
    if (result.cellType == 1 && height > 30) {
      final mortarColor = Color.fromARGB(40, 0, 0, 0);
      final mortarPaint = Paint()..color = mortarColor;
      final brickH = height / 8;
      for (int row = 1; row < 8; row++) {
        final ly = top + row * brickH;
        canvas.drawRect(
          Rect.fromLTWH(x, ly, stripWidth.toDouble(), 1),
          mortarPaint,
        );
      }

      // Vertical mortar (offset per row for brick pattern)
      final u = wallU ?? 0;
      if (u != 0) {
        final brickW = 0.25; // fraction of tile
        final uMod = u % brickW;
        if (uMod < 0.02 || uMod > brickW - 0.02) {
          canvas.drawRect(
            Rect.fromLTWH(x, top, stripWidth.toDouble(), height),
            Paint()..color = Color.fromARGB(25, 0, 0, 0),
          );
        }
      }
    }

    // Edge highlight at top of wall for depth
    if (height > 10) {
      final highlight = Color.fromARGB(
        (20 * fog).round().clamp(0, 255), 255, 255, 220);
      canvas.drawRect(
        Rect.fromLTWH(x, top, stripWidth.toDouble(), min(2, height * 0.02)),
        Paint()..color = highlight,
      );
      // Dark edge at bottom
      final shadow = Color.fromARGB(
        (40 * fog).round().clamp(0, 255), 0, 0, 0);
      canvas.drawRect(
        Rect.fromLTWH(x, top + height - min(2, height * 0.02), stripWidth.toDouble(), min(2, height * 0.02)),
        Paint()..color = shadow,
      );
    }

    // Window boards (barricade planks)
    if (result.cellType == 3) {
      // Find the barricade for this window
      int plankCount = 4; // default full
      for (final spawn in spawns) {
        final spawnGx = (spawn.x / tileSize).floor();
        final spawnGy = (spawn.y / tileSize).floor();
        if (spawnGx == result.mapX && spawnGy == result.mapY) {
          plankCount = spawn.barricade.planks;
          break;
        }
      }

      // Draw boards based on plank count
      if (plankCount > 0) {
        final boardFogR = (110 * fog).round().clamp(0, 255);
        final boardFogG = (75 * fog).round().clamp(0, 255);
        final boardFogB = (35 * fog).round().clamp(0, 255);
        final boardColor = Color.fromARGB(255, boardFogR, boardFogG, boardFogB);
        final boardPaint = Paint()..color = boardColor;
        final nailColor = Color.fromARGB(
          (200 * fog).round().clamp(0, 255), 140, 140, 140);

        final boardH = max(2.0, height * 0.10);
        final spacing = height / (4 + 1);

        for (int p = 0; p < plankCount; p++) {
          final boardY = top + spacing * (p + 0.5);
          canvas.drawRect(
            Rect.fromLTWH(x, boardY, stripWidth.toDouble(), boardH),
            boardPaint,
          );
          // Nail highlight
          if (stripWidth >= 2) {
            canvas.drawRect(
              Rect.fromLTWH(x, boardY + boardH * 0.4, 1, 1),
              Paint()..color = nailColor,
            );
          }
        }
      } else {
        // Broken window - darker void behind
        final voidColor = Color.fromARGB(
          (180 * fog).round().clamp(0, 255), 5, 5, 10);
        canvas.drawRect(
          Rect.fromLTWH(x, top + height * 0.1, stripWidth.toDouble(), height * 0.8),
          Paint()..color = voidColor,
        );
      }
    }

    // Door frame and metal detail
    if (result.cellType == 2) {
      final frameR = (200 * fog).round().clamp(0, 255);
      final frameG = (170 * fog).round().clamp(0, 255);
      final frameB = (50 * fog).round().clamp(0, 255);
      final frameColor = Color.fromARGB(255, frameR, frameG, frameB);
      // Top and bottom frame
      canvas.drawRect(
        Rect.fromLTWH(x, top, stripWidth.toDouble(), min(3, height * 0.03)),
        Paint()..color = frameColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, top + height - min(3, height * 0.03), stripWidth.toDouble(), min(3, height * 0.03)),
        Paint()..color = frameColor,
      );
      // Center band (handle area)
      if (height > 40) {
        canvas.drawRect(
          Rect.fromLTWH(x, top + height * 0.45, stripWidth.toDouble(), height * 0.1),
          Paint()..color = frameColor,
        );
      }
    }
  }

  _RayResult? _castRay(double px, double py, double angle,
      BuiltMap map, Set<String> openedDoors) {
    final dirX = cos(angle);
    final dirY = sin(angle);

    int mapX = (px / tileSize).floor();
    int mapY = (py / tileSize).floor();

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
      if (cell == 1 || cell == 3) {
        final dist = side == 0
            ? sideDistX - deltaDistX
            : sideDistY - deltaDistY;
        // Calculate wall texture U coordinate
        double wallU;
        if (side == 0) {
          wallU = (py + dist * dirY / (dist == 0 ? 1 : 1)) / tileSize;
          // Actually compute from exact hit point
          wallU = py / tileSize + (dist / tileSize) * (dirY / (dirX.abs() < 0.001 ? 0.001 : dirX.abs())) * (dirX < 0 ? -1 : 1);
          wallU = (wallU % 1.0 + 1.0) % 1.0;
        } else {
          wallU = px / tileSize + (dist / tileSize) * (dirX / (dirY.abs() < 0.001 ? 0.001 : dirY.abs())) * (dirY < 0 ? -1 : 1);
          wallU = (wallU % 1.0 + 1.0) % 1.0;
        }
        return _RayResult(distance: dist, side: side, cellType: cell,
            mapX: mapX, mapY: mapY, wallU: wallU);
      } else if (cell == 2) {
        final isDoorOpen = map.doors
            .where((d) => (d.x / tileSize).floor() == mapX &&
                          (d.y / tileSize).floor() == mapY)
            .any((d) => d.open);
        if (!isDoorOpen) {
          final dist = side == 0
              ? sideDistX - deltaDistX
              : sideDistY - deltaDistY;
          return _RayResult(distance: dist, side: side, cellType: 2,
              mapX: mapX, mapY: mapY, wallU: 0.5);
        }
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
          case 'brute': color = const Color(0xFF6B3A1E); break;
          case 'runner': color = const Color(0xFF4A6B2D); break;
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
        label: perk.perk[0].toUpperCase(),
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
          label: '?',
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
          label: 'P',
        ));
      }
    }

    // Sort back-to-front
    sprites.sort((a, b) => b.dist.compareTo(a.dist));

    for (final sprite in sprites) {
      final dx = sprite.x - px;
      final dy = sprite.y - py;

      double spriteAngle = atan2(dy, dx) - pAngle;
      while (spriteAngle > pi) spriteAngle -= 2 * pi;
      while (spriteAngle < -pi) spriteAngle += 2 * pi;

      if (spriteAngle.abs() > fov / 2 + 0.3) continue;

      final screenX = (size.width / 2) * (1 + spriteAngle / (fov / 2));

      final spriteHeight = (tileSize * size.height / sprite.dist * sprite.sizeMultiplier)
          .clamp(0.0, size.height * 2);
      final spriteWidth = spriteHeight * 0.6;
      final spriteTop = halfH - spriteHeight / 2;
      final spriteLeft = screenX - spriteWidth / 2;

      // Exponential fog matching walls
      final normalizedDist = sprite.dist / (maxDist * tileSize);
      final fogFactor = exp(-normalizedDist * 3.0).clamp(0.08, 1.0);

      // Z-buffer clipping
      final centerCol = screenX.round().clamp(0, _screenW - 1);
      if (sprite.dist > _zBuffer[centerCol]) continue;

      final fogR = (sprite.color.red * fogFactor).round().clamp(0, 255);
      final fogG = (sprite.color.green * fogFactor).round().clamp(0, 255);
      final fogB = (sprite.color.blue * fogFactor).round().clamp(0, 255);
      final fogAlpha = sprite.color.alpha;
      final fogColor = Color.fromARGB(fogAlpha, fogR, fogG, fogB);

      if (sprite.type == 'zombie') {
        _drawZombieSprite(canvas, spriteLeft, spriteTop, spriteWidth,
            spriteHeight, fogColor, sprite, fogFactor);
      } else {
        _drawItemSprite(canvas, spriteLeft, spriteTop, spriteWidth,
            spriteHeight, fogColor, sprite, fogFactor);
      }
    }
  }

  void _drawZombieSprite(Canvas canvas, double left, double top, double width,
      double height, Color color, _SpriteInfo sprite, double fog) {
    final z = sprite.data as ZombieState?;
    if (z == null) return;

    final limbPhase = z.limbOffset;

    // Shadow on ground
    final shadowY = top + height;
    final shadowW = width * 0.6;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(left + width / 2, shadowY),
        width: shadowW,
        height: shadowW * 0.2,
      ),
      Paint()..color = Color.fromARGB((30 * fog).round().clamp(0, 255), 0, 0, 0),
    );

    // Legs
    final legW = width * 0.18;
    final legH = height * 0.3;
    final legY = top + height * 0.65;
    final legSwing = sin(limbPhase) * width * 0.08;
    final legColor = _darken(color, 0.7);
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.25 + legSwing, legY, legW, legH),
      Paint()..color = legColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(left + width * 0.55 - legSwing, legY, legW, legH),
      Paint()..color = legColor,
    );

    // Torso
    final torsoW = width * 0.55;
    final torsoH = height * 0.4;
    final torsoX = left + (width - torsoW) / 2;
    final torsoY = top + height * 0.2;
    canvas.drawRect(
      Rect.fromLTWH(torsoX, torsoY, torsoW, torsoH),
      Paint()..color = color,
    );
    // Torn clothing detail
    final tearColor = _darken(color, 0.6);
    canvas.drawRect(
      Rect.fromLTWH(torsoX + torsoW * 0.1, torsoY + torsoH * 0.6, torsoW * 0.3, torsoH * 0.15),
      Paint()..color = tearColor,
    );

    // Arms (reaching forward with swing)
    final armW = width * 0.15;
    final armH = height * 0.25;
    final armY = top + height * 0.25;
    final armSwing = sin(limbPhase * 0.8) * width * 0.06;
    final armColor = _lighten(color, 1.1);
    // Left arm
    canvas.drawRect(
      Rect.fromLTWH(left - armW * 0.3 + armSwing, armY, armW, armH),
      Paint()..color = armColor,
    );
    // Right arm
    canvas.drawRect(
      Rect.fromLTWH(left + width - armW * 0.7 - armSwing, armY, armW, armH),
      Paint()..color = armColor,
    );

    // Head
    final headW = width * 0.35;
    final headH = height * 0.22;
    final headX = left + (width - headW) / 2;
    final headY = top + height * 0.02;
    final headColor = _lighten(color, 1.15);
    canvas.drawRect(
      Rect.fromLTWH(headX, headY, headW, headH),
      Paint()..color = headColor,
    );

    // Eyes - glowing
    final eyeGlow = z.type == 'runner'
        ? Color.fromARGB(255, (255 * fog).round().clamp(0, 255), (240 * fog).round().clamp(0, 255), 0)
        : Color.fromARGB(255, (255 * fog).round().clamp(0, 255), (40 * fog).round().clamp(0, 255), 0);
    final eyeSize = max(2.0, width * 0.10);
    final eyeY = headY + headH * 0.35;
    // Eye glow aura
    if (fog > 0.3) {
      final glowPaint = Paint()
        ..color = eyeGlow.withAlpha((60 * fog).round().clamp(0, 255))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(headX + headW * 0.3, eyeY + eyeSize / 2), eyeSize * 1.5, glowPaint);
      canvas.drawCircle(Offset(headX + headW * 0.7, eyeY + eyeSize / 2), eyeSize * 1.5, glowPaint);
    }
    canvas.drawRect(
      Rect.fromLTWH(headX + headW * 0.2, eyeY, eyeSize, eyeSize),
      Paint()..color = eyeGlow,
    );
    canvas.drawRect(
      Rect.fromLTWH(headX + headW * 0.6, eyeY, eyeSize, eyeSize),
      Paint()..color = eyeGlow,
    );

    // Mouth (dark slash)
    canvas.drawRect(
      Rect.fromLTWH(headX + headW * 0.25, headY + headH * 0.7, headW * 0.5, max(1, headH * 0.1)),
      Paint()..color = Color.fromARGB((180 * fog).round().clamp(0, 255), 20, 0, 0),
    );

    // Brute: extra bulk outline
    if (z.type == 'brute') {
      canvas.drawRect(
        Rect.fromLTWH(torsoX - 2, torsoY - 1, torsoW + 4, torsoH + 2),
        Paint()
          ..color = color.withAlpha((60 * fog).round().clamp(0, 255))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Health bar (if damaged)
    if (z.alive && z.health < z.maxHealth) {
      final barW = width * 0.7;
      final barH = max(3.0, height * 0.035);
      final barLeft = left + (width - barW) / 2;
      final barTop = top - barH - 4;
      // Background
      canvas.drawRect(
        Rect.fromLTWH(barLeft - 1, barTop - 1, barW + 2, barH + 2),
        Paint()..color = const Color(0xAA000000),
      );
      canvas.drawRect(
        Rect.fromLTWH(barLeft, barTop, barW, barH),
        Paint()..color = const Color(0xFF333333),
      );
      final ratio = z.health / z.maxHealth;
      final hpColor = ratio > 0.5
          ? const Color(0xFFCC0000)
          : const Color(0xFFFF4500);
      canvas.drawRect(
        Rect.fromLTWH(barLeft, barTop, barW * ratio, barH),
        Paint()..color = hpColor,
      );
    }
  }

  Color _darken(Color c, double factor) {
    return Color.fromARGB(c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );
  }

  Color _lighten(Color c, double factor) {
    return Color.fromARGB(c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );
  }

  void _drawItemSprite(Canvas canvas, double left, double top, double width,
      double height, Color color, _SpriteInfo sprite, double fog) {

    // Shadow
    final shadowY = top + height;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(left + width / 2, shadowY),
        width: width * 0.5,
        height: width * 0.15,
      ),
      Paint()..color = Color.fromARGB((25 * fog).round().clamp(0, 255), 0, 0, 0),
    );

    // Main body with rounded appearance (two layers)
    final bodyRect = Rect.fromLTWH(
      left + width * 0.1, top + height * 0.1,
      width * 0.8, height * 0.8);
    canvas.drawRect(bodyRect, Paint()..color = _darken(color, 0.6));
    canvas.drawRect(
      Rect.fromLTWH(
        left + width * 0.15, top + height * 0.12,
        width * 0.7, height * 0.76),
      Paint()..color = color,
    );

    // Glow effect for special items
    if (sprite.type == 'mysterybox' || sprite.type == 'packapunch' || sprite.type == 'perk') {
      final pulseAlpha = (sin(_time * 4) * 25 + 45).round().clamp(0, 255);
      canvas.drawRect(
        Rect.fromLTWH(left + width * 0.05, top + height * 0.05,
            width * 0.9, height * 0.9),
        Paint()
          ..color = color.withAlpha(pulseAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
    }

    // Label text on the sprite
    if (sprite.label != null && height > 20) {
      final textSize = max(8.0, min(height * 0.25, 24.0));
      final textPainter = TextPainter(
        text: TextSpan(
          text: sprite.label!,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: textSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(
        left + (width - textPainter.width) / 2,
        top + (height - textPainter.height) / 2,
      ));
    }
  }

  void _renderWeaponView(Canvas canvas, Size size, GameWeapon weapon,
      double weaponBob, double muzzleFlashTimer, PlayerState player) {
    final weaponColor = Color(weapon.color);
    final centerX = size.width / 2;
    final bottomY = size.height;

    // Realistic weapon bob from walking
    final bobX = sin(weaponBob) * 6;
    final bobY = cos(weaponBob * 2).abs() * 3;

    // Idle sway (subtle)
    final swayX = sin(_time * 1.2) * 1.5;
    final swayY = cos(_time * 0.8) * 1.0;

    final totalBobX = bobX + swayX;
    final totalBobY = bobY + swayY;

    // Recoil kick
    final recoilY = muzzleFlashTimer > 0 ? -12.0 * (muzzleFlashTimer / 0.08) : 0.0;
    final recoilAngle = muzzleFlashTimer > 0 ? -0.05 * (muzzleFlashTimer / 0.08) : 0.0;

    // Reload animation - weapon drops down
    double reloadDrop = 0;
    if (weapon.reloading) {
      final reloadProgress = 1.0 - (weapon.reloadTimer / weapon.stats.reloadTime);
      // Drop down, pause, come back up
      if (reloadProgress < 0.3) {
        reloadDrop = reloadProgress / 0.3 * 80;
      } else if (reloadProgress < 0.7) {
        reloadDrop = 80;
      } else {
        reloadDrop = (1.0 - (reloadProgress - 0.7) / 0.3) * 80;
      }
    }

    canvas.save();
    canvas.translate(centerX + 50 + totalBobX, bottomY - 100 + totalBobY + recoilY + reloadDrop);
    if (recoilAngle != 0) {
      canvas.rotate(recoilAngle);
    }

    // Draw weapon based on type feel
    _drawWeaponModel(canvas, weapon, weaponColor);

    canvas.restore();

    // Muzzle flash - drawn at barrel tip
    if (muzzleFlashTimer > 0) {
      final flashAlpha = (muzzleFlashTimer / 0.08 * 255).round().clamp(0, 255);
      final flashCX = centerX + 50 + totalBobX + 8;
      final flashCY = bottomY - 100 + totalBobY + recoilY + reloadDrop - 50;

      // Bright flash circle
      canvas.drawCircle(
        Offset(flashCX, flashCY),
        18 + muzzleFlashTimer * 60,
        Paint()
          ..color = Color.fromARGB(flashAlpha, 255, 240, 120)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      // Core white
      canvas.drawCircle(
        Offset(flashCX, flashCY),
        8,
        Paint()..color = Color.fromARGB(flashAlpha, 255, 255, 255),
      );
      // Screen flash
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color.fromARGB((flashAlpha * 0.05).round().clamp(0, 255), 255, 200, 100),
      );
    }
  }

  void _drawWeaponModel(Canvas canvas, GameWeapon weapon, Color weaponColor) {
    final darkColor = _darken(weaponColor, 0.6);
    final highlightColor = _lighten(weaponColor, 1.3);

    // Barrel
    final barrelW = 12.0;
    final barrelH = 55.0;
    canvas.drawRect(
      Rect.fromLTWH(-barrelW / 2, -barrelH, barrelW, barrelH),
      Paint()..color = darkColor,
    );
    // Barrel highlight edge
    canvas.drawRect(
      Rect.fromLTWH(-barrelW / 2, -barrelH, 2, barrelH),
      Paint()..color = highlightColor.withAlpha(60),
    );

    // Receiver/body
    final bodyW = 50.0;
    final bodyH = 28.0;
    canvas.drawRect(
      Rect.fromLTWH(-bodyW / 2, 0, bodyW, bodyH),
      Paint()..color = weaponColor,
    );
    // Body top highlight
    canvas.drawRect(
      Rect.fromLTWH(-bodyW / 2, 0, bodyW, 2),
      Paint()..color = highlightColor.withAlpha(40),
    );
    // Body side shadow
    canvas.drawRect(
      Rect.fromLTWH(bodyW / 2 - 3, 0, 3, bodyH),
      Paint()..color = darkColor,
    );

    // Trigger guard area
    canvas.drawRect(
      Rect.fromLTWH(-8, bodyH, 16, 8),
      Paint()..color = darkColor,
    );

    // Grip/handle
    final gripW = 16.0;
    final gripH = 35.0;
    canvas.drawRect(
      Rect.fromLTWH(-gripW / 2, bodyH + 5, gripW, gripH),
      Paint()..color = const Color(0xFF2A2420),
    );
    // Grip texture lines
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(-gripW / 2, bodyH + 12 + i * 7.0, gripW, 1),
        Paint()..color = const Color(0xFF1A1614),
      );
    }

    // Magazine (below receiver)
    canvas.drawRect(
      Rect.fromLTWH(-12, bodyH + 2, 10, 20),
      Paint()..color = const Color(0xFF333333),
    );

    // Pack-a-Punch glow
    if (weapon.isPaP) {
      canvas.drawRect(
        Rect.fromLTWH(-bodyW / 2 - 5, -barrelH - 5, bodyW + 10, barrelH + bodyH + gripH + 15),
        Paint()
          ..color = weaponColor.withAlpha(50)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 15),
      );
    }
  }
}

class _RayResult {
  final double distance;
  final int side;
  final int cellType;
  final int mapX, mapY;
  final double? wallU; // texture coordinate along the wall surface

  _RayResult({
    required this.distance,
    required this.side,
    required this.cellType,
    required this.mapX,
    required this.mapY,
    this.wallU,
  });
}

class _SpriteInfo {
  final double x, y, dist;
  final Color color;
  final String type;
  final Object? data;
  final double sizeMultiplier;
  final String? label;

  _SpriteInfo({
    required this.x,
    required this.y,
    required this.dist,
    required this.color,
    required this.type,
    this.data,
    this.sizeMultiplier = 1.0,
    this.label,
  });
}
