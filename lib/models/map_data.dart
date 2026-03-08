import 'game_state.dart';

const double tileSize = 40;

class MapInfo {
  final String key;
  final String name;
  final String description;
  final int width; // in tiles
  final int height;
  final double playerSpawnX;
  final double playerSpawnY;

  const MapInfo({
    required this.key,
    required this.name,
    required this.description,
    required this.width,
    required this.height,
    required this.playerSpawnX,
    required this.playerSpawnY,
  });
}

class BuiltMap {
  final MapInfo info;
  final List<List<int>> grid;
  final List<MapRect> walls;
  final List<DoorState> doors;
  final List<SpawnPoint> zombieSpawns;
  final List<WallWeaponState> wallWeapons;
  final List<PerkState> perkLocations;
  final MysteryBoxState? mysteryBox;
  final PackAPunchState? packAPunch;

  BuiltMap({
    required this.info,
    required this.grid,
    required this.walls,
    required this.doors,
    required this.zombieSpawns,
    required this.wallWeapons,
    required this.perkLocations,
    this.mysteryBox,
    this.packAPunch,
  });
}

class MapRect {
  final double x, y, w, h;
  const MapRect(this.x, this.y, this.w, this.h);
}

BuiltMap buildNachtDerUntoten() {
  const info = MapInfo(
    key: 'nacht_der_untoten',
    name: 'Nacht Der Untoten',
    description: 'The original bunker.\nSurvive the night.',
    width: 40,
    height: 30,
    playerSpawnX: 16 * tileSize,
    playerSpawnY: 15 * tileSize,
  );

  final W = info.width;
  final H = info.height;
  final grid = List.generate(H, (_) => List.filled(W, 0));

  // 0 = floor, 1 = wall, 2 = door, 3 = window (zombie spawn)

  // Outer boundary
  for (int x = 0; x < W; x++) {
    grid[0][x] = 1;
    grid[H - 1][x] = 1;
  }
  for (int y = 0; y < H; y++) {
    grid[y][0] = 1;
    grid[y][W - 1] = 1;
  }

  // Starting room: x:10-22, y:10-20
  for (int x = 10; x <= 22; x++) {
    grid[10][x] = 1;
    grid[20][x] = 1;
  }
  for (int y = 10; y <= 20; y++) {
    grid[y][10] = 1;
    grid[y][22] = 1;
  }

  // Windows in starting room
  grid[10][14] = 3;
  grid[10][18] = 3;
  grid[20][14] = 3;
  grid[20][18] = 3;
  grid[15][10] = 3;
  grid[15][22] = 3;

  // Door to right hallway
  grid[13][22] = 2;
  grid[14][22] = 2;

  // Right hallway: x:22-30, y:8-22
  for (int x = 22; x <= 30; x++) {
    grid[8][x] = 1;
    grid[22][x] = 1;
  }
  for (int y = 8; y <= 22; y++) {
    grid[y][30] = 1;
  }
  for (int y = 8; y <= 10; y++) {
    grid[y][22] = 1;
  }
  for (int y = 15; y <= 22; y++) {
    grid[y][22] = 1;
  }

  // Windows in hallway
  grid[8][25] = 3;
  grid[8][28] = 3;
  grid[22][25] = 3;
  grid[15][30] = 3;

  // Door to upper room
  grid[8][26] = 2;
  grid[8][27] = 2;

  // Upper room: x:22-35, y:2-8
  for (int x = 22; x <= 35; x++) {
    grid[2][x] = 1;
  }
  for (int y = 2; y <= 8; y++) {
    grid[y][35] = 1;
    grid[y][22] = 1;
  }
  for (int x = 22; x <= 25; x++) {
    grid[8][x] = 1;
  }
  for (int x = 28; x <= 35; x++) {
    grid[8][x] = 1;
  }

  // Windows in upper room
  grid[2][27] = 3;
  grid[2][32] = 3;
  grid[5][35] = 3;

  // Door to lower room
  grid[20][16] = 2;
  grid[20][17] = 2;

  // Lower room: x:8-24, y:20-27
  for (int x = 8; x <= 24; x++) {
    grid[27][x] = 1;
  }
  for (int y = 20; y <= 27; y++) {
    grid[y][8] = 1;
    grid[y][24] = 1;
  }
  for (int x = 8; x <= 15; x++) {
    grid[20][x] = 1;
  }
  for (int x = 18; x <= 24; x++) {
    grid[20][x] = 1;
  }

  // Windows in lower room
  grid[27][12] = 3;
  grid[27][20] = 3;
  grid[24][8] = 3;
  grid[24][24] = 3;

  // Convert grid to game objects
  final walls = <MapRect>[];
  final doors = <DoorState>[];
  final zombieSpawns = <SpawnPoint>[];

  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = x * tileSize;
      final py = y * tileSize;

      if (grid[y][x] == 1) {
        walls.add(MapRect(px, py, tileSize, tileSize));
      } else if (grid[y][x] == 3) {
        // Windows are walls too (player can't walk through)
        walls.add(MapRect(px, py, tileSize, tileSize));
        zombieSpawns.add(SpawnPoint(
          x: px, y: py,
          room: _getRoom(x, y),
        ));
      } else if (grid[y][x] == 2) {
        String doorId;
        int cost;
        if (x == 22 && (y == 13 || y == 14)) {
          doorId = 'door_hallway';
          cost = 750;
        } else if ((x == 26 || x == 27) && y == 8) {
          doorId = 'door_upper';
          cost = 1000;
        } else if ((x == 16 || x == 17) && y == 20) {
          doorId = 'door_lower';
          cost = 1250;
        } else {
          doorId = 'door_unknown';
          cost = 500;
        }
        doors.add(DoorState(
          x: px, y: py, w: tileSize, h: tileSize,
          id: doorId, cost: cost,
        ));
      }
    }
  }

  final wallWeapons = <WallWeaponState>[
    WallWeaponState(
      x: 11 * tileSize + 5, y: 11 * tileSize,
      weapon: 'olympia', cost: 500, label: 'Olympia - 500',
    ),
    WallWeaponState(
      x: 25 * tileSize, y: 9 * tileSize,
      weapon: 'mp40', cost: 1000, label: 'MP40 - 1000',
      requiresDoor: 'door_hallway',
    ),
  ];

  final perkLocations = <PerkState>[
    PerkState(x: 12 * tileSize, y: 17 * tileSize, perk: 'juggernog', cost: 2500, label: 'Juggernog - 2500'),
    PerkState(x: 28 * tileSize, y: 18 * tileSize, perk: 'speedcola', cost: 3000, label: 'Speed Cola - 3000', requiresDoor: 'door_hallway'),
    PerkState(x: 12 * tileSize, y: 24 * tileSize, perk: 'quickrevive', cost: 500, label: 'Quick Revive - 500', requiresDoor: 'door_lower'),
    PerkState(x: 20 * tileSize, y: 24 * tileSize, perk: 'staminup', cost: 2000, label: 'Stamin-Up - 2000', requiresDoor: 'door_lower'),
    PerkState(x: 27 * tileSize, y: 5 * tileSize, perk: 'doubletap', cost: 2000, label: 'Double Tap - 2000', requiresDoor: 'door_upper'),
  ];

  final mysteryBox = MysteryBoxState(
    x: 30 * tileSize, y: 4 * tileSize,
    requiresDoor: 'door_upper',
  );

  final packAPunch = PackAPunchState(
    x: 33 * tileSize, y: 4 * tileSize,
    requiresDoor: 'door_upper',
  );

  return BuiltMap(
    info: info,
    grid: grid,
    walls: walls,
    doors: doors,
    zombieSpawns: zombieSpawns,
    wallWeapons: wallWeapons,
    perkLocations: perkLocations,
    mysteryBox: mysteryBox,
    packAPunch: packAPunch,
  );
}

String _getRoom(int x, int y) {
  if (x >= 10 && x <= 22 && y >= 10 && y <= 20) return 'start';
  if (x >= 22 && x <= 30 && y >= 8 && y <= 22) return 'hallway';
  if (x >= 22 && x <= 35 && y >= 2 && y <= 8) return 'upper';
  if (x >= 8 && x <= 24 && y >= 20 && y <= 27) return 'lower';
  return 'start';
}
