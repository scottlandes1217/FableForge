# Hybrid World System Implementation

## Overview

A hybrid world system that combines:
- **Procedural infinite/open world** generated at runtime in Swift
- **Hand-authored TMX maps** for specific towns/dungeons/indoors
- **Player building**: end-users can place buildings/decorations persistently in the procedural world

## Architecture

### Core Components

1. **ChunkSystem.swift**: Core chunking infrastructure
   - `ChunkKey`: Identifies chunks by (x, y) coordinates
   - `ChunkData`: Complete chunk data (tiles, entities)
   - `ChunkDelta`: Player modifications (added/removed entities, tile overrides)
   - `ChunkManager`: Loads/unloads chunks around player, manages chunk lifecycle

2. **WorldGenerator.swift**: Deterministic procedural generation
   - Generates ground tiles (grass, water, dirt, stone)
   - Places trees, rocks, decorations procedurally
   - Respects TMX instance footprints (no overlap)
   - Supports "base + delta" model (regenerate base, apply player changes)

3. **PrefabFactory.swift**: Entity spawning
   - Creates sprites and physics bodies for entities
   - Supports multi-part entities (trees: trunk+canopy, buildings: base+roof)
   - Registered prefabs: `tree_oak_01`, `rock_stone_01`, `cabin_small_01`

4. **DeltaPersistence.swift**: Save/load player changes
   - Stores chunk deltas as JSON files in Documents/WorldDeltas/
   - Format: `chunk_X_Y.json`
   - Persists across app restarts

5. **TMXInstanceLoader.swift**: Mount TMX maps at world coordinates
   - Loads TMX files and renders them at specified world tile origins
   - Calculates bounds for collision/reservation
   - Integrates with chunk system

### Integration with GameScene

The system integrates into `GameScene` with:
- Chunk loading/unloading in `update()` loop
- Chunk boundary detection on player movement
- Works alongside existing Tiled map system (controlled by `useTiledMap` flag)

## File Structure

```
FableForge Shared/Systems/
├── ChunkSystem.swift        # Core chunk models and ChunkManager
├── WorldGenerator.swift     # Procedural generation logic
├── PrefabFactory.swift      # Entity spawning and rendering
├── DeltaPersistence.swift   # Save/load chunk deltas
└── TMXInstanceLoader.swift  # TMX instance mounting

GameScene.swift (modified)
├── Added: chunkManager, worldGenerator, deltaPersistence properties
├── Modified: setUpScene() - calls setupHybridWorldSystem() when useTiledMap=false
└── Modified: update() - checks chunk boundaries and loads/unloads chunks
```

## Configuration

### Enabling the Hybrid System

Set `useTiledMap = false` in GameScene to use chunk-based procedural generation:

```swift
var useTiledMap: Bool = false  // Use chunk-based procedural world
```

### World Seed

The world seed is set in `setUpScene()`:

```swift
let worldSeed = 12345  // Change this for different worlds
```

### Chunk Configuration

Default values in `ChunkManager`:
- `defaultChunkSize = 32` (32x32 tiles per chunk)
- `defaultLoadRadius = 3` (loads 7x7 chunks = 49 chunks total)

### TMX Instance Registration

TMX instances are registered in `setupHybridWorldSystem()`:

```swift
let townInstance = TMXInstance(
    fileName: "Town_01",  // TMX file name (without .tmx extension)
    worldTileOrigin: (x: 100, y: 100),  // World tile coordinates
    worldBounds: nil,  // Calculated automatically
    tiledMap: nil  // Loaded on demand
)
chunkManager?.registerTMXInstance(townInstance)
```

## Entity Prefabs

### Registered Prefabs

1. **tree_oak_01**: Oak tree with trunk (below player) and canopy (above player)
2. **rock_stone_01**: Stone rock decoration
3. **cabin_small_01**: Small cabin building (player buildable)

### Adding New Prefabs

Edit `PrefabFactory.registerDefaultPrefabs()` to add new prefab definitions:

```swift
registerPrefab(PrefabDefinition(
    id: "my_prefab_id",
    type: .building,
    parts: [
        PrefabPart(name: "base", gid: nil, assetName: nil, offset: .zero, size: CGSize(width: 64, height: 64), zOffset: 0),
        PrefabPart(name: "roof", gid: nil, assetName: nil, offset: CGPoint(x: 0, y: 32), size: CGSize(width: 64, height: 32), zOffset: 0)
    ],
    collisionShape: .rectangle(size: CGSize(width: 64, height: 64)),
    zPosition: 0
))
```

**TODO**: Set appropriate GIDs from tilesets for prefab parts (currently using fallback colors).

## Player Building

