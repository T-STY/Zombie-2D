import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_state.dart';
import '../models/map_data.dart';
import '../models/weapon_data.dart';

class ZombieGame extends FlameGame with KeyboardEvents {
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

  // Input
  final Set<LogicalKeyboardKey> _keysPressed = {};
  double _mouseX = 0, _mouseY = 0;
  bool _firing = false;
  bool _mobileFiring = false;
  double _mobileMoveDx = 0, _mobileMoveDy = 0;

  // Camera
  double _camX = 0, _camY = 0;

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

  void setFiring(bool firing) {
    _firing = firing;
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

  void updateMousePosition(double x, double y) {
    _mouseX = x;
    _mouseY = y;
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
    for (final wall in _map.walls) {
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
      if (mb.requiresDoor != null && !_openedDoors.contains(mb.requiresDoor)) {
      } else {
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
      if (pap.requiresDoor != null && !_openedDoors.contains(pap.requiresDoor)) {
      } else {
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

    _spawnFloatingText(zombie.x, zombie.y - 10, '+${zombie.pointsOnKill * multiplier}',
        0xFFFFD700, size: 14);
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
    _updateCamera();
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
    if (spawn.barricade.intact) {
      z.targetBarricade = spawn.barricade;
      z.insideMap = false;
    } else {
      z.insideMap = true;
    }
    _zombies.add(z);
  }

  void _updatePlayer(double dt) {
    // Movement from keyboard
    double mx = 0, my = 0;
    if (_keysPressed.contains(LogicalKeyboardKey.keyA) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      mx -= 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyD) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      mx += 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyW) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      my -= 1;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.keyS) ||
        _keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      my += 1;
    }

    // Add mobile input
    if (_mobileMoveDx != 0 || _mobileMoveDy != 0) {
      mx = _mobileMoveDx;
      my = _mobileMoveDy;
    }

    // Normalize diagonal
    if (mx != 0 && my != 0) {
      final len = sqrt(mx * mx + my * my);
      mx /= len;
      my /= len;
    }

    _player.moveX = mx;
    _player.moveY = my;

    // Aim toward mouse
    final worldMouseX = _mouseX + _camX;
    final worldMouseY = _mouseY + _camY;
    _player.angle = atan2(
      worldMouseY - (_player.y + _player.height / 2),
      worldMouseX - (_player.x + _player.width / 2),
    );

    // Movement
    double spd = _player.speed;
    if (_player.perks.contains('staminup')) spd *= 1.3;
    if (_player.currentWeapon.reloading) spd *= 0.7;
    if (_player.perks.contains('speedcola') && _player.currentWeapon.reloading) {
      _player.currentWeapon.reloadTimer -= dt * 0.5;
    }

    double newX = _player.x + _player.moveX * spd * dt * 60;
    double newY = _player.y + _player.moveY * spd * dt * 60;

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

    // Firing
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

    _spawnParticles(
      px + cos(_player.angle) * 24,
      py + sin(_player.angle) * 24,
      0xFFFFFF00, 3, 2, life: 0.1,
    );

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
          if (z.attackCooldown > 0) {
            z.attackCooldown -= dt;
          } else {
            z.attackCooldown = z.attackRate;
            z.targetBarricade!.hitPlank(z.damage);
          }
          z.limbOffset += dt * 4;
          continue;
        } else {
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

        // POST-MOVE WALL RESOLUTION
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

      final overlapLeft = (z.x + z.width) - wall.x;
      final overlapRight = (wall.x + wall.w) - z.x;
      final overlapTop = (z.y + z.height) - wall.y;
      final overlapBottom = (wall.y + wall.h) - z.y;

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
          _spawnParticles(b.x, b.y, 0xFFFFFF00, 3, 2, life: 0.2);
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
            _spawnParticles(b.x, b.y, 0xFF8B0000, 3, 2, life: 0.3);

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
              _spawnParticles(b.x, b.y, 0xFF00FF00, 10, 5, life: 0.4);
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

  void _updateCamera() {
    final targetX = _player.x + _player.width / 2 - size.x / 2;
    final targetY = _player.y + _player.height / 2 - size.y / 2;
    _camX += (targetX - _camX) * 0.1;
    _camY += (targetY - _camY) * 0.1;
  }

  // ---- Rendering ----

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    canvas.save();
    canvas.translate(_shakeX, _shakeY);

    _renderMap(canvas);
    _renderZombies(canvas);
    _renderBullets(canvas);
    _renderPlayer(canvas);
    _renderParticles(canvas);
    _renderFloatingTexts(canvas);
    _renderInteractPrompts(canvas);
    _renderMysteryBox(canvas);
    _renderPackAPunch(canvas);

    canvas.restore();

    _renderHUD(canvas);
    _renderDamageOverlay(canvas);
    _renderRoundDisplay(canvas);
    _renderPowerUpTimers(canvas);
  }

  void _renderMap(Canvas canvas) {
    final W = _map.info.width;
    final H = _map.info.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = const Color(0xFF1a1a1a),
    );

    final startTX = max(0, (_camX / tileSize).floor());
    final startTY = max(0, (_camY / tileSize).floor());
    final endTX = min(W - 1, ((_camX + size.x) / tileSize).ceil());
    final endTY = min(H - 1, ((_camY + size.y) / tileSize).ceil());

    for (int ty = startTY; ty <= endTY; ty++) {
      for (int tx = startTX; tx <= endTX; tx++) {
        if (ty >= H || tx >= W) continue;
        final cell = _map.grid[ty][tx];
        final drawX = tx * tileSize - _camX;
        final drawY = ty * tileSize - _camY;

        if (cell == 0 || cell == 3) {
          final color = (tx + ty) % 2 == 0
              ? const Color(0xFF2a2a2a)
              : const Color(0xFF252525);
          canvas.drawRect(
            Rect.fromLTWH(drawX, drawY, tileSize, tileSize),
            Paint()..color = color,
          );
        }
      }
    }

    // Walls
    for (final wall in _map.walls) {
      final wx = wall.x - _camX;
      final wy = wall.y - _camY;
      if (wx + wall.w < 0 || wx > size.x || wy + wall.h < 0 || wy > size.y) continue;

      canvas.drawRect(
        Rect.fromLTWH(wx, wy, wall.w, wall.h),
        Paint()..color = const Color(0xFF4A4A4A),
      );
      canvas.drawRect(
        Rect.fromLTWH(wx, wy, wall.w, 2),
        Paint()..color = const Color(0xFF5A5A5A),
      );
      canvas.drawRect(
        Rect.fromLTWH(wx, wy, 2, wall.h),
        Paint()..color = const Color(0xFF5A5A5A),
      );
    }

    // Doors
    for (final door in _map.doors) {
      if (door.open) continue;
      final dx = door.x - _camX;
      final dy = door.y - _camY;
      if (dx + door.w < 0 || dx > size.x || dy + door.h < 0 || dy > size.y) continue;

      canvas.drawRect(
        Rect.fromLTWH(dx, dy, door.w, door.h),
        Paint()..color = const Color(0xFF8B4513),
      );
      canvas.drawRect(
        Rect.fromLTWH(dx + 2, dy + 2, door.w - 4, door.h - 4),
        Paint()
          ..color = const Color(0xFFDAA520)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _drawText(canvas, '${door.cost}', dx + door.w / 2, dy + door.h / 2 + 4,
          const Color(0xFFFFD700), 10, TextAlign.center);
    }

    // Zombie spawn windows with barricade planks
    for (final spawn in _map.zombieSpawns) {
      final sx = spawn.x - _camX;
      final sy = spawn.y - _camY;
      if (sx + tileSize < 0 || sx > size.x || sy + tileSize < 0 || sy > size.y) continue;

      canvas.drawRect(
        Rect.fromLTWH(sx, sy, tileSize, tileSize),
        Paint()..color = const Color(0xFF2A2A3A),
      );
      // Draw boards based on barricade plank count
      final planks = spawn.barricade.planks;
      final boardPaint = Paint()
        ..color = const Color(0xFF654321)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final spacing = tileSize / (spawn.barricade.maxPlanks + 1);
      for (int b = 0; b < planks; b++) {
        final offset = spacing * (b + 1);
        canvas.drawLine(
          Offset(sx + 2, sy + offset),
          Offset(sx + tileSize - 2, sy + offset),
          boardPaint,
        );
      }
    }

    // Wall weapons
    for (final ww in _map.wallWeapons) {
      if (ww.requiresDoor != null && !_openedDoors.contains(ww.requiresDoor)) continue;
      final wx = ww.x - _camX;
      final wy = ww.y - _camY;

      canvas.drawRect(
        Rect.fromLTWH(wx - 5, wy - 5, 70, 30),
        Paint()..color = const Color(0xFF333333),
      );
      canvas.drawRect(
        Rect.fromLTWH(wx - 5, wy - 5, 70, 30),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      final wColor = Color(WeaponData.weapons[ww.weapon]?.color ?? 0xFFFFFFFF);
      _drawText(canvas, ww.label, wx + 30, wy + 7, wColor, 8, TextAlign.center);
      _drawText(canvas, '[F] Buy', wx + 30, wy + 18, const Color(0xFFCCCCCC), 8, TextAlign.center);
    }

    // Perk machines
    for (final perk in _map.perkLocations) {
      if (perk.requiresDoor != null && !_openedDoors.contains(perk.requiresDoor)) continue;
      final px = perk.x - _camX;
      final py = perk.y - _camY;

      final perkColors = {
        'juggernog': const Color(0xFFFF4444),
        'speedcola': const Color(0xFF44FF44),
        'quickrevive': const Color(0xFF4444FF),
        'staminup': const Color(0xFFFFFF44),
        'doubletap': const Color(0xFFFF8800),
      };

      final color = perkColors[perk.perk] ?? const Color(0xFFFFFFFF);
      final pulse = 0.6 + sin(DateTime.now().millisecondsSinceEpoch * 0.003) * 0.2;
      canvas.drawRect(
        Rect.fromLTWH(px, py, 30, 36),
        Paint()..color = color.withAlpha((pulse * 255).round()),
      );
      canvas.drawRect(
        Rect.fromLTWH(px, py, 30, 36),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      _drawText(canvas, perk.perk.toUpperCase().substring(0, min(5, perk.perk.length)),
          px + 15, py + 14, const Color(0xFFFFFFFF), 7, TextAlign.center);
      _drawText(canvas, '${perk.cost}', px + 15, py + 26,
          const Color(0xFFFFFFFF), 8, TextAlign.center);
    }
  }

  void _renderMysteryBox(Canvas canvas) {
    final mb = _map.mysteryBox;
    if (mb == null) return;
    if (mb.requiresDoor != null && !_openedDoors.contains(mb.requiresDoor)) return;

    final bx = mb.x - _camX;
    final by = mb.y - _camY;

    final glow = sin(DateTime.now().millisecondsSinceEpoch * 0.004) * 0.3 + 0.7;
    canvas.drawRect(
      Rect.fromLTWH(bx, by, 40, 30),
      Paint()..color = Color.fromARGB((glow * 255).round(), 0, 150, 255),
    );
    canvas.drawRect(
      Rect.fromLTWH(bx, by, 40, 30),
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _drawText(canvas, '?', bx + 20, by + 20, const Color(0xFFFFFFFF), 18, TextAlign.center);

    if (mb.active) {
      if (mb.rollTimer > 0 && mb.rollingWeapon != null) {
        final name = WeaponData.weapons[mb.rollingWeapon]?.name ?? '???';
        _drawText(canvas, name, bx + 20, by - 10, const Color(0xFF00FFFF), 12, TextAlign.center);
      } else if (mb.resultWeapon != null) {
        final name = WeaponData.weapons[mb.resultWeapon]?.name ?? '???';
        _drawText(canvas, name, bx + 20, by - 10, const Color(0xFF00FF00), 14, TextAlign.center);
        _drawText(canvas, '[F] Take', bx + 20, by + 45, const Color(0xFFFFFFFF), 10, TextAlign.center);
      }
    } else {
      _drawText(canvas, '${MysteryBoxState.cost} pts', bx + 20, by + 42,
          const Color(0xFF00AAFF), 9, TextAlign.center);
    }
  }

  void _renderPackAPunch(Canvas canvas) {
    final pap = _map.packAPunch;
    if (pap == null) return;
    if (pap.requiresDoor != null && !_openedDoors.contains(pap.requiresDoor)) return;

    final px = pap.x - _camX;
    final py = pap.y - _camY;

    final glow = sin(DateTime.now().millisecondsSinceEpoch * 0.003) * 0.3 + 0.7;
    canvas.drawRect(
      Rect.fromLTWH(px, py, 40, 36),
      Paint()..color = Color.fromARGB((glow * 255).round(), 180, 0, 255),
    );
    canvas.drawRect(
      Rect.fromLTWH(px, py, 40, 36),
      Paint()
        ..color = const Color(0xFFFF00FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _drawText(canvas, 'PaP', px + 20, py + 16, const Color(0xFFFFFFFF), 12, TextAlign.center);

    if (pap.active) {
      _drawText(canvas, 'UPGRADING...', px + 20, py - 10, const Color(0xFFFF00FF), 12, TextAlign.center);
    } else {
      _drawText(canvas, '${PackAPunchState.cost}', px + 20, py + 30,
          const Color(0xFFFF00FF), 9, TextAlign.center);
    }
  }

  void _renderInteractPrompts(Canvas canvas) {
    if (!_player.alive) return;
    final px = _player.x + _player.width / 2;
    final py = _player.y + _player.height / 2;

    for (final door in _map.doors) {
      if (door.open) continue;
      final dist = _dist(px, py, door.x + door.w / 2, door.y + door.h / 2);
      if (dist < 100) {
        _drawText(canvas, 'Press [F] - ${door.cost} pts',
            door.x + door.w / 2 - _camX, door.y - 15 - _camY,
            const Color(0xFFFFD700), 11, TextAlign.center);
      }
    }
  }

  void _renderPlayer(Canvas canvas) {
    if (!_player.alive) return;
    final drawX = _player.x - _camX;
    final drawY = _player.y - _camY;
    final cx = drawX + _player.width / 2;
    final cy = drawY + _player.height / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_player.angle);

    canvas.drawRect(
      Rect.fromLTWH(-_player.width / 2, -_player.height / 2, _player.width, _player.height),
      Paint()..color = const Color(0xFF4A90D9),
    );

    final weaponColor = Color(_player.currentWeapon.color);
    canvas.drawRect(
      Rect.fromLTWH(_player.width / 2 - 4, -3, 16, 6),
      Paint()..color = weaponColor,
    );

    if (_player.currentWeapon.isPaP) {
      canvas.drawRect(
        Rect.fromLTWH(_player.width / 2 - 4, -3, 16, 6),
        Paint()
          ..color = weaponColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(6, -6, 4, 4),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(6, 2, 4, 4),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    canvas.restore();

    if (_player.health < _player.maxHealth) {
      final barW = 36.0;
      final barH = 4.0;
      canvas.drawRect(
        Rect.fromLTWH(cx - barW / 2, drawY - 10, barW, barH),
        Paint()..color = const Color(0xFF333333),
      );
      final ratio = _player.health / _player.maxHealth;
      final barColor = ratio > 0.5
          ? const Color(0xFF00FF00)
          : ratio > 0.25
              ? const Color(0xFFFFFF00)
              : const Color(0xFFFF0000);
      canvas.drawRect(
        Rect.fromLTWH(cx - barW / 2, drawY - 10, barW * ratio, barH),
        Paint()..color = barColor,
      );
    }
  }

  void _renderZombies(Canvas canvas) {
    for (final z in _zombies) {
      final drawX = z.x - _camX;
      final drawY = z.y - _camY;
      final cx = drawX + z.width / 2;
      final cy = drawY + z.height / 2;

      if (!z.alive) {
        if (z.deathTimer > 0) {
          canvas.drawRect(
            Rect.fromLTWH(drawX + 2, drawY + 2, z.width - 4, z.height - 4),
            Paint()..color = Color.fromARGB(
              (min(1.0, z.deathTimer) * 255).round(), 58, 26, 10),
          );
        }
        continue;
      }

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(z.angle);

      Color bodyColor;
      switch (z.type) {
        case 'brute':
          bodyColor = const Color(0xFF5A2D0C);
          break;
        case 'runner':
          bodyColor = const Color(0xFF4A5A2D);
          break;
        default:
          bodyColor = const Color(0xFF3D5A3D);
      }

      final sizeM = z.type == 'brute' ? 1.3 : 1.0;

      canvas.drawRect(
        Rect.fromLTWH(-z.width / 2 * sizeM, -z.height / 2 * sizeM,
            z.width * sizeM, z.height * sizeM),
        Paint()..color = bodyColor,
      );

      final armColor = z.type == 'brute'
          ? const Color(0xFF4A1D00)
          : const Color(0xFF2D4A2D);
      final armSwing = sin(z.limbOffset) * 0.3;
      canvas.save();
      canvas.rotate(armSwing);
      canvas.drawRect(
        Rect.fromLTWH(z.width / 2 * sizeM - 2, -8 * sizeM, 14, 5),
        Paint()..color = armColor,
      );
      canvas.restore();
      canvas.save();
      canvas.rotate(-armSwing);
      canvas.drawRect(
        Rect.fromLTWH(z.width / 2 * sizeM - 2, 3 * sizeM, 14, 5),
        Paint()..color = armColor,
      );
      canvas.restore();

      final eyeColor = z.type == 'runner'
          ? const Color(0xFFFFFF00)
          : const Color(0xFFFF0000);
      canvas.drawRect(
        Rect.fromLTWH(6, -5 * sizeM, 3, 3),
        Paint()..color = eyeColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(6, 2 * sizeM, 3, 3),
        Paint()..color = eyeColor,
      );

      canvas.restore();

      if (z.health < z.maxHealth) {
        final barW = 24 * sizeM;
        const barH = 3.0;
        canvas.drawRect(
          Rect.fromLTWH(cx - barW / 2, drawY - 8, barW, barH),
          Paint()..color = const Color(0xFF333333),
        );
        final ratio = z.health / z.maxHealth;
        canvas.drawRect(
          Rect.fromLTWH(cx - barW / 2, drawY - 8, barW * ratio, barH),
          Paint()..color = ratio > 0.5 ? const Color(0xFFFF0000) : const Color(0xFFFF4500),
        );
      }
    }
  }

  void _renderBullets(Canvas canvas) {
    for (final b in _bullets) {
      final bx = b.x - _camX;
      final by = b.y - _camY;
      final color = Color(b.color);

      if (b.isPaP) {
        canvas.drawRect(
          Rect.fromLTWH(bx - b.size / 2, by - b.size / 2, b.size, b.size),
          Paint()
            ..color = color
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(bx - b.size / 2, by - b.size / 2, b.size, b.size),
        Paint()..color = color,
      );
    }
  }

  void _renderParticles(Canvas canvas) {
    for (final p in _particles) {
      final alpha = (p.life / p.maxLife * 255).round().clamp(0, 255);
      canvas.drawRect(
        Rect.fromLTWH(
          p.x - _camX - p.size / 2,
          p.y - _camY - p.size / 2,
          p.size, p.size,
        ),
        Paint()..color = Color(p.color).withAlpha(alpha),
      );
    }
  }

  void _renderFloatingTexts(Canvas canvas) {
    for (final ft in _floatingTexts) {
      final alpha = (ft.life * 255).round().clamp(0, 255);
      _drawText(
        canvas, ft.text,
        ft.x - _camX, ft.y - _camY,
        Color(ft.color).withAlpha(alpha),
        ft.size, TextAlign.center,
      );
    }
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

    // Ammo display - bottom center
    _drawText(canvas, ammoText, size.x / 2, size.y - 40,
        const Color(0xFFFFFFFF), 24, TextAlign.center);
    _drawText(canvas, weapon.name, size.x / 2, size.y - 16,
        Color(weapon.color), 14, TextAlign.center);

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
    final hbarY = size.y - 60.0;
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
      final slotY = size.y - 80.0 + i * 22.0;
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
