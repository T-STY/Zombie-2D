import 'dart:math';
import 'weapon_data.dart';

class GameWeapon {
  final String key;
  final WeaponStats stats;
  final bool isPaP;
  int currentAmmo;
  int currentReserve;
  double fireTimer;
  bool reloading;
  double reloadTimer;

  GameWeapon({
    required this.key,
    required this.stats,
    this.isPaP = false,
  })  : currentAmmo = stats.magSize,
        currentReserve = stats.reserveAmmo,
        fireTimer = 0,
        reloading = false,
        reloadTimer = 0;

  String get name => stats.name;
  double get damage => stats.damage;
  int get magSize => stats.magSize;
  int get color => stats.color;

  void update(double dt) {
    if (fireTimer > 0) fireTimer -= dt;
    if (reloading) {
      reloadTimer -= dt;
      if (reloadTimer <= 0) {
        reloading = false;
        final needed = magSize - currentAmmo;
        final available = min(needed, currentReserve);
        currentAmmo += available;
        currentReserve -= available;
      }
    }
  }

  bool get canFire => fireTimer <= 0 && !reloading && currentAmmo > 0;

  bool fire() {
    if (!canFire) return false;
    fireTimer = stats.fireRate;
    currentAmmo--;
    return true;
  }

  void startReload() {
    if (reloading || currentAmmo == magSize || currentReserve <= 0) return;
    reloading = true;
    reloadTimer = stats.reloadTime;
  }

  void refillAmmo() {
    currentReserve = stats.reserveAmmo;
  }

  GameWeapon packAPunch() {
    if (isPaP || stats.pap == null) return this;
    return GameWeapon(key: key, stats: stats.pap!, isPaP: true);
  }
}

class PlayerState {
  double x, y;
  double angle = 0;
  double health = 100;
  double maxHealth = 100;
  int points = 500;
  int totalPoints = 500;
  int kills = 0;
  bool alive = true;
  List<GameWeapon> weapons = [];
  int currentWeaponIndex = 0;
  final int maxWeapons = 2;
  List<String> perks = [];
  double damageCooldown = 0;
  double healthRegenTimer = 0;
  final double healthRegenDelay = 5.0;
  double damageOverlayAlpha = 0;
  double moveX = 0, moveY = 0;
  final double speed = 3.5;
  final double width = 28;
  final double height = 28;
  double knifeTimer = 0;
  final double knifeCooldown = 0.8;
  final double knifeDamage = 150;
  final double knifeRange = 50;

  PlayerState({required this.x, required this.y}) {
    final startWeapon = WeaponData.weapons['m1911']!;
    weapons.add(GameWeapon(key: 'm1911', stats: startWeapon));
  }

  GameWeapon get currentWeapon => weapons[currentWeaponIndex];

  void addPoints(int amount) {
    points += amount;
    totalPoints += amount;
  }

  bool spendPoints(int amount) {
    if (points >= amount) {
      points -= amount;
      return true;
    }
    return false;
  }

  void switchWeapon() {
    if (weapons.length < 2) return;
    currentWeaponIndex = (currentWeaponIndex + 1) % weapons.length;
    if (currentWeapon.reloading) {
      currentWeapon.reloading = false;
    }
  }

  void giveWeapon(String weaponKey, {bool isPaP = false}) {
    final stats = WeaponData.weapons[weaponKey]!;
    final newWeapon = GameWeapon(
      key: weaponKey,
      stats: isPaP ? (stats.pap ?? stats) : stats,
      isPaP: isPaP,
    );
    if (weapons.length < maxWeapons) {
      weapons.add(newWeapon);
      currentWeaponIndex = weapons.length - 1;
    } else {
      weapons[currentWeaponIndex] = newWeapon;
    }
  }

  void addPerk(String perkId) {
    if (!perks.contains(perkId)) {
      perks.add(perkId);
      if (perkId == 'juggernog') maxHealth = 250;
    }
  }

  void takeDamage(double amount) {
    if (damageCooldown > 0) return;
    if (perks.contains('juggernog')) amount *= 0.5;
    health -= amount;
    damageCooldown = 0.3;
    healthRegenTimer = 0;
    damageOverlayAlpha = min(1.0, damageOverlayAlpha + 0.5);
    if (health <= 0) {
      health = 0;
      alive = false;
    }
  }
}

class ZombieState {
  double x, y;
  double angle = 0;
  double health;
  double maxHealth;
  double damage;
  double speed;
  bool alive = true;
  double deathTimer = 0;
  double attackCooldown = 0;
  final double attackRate = 1.0;
  final double attackRange = 35;
  String type;
  double stuckTimer = 0;
  double lastX, lastY;
  double limbOffset;
  final int pointsOnHit = 10;
  int pointsOnKill;
  final double width = 24;
  final double height = 24;

  ZombieState({
    required this.x,
    required this.y,
    required int round,
  })  : lastX = x,
        lastY = y,
        limbOffset = Random().nextDouble() * pi * 2,
        health = _calcHealth(round),
        maxHealth = _calcHealth(round),
        damage = _calcDamage(round),
        speed = _calcSpeed(round),
        type = _getType(round),
        pointsOnKill = _getType(round) == 'brute'
            ? 150
            : _getType(round) == 'runner'
                ? 100
                : 60;

  static double _calcHealth(int round) {
    if (round <= 1) return 100;
    if (round <= 5) return 100 + (round - 1) * 50;
    if (round <= 10) return 300 + (round - 5) * 100;
    return 800 + (round - 10) * 150;
  }

