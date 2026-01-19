//
//  WorldGenerator.swift
//  FableForge Shared
//
//  Deterministic procedural world generation
//

import Foundation
import SpriteKit

/// Deterministic world generator for procedural chunks
class WorldGenerator {
    let worldSeed: UInt64
    private var rng: SeededRandomNumberGenerator
    private var config: WorldConfig?
    
    init(seed: Int, config: WorldConfig? = nil) {
        self.worldSeed = UInt64(seed)
        self.rng = SeededRandomNumberGenerator(seed: self.worldSeed)
        self.config = config
    }
    
    /// Update world configuration (for switching between worlds)
    func setConfig(_ config: WorldConfig?) {
        self.config = config
    }
    
    /// Generate a chunk's base data (before applying deltas)
    func generateChunk(_ chunkKey: ChunkKey, chunkSize: Int, tileSize: CGFloat, delta: ChunkDelta, tmxInstances: [TMXInstance]) -> ChunkData {
        // Reset RNG with chunk-specific seed for deterministic generation
        // Combine world seed with chunk coordinates
        let chunkSeed = combineSeeds(worldSeed, chunkX: Int64(chunkKey.x), chunkY: Int64(chunkKey.y))
        var chunkRNG = SeededRandomNumberGenerator(seed: chunkSeed)
        
        // Generate ground tiles
        let tiles = generateGroundTiles(chunkKey: chunkKey, chunkSize: chunkSize, rng: &chunkRNG)
        
        // Generate procedural entities
        var entitiesBelow: [ProceduralEntity] = []
        var entitiesAbove: [ProceduralEntity] = []
        
        // Check which tiles are reserved by TMX instances
        let reservedTiles = getReservedTiles(for: chunkKey, chunkSize: chunkSize, tileSize: tileSize, tmxInstances: tmxInstances)
        
        // Generate trees, rocks, etc.
        let proceduralEntities = generateProceduralEntities(
            chunkKey: chunkKey,
            chunkSize: chunkSize,
            tileSize: tileSize,
            reservedTiles: reservedTiles,
            delta: delta,
            rng: &chunkRNG
        )
        
        // Separate entities by z-ordering requirements
        // NOTE: Trees and buildings have both low and high parts, but we keep them as SINGLE entities
        // The rendering system (ChunkSystem) will split the parts by layer automatically
        for entity in proceduralEntities {
            switch entity.type {
            case .tree, .building:
                // Trees and buildings: Keep as single entity, rendering system will split parts by layer
                // Low parts (trunk/walls) go to entitiesBelow container (zPosition 40, behind player)
                // High parts (canopy/roof) go to entitiesAbove container (zPosition 110, in front of player)
                // But we put the entity in entitiesBelow so low parts render correctly
                entitiesBelow.append(entity)
            case .rock, .decoration, .chest:
                // Rocks, decorations, and chests only have a low layer (single part)
                entitiesBelow.append(entity)
            }
        }
        
        // Apply player-placed entities from delta
        // Keep entities as single entities - rendering system will handle layer splitting
        for addedEntity in delta.addedEntities {
            entitiesBelow.append(addedEntity)
        }
        
        return ChunkData(chunkKey: chunkKey, tiles: tiles, entitiesBelow: entitiesBelow, entitiesAbove: entitiesAbove)
    }
    