### Placing Entities

Use `ChunkManager.placeEntity()`:

```swift
let entity = ProceduralEntity(
    type: .building,
    prefabId: "cabin_small_01",
    position: player.position,  // World position
    rotation: 0,
    variant: nil
)

chunkManager?.placeEntity(entity, at: player.position)
```

The entity will be:
- Saved to the chunk's delta (persistent)
- Rendered immediately if chunk is loaded
- Regenerated on next chunk load (base + delta)

### Removing Entities

Use `ChunkManager.removeEntity()`:

```swift
let entityKey = EntityKey(chunkKey: chunkKey, entityIndex: index)
chunkManager?.removeEntity(entityKey)
```

## Coordinate System

### Tile Coordinates

- **World tiles**: Infinite grid starting at (0, 0)
- **Chunk coordinates**: Chunks at (chunkX, chunkY), each 32x32 tiles
- **Conversion**: `ChunkKey.fromWorldTile(x: 100, y: 100, chunkSize: 32)` → `ChunkKey(x: 3, y: 3)`

### SpriteKit Positions

- **Tile size**: Base 16px, scaled by 2.0 = 32px rendered
- **World position**: `worldX = tileX * tileSize`, `worldY = tileY * tileSize`
- **Origin**: Bottom-left corner (SpriteKit standard)

### Z-Ordering

- **Tiles**: zPosition = 0
- **Entities Below Player**: zPosition = 50 (trees, rocks, building bases)
- **Player**: zPosition = 100 (characterZPosition)
- **Entities Above Player**: zPosition = 150 (tree canopies, roofs)

## Collision Detection

### Current Status

Collision detection needs to be integrated with the chunk system. Currently:
- Tiled maps use `collisionMap: Set<String>` with "x,y" keys
- Procedural chunks need collision data from:
  - Ground tiles (water = non-walkable)
  - Entity physics bodies (trees, rocks, buildings)

### TODO: Collision Integration

1. Generate collision map from chunk tiles + entities
2. Update `canMoveToTiledMap()` to check chunk collision data
3. Merge chunk collision with TMX instance collision

## Testing Checklist

### Basic Functionality

- [ ] Set `useTiledMap = false` in GameScene
- [ ] Run app - world should generate procedurally
- [ ] Move player - chunks should load/unload around player
- [ ] Verify trees, rocks appear in world
- [ ] Verify ground tiles (grass, water, dirt) generate correctly

### TMX Instance

- [ ] Create or reference `Town_01.tmx` file
- [ ] Register instance at world tile (100, 100) in `setupHybridWorldSystem()`
- [ ] Walk to (100, 100) - TMX map should render
- [ ] Verify procedural objects don't spawn inside TMX instance

### Player Building

- [ ] Implement UI/button to place "cabin_small_01" at player position
- [ ] Place building - verify it appears immediately
- [ ] Reload app - building should persist
- [ ] Move away from chunk, return - building should still be there

### Persistence

- [ ] Place several buildings in different chunks
- [ ] Reload app
- [ ] Verify all buildings persist
- [ ] Check `Documents/WorldDeltas/` folder for JSON files

## Known Issues / TODOs

1. **Prefab GIDs**: Prefab definitions need actual GIDs from tilesets (currently using fallback colors)
2. **Collision Integration**: Chunk collision not integrated with movement system
3. **TMX Instance Loading**: `TMXInstanceLoader.renderInstance()` needs full implementation (object rendering placeholder)
4. **Y-Flip Offset**: TMX instances may need Y-flip adjustment for proper positioning
5. **Entity Removal**: UI for chopping trees/mining rocks not implemented
6. **Performance**: May need optimization for large load radius or many entities per chunk

## Migration Notes

### Backward Compatibility

The system is designed to work alongside the existing Tiled map system:
- `useTiledMap = true`: Uses existing `loadAndRenderTiledMap()` (no changes)
- `useTiledMap = false`: Uses new chunk-based system

### Existing Functionality Preserved

- TileManager: Unchanged (still used by chunk system)
- TiledMapParser: Unchanged (used by TMX instances)
- Player movement: Works with both systems
- Collision: Needs integration (see TODOs)

## Future Enhancements

1. **Biomes**: Add biome-based terrain generation (forest, desert, tundra)
2. **Roads**: Generate connecting roads between towns
3. **More Prefabs**: Expand prefab library (fences, wells, crops, etc.)
4. **Entity Interaction**: Chop trees, mine rocks, enter buildings
5. **Chunk Streaming**: Asynchronous chunk loading for better performance
6. **World Boundaries**: Optional world size limits
7. **Save/Load Optimization**: Compress deltas, batch operations
