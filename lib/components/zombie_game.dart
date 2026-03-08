import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_state.dart';
import '../models/map_data.dart';
import '../models/weapon_data.dart';
import 'raycaster.dart';

class ZombieGame extends FlameGame
    with KeyboardEvents, TapDetector, SecondaryTapDetector {
  final String mapKey;
  final void Function(int round, int kills, int points) onGameOver;

  late BuiltMap _map;
  late PlayerState _player;
  final List<ZombieState> _zombies = [];
  final List<BulletState> _bullets = [];
  final List<FloatingText> _floatingTexts = [];
  final List<Particle> _particles = [];
  late RoundState _round;
  final Set<String> _openedDoors = {};

  // Raycaster
  final Raycaster _raycaster = Raycaster();

  // Input
  final Set<LogicalKeyboardKey> _keysPressed = {};
  bool _firing = false;
  bool _mobileFiring = false;
  double _mobileMoveDx = 0, _mobileMoveDy = 0;
  double _mouseSensitivity = 0.003;

  // Screen shake
  double _shakeX = 0, _shakeY = 0;
  double _shakeIntensity = 0, _shakeDuration = 0;

  // Power-ups
  double _nukeTimer = 0;
  double _doublePointsTimer = 0;
  double _instaKillTimer = 0;

  // Compliment system
  int _killStreak = 0;
  double _killStreakTimer = 0;

  // Weapon view
  double _weaponBob = 0;
  double _muzzleFlashTimer = 0;

  // Interaction prompt
  String? _interactionPrompt;

  // Round compliments
  final List<String> _roundCompliments = [
    '',
    'SURVIVE THE NIGHT...',
    'THEY\'RE GETTING STRONGER...',
    'HOLD YOUR GROUND!',
    'THE HORDE APPROACHES!',
    'NICE WORK, SOLDIER!',
    'THEY SMELL YOUR FEAR...',
    'DON\'T LET UP!',
    'ELITE ZOMBIES INCOMING!',
    'YOU\'RE A MACHINE!',
    'DOUBLE DIGITS, IMPRESSIVE!',
    'THE DEAD WILL NOT REST!',
    'KEEP FIGHTING!',
    'THEY\'RE ENDLESS!',
    'FEAR NOTHING!',
    'ROUND 15! LEGENDARY!',
    'UNSTOPPABLE!',
    'THEY TREMBLE BEFORE YOU!',
    'DEATH INCARNATE!',
    'NIGHTMARE MODE!',
    'ROUND 20! GODLIKE!',
  ];

  final List<_StreakCompliment> _streakThresholds = [
    _StreakCompliment(5, 'NICE!', 0xFFFFFF00),
    _StreakCompliment(10, 'KILLING SPREE!', 0xFFFFA500),
    _StreakCompliment(15, 'UNSTOPPABLE!', 0xFFFF4500),
    _StreakCompliment(20, 'RAMPAGE!', 0xFFFF0000),
    _StreakCompliment(30, 'GODLIKE!', 0xFF8A2BE2),
    _StreakCompliment(50, 'BEYOND GODLIKE!', 0xFFFF00FF),
  ];

  bool _gameOverTriggered = false;

  ZombieGame({required this.mapKey, required this.onGameOver});

  @override
  Future<void> onLoad() async {
    _map = buildNachtDerUntoten();
    _player = PlayerState(x: _map.info.playerSpawnX, y: _map.info.playerSpawnY);
    _round = RoundState();
    _round.startRound(1);
  }

  // ---- Public API for game_screen ----

  void setMobileMove(double dx, double dy) {
    _mobileMoveDx = dx;
    _mobileMoveDy = dy;
  }

  void setMobileFiring(bool firing) {
    _mobileFiring = firing;
  }

  void onReloadPressed() {
    _player.currentWeapon.startReload();
  }

  void onSwitchWeapon() {
    _player.switchWeapon();
  }

  void onInteract() {
    _tryInteract();
  }

  void onKnife() {
    _tryKnife();
  }

  void updateMouseDelta(double dx) {
    if (!_player.alive) return;
    _player.angle += dx * _mouseSensitivity;
    // Keep angle in range
    while (_player.angle > pi) _player.angle -= 2 * pi;
    while (_player.angle < -pi) _player.angle += 2 * pi;
  }

  // ---- Input Handling ----

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _keysPressed.clear();
    _keysPressed.addAll(keysPressed);

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        _player.currentWeapon.startReload();
      }
      if (event.logicalKey == LogicalKeyboardKey.keyQ) {
        _player.switchWeapon();
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _tryInteract();
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        _tryKnife();
      }
    }

    return KeyEventResult.handled;
  }

  @override
  void onTapDown(TapDownInfo info) {
    _firing = true;
  }

  @override
  void onTapUp(TapUpInfo info) {
    _firing = false;
  }

  @override
  void onSecondaryTapDown(TapDownInfo info) {
    _tryKnife();
  }

  // ---- Collision helpers ----

  List<MapRect> _getActiveWalls() {
    final walls = <MapRect>[..._map.walls];
    for (final door in _map.doors) {
      if (!door.open) {
        walls.add(MapRect(door.x, door.y, door.w, door.h));
      }
    }
    return walls;
  }

  // Walls that block zombies (exclude windows with broken barricades)
  List<MapRect> _getZombieWalls() {
    final walls = <MapRect>[];
    // Add regular walls
    for (final wall in _map.walls) {
      // Check if this wall is actually a window spawn point
      bool isWindow = false;
      for (final spawn in _map.zombieSpawns) {
        if (spawn.x == wall.x && spawn.y == wall.y) {
          isWindow = true;
          break;
        }
      }
      if (!isWindow) {
        walls.add(wall);
      }
      // Windows only block zombies if barricade is intact
      // (zombies pass through if barricade is broken)
    }
    for (final door in _map.doors) {
      if (!door.open) {
        walls.add(MapRect(door.x, door.y, door.w, door.h));
      }
    }
    return walls;
  }

  List<SpawnPoint> _getActiveSpawns() {
    return _map.zombieSpawns.where((spawn) {
      if (spawn.room == 'start') return true;
      if (spawn.room == 'hallway') return _openedDoors.contains('door_hallway');
      if (spawn.room == 'upper') return _openedDoors.contains('door_upper');
      if (spawn.room == 'lower') return _openedDoors.contains('door_lower');
      return true;
    }).toList();
  }

  void _triggerShake(double intensity, double duration) {
    _shakeIntensity = intensity;
    _shakeDuration = duration;
  }

  void _spawnFloatingText(double x, double y, String text, int color, {double size = 16}) {
    _floatingTexts.add(FloatingText(x: x, y: y, text: text, color: color, size: size));
  }

  void _spawnParticles(double x, double y, int color, int count, double speed, {double? life}) {
    for (int i = 0; i < count; i++) {
      _particles.add(Particle(x: x, y: y, color: color, speed: speed, life: life));
    }
  }

  double _dist(double x1, double y1, double x2, double y2) {
    return sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }

  bool _rectCollision(double ax, double ay, double aw, double ah,
      double bx, double by, double bw, double bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  }

  // ---- Interaction ----

  void _tryInteract() {
    if (!_player.alive) return;
    final px = _player.x + _player.width / 2;
    final py = _player.y + _player.height / 2;

    // Try barricade repair
    for (final spawn in _map.zombieSpawns) {
      final dist = _dist(px, py, spawn.x + tileSize / 2, spawn.y + tileSize / 2);
      if (dist < 80 && spawn.barricade.planks < spawn.barricade.maxPlanks) {
        if (spawn.barricade.addPlank()) {
          _player.addPoints(10);
          _spawnFloatingText(spawn.x, spawn.y - 10, 'BARRICADE +1', 0xFF00FF00, size: 14);
        }
        return;
      }
    }

    // Try doors
    for (final door in _map.doors) {
      if (door.open) continue;
      final dx = door.x + door.w / 2;
      final dy = door.y + door.h / 2;
      final dist = _dist(px, py, dx, dy);
      if (dist < 80) {
        if (_player.spendPoints(door.cost)) {
          for (final d in _map.doors) {
            if (d.id == door.id) d.open = true;
          }
          _openedDoors.add(door.id);
          _spawnFloatingText(dx, dy, 'DOOR OPENED', 0xFF00FF00, size: 18);
          return;
        } else {
          _spawnFloatingText(dx, dy, 'Need ${door.cost} pts', 0xFFFF0000, size: 14);
          return;
        }
      }
    }

    // Try wall weapons
    for (final ww in _map.wallWeapons) {
      if (ww.requiresDoor != null && !_openedDoors.contains(ww.requiresDoor)) continue;
      final dist = _dist(px, py, ww.x + 30, ww.y + 15);
      if (dist < 80) {
        final existingIdx = _player.weapons.indexWhere((w) => w.key == ww.weapon && !w.isPaP);
        if (existingIdx >= 0) {
          final ammoCost = (ww.cost / 2).round();
          if (_player.spendPoints(ammoCost)) {
            _player.weapons[existingIdx].refillAmmo();
            _spawnFloatingText(ww.x, ww.y, 'AMMO REFILLED', 0xFF00FF00, size: 14);
          } else {
            _spawnFloatingText(ww.x, ww.y, 'Need $ammoCost pts', 0xFFFF0000, size: 14);
          }
        } else {
          if (_player.spendPoints(ww.cost)) {
            _player.giveWeapon(ww.weapon);
            _spawnFloatingText(ww.x, ww.y, WeaponData.weapons[ww.weapon]!.name, 0xFF00FF00, size: 16);
          } else {
            _spawnFloatingText(ww.x, ww.y, 'Need ${ww.cost} pts', 0xFFFF0000, size: 14);
          }
        }
        return;
      }
    }

    // Try perks
    for (final perk in _map.perkLocations) {
      if (perk.requiresDoor != null && !_openedDoors.contains(perk.requiresDoor)) continue;
      final dist = _dist(px, py, perk.x + 15, perk.y + 18);
      if (dist < 80) {
        if (_player.perks.contains(perk.perk)) {
          _spawnFloatingText(perk.x, perk.y, 'ALREADY OWNED', 0xFFFFFF00, size: 14);
          return;
        }
        if (_player.spendPoints(perk.cost)) {
          _player.addPerk(perk.perk);
          _spawnFloatingText(perk.x, perk.y, perk.perk.toUpperCase(), 0xFF00FF00, size: 18);
        } else {
          _spawnFloatingText(perk.x, perk.y, 'Need ${perk.cost} pts', 0xFFFF0000, size: 14);
        }
        return;
      }
    }

    // Try mystery box
    final mb = _map.mysteryBox;
    if (mb != null) {
      if (mb.requiresDoor != null && !_openedDoors.contains(mb.requiresDoor)) {}
      else {
        final dist = _dist(px, py, mb.x + 20, mb.y + 15);
        if (dist < 80) {
          if (mb.active) {
            if (mb.resultWeapon != null && mb.timer <= MysteryBoxState.resultDisplayTime) {
              _player.giveWeapon(mb.resultWeapon!);
              _spawnFloatingText(mb.x, mb.y, WeaponData.weapons[mb.resultWeapon]!.name,
                  0xFF00FFFF, size: 18);
              mb.active = false;
              mb.resultWeapon = null;
            }
            return;
          }
          if (_player.spendPoints(MysteryBoxState.cost)) {
            mb.active = true;
            mb.timer = MysteryBoxState.rollDuration + MysteryBoxState.resultDisplayTime;
            mb.rollTimer = MysteryBoxState.rollDuration;
            mb.resultWeapon = WeaponData.mysteryBoxPool[
                Random().nextInt(WeaponData.mysteryBoxPool.length)];
            _spawnFloatingText(mb.x, mb.y - 10, 'MYSTERY BOX', 0xFF00FFFF, size: 16);
          } else {
            _spawnFloatingText(mb.x, mb.y, 'Need ${MysteryBoxState.cost} pts', 0xFFFF0000, size: 14);
          }
          return;
        }
      }
    }

    // Try Pack-a-Punch
    final pap = _map.packAPunch;
    if (pap != null) {
      if (pap.requiresDoor != null && !_openedDoors.contains(pap.requiresDoor)) {}
      else {
        final dist = _dist(px, py, pap.x + 20, pap.y + 15);
        if (dist < 80) {
          if (pap.active) return;
          if (_player.currentWeapon.isPaP) {
            _spawnFloatingText(pap.x, pap.y, 'ALREADY UPGRADED', 0xFFFFFF00, size: 14);
            return;
          }
          if (_player.spendPoints(PackAPunchState.cost)) {
            pap.active = true;
            pap.timer = PackAPunchState.upgradeTime;
            _spawnFloatingText(pap.x, pap.y - 10, 'PACK-A-PUNCH!', 0xFFFF00FF, size: 18);
          } else {
            _spawnFloatingText(pap.x, pap.y, 'Need ${PackAPunchState.cost} pts', 0xFFFF0000, size: 14);
          }
          return;
        }
      }
    }
  }

  void _tryKnife() {
    if (!_player.alive || _player.knifeTimer > 0) return;
    _player.knifeTimer = _player.knifeCooldown;

    final knifeX = _player.x + _player.width / 2 + cos(_player.angle) * _player.knifeRange / 2;
    final knifeY = _player.y + _player.height / 2 + sin(_player.angle) * _player.knifeRange / 2;

    for (final zombie in _zombies) {
      if (!zombie.alive) continue;
      final dist = _dist(knifeX, knifeY, zombie.x + zombie.width / 2, zombie.y + zombie.height / 2);
      if (dist < _player.knifeRange) {
        final killed = zombie.takeDamage(_instaKillTimer > 0 ? 99999 : _player.knifeDamage);
        _spawnParticles(zombie.x + zombie.width / 2, zombie.y + zombie.height / 2, 0xFF8B0000, 5, 3);
        _player.addPoints(zombie.pointsOnHit * (_doublePointsTimer > 0 ? 2 : 1));
        if (killed) {
          _onZombieKilled(zombie);
        }
        break;
      }
    }
  }

  void _onZombieKilled(ZombieState zombie) {
    final multiplier = _doublePointsTimer > 0 ? 2 : 1;
    _player.addPoints(zombie.pointsOnKill * multiplier);
    _player.kills++;
    _round.zombiesKilled++;
    _killStreak++;
    _killStreakTimer = 3.0;

    _spawnParticles(zombie.x + zombie.width / 2, zombie.y + zombie.height / 2,
        0xFF8B0000, 8, 3, life: 0.5);

    for (final sc in _streakThresholds.reversed) {
      if (_killStreak == sc.count) {
        _spawnFloatingText(_player.x, _player.y - 40, sc.text, sc.color, size: 24);
        break;
      }
    }

    _tryDropPowerUp(zombie.x, zombie.y);
  }

  void _tryDropPowerUp(double x, double y) {
    final roll = Random().nextDouble();
    if (roll < 0.03) {
      _nukeTimer = 0.5;
      _spawnFloatingText(x, y - 20, 'NUKE!', 0xFFFF0000, size: 28);
      _triggerShake(10, 0.5);
      for (final z in _zombies) {
        if (z.alive) {
          z.takeDamage(99999);
          _round.zombiesKilled++;
          _player.addPoints(400);
        }
      }
    } else if (roll < 0.06) {
      for (final w in _player.weapons) {
        w.refillAmmo();
      }
      _spawnFloatingText(x, y - 20, 'MAX AMMO!', 0xFF00FF00, size: 28);
    } else if (roll < 0.09) {
      _doublePointsTimer = 30;
      _spawnFloatingText(x, y - 20, 'DOUBLE POINTS!', 0xFFFFFF00, size: 28);
    } else if (roll < 0.12) {
      _instaKillTimer = 30;
      _spawnFloatingText(x, y - 20, 'INSTA-KILL!', 0xFFFF4500, size: 28);
    }
  }

  // ---- Update Loop ----

  @override
  void update(double dt) {
    super.update(dt);
    if (!_player.alive) {
      if (!_gameOverTriggered) {
        _gameOverTriggered = true;
        Future.delayed(const Duration(seconds: 2), () {
          onGameOver(_round.currentRound, _player.kills, _player.totalPoints);
        });
      }
      return;
    }

    _updateRound(dt);
    _updatePlayer(dt);
    _updateZombies(dt);
    _updateBullets(dt);
    _updateMysteryBox(dt);
    _updatePackAPunch(dt);
    _updateEffects(dt);
    _updateInteractionPrompt();
  }

  void _updateRound(double dt) {
    switch (_round.phase) {
      case RoundPhase.roundStart:
        _round.phaseTimer -= dt;
        if (_round.phaseTimer <= 0) {
          _round.phase = RoundPhase.playing;
        }
        break;
      case RoundPhase.playing:
        if (_round.zombiesSpawned < _round.zombiesThisRound) {
          _round.spawnTimer -= dt;
          if (_round.spawnTimer <= 0) {
            _spawnZombie();
            _round.zombiesSpawned++;
            _round.spawnTimer = _round.spawnInterval;
          }
        }
        if (_round.zombiesKilled >= _round.zombiesThisRound &&
            _zombies.every((z) => !z.alive)) {
          _round.nextRound();
        }
        break;
      case RoundPhase.roundEnd:
        _round.phaseTimer -= dt;
        if (_round.phaseTimer <= 0) {
          for (final w in _player.weapons) {
            final base = WeaponData.weapons[w.key]!;
            final ammoGift = (base.magSize * 1.5).round();
            w.currentReserve = min(w.stats.reserveAmmo, w.currentReserve + ammoGift);
          }
          _round.startRound(_round.currentRound + 1);
        }
        break;
      case RoundPhase.gameOver:
        break;
    }
  }

  void _spawnZombie() {
    final spawns = _getActiveSpawns();
    if (spawns.isEmpty) return;
    final spawn = spawns[Random().nextInt(spawns.length)];
    final z = ZombieState(
      x: spawn.x,
      y: spawn.y,
      round: _round.currentRound,
    );
    // Assign barricade target if barricade intact
    if (spawn.barricade.intact) {
      z.targetBarricade = spawn.barricade;
      z.insideMap = false;
    } else {
      z.insideMap = true;
    }
    _zombies.add(z);
  }

  void _updatePlayer(double dt) {
    // FPS-style movement: forward/back/strafe relative to facing angle
    double forward = 0, strafe = 0;
    if (_keysPressed.contains(LogicalKeyboardKey.keyW) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      forward += 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyS) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      forward -= 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyA) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      strafe -= 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyD) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      strafe += 1;
    }

    // Mobile input: joystick Y = forward/back, joystick X = strafe
    if (_mobileMoveDx != 0 || _mobileMoveDy != 0) {
      forward = -_mobileMoveDy; // up on joystick = forward
      strafe = _mobileMoveDx;
    }

    // Normalize diagonal
    if (forward != 0 && strafe != 0) {
      final len = sqrt(forward * forward + strafe * strafe);
      forward /= len;
      strafe /= len;
    }

    // Convert to world movement using player angle
    final moveX = cos(_player.angle) * forward + cos(_player.angle + pi / 2) * strafe;
    final moveY = sin(_player.angle) * forward + sin(_player.angle + pi / 2) * strafe;

    _player.moveX = moveX;
    _player.moveY = moveY;

    double spd = _player.speed;
    if (_player.perks.contains('staminup')) spd *= 1.3;
    if (_player.currentWeapon.reloading) spd *= 0.7;
    if (_player.perks.contains('speedcola') && _player.currentWeapon.reloading) {
      _player.currentWeapon.reloadTimer -= dt * 0.5;
    }

    double newX = _player.x + moveX * spd * dt * 60;
    double newY = _player.y + moveY * spd * dt * 60;

    final walls = _getActiveWalls();
    bool blockedX = false, blockedY = false;
    for (final wall in walls) {
      if (_rectCollision(newX, _player.y, _player.width, _player.height,
          wall.x, wall.y, wall.w, wall.h)) {
        blockedX = true;
      }
      if (_rectCollision(_player.x, newY, _player.width, _player.height,
          wall.x, wall.y, wall.w, wall.h)) {
        blockedY = true;
      }
    }
    if (!blockedX) _player.x = newX;
    if (!blockedY) _player.y = newY;

    _player.currentWeapon.update(dt);
    if (_player.knifeTimer > 0) _player.knifeTimer -= dt;
    if (_player.damageCooldown > 0) _player.damageCooldown -= dt;

    if (_player.health < _player.maxHealth) {
      _player.healthRegenTimer += dt;
      if (_player.healthRegenTimer >= _player.healthRegenDelay) {
        _player.health = min(_player.maxHealth, _player.health + 30 * dt);
      }
    }

    if (_player.damageOverlayAlpha > 0) {
      _player.damageOverlayAlpha -= dt * 0.5;
    }

    // Weapon bob when moving
    if (moveX != 0 || moveY != 0) {
      _weaponBob += dt * 8;
    } else {
      _weaponBob *= 0.9;
    }

    // Muzzle flash decay
    if (_muzzleFlashTimer > 0) _muzzleFlashTimer -= dt;

    // Firing - shoots along player angle (center of screen)
    final shouldFire = _firing || _mobileFiring ||
        _keysPressed.contains(LogicalKeyboardKey.space);
    final doubleTap = _player.perks.contains('doubletap');

    if (shouldFire && _player.currentWeapon.canFire) {
      _fireWeapon();
      if (doubleTap) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_player.alive && _player.currentWeapon.currentAmmo > 0) {
            _fireWeapon();
          }
        });
      }
    } else if (shouldFire && _player.currentWeapon.currentAmmo == 0 &&
        !_player.currentWeapon.reloading) {
      _player.currentWeapon.startReload();
    }
  }

  void _fireWeapon() {
    if (!_player.currentWeapon.fire()) return;

    final weapon = _player.currentWeapon;
    final px = _player.x + _player.width / 2;
    final py = _player.y + _player.height / 2;

    for (int i = 0; i < weapon.stats.bulletCount; i++) {
      _bullets.add(BulletState(
        x: px + cos(_player.angle) * 20,
        y: py + sin(_player.angle) * 20,
        angle: _player.angle,
        speed: weapon.stats.bulletSpeed,
        damage: weapon.damage,
        color: weapon.color,
        range: weapon.stats.range,
        spread: weapon.stats.spread,
        splash: weapon.stats.splash,
        splashRadius: weapon.stats.splashRadius,
        isPaP: weapon.isPaP,
      ));
    }

    _muzzleFlashTimer = 0.08;
    _triggerShake(2, 0.05);
  }

  void _updateZombies(double dt) {
    final walls = _getZombieWalls();

    for (int i = _zombies.length - 1; i >= 0; i--) {
      final z = _zombies[i];
      if (!z.alive) {
        z.deathTimer -= dt;
        if (z.deathTimer <= 0) {
          _zombies.removeAt(i);
        }
        continue;
      }

      // Barricade attack phase
      if (!z.insideMap && z.targetBarricade != null) {
        if (z.targetBarricade!.intact) {
          // Attack barricade
          if (z.attackCooldown > 0) {
            z.attackCooldown -= dt;
          } else {
            z.attackCooldown = z.attackRate;
            z.targetBarricade!.hitPlank(z.damage);
          }
          z.limbOffset += dt * 4;
          continue; // Don't move while attacking barricade
        } else {
          // Barricade broken, enter the map
          z.insideMap = true;
          z.targetBarricade = null;
        }
      }

      final px = _player.x + _player.width / 2;
      final py = _player.y + _player.height / 2;
      final zx = z.x + z.width / 2;
      final zy = z.y + z.height / 2;
      final dist = _dist(zx, zy, px, py);

      z.angle = atan2(py - zy, px - zx);
      if (z.attackCooldown > 0) z.attackCooldown -= dt;

      double currentSpeed = z.speed;
      if (z.type == 'brute') currentSpeed *= 0.7;
      if (z.type == 'runner') currentSpeed *= 1.4;

      if (dist < z.attackRange) {
        if (z.attackCooldown <= 0 && _player.alive) {
          z.attackCooldown = z.attackRate;
          _player.takeDamage(z.damage);
          _triggerShake(5, 0.2);
        }
      } else {
        double moveAngle = z.angle;
        if (z.stuckTimer > 0.5) {
          // Improved stuck resolution: try perpendicular directions
          moveAngle += (z.stuckTimer > 1.0 ? pi / 2 : pi / 4) *
              (z.stuckTimer.toInt() % 2 == 0 ? 1 : -1);
          if (z.stuckTimer > 2.0) z.stuckTimer = 0;
        }

        double newX = z.x + cos(moveAngle) * currentSpeed * dt * 60;
        double newY = z.y + sin(moveAngle) * currentSpeed * dt * 60;

        bool bx = false, by = false;
        for (final wall in walls) {
          if (_rectCollision(newX, z.y, z.width, z.height, wall.x, wall.y, wall.w, wall.h)) {
            bx = true;
          }
          if (_rectCollision(z.x, newY, z.width, z.height, wall.x, wall.y, wall.w, wall.h)) {
            by = true;
          }
        }
        if (!bx) z.x = newX;
        if (!by) z.y = newY;

        // Zombie-zombie push
        for (final other in _zombies) {
          if (other == z || !other.alive) continue;
          final d = _dist(zx, zy, other.x + other.width / 2, other.y + other.height / 2);
          if (d < 20 && d > 0) {
            final pushAngle = atan2(zy - (other.y + other.height / 2),
                zx - (other.x + other.width / 2));
            z.x += cos(pushAngle) * 0.5;
            z.y += sin(pushAngle) * 0.5;
          }
        }

        // POST-MOVE WALL RESOLUTION: push zombie out of any wall it ended up in
        _resolveWallOverlap(z, walls);

        final moved = _dist(z.x, z.y, z.lastX, z.lastY);
        z.stuckTimer = moved < 0.5 ? z.stuckTimer + dt : 0;
        z.lastX = z.x;
        z.lastY = z.y;
      }

      z.limbOffset += dt * 6;
    }
  }

  void _resolveWallOverlap(ZombieState z, List<MapRect> walls) {
    for (final wall in walls) {
      if (!_rectCollision(z.x, z.y, z.width, z.height,
          wall.x, wall.y, wall.w, wall.h)) continue;

      // Calculate overlap on each axis
      final overlapLeft = (z.x + z.width) - wall.x;
      final overlapRight = (wall.x + wall.w) - z.x;
      final overlapTop = (z.y + z.height) - wall.y;
      final overlapBottom = (wall.y + wall.h) - z.y;

      // Find minimum push direction
      final minOverlap = [overlapLeft, overlapRight, overlapTop, overlapBottom]
          .reduce(min);

      if (minOverlap == overlapLeft) {
        z.x = wall.x - z.width - 0.1;
      } else if (minOverlap == overlapRight) {
        z.x = wall.x + wall.w + 0.1;
      } else if (minOverlap == overlapTop) {
        z.y = wall.y - z.height - 0.1;
      } else {
        z.y = wall.y + wall.h + 0.1;
      }
    }
  }

  void _updateBullets(double dt) {
    final walls = _getActiveWalls();

    for (int i = _bullets.length - 1; i >= 0; i--) {
      final b = _bullets[i];
      b.update(dt);

      for (final wall in walls) {
        if (_rectCollision(b.x - b.size / 2, b.y - b.size / 2, b.size, b.size,
            wall.x, wall.y, wall.w, wall.h)) {
          b.alive = false;
          break;
        }
      }

      if (b.alive) {
        for (final z in _zombies) {
          if (!z.alive) continue;
          if (_rectCollision(b.x - b.size / 2, b.y - b.size / 2, b.size, b.size,
              z.x, z.y, z.width, z.height)) {
            b.alive = false;
            final dmg = _instaKillTimer > 0 ? 99999.0 : b.damage;
            final killed = z.takeDamage(dmg);
            _player.addPoints(z.pointsOnHit * (_doublePointsTimer > 0 ? 2 : 1));

            if (killed) {
              _onZombieKilled(z);
            }

            if (b.splash && b.splashRadius > 0) {
              for (final oz in _zombies) {
                if (!oz.alive || oz == z) continue;
                final dist = _dist(b.x, b.y, oz.x + oz.width / 2, oz.y + oz.height / 2);
                if (dist < b.splashRadius) {
                  final splashDmg = dmg * (1 - dist / b.splashRadius);
                  final sk = oz.takeDamage(splashDmg);
                  if (sk) _onZombieKilled(oz);
                }
              }
            }
            break;
          }
        }
      }

      if (!b.alive) {
        _bullets.removeAt(i);
      }
    }
  }

  void _updateMysteryBox(double dt) {
    final mb = _map.mysteryBox;
    if (mb == null || !mb.active) return;
    mb.timer -= dt;
    mb.rollTimer -= dt;
    if (mb.rollTimer > 0) {
      mb.rollingWeapon = WeaponData.mysteryBoxPool[
          Random().nextInt(WeaponData.mysteryBoxPool.length)];
    }
    if (mb.timer <= 0) {
      mb.active = false;
      mb.resultWeapon = null;
    }
  }

  void _updatePackAPunch(double dt) {
    final pap = _map.packAPunch;
    if (pap == null || !pap.active) return;
    pap.timer -= dt;
    if (pap.timer <= 0) {
      final weapon = _player.currentWeapon;
      if (!weapon.isPaP && weapon.stats.pap != null) {
        final papWeapon = weapon.packAPunch();
        _player.weapons[_player.currentWeaponIndex] = papWeapon;
        _spawnFloatingText(pap.x, pap.y, papWeapon.name, 0xFFFF00FF, size: 22);
      }
      pap.active = false;
    }
  }

  void _updateEffects(double dt) {
    if (_shakeDuration > 0) {
      _shakeX = (Random().nextDouble() - 0.5) * _shakeIntensity * 2;
      _shakeY = (Random().nextDouble() - 0.5) * _shakeIntensity * 2;
      _shakeDuration -= dt;
      _shakeIntensity *= 0.95;
    } else {
      _shakeX = 0;
      _shakeY = 0;
    }

    for (int i = _floatingTexts.length - 1; i >= 0; i--) {
      _floatingTexts[i].update(dt);
      if (_floatingTexts[i].life <= 0) _floatingTexts.removeAt(i);
    }

    for (int i = _particles.length - 1; i >= 0; i--) {
      _particles[i].update(dt);
      if (_particles[i].life <= 0) _particles.removeAt(i);
    }

    if (_doublePointsTimer > 0) _doublePointsTimer -= dt;
    if (_instaKillTimer > 0) _instaKillTimer -= dt;
    if (_nukeTimer > 0) _nukeTimer -= dt;

    if (_killStreakTimer > 0) {
      _killStreakTimer -= dt;
      if (_killStreakTimer <= 0) _killStreak = 0;
    }
  }

  void _updateInteractionPrompt() {
    _interactionPrompt = null;
    if (!_player.alive) return;
    final px = _player.x + _player.width / 2;
    final py = _player.y + _player.height / 2;

    // Check what the player is looking at (within range)
    for (final spawn in _map.zombieSpawns) {
      final dist = _dist(px, py, spawn.x + tileSize / 2, spawn.y + tileSize / 2);
      if (dist < 80 && spawn.barricade.planks < spawn.barricade.maxPlanks) {
        _interactionPrompt = '[F] Repair Barricade (${spawn.barricade.planks}/${spawn.barricade.maxPlanks})';
        return;
      }
    }

    for (final door in _map.doors) {
      if (door.open) continue;
      final dist = _dist(px, py, door.x + door.w / 2, door.y + door.h / 2);
      if (dist < 100) {
        _interactionPrompt = '[F] Open Door - ${door.cost} pts';
        return;
      }
    }

    for (final ww in _map.wallWeapons) {
      if (ww.requiresDoor != null && !_openedDoors.contains(ww.requiresDoor)) continue;
      final dist = _dist(px, py, ww.x + 30, ww.y + 15);
      if (dist < 80) {
        _interactionPrompt = '[F] ${ww.label}';
        return;
      }
    }

    for (final perk in _map.perkLocations) {
      if (perk.requiresDoor != null && !_openedDoors.contains(perk.requiresDoor)) continue;
      final dist = _dist(px, py, perk.x + 15, perk.y + 18);
      if (dist < 80) {
        _interactionPrompt = '[F] ${perk.label}';
        return;
      }
    }

    final mb = _map.mysteryBox;
    if (mb != null && (mb.requiresDoor == null || _openedDoors.contains(mb.requiresDoor))) {
      final dist = _dist(px, py, mb.x + 20, mb.y + 15);
      if (dist < 80) {
        if (mb.active && mb.resultWeapon != null && mb.rollTimer <= 0) {
          _interactionPrompt = '[F] Take ${WeaponData.weapons[mb.resultWeapon]?.name ?? "weapon"}';
        } else if (!mb.active) {
          _interactionPrompt = '[F] Mystery Box - ${MysteryBoxState.cost} pts';
        }
        return;
      }
    }

    final pap = _map.packAPunch;
    if (pap != null && !pap.active &&
        (pap.requiresDoor == null || _openedDoors.contains(pap.requiresDoor))) {
      final dist = _dist(px, py, pap.x + 20, pap.y + 15);
      if (dist < 80) {
        _interactionPrompt = '[F] Pack-a-Punch - ${PackAPunchState.cost} pts';
        return;
      }
    }
  }

  // ---- Rendering ----

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Raycasted 3D view
    _raycaster.render(
      canvas, Size(size.x, size.y), _player, _map, _openedDoors, _zombies,
      _map.zombieSpawns, _map.wallWeapons, _map.perkLocations,
      _map.mysteryBox, _map.packAPunch,
      _player.currentWeapon, _weaponBob, _muzzleFlashTimer,
      _shakeX, _shakeY,
    );

    // Screen-space overlays
    _renderCrosshair(canvas);
    _renderHUD(canvas);
    _renderDamageOverlay(canvas);
    _renderRoundDisplay(canvas);
    _renderPowerUpTimers(canvas);
    _renderInteractionPrompt(canvas);
  }

  void _renderCrosshair(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final crossPaint = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx - 4, cy), crossPaint);
    canvas.drawLine(Offset(cx + 4, cy), Offset(cx + 10, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy - 4), crossPaint);
    canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + 10), crossPaint);
    // Center dot
    canvas.drawCircle(Offset(cx, cy), 1.5,
        Paint()..color = const Color(0xCCFF0000));
  }

  void _renderInteractionPrompt(Canvas canvas) {
    if (_interactionPrompt == null) return;
    _drawText(canvas, _interactionPrompt!, size.x / 2, size.y * 0.65,
        const Color(0xFFFFD700), 16, TextAlign.center);
  }

  void _renderDamageOverlay(Canvas canvas) {
    if (_player.damageOverlayAlpha > 0) {
      final gradient = ui.Gradient.radial(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.7,
        [
          Colors.transparent,
          Color.fromARGB((_player.damageOverlayAlpha * 150).round(), 255, 0, 0),
        ],
        [0.3, 1.0],
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..shader = gradient,
      );
    }
  }

  void _renderHUD(Canvas canvas) {
    final weapon = _player.currentWeapon;
    final ammoText = weapon.reloading
        ? 'RELOADING...'
        : '${weapon.currentAmmo} / ${weapon.currentReserve}';

    // Ammo - bottom right
    _drawText(canvas, ammoText, size.x - 20, size.y - 30,
        const Color(0xFFFFFFFF), 24, TextAlign.right);
    _drawText(canvas, weapon.name, size.x - 20, size.y - 8,
        Color(weapon.color), 14, TextAlign.right);

    // Points - top left
    _drawText(canvas, 'POINTS', 20, 25,
        const Color(0xFF888888), 12, TextAlign.left);
    _drawText(canvas, '${_player.points}', 20, 45,
        const Color(0xFFFFD700), 24, TextAlign.left);

    // Round - top right
    _drawText(canvas, 'ROUND', size.x - 20, 25,
        const Color(0xFF888888), 12, TextAlign.right);
    _drawText(canvas, '${_round.currentRound}', size.x - 20, 50,
        const Color(0xFFFF4444), 28, TextAlign.right);

    // Kills
    _drawText(canvas, 'KILLS: ${_player.kills}', size.x - 20, 70,
        const Color(0xFF888888), 12, TextAlign.right);

    // Health bar - bottom left
    final hbarX = 20.0;
    final hbarY = size.y - 50.0;
    final hbarW = 150.0;
    final hbarH = 12.0;
    canvas.drawRect(
      Rect.fromLTWH(hbarX, hbarY, hbarW, hbarH),
      Paint()..color = const Color(0xFF333333),
    );
    final hRatio = _player.health / _player.maxHealth;
    final hColor = hRatio > 0.5
        ? const Color(0xFF00FF00)
        : hRatio > 0.25
            ? const Color(0xFFFFFF00)
            : const Color(0xFFFF0000);
    canvas.drawRect(
      Rect.fromLTWH(hbarX, hbarY, hbarW * hRatio, hbarH),
      Paint()..color = hColor,
    );
    _drawText(canvas, '${_player.health.round()}/${_player.maxHealth.round()}',
        hbarX + hbarW / 2, hbarY + 10, const Color(0xFFFFFFFF), 10, TextAlign.center);

    // Perks
    double perkX = 20;
    for (final perk in _player.perks) {
      final perkColors = {
        'juggernog': const Color(0xFFFF4444),
        'speedcola': const Color(0xFF44FF44),
        'quickrevive': const Color(0xFF4444FF),
        'staminup': const Color(0xFFFFFF44),
        'doubletap': const Color(0xFFFF8800),
      };
      final color = perkColors[perk] ?? const Color(0xFFFFFFFF);
      canvas.drawRect(
        Rect.fromLTWH(perkX, hbarY + 18, 20, 20),
        Paint()..color = color.withAlpha(180),
      );
      _drawText(canvas, perk[0].toUpperCase(), perkX + 10, hbarY + 33,
          const Color(0xFFFFFFFF), 10, TextAlign.center);
      perkX += 24;
    }

    // Weapon slots
    for (int i = 0; i < _player.weapons.length; i++) {
      final w = _player.weapons[i];
      final isActive = i == _player.currentWeaponIndex;
      final slotX = size.x - 180.0;
      final slotY = size.y - 70.0 + i * 22.0;
      final wColor = Color(w.color);

      if (isActive) {
        canvas.drawRect(
          Rect.fromLTWH(slotX - 2, slotY - 2, 160, 20),
          Paint()..color = wColor.withAlpha(40),
        );
      }
      _drawText(canvas, '${i + 1}. ${w.name}', slotX, slotY + 12,
          isActive ? wColor : const Color(0xFF666666), 11, TextAlign.left);
    }
  }

  void _renderRoundDisplay(Canvas canvas) {
    if (_round.phase == RoundPhase.roundStart) {
      final alpha = min(1.0, _round.phaseTimer);
      _drawText(canvas, 'ROUND ${_round.currentRound}', size.x / 2, size.y / 2 - 30,
          Color.fromARGB((alpha * 255).round(), 255, 68, 68), 48, TextAlign.center);
      final compIdx = min(_round.currentRound, _roundCompliments.length - 1);
      if (compIdx > 0) {
        _drawText(canvas, _roundCompliments[compIdx], size.x / 2, size.y / 2 + 20,
            Color.fromARGB((alpha * 255).round(), 255, 200, 50), 16, TextAlign.center);
      }
    } else if (_round.phase == RoundPhase.roundEnd) {
      final alpha = min(1.0, _round.phaseTimer);
      _drawText(canvas, 'ROUND COMPLETE', size.x / 2, size.y / 2 - 10,
          Color.fromARGB((alpha * 255).round(), 0, 255, 0), 32, TextAlign.center);
    }
  }

  void _renderPowerUpTimers(Canvas canvas) {
    double y = 90;
    if (_doublePointsTimer > 0) {
      _drawText(canvas, 'x2 POINTS ${_doublePointsTimer.ceil()}s',
          size.x - 20, y, const Color(0xFFFFFF00), 14, TextAlign.right);
      y += 20;
    }
    if (_instaKillTimer > 0) {
      _drawText(canvas, 'INSTA-KILL ${_instaKillTimer.ceil()}s',
          size.x - 20, y, const Color(0xFFFF4500), 14, TextAlign.right);
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      Color color, double fontSize, TextAlign align) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();

    double dx;
    switch (align) {
      case TextAlign.center:
        dx = x - textPainter.width / 2;
        break;
      case TextAlign.right:
        dx = x - textPainter.width;
        break;
      default:
        dx = x;
    }

    textPainter.paint(canvas, Offset(dx, y - textPainter.height));
  }
}

class _StreakCompliment {
  final int count;
  final String text;
  final int color;
  const _StreakCompliment(this.count, this.text, this.color);
}