    /// Generate ground tiles for a chunk
    private func generateGroundTiles(chunkKey: ChunkKey, chunkSize: Int, rng: inout SeededRandomNumberGenerator) -> [[Int]] {
        var tiles: [[Int]] = []
        let origin = chunkKey.worldTileOrigin(chunkSize: chunkSize)
        
        // Simple terrain generation: mostly grass with some variation
        for y in 0..<chunkSize {
            var row: [Int] = []
            for x in 0..<chunkSize {
                let worldTileX = origin.x + x
                let worldTileY = origin.y + y
                
                // Use tile coordinates for noise/variation
                let noiseValue = generateNoise(x: worldTileX, y: worldTileY, rng: &rng)
                
                // Map noise to tile types using world config (or defaults)
                let terrainConfig = config?.terrain
                let waterThreshold = terrainConfig?.waterThreshold ?? 0.15
                let grassThreshold = terrainConfig?.grassThreshold ?? 0.9
                let dirtThreshold = terrainConfig?.dirtThreshold ?? 0.95
                
                // Get ground tile GIDs from config or PrefabFactory fallback
                let groundTiles: GroundTileGIDs
                if let configTiles = terrainConfig?.groundTiles {
                    // Use world-specific ground tiles
                    groundTiles = GroundTileGIDs(
                        water: configTiles.water,
                        grass: configTiles.grass,
                        dirt: configTiles.dirt,
                        stone: configTiles.stone
                    )
                } else {
                    // Fallback to PrefabFactory defaults
                    groundTiles = PrefabFactory.shared.getGroundTileGIDs()
                }
                
                var gid: Int = 0
                
                // Water areas (low noise values)
                if noiseValue < waterThreshold {
                    gid = groundTiles.randomGID(for: .water, using: &rng)
                }
                // Grass (most common)
                else if noiseValue < grassThreshold {
                    gid = groundTiles.randomGID(for: .grass, using: &rng)
                }
                // Dirt patches
                else if noiseValue < dirtThreshold {
                    gid = groundTiles.randomGID(for: .dirt, using: &rng)
                }
                // Stone patches
                else {
                    gid = groundTiles.randomGID(for: .stone, using: &rng)
                }
                
                // Validate GID is positive (GIDs can come from different tilesets)
                // Note: ground_grass_details is 1-378, but other tilesets may have different ranges
                // We'll let TileManager.validate if the GID exists
                if gid <= 0 {
                    // Fallback to a grass tile if GID is invalid
                    // Use randomGID to parse the string format correctly
                    gid = groundTiles.randomGID(for: .grass, using: &rng)
                }
                
                row.append(gid)
            }
            tiles.append(row)
        }
        
        return tiles
    }
    
    /// Generate procedural entities (trees, rocks, decorations)
    private func generateProceduralEntities(
        chunkKey: ChunkKey,
        chunkSize: Int,
        tileSize: CGFloat,
        reservedTiles: Set<String>,
        delta: ChunkDelta,
        rng: inout SeededRandomNumberGenerator
    ) -> [ProceduralEntity] {
        var entities: [ProceduralEntity] = []
        let origin = chunkKey.worldTileOrigin(chunkSize: chunkSize)
        
        // Track occupied tiles to avoid overlap
        var occupiedTiles: Set<String> = reservedTiles
        
        // Get entity config (or use defaults)
        let entityConfig = config?.entities
        let treeDensity = entityConfig?.treeDensity ?? 0.02
        let rockDensity = entityConfig?.rockDensity ?? 0.005
        let treePrefabs = entityConfig?.treePrefabs ?? ["tree_oak_01"]
        let rockPrefabs = entityConfig?.rockPrefabs ?? ["rock_stone_01"]
        
        // Generate trees (scattered)
        let numTrees = Int(Double(chunkSize * chunkSize) * treeDensity)
        
        for _ in 0..<numTrees {
            let localX = Int.random(in: 0..<chunkSize, using: &rng)
            let localY = Int.random(in: 0..<chunkSize, using: &rng)
            let worldX = origin.x + localX
            let worldY = origin.y + localY
            let tileKey = "\(worldX),\(worldY)"
            
            // Skip if tile is reserved or occupied
            if occupiedTiles.contains(tileKey) { continue }
            
            // Check if entity was removed by player
            let entityIndex = entities.count
            let entityKey = EntityKey(chunkKey: chunkKey, entityIndex: entityIndex)
            if delta.isEntityRemoved(entityKey) { continue }
            
            // Pick tree prefab from config (or default) using seeded RNG
            let treePrefabId = treePrefabs.isEmpty ? "tree_oak_01" : treePrefabs[Int.random(in: 0..<treePrefabs.count, using: &rng)]
            
            // Place tree
            let worldPos = CGPoint(x: CGFloat(worldX) * tileSize + tileSize / 2, y: CGFloat(worldY) * tileSize + tileSize / 2)
            entities.append(ProceduralEntity(
                type: .tree,
                prefabId: treePrefabId,
                position: worldPos,
                rotation: 0,
                variant: Int.random(in: 0..<3, using: &rng)
            ))
            
            // Mark tile and neighbors as occupied (trees take 1 tile, but mark neighbors to avoid clustering)
            occupiedTiles.insert(tileKey)
            for dy in -1...1 {
                for dx in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    let neighborX = worldX + dx
                    let neighborY = worldY + dy
                    occupiedTiles.insert("\(neighborX),\(neighborY)")
                }
            }
        }
        