  static double _calcDamage(int round) {
    if (round <= 1) return 20;
    if (round <= 5) return 20 + round * 5;
    return 30 + round * 5;
  }

  static double _calcSpeed(int round) {
    final base = 1.2;
    final maxSpd = 3.5;
    return min(maxSpd, base + round * 0.12 + Random().nextDouble() * 0.5);
  }

  static String _getType(int round) {
    if (round >= 8 && Random().nextDouble() < 0.15) return 'brute';
    if (round >= 5 && Random().nextDouble() < 0.2) return 'runner';
    return 'normal';
  }

  bool takeDamage(double amount) {
    health -= amount;
    if (health <= 0) {
      alive = false;
      deathTimer = 3;
      return true;
    }
    return false;
  }
}

class BulletState {
  double x, y;
  double vx, vy;
  double damage;
  int color;
  double range;
  double distanceTraveled = 0;
  bool alive = true;
  bool splash;
  double splashRadius;
  bool isPaP;
  double size;

  BulletState({
    required this.x,
    required this.y,
    required double angle,
    required double speed,
    required this.damage,
    required this.color,
    required this.range,
    required double spread,
    this.splash = false,
    this.splashRadius = 0,
    this.isPaP = false,
  })  : size = isPaP ? 4 : 3,
        vx = cos(angle + (Random().nextDouble() - 0.5) * spread * 2) * speed,
        vy = sin(angle + (Random().nextDouble() - 0.5) * spread * 2) * speed;

  void update(double dt) {
    final dx = vx * dt * 60;
    final dy = vy * dt * 60;
    x += dx;
    y += dy;
    distanceTraveled += sqrt(dx * dx + dy * dy);
    if (distanceTraveled > range) alive = false;
  }
}

class FloatingText {
  double x, y;
  String text;
  int color;
  double life = 1.0;
  double vy = -1.5;
  double size;

  FloatingText({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.size = 16,
  });

  void update(double dt) {
    y += vy * dt * 60;
    life -= dt;
  }
}

class Particle {
  double x, y, vx, vy;
  double life, maxLife;
  int color;
  double size;

  Particle({
    required this.x,
    required this.y,
    required this.color,
    required double speed,
    double? life,
  })  : maxLife = life ?? 0.5,
        life = life ?? 0.5,
        size = Random().nextDouble() * 3 + 1,
        vx = cos(Random().nextDouble() * pi * 2) * Random().nextDouble() * speed,
        vy = sin(Random().nextDouble() * pi * 2) * Random().nextDouble() * speed;

  void update(double dt) {
    x += vx * dt * 60;
    y += vy * dt * 60;
    life -= dt;
  }
}

enum RoundPhase { playing, roundEnd, roundStart, gameOver }

class RoundState {
  int currentRound = 1;
  int zombiesThisRound = 6;
  int zombiesSpawned = 0;
  int zombiesKilled = 0;
  double spawnTimer = 0;
  double spawnInterval = 2.0;
  RoundPhase phase = RoundPhase.roundStart;
  double phaseTimer = 0;
  double roundStartDisplayTime = 3.0;
  double roundEndDisplayTime = 3.0;

  int getZombieCount(int round) {
    return (4 + round * 2 + (round * round * 0.3)).round();
  }

  void startRound(int round) {
    currentRound = round;
    zombiesThisRound = getZombieCount(round);
    zombiesSpawned = 0;
    zombiesKilled = 0;
    spawnInterval = max(0.5, 2.0 - round * 0.1);
    spawnTimer = 0;
    phase = RoundPhase.roundStart;
    phaseTimer = roundStartDisplayTime;
  }

  void nextRound() {
    phase = RoundPhase.roundEnd;
    phaseTimer = roundEndDisplayTime;
  }
}

class DoorState {
  final double x, y, w, h;
  final String id;
  final int cost;
  bool open;

  DoorState({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.id,
    required this.cost,
    this.open = false,
  });
}

class WallWeaponState {
  final double x, y;
  final String weapon;
  final int cost;
  final String label;
  final String? requiresDoor;

  WallWeaponState({
    required this.x,
    required this.y,
    required this.weapon,
    required this.cost,
    required this.label,
    this.requiresDoor,
  });
}

class PerkState {
  final double x, y;
  final String perk;
  final int cost;
  final String label;
  final String? requiresDoor;

  PerkState({
    required this.x,
    required this.y,
    required this.perk,
    required this.cost,
    required this.label,
    this.requiresDoor,
  });
}

class SpawnPoint {
  final double x, y;
  final String room;

  SpawnPoint({required this.x, required this.y, required this.room});
}

class MysteryBoxState {
  final double x, y;
  final String? requiresDoor;
  bool active = false;
  double timer = 0;
  String? rollingWeapon;
  String? resultWeapon;
  double rollTimer = 0;
  static const int cost = 950;
  static const double rollDuration = 2.0;
  static const double resultDisplayTime = 5.0;

  MysteryBoxState({
    required this.x,
    required this.y,
    this.requiresDoor,
  });
}

class PackAPunchState {
  final double x, y;
  final String? requiresDoor;
  bool active = false;
  double timer = 0;
  static const int cost = 5000;
  static const double upgradeTime = 3.0;

  PackAPunchState({
    required this.x,
    required this.y,
    this.requiresDoor,
  });
}
