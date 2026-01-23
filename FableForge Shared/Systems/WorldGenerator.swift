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
    private static var hasLoggedGroundTiles = false  // Track if we've already logged ground tiles loading
    
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
        // Dictionary to store chest contents (entity key -> items)
        var chestContents: [EntityKey: [Item]] = [:]
        // Reset RNG with chunk-specific seed for deterministic generation
        // Combine world seed with chunk coordinates
        let chunkSeed = combineSeeds(worldSeed, chunkX: Int64(chunkKey.x), chunkY: Int64(chunkKey.y))
        var chunkRNG = SeededRandomNumberGenerator(seed: chunkSeed)
        
        // Generate ground tiles and terrain map
        let (tiles, terrainMap) = generateGroundTiles(chunkKey: chunkKey, chunkSize: chunkSize, rng: &chunkRNG)
        
        // Generate terrain decorations (placed on top of ground tiles)
        let decorations = generateDecorations(chunkKey: chunkKey, chunkSize: chunkSize, terrainMap: terrainMap, rng: &chunkRNG)
        
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
            terrainMap: terrainMap,
            delta: delta,
            rng: &chunkRNG,
            chestContents: &chestContents
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
        
        let chunkData = ChunkData(chunkKey: chunkKey, tiles: tiles, terrainMap: terrainMap, decorations: decorations, entitiesBelow: entitiesBelow, entitiesAbove: entitiesAbove)
        
        // Store chest contents in ChunkData
        chunkData.chestContents = chestContents
        
        return chunkData
    }
    
    /// Generate ground tiles for a chunk with autotiling support
    /// Returns tuple: (tile specs, terrain map) where tile specs are strings (GID specs or sprite atlas specs)
    private func generateGroundTiles(chunkKey: ChunkKey, chunkSize: Int, rng: inout SeededRandomNumberGenerator) -> ([[String]], [[TerrainType]]) {
        let origin = chunkKey.worldTileOrigin(chunkSize: chunkSize)
        
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
                water: configTiles.water ?? [],
                grass: configTiles.grass ?? [],
                dirt: configTiles.dirt ?? [],
                stone: configTiles.stone ?? [],
                waterVariants: configTiles.waterVariants,
                grassVariants: configTiles.grassVariants,
                dirtVariants: configTiles.dirtVariants,
                stoneVariants: configTiles.stoneVariants
            )
            
            // Debug logging: Show what ground tiles were loaded (only once to avoid spam)
            if !WorldGenerator.hasLoggedGroundTiles {
                print("🔍 WorldGenerator: Loaded ground tiles from config:")
                print("   water: \(groundTiles.water)")
                print("   grass: \(groundTiles.grass)")
                print("   dirt: \(groundTiles.dirt)")
                print("   stone: \(groundTiles.stone)")
                if let grassVariants = groundTiles.grassVariants {
                    print("   grassVariants.base: \(grassVariants.base ?? [])")
                }
                WorldGenerator.hasLoggedGroundTiles = true
            }
        } else {
            // Fallback to PrefabFactory defaults
            groundTiles = PrefabFactory.shared.getGroundTileGIDs()
            if !WorldGenerator.hasLoggedGroundTiles {
                print("⚠️ WorldGenerator: No config tiles found, using PrefabFactory defaults")
                WorldGenerator.hasLoggedGroundTiles = true
            }
        }
        
        // Step 1: Generate terrain type map (what terrain each tile is)
        var terrainMap: [[TerrainType]] = []
        for y in 0..<chunkSize {
            var row: [TerrainType] = []
            for x in 0..<chunkSize {
                let worldTileX = origin.x + x
                let worldTileY = origin.y + y
                
                // Use tile coordinates for noise/variation
                let noiseValue = generateNoise(x: worldTileX, y: worldTileY, rng: &rng)
                
                // Map noise to terrain type
                let terrainType: TerrainType
                if noiseValue < waterThreshold {
                    terrainType = .water
                } else if noiseValue < grassThreshold {
                    terrainType = .grass
                } else if noiseValue < dirtThreshold {
                    terrainType = .dirt
                } else {
                    terrainType = .stone
                }
                
                row.append(terrainType)
            }
            terrainMap.append(row)
        }
        
        // Step 2: Apply autotiling to determine tile variants
        var tiles: [[String]] = []
        // Track last used tile spec for consecutive selection (per terrain type)
        var lastUsedTileSpecs: [TerrainType: String] = [:]
        
        for y in 0..<chunkSize {
            var row: [String] = []
            for x in 0..<chunkSize {
                let terrainType = terrainMap[y][x]
                
                // Build neighbor mask for autotiling
                let neighborMask = TerrainAutotiling.buildNeighborMask(
                    x: x,
                    y: y,
                    terrainType: terrainType,
                    terrainMap: terrainMap,
                    width: chunkSize,
                    height: chunkSize
                )
                
                // Determine tile variant based on neighbors
                let variant = TerrainAutotiling.getTileVariant(
                    terrain: terrainType,
                    neighbors: neighborMask
                )
                
                // Get tile spec for this terrain type and variant
                // Pass last used tile spec for this terrain type to maintain visual continuity
                let lastUsedSpec = lastUsedTileSpecs[terrainType]
                var tileSpec = groundTiles.getTileSpec(for: terrainType, variant: variant, lastUsedTileSpec: lastUsedSpec, using: &rng)
                
                // Debug logging for first few tiles of each type
                if (x < 3 && y < 3) || (x == chunkSize / 2 && y == chunkSize / 2) {
                    print("🔍 WorldGenerator: terrainType=\(terrainType), variant=\(variant) -> tileSpec=\(tileSpec ?? "nil")")
                }
                
                // Fallback if tile spec is invalid
                if tileSpec == nil || tileSpec?.isEmpty == true {
                    // Fallback to base terrain tile if spec is invalid
                    let fallbackSpecs: [String]
                    switch terrainType {
                    case .water: fallbackSpecs = groundTiles.water
                    case .grass: fallbackSpecs = groundTiles.grass
                    case .dirt: fallbackSpecs = groundTiles.dirt
                    case .stone: fallbackSpecs = groundTiles.stone
                    }
                    if !fallbackSpecs.isEmpty {
                        let index = Int.random(in: 0..<fallbackSpecs.count, using: &rng)
                        tileSpec = fallbackSpecs[index]
                        if (x < 3 && y < 3) || (x == chunkSize / 2 && y == chunkSize / 2) {
                            print("   ⚠️ Used fallback: \(tileSpec!) from \(terrainType) array")
                        }
                    }
                }
                
                // Use fallback if still nil
                let finalTileSpec = tileSpec ?? "exterior-257"
                row.append(finalTileSpec)  // Default fallback
                
                // Update last used tile spec for this terrain type (for consecutive selection)
                lastUsedTileSpecs[terrainType] = finalTileSpec
                
                // Debug logging for first few tiles
                if (x < 3 && y < 3) || (x == chunkSize / 2 && y == chunkSize / 2) {
                    print("   ✅ Final tileSpec for chunk tile (\(x), \(y)): '\(finalTileSpec)'")
                }
            }
            tiles.append(row)
        }
        
        return (tiles, terrainMap)
    }
    
    /// Generate terrain decorations (placed on top of ground tiles)
    /// Returns dictionary mapping tile positions "x,y" to decoration tile specs
    private func generateDecorations(chunkKey: ChunkKey, chunkSize: Int, terrainMap: [[TerrainType]], rng: inout SeededRandomNumberGenerator) -> [String: String] {
        var decorations: [String: String] = [:]
        let origin = chunkKey.worldTileOrigin(chunkSize: chunkSize)
        
        // Get decoration config from world config
        guard let terrainConfig = config?.terrain,
              let decorationConfigs = terrainConfig.groundTiles.decorations else {
            return decorations  // No decorations configured
        }
        
        // Process each decoration configuration
        for decorationConfig in decorationConfigs {
            // Get terrain types this decoration can appear on
            let allowedTerrainTypes = decorationConfig.terrainTypes
            let allowOnEdges = decorationConfig.allowOnEdges ?? false
            
            // Check if this decoration should appear on each tile
            for y in 0..<chunkSize {
                for x in 0..<chunkSize {
                    // Skip edge tiles if not allowed
                    if !allowOnEdges && (x == 0 || x == chunkSize - 1 || y == 0 || y == chunkSize - 1) {
                        continue
                    }
                    
                    // Get terrain type for this tile
                    let terrainType = terrainMap[y][x]
                    let terrainTypeString = terrainTypeToString(terrainType)
                    
                    // Check if decoration can appear on this terrain type
                    guard allowedTerrainTypes.contains(terrainTypeString) else {
                        continue
                    }
                    
                    // Roll for decoration placement based on density
                    let roll = Double.random(in: 0...1, using: &rng)
                    if roll < decorationConfig.density {
                        // Place decoration - pick random tile from available options
                        let decorationTiles = decorationConfig.tileGIDs
                        guard !decorationTiles.isEmpty else { continue }
                        
                        let tileIndex = Int.random(in: 0..<decorationTiles.count, using: &rng)
                        let decorationTileSpec = decorationTiles[tileIndex]
                        
                        // Store decoration at this position
                        let worldX = origin.x + x
                        let worldY = origin.y + y
                        let positionKey = "\(worldX),\(worldY)"
                        decorations[positionKey] = decorationTileSpec
                    }
                }
            }
        }
        
        return decorations
    }
    
    /// Convert TerrainType enum to string for matching with JSON config
    private func terrainTypeToString(_ terrainType: TerrainType) -> String {
        switch terrainType {
        case .water: return "water"
        case .grass: return "grass"
        case .dirt: return "dirt"
        case .stone: return "stone"
        }
    }
    
    /// Generate procedural entities (trees, rocks, decorations)
    private func generateProceduralEntities(
        chunkKey: ChunkKey,
        chunkSize: Int,
        tileSize: CGFloat,
        reservedTiles: Set<String>,
        terrainMap: [[TerrainType]],
        delta: ChunkDelta,
        rng: inout SeededRandomNumberGenerator,
        chestContents: inout [EntityKey: [Item]]
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
        let treeBlockedTerrainTypes = entityConfig?.treeBlockedTerrainTypes ?? []
        let rockBlockedTerrainTypes = entityConfig?.rockBlockedTerrainTypes ?? []
        
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
            
            // Check terrain type - skip if blocked
            if localY >= 0 && localY < terrainMap.count && localX >= 0 && localX < terrainMap[localY].count {
                let terrainType = terrainMap[localY][localX]
                let terrainTypeString = terrainTypeToString(terrainType)
                if treeBlockedTerrainTypes.contains(terrainTypeString) {
                    continue
                }
            }
            
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
            
            // Check terrain type - skip if blocked
            if localY >= 0 && localY < terrainMap.count && localX >= 0 && localX < terrainMap[localY].count {
                let terrainType = terrainMap[localY][localX]
                let terrainTypeString = terrainTypeToString(terrainType)
                if rockBlockedTerrainTypes.contains(terrainTypeString) {
                    continue
                }
            }
            
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
                        let blockedTerrainTypes = chestConfig.blockedTerrainTypes ?? []
                        
                        for dy in 0..<chestHeight {
                            for dx in 0..<chestWidth {
                                let checkX = origin.x + localX + dx
                                let checkY = origin.y + localY + dy
                                let tileKey = "\(checkX),\(checkY)"
                                
                                if occupiedTiles.contains(tileKey) || reservedTiles.contains(tileKey) {
                                    canPlace = false
                                    break
                                }
                                
                                // Check terrain type - skip if blocked
                                let checkLocalX = localX + dx
                                let checkLocalY = localY + dy
                                if checkLocalY >= 0 && checkLocalY < terrainMap.count && checkLocalX >= 0 && checkLocalX < terrainMap[checkLocalY].count {
                                    let terrainType = terrainMap[checkLocalY][checkLocalX]
                                    let terrainTypeString = terrainTypeToString(terrainType)
                                    if blockedTerrainTypes.contains(terrainTypeString) {
                                        canPlace = false
                                        break
                                    }
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
                                // Generate chest contents if not already generated for this chest
                                // Check if chest contents exist in delta (persistent across reloads)
                                // For now, generate fresh each time (we can add persistence later)
                                let chestItems = PrefabFactory.shared.generateChestLoot(for: chestPrefab)
                                
                                // Store chest contents (will be added to ChunkData later)
                                chestContents[entityKey] = chestItems
                                
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