        // Generate rocks (less dense)
        let numRocks = Int(Double(chunkSize * chunkSize) * rockDensity)
        
        for _ in 0..<numRocks {
            let localX = Int.random(in: 0..<chunkSize, using: &rng)
            let localY = Int.random(in: 0..<chunkSize, using: &rng)
            let worldX = origin.x + localX
            let worldY = origin.y + localY
            let tileKey = "\(worldX),\(worldY)"
            
            if occupiedTiles.contains(tileKey) { continue }
            
            let entityIndex = entities.count
            let entityKey = EntityKey(chunkKey: chunkKey, entityIndex: entityIndex)
            if delta.isEntityRemoved(entityKey) { continue }
            
            // Pick rock prefab from config (or default) using seeded RNG
            let rockPrefabId = rockPrefabs.isEmpty ? "rock_stone_01" : rockPrefabs[Int.random(in: 0..<rockPrefabs.count, using: &rng)]
            
            let worldPos = CGPoint(x: CGFloat(worldX) * tileSize + tileSize / 2, y: CGFloat(worldY) * tileSize + tileSize / 2)
            entities.append(ProceduralEntity(
                type: .rock,
                prefabId: rockPrefabId,
                position: worldPos,
                rotation: CGFloat.random(in: 0..<(2 * .pi), using: &rng),
                variant: Int.random(in: 0..<2, using: &rng)
            ))
            
            occupiedTiles.insert(tileKey)
        }
        
        // Generate chests (from world config)
        if let chestConfigs = entityConfig?.chests {
            for chestConfig in chestConfigs {
                let chestCount = chestConfig.count
                let chestPrefabId = chestConfig.chestId
                
                // Verify chest prefab exists
                guard PrefabFactory.shared.getChestPrefab(chestPrefabId) != nil else {
                    print("⚠️ WorldGenerator: Chest prefab '\(chestPrefabId)' not found, skipping")
                    continue
                }
                
                // Get chest prefab to determine size for collision
                let chestPrefab = PrefabFactory.shared.getChestPrefab(chestPrefabId)!
                let chestWidth = Int(ceil(chestPrefab.size.width / tileSize))
                let chestHeight = Int(ceil(chestPrefab.size.height / tileSize))
                
                // Spawn specified number of chests
                for _ in 0..<chestCount {
                    var attempts = 0
                    var placed = false
                    
                    // Try up to 50 times to find a valid placement
                    while !placed && attempts < 50 {
                        let localX = Int.random(in: 0..<chunkSize, using: &rng)
                        let localY = Int.random(in: 0..<chunkSize, using: &rng)
                        
                        // Check if all tiles for chest are available
                        var canPlace = true
                        var chestTiles: Set<String> = []
                        
                        for dy in 0..<chestHeight {
                            for dx in 0..<chestWidth {
                                let checkX = origin.x + localX + dx
                                let checkY = origin.y + localY + dy
                                let tileKey = "\(checkX),\(checkY)"
                                
                                if occupiedTiles.contains(tileKey) || reservedTiles.contains(tileKey) {
                                    canPlace = false
                                    break
                                }
                                chestTiles.insert(tileKey)
                            }
                            if !canPlace { break }
                        }
                        
                        if canPlace {
                            // Place chest
                            let worldX = origin.x + localX
                            let worldY = origin.y + localY
                            let worldPos = CGPoint(
                                x: CGFloat(worldX) * tileSize + tileSize / 2,
                                y: CGFloat(worldY) * tileSize + tileSize / 2
                            )
                            
                            let entityIndex = entities.count
                            let entityKey = EntityKey(chunkKey: chunkKey, entityIndex: entityIndex)
                            
                            // Check if entity was removed by player
                            if !delta.isEntityRemoved(entityKey) {
                                entities.append(ProceduralEntity(
                                    type: .chest,
                                    prefabId: chestPrefabId,
                                    position: worldPos,
                                    rotation: 0,
                                    variant: nil
                                ))
                                
                                // Mark all tiles as occupied
                                for tileKey in chestTiles {
                                    occupiedTiles.insert(tileKey)
                                }
                                
                                placed = true
                            }
                        }
                        
                        attempts += 1
                    }
                    
                    if !placed {
                        print("⚠️ WorldGenerator: Could not place chest '\(chestPrefabId)' in chunk \(chunkKey.x),\(chunkKey.y) after \(attempts) attempts")
                    }
                }
            }
        }
        
        return entities
    }
    
    /// Get set of reserved tile keys for TMX instances
    private func getReservedTiles(for chunkKey: ChunkKey, chunkSize: Int, tileSize: CGFloat, tmxInstances: [TMXInstance]) -> Set<String> {
        var reserved: Set<String> = []
        let chunkBounds = CGRect(
            x: CGFloat(chunkKey.x * chunkSize) * tileSize,
            y: CGFloat(chunkKey.y * chunkSize) * tileSize,
            width: CGFloat(chunkSize) * tileSize,
            height: CGFloat(chunkSize) * tileSize
        )
        
        for instance in tmxInstances {
            // Check if instance overlaps with this chunk
            if let instanceBounds = instance.worldBounds {
                if chunkBounds.intersects(instanceBounds) {
                    // Mark tiles covered by instance as reserved
                    let minTileX = Int(instanceBounds.minX / tileSize)
                    let maxTileX = Int(instanceBounds.maxX / tileSize)
                    let minTileY = Int(instanceBounds.minY / tileSize)
                    let maxTileY = Int(instanceBounds.maxY / tileSize)
                    
                    for tileY in minTileY...maxTileY {
                        for tileX in minTileX...maxTileX {
                            reserved.insert("\(tileX),\(tileY)")
                        }
                    }
                }
            }
        }
        
        return reserved
    }
    
    /// Simple 2D noise function for terrain variation
    private func generateNoise(x: Int, y: Int, rng: inout SeededRandomNumberGenerator) -> Double {
        // Simple hash-based noise (can be improved with proper noise functions)
        // Handle negative coordinates using bit pattern conversion
        let xUInt = UInt64(bitPattern: Int64(x))
        let yUInt = UInt64(bitPattern: Int64(y))
        let hash = xUInt &* 73856093 &+ yUInt &* 19349663
        let seed = combineSeeds(worldSeed, hash)
        var localRNG = SeededRandomNumberGenerator(seed: seed)
        return Double.random(in: 0...1, using: &localRNG)
    }
    
    /// Combine multiple seeds into one
    /// Handles negative chunk coordinates by converting to unsigned using bitwise operations
    private func combineSeeds(_ seed1: UInt64, chunkX: Int64, chunkY: Int64) -> UInt64 {
        var combined = seed1
        
        // Convert signed Int64 to UInt64 using bit pattern (handles negative values)
        // This preserves uniqueness: negative chunks get different seeds than positive chunks
        let chunkXUInt = UInt64(bitPattern: chunkX)
        let chunkYUInt = UInt64(bitPattern: chunkY)
        
        combined = combined &* 1103515245 &+ chunkXUInt
        combined = combined &* 1103515245 &+ chunkYUInt
        return combined
    }
    
    private func combineSeeds(_ seed1: UInt64, _ seed2: UInt64) -> UInt64 {
        return seed1 &* 1103515245 &+ seed2
    }
}
