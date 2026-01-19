//
//  ChunkSystem.swift
//  FableForge Shared
//
//  Hybrid World System: Chunk-based procedural generation with TMX instances and player building
//

import Foundation
import SpriteKit

// MARK: - ChunkKey

/// Unique identifier for a chunk in the infinite world
struct ChunkKey: Hashable, Codable {
    let x: Int  // Chunk X coordinate (in chunks, not tiles)
    let y: Int  // Chunk Y coordinate (in chunks, not tiles)
    
    /// Convert world tile coordinates to chunk coordinates
    static func fromWorldTile(x: Int, y: Int, chunkSize: Int) -> ChunkKey {
        let chunkX = x >= 0 ? x / chunkSize : (x - chunkSize + 1) / chunkSize
        let chunkY = y >= 0 ? y / chunkSize : (y - chunkSize + 1) / chunkSize
        return ChunkKey(x: chunkX, y: chunkY)
    }
    
    /// Convert world position (CGPoint) to chunk coordinates
    static func fromWorldPosition(_ position: CGPoint, chunkSize: Int, tileSize: CGFloat) -> ChunkKey {
        let tileX = Int(position.x / tileSize)
        let tileY = Int(position.y / tileSize)
        return fromWorldTile(x: tileX, y: tileY, chunkSize: chunkSize)
    }
    
    /// Get the world tile origin (bottom-left corner) of this chunk
    func worldTileOrigin(chunkSize: Int) -> (x: Int, y: Int) {
        return (x * chunkSize, y * chunkSize)
    }
    
    /// Get world position (CGPoint) of the chunk's bottom-left corner
    func worldPosition(chunkSize: Int, tileSize: CGFloat) -> CGPoint {
        let tileOrigin = worldTileOrigin(chunkSize: chunkSize)
        return CGPoint(x: CGFloat(tileOrigin.x) * tileSize, y: CGFloat(tileOrigin.y) * tileSize)
    }
}

// MARK: - EntityKey

/// Unique identifier for a procedural or placed entity
struct EntityKey: Hashable, Codable {
    let chunkKey: ChunkKey
    let entityIndex: Int  // Index within the chunk (0-based)
    
    /// Create a unique string key for persistence
    var stringKey: String {
        return "\(chunkKey.x),\(chunkKey.y),\(entityIndex)"
    }
}

// MARK: - ProceduralEntity

/// Represents a procedurally generated entity (tree, rock, building, etc.)
enum ProceduralEntityType: String, Codable {
    case tree
    case rock
    case building
    case decoration
    case chest
}

struct ProceduralEntity: Codable {
    let type: ProceduralEntityType
    let prefabId: String  // e.g., "tree_oak_01", "rock_stone_01", "cabin_small_01"
    let position: CGPoint  // World position
    let rotation: CGFloat  // Rotation in radians (default 0)
    let variant: Int?  // Optional variant index for visual variation
    
    /// Create an entity key for this entity (must know its index in the chunk)
    func entityKey(chunkKey: ChunkKey, index: Int) -> EntityKey {
        return EntityKey(chunkKey: chunkKey, entityIndex: index)
    }
}

// MARK: - ChunkDelta

/// Stores player modifications to a chunk (base + delta model)
struct ChunkDelta: Codable {
    var addedEntities: [ProceduralEntity] = []  // Player-placed entities
    var removedEntityKeys: Set<String> = []  // Chopped trees, mined rocks, etc.
    var tileOverrides: [String: Int] = [:]  // Optional: override specific tiles (key: "x,y", value: GID)
    
    /// Check if an entity key has been removed
    func isEntityRemoved(_ entityKey: EntityKey) -> Bool {
        return removedEntityKeys.contains(entityKey.stringKey)
    }
    
    /// Mark an entity as removed
    mutating func removeEntity(_ entityKey: EntityKey) {
        removedEntityKeys.insert(entityKey.stringKey)
    }
    
    /// Add a player-placed entity
    mutating func addEntity(_ entity: ProceduralEntity) {
        addedEntities.append(entity)
    }
}

// MARK: - ChunkData

/// Complete chunk data ready for rendering
class ChunkData {
    let chunkKey: ChunkKey
    let tiles: [[Int]]  // 2D array of GIDs for ground tiles (chunkSize x chunkSize)
    let entitiesBelow: [ProceduralEntity]  // Trees/rocks/walls (render below player)
    let entitiesAbove: [ProceduralEntity]  // Tree canopies/roofs (render above player)
    
    // SpriteKit nodes (set after rendering)
    var chunkNode: SKNode?  // Parent node containing all chunk content
    var tilesNode: SKNode?  // Container for tile sprites
    var entitiesBelowNode: SKNode?  // Container for entities below player
    var entitiesAboveNode: SKNode?  // Container for entities above player
    
    // TMX instance bounds (if this chunk contains a TMX instance)
    var tmxInstanceBounds: CGRect?  // World-space bounds of TMX instance(s) in this chunk
    
    init(chunkKey: ChunkKey, tiles: [[Int]], entitiesBelow: [ProceduralEntity], entitiesAbove: [ProceduralEntity]) {
        self.chunkKey = chunkKey
        self.tiles = tiles
        self.entitiesBelow = entitiesBelow
        self.entitiesAbove = entitiesAbove
    }
    
    /// Check if a world tile position is within this chunk's bounds
    func containsWorldTile(x: Int, y: Int, chunkSize: Int) -> Bool {
        let origin = chunkKey.worldTileOrigin(chunkSize: chunkSize)
        return x >= origin.x && x < origin.x + chunkSize &&
               y >= origin.y && y < origin.y + chunkSize
    }
}

// MARK: - ChunkManager

/// Manages loading/unloading chunks around the player
class ChunkManager {
    static let defaultChunkSize = 32  // 32x32 tiles per chunk
    static let defaultLoadRadius = 3  // Load chunks within 3 chunks of player
    
    private let chunkSize: Int
    private let loadRadius: Int
    private let tileSize: CGFloat
    private var loadedChunks: [ChunkKey: ChunkData] = [:]
    private weak var scene: SKScene?
    private var worldGenerator: WorldGenerator?
    private var deltaPersistence: DeltaPersistence?
    private var tmxInstances: [TMXInstance] = []  // Registered TMX instances
    
    init(chunkSize: Int = defaultChunkSize, loadRadius: Int = defaultLoadRadius, tileSize: CGFloat, scene: SKScene) {
        self.chunkSize = chunkSize
        self.loadRadius = loadRadius
        self.tileSize = tileSize
        self.scene = scene
    }
    
    /// Set the world generator for procedural generation
    func setWorldGenerator(_ generator: WorldGenerator) {
        self.worldGenerator = generator
    }
    
    /// Set the delta persistence for player changes
    func setDeltaPersistence(_ persistence: DeltaPersistence) {
        self.deltaPersistence = persistence
    }
    
    /// Register a TMX instance (town/dungeon) at a world position
    func registerTMXInstance(_ instance: TMXInstance) {
        tmxInstances.append(instance)
    }
    
    /// Update chunks based on player position
    /// Unloads chunks that are too far away, loads chunks that are nearby
    func updateChunks(around playerPosition: CGPoint) {
        guard let scene = scene else { return }
        
        let currentChunkKey = ChunkKey.fromWorldPosition(playerPosition, chunkSize: chunkSize, tileSize: tileSize)
        
        // Calculate which chunks should be loaded
        var chunksToLoad: Set<ChunkKey> = []
        for dy in -loadRadius...loadRadius {
            for dx in -loadRadius...loadRadius {
                let chunkKey = ChunkKey(x: currentChunkKey.x + dx, y: currentChunkKey.y + dy)
                chunksToLoad.insert(chunkKey)
            }
        }
        
        // Load chunks that are nearby but not yet loaded (async for performance)
        // Do this FIRST before unloading to prevent visible gaps
        let chunksNeedingLoad = chunksToLoad.subtracting(Set(loadedChunks.keys))
        for chunkKey in chunksNeedingLoad {
            loadChunkAsyncInternal(chunkKey)
        }
        
        // Unload chunks that are too far away, but only if they're beyond a buffer zone
        // This prevents black space when moving - only unload chunks that are clearly out of range
        let unloadBufferRadius = loadRadius + 1  // Add 1 chunk buffer to prevent premature unloading
        var chunksToKeep: Set<ChunkKey> = []
        for dy in -unloadBufferRadius...unloadBufferRadius {
            for dx in -unloadBufferRadius...unloadBufferRadius {
                let chunkKey = ChunkKey(x: currentChunkKey.x + dx, y: currentChunkKey.y + dy)
                chunksToKeep.insert(chunkKey)
            }
        }
        
        // Only unload chunks that are beyond the buffer radius
        let chunksToUnload = Set(loadedChunks.keys).subtracting(chunksToKeep)
        for chunkKey in chunksToUnload {
            unloadChunk(chunkKey)
        }
    }
    
    /// Async version of updateChunks with completion callback
    func updateChunksAsync(around playerPosition: CGPoint, completion: @escaping () -> Void) {
        guard let scene = scene else {
            completion()
            return
        }
        
        let currentChunkKey = ChunkKey.fromWorldPosition(playerPosition, chunkSize: chunkSize, tileSize: tileSize)
        
        // Calculate which chunks should be loaded
        var chunksToLoad: Set<ChunkKey> = []
        for dy in -loadRadius...loadRadius {
            for dx in -loadRadius...loadRadius {
                let chunkKey = ChunkKey(x: currentChunkKey.x + dx, y: currentChunkKey.y + dy)
                chunksToLoad.insert(chunkKey)
            }
        }
        
        // Load chunks that are nearby but not yet loaded (async)
        // Do this FIRST before unloading to prevent visible gaps
        let chunksNeedingLoad = chunksToLoad.subtracting(Set(loadedChunks.keys))
        
        if chunksNeedingLoad.isEmpty {
            // No chunks to load, but still need to unload old chunks
            let unloadBufferRadius = loadRadius + 1  // Add 1 chunk buffer to prevent premature unloading
            var chunksToKeep: Set<ChunkKey> = []
            for dy in -unloadBufferRadius...unloadBufferRadius {
                for dx in -unloadBufferRadius...unloadBufferRadius {
                    let chunkKey = ChunkKey(x: currentChunkKey.x + dx, y: currentChunkKey.y + dy)
                    chunksToKeep.insert(chunkKey)
                }
            }
            
            let chunksToUnload = Set(loadedChunks.keys).subtracting(chunksToKeep)
            for chunkKey in chunksToUnload {
                unloadChunk(chunkKey)
            }
            
            completion()
            return
        }
        
        // Use dispatch group to wait for all chunks to load
        let group = DispatchGroup()
        for chunkKey in chunksNeedingLoad {
            group.enter()
            loadChunkAsyncInternal(chunkKey) {
                group.leave()
            }
        }
        
        // Call completion when all chunks are loaded, then unload old chunks
        group.notify(queue: .main) {
            // Unload chunks that are too far away, but only if they're beyond a buffer zone
            let unloadBufferRadius = self.loadRadius + 1  // Add 1 chunk buffer to prevent premature unloading
            var chunksToKeep: Set<ChunkKey> = []
            for dy in -unloadBufferRadius...unloadBufferRadius {
                for dx in -unloadBufferRadius...unloadBufferRadius {
                    let chunkKey = ChunkKey(x: currentChunkKey.x + dx, y: currentChunkKey.y + dy)
                    chunksToKeep.insert(chunkKey)
                }
            }
            
            // Only unload chunks that are beyond the buffer radius
            let chunksToUnload = Set(self.loadedChunks.keys).subtracting(chunksToKeep)
            for chunkKey in chunksToUnload {
                self.unloadChunk(chunkKey)
            }
            
            completion()
        }
    }
    
    /// Load a chunk synchronously (for backwards compatibility)
    private func loadChunk(_ chunkKey: ChunkKey) {
        loadChunkAsyncInternal(chunkKey, completion: nil)
    }
    
    /// Load a chunk asynchronously (generate on background thread, render on main thread)
    private func loadChunkAsyncInternal(_ chunkKey: ChunkKey, completion: (() -> Void)? = nil) {
        guard let scene = scene, let generator = worldGenerator else {
            print("⚠️ ChunkManager: Cannot load chunk - missing scene or generator")
            completion?()
            return
        }
        
        // Check if chunk is already loaded (race condition protection)
        if loadedChunks[chunkKey] != nil {
            completion?()
            return
        }
        
        // Generate chunk data on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            
            // Load or create delta (I/O operation, can be slow)
            let delta = self.deltaPersistence?.loadDelta(for: chunkKey) ?? ChunkDelta()
            
            // Generate base chunk data (CPU-intensive)
            let baseChunkData = generator.generateChunk(chunkKey, chunkSize: self.chunkSize, tileSize: self.tileSize, delta: delta, tmxInstances: self.tmxInstances)
            
            // Render on main thread (SpriteKit requires main thread)
            DispatchQueue.main.async {
                // Double-check chunk wasn't loaded while we were generating (race condition)
                if self.loadedChunks[chunkKey] == nil {
                    // Store chunk data
                    self.loadedChunks[chunkKey] = baseChunkData
                    
                    // Render the chunk
                    self.renderChunk(baseChunkData)
                    
                    // Debug: Log chunk loading progress
                    let totalTiles = baseChunkData.tiles.flatMap { $0 }.filter { $0 > 0 }.count
                    print("✅ Loaded chunk (\(chunkKey.x), \(chunkKey.y)): \(totalTiles) ground tiles, \(baseChunkData.entitiesBelow.count) entities below, \(baseChunkData.entitiesAbove.count) entities above")
                }
                
                completion?()
            }
        }
    }
    
    /// Unload a chunk (remove from scene and memory)
    private func unloadChunk(_ chunkKey: ChunkKey) {
        guard let chunkData = loadedChunks[chunkKey] else { return }
        
        // Remove sprite nodes from scene
        chunkData.chunkNode?.removeFromParent()
        
        // Clear references
        chunkData.chunkNode = nil
        chunkData.tilesNode = nil
        chunkData.entitiesBelowNode = nil
        chunkData.entitiesAboveNode = nil
        
        // Remove from loaded chunks
        loadedChunks.removeValue(forKey: chunkKey)
    }
    
    /// Render a chunk's visual representation
    private func renderChunk(_ chunkData: ChunkData) {
        guard let scene = scene else { return }
        
        // Create parent node for this chunk
        let chunkNode = SKNode()
        chunkNode.name = "chunk_\(chunkData.chunkKey.x)_\(chunkData.chunkKey.y)"
        chunkNode.position = .zero  // Position tiles/entities relative to world coordinates
        scene.addChild(chunkNode)
        chunkData.chunkNode = chunkNode
        
        // Create sub-nodes for organization
        let tilesNode = SKNode()
        tilesNode.name = "tiles"
        tilesNode.zPosition = 0
        chunkNode.addChild(tilesNode)
        chunkData.tilesNode = tilesNode
        
        let entitiesBelowNode = SKNode()
        entitiesBelowNode.name = "entitiesBelow"
        entitiesBelowNode.zPosition = 40  // Below player (100) - character walks in front
        chunkNode.addChild(entitiesBelowNode)
        chunkData.entitiesBelowNode = entitiesBelowNode
        
        let entitiesAboveNode = SKNode()
        entitiesAboveNode.name = "entitiesAbove"
        entitiesAboveNode.zPosition = 110  // Above player (100) - character walks behind
        chunkNode.addChild(entitiesAboveNode)
        chunkData.entitiesAboveNode = entitiesAboveNode
        
        // Render tiles
        let origin = chunkData.chunkKey.worldTileOrigin(chunkSize: chunkSize)
        var tilesRendered = 0
        var tilesFailed = 0
        var gidCounts: [Int: Int] = [:]  // Track which GIDs are being used
        
        for (y, row) in chunkData.tiles.enumerated() {
            for (x, gid) in row.enumerated() {
                guard gid > 0 else { continue }  // Skip empty tiles
                
                // Track GID usage
                gidCounts[gid, default: 0] += 1
                
                // Calculate world position for seamless tiling
                // Each tile occupies exactly tileSize x tileSize space
                // Position tiles so they tile seamlessly without gaps
                let worldX = CGFloat(origin.x + x) * tileSize
                let worldY = CGFloat(origin.y + y) * tileSize
                
                // Create sprite with exact tile size
                guard tileSize > 0 && tileSize <= 256 else {
                    print("⚠️ ChunkSystem: Invalid tileSize \(tileSize), skipping tile at (\(x), \(y))")
                    continue
                }
                
                if let sprite = TileManager.shared.createSprite(for: gid, size: CGSize(width: tileSize, height: tileSize)) {
                    // CRITICAL: Ensure sprite is exactly tileSize for seamless tiling
                    sprite.size = CGSize(width: tileSize, height: tileSize)
                    
                    // CRITICAL FIX: Snap positions to pixel boundaries to prevent sub-pixel rendering gaps
                    // Round to nearest 0.5 pixel (half-pixel precision) to avoid floating-point precision errors
                    // This eliminates seams between tiles caused by sub-pixel rendering
                    let snappedX = round(worldX * 2.0) / 2.0
                    let snappedY = round(worldY * 2.0) / 2.0
                    
                    // Position at exact grid position (no gaps between tiles)
                    sprite.position = CGPoint(x: snappedX, y: snappedY)
                    sprite.anchorPoint = CGPoint(x: 0, y: 0)  // Bottom-left anchor - tile starts at position
                    sprite.zPosition = 0
                    
                    tilesNode.addChild(sprite)
                    tilesRendered += 1
                } else {
                    tilesFailed += 1
                    // Only log first few failures to avoid spam
                    if tilesFailed <= 5 {
                        print("⚠️ ChunkSystem: Failed to create sprite for GID \(gid) at chunk tile (\(x), \(y)), world tile (\(origin.x + x), \(origin.y + y))")
                    }
                }
            }
        }
        
        // Debug: Log chunk rendering summary
        if tilesRendered > 0 || tilesFailed > 0 {
            // Chunk rendered (debug log removed for performance)
            if !gidCounts.isEmpty {
                let topGIDs = gidCounts.sorted { $0.value > $1.value }.prefix(5)
                print("   Top GIDs used: \(topGIDs.map { "GID \($0.key): \($0.value)" }.joined(separator: ", "))")
            }
        }
        
        // Render entities below player
        // CORRECT: Low parts (trunk/bottom) go to entitiesBelow (zPosition 40, BEHIND player)
        //          High parts (canopy/top) go to entitiesAbove (zPosition 110, IN FRONT of player)
        renderEntities(chunkData.entitiesBelow, lowContainer: entitiesBelowNode, highContainer: entitiesAboveNode, tileSize: tileSize)
        
        // Render entities above player (only high parts, all go to entitiesAbove)
        renderEntities(chunkData.entitiesAbove, lowContainer: entitiesBelowNode, highContainer: entitiesAboveNode, tileSize: tileSize)
    }
    
    /// Render entities using PrefabFactory
    /// Properly separates low and high layer parts into appropriate containers
    /// CORRECT: Low parts (trunk/bottom) go to entitiesBelow (zPosition 40, BEHIND player)
    ///          High parts (canopy/top) go to entitiesAbove (zPosition 110, IN FRONT of player)
    private func renderEntities(_ entities: [ProceduralEntity], lowContainer: SKNode, highContainer: SKNode, tileSize: CGFloat) {
        for entity in entities {
            // Get sprites separated by layer
            let (lowSprites, highSprites) = PrefabFactory.shared.createEntitySpritesByLayer(entity, tileSize: tileSize)
            
            // Debug: Log layer assignment for trees
            if entity.type == .tree {
                print("🌳 Tree entity '\(entity.prefabId)': \(lowSprites.count) low sprites, \(highSprites.count) high sprites")
            }
            
            // Create container node for physics body (only needed if entity has collision)
            var physicsContainer: SKNode? = nil
            
            // CORRECT: Low parts (trunk/bottom) should be BEHIND player (zPosition 40)
            //          High parts (canopy/top) should be IN FRONT of player (zPosition 110)
            // Note: "low" in JSON = bottom/trunk, "high" in JSON = top/canopy
            
            // Low parts (trunk/bottom) go to lowContainer which is entitiesBelowNode (zPosition 40 = behind player)
            // CRITICAL: For trees, lowSprites are the TRUNK sprites (from "layer": "low" in JSON)
            if !lowSprites.isEmpty {
                // Create container for low parts (for physics body attachment)
                let lowEntityContainer = SKNode()
                lowEntityContainer.position = entity.position
                lowEntityContainer.name = "entity_\(entity.prefabId)_low"
                lowEntityContainer.zPosition = 0  // Inherit from parent (entitiesBelowNode has zPosition 40)
                
                // Add sprites to container, adjusting positions to be relative to container
                // CRITICAL: These sprites are the TRUNK sprites (lowSprites from "layer": "low")
                for sprite in lowSprites {
                    // Convert from world coordinates to container-relative coordinates
                    // Sprites were created at: entity.position + part.offset + tileOffset
                    // Trunk part has offset (0, 0), so sprites are at: entity.position + tileOffset
                    // After conversion: tileOffset (relative to container)
                    sprite.position = CGPoint(
                        x: sprite.position.x - entity.position.x,
                        y: sprite.position.y - entity.position.y
                    )
                    sprite.zPosition = 0  // Ensure sprites inherit container zPosition
                    lowEntityContainer.addChild(sprite)
                }
                
                // Add to entitiesBelow container (behind player)
                lowContainer.addChild(lowEntityContainer)
                // CRITICAL: Set physicsContainer to trunk container for trees
                // This ensures physics and debug boxes are on the trunk, not canopy
                physicsContainer = lowEntityContainer  // Use low container for physics
            }
            
            // High parts (canopy/top) go to highContainer which is entitiesAboveNode (zPosition 110 = in front of player)
            if !highSprites.isEmpty {
                // Create container for high parts
                let highEntityContainer = SKNode()
                highEntityContainer.position = entity.position
                highEntityContainer.name = "entity_\(entity.prefabId)_high"
                highEntityContainer.zPosition = 0  // Inherit from parent (entitiesAboveNode has zPosition 110)
                
                // Add sprites to container, adjusting positions to be relative to container
                for sprite in highSprites {
                    // Convert from world coordinates to container-relative coordinates
                    sprite.position = CGPoint(
                        x: sprite.position.x - entity.position.x,
                        y: sprite.position.y - entity.position.y
                    )
                    sprite.zPosition = 0  // Ensure sprites inherit container zPosition
                    highEntityContainer.addChild(sprite)
                }
                
                // Add to entitiesAbove container (in front of player)
                highContainer.addChild(highEntityContainer)
                
                // If no low container was created, use high container for physics
                if physicsContainer == nil {
                    physicsContainer = highEntityContainer
                }
            }
            
            // Add physics body to container (only once per entity)
            // IMPORTANT: For trees, physics should be on the LOW container (trunk), not high container (canopy)
            if let container = physicsContainer {
                // CRITICAL: For trees, verify we're using the LOW container (trunk), not high container (canopy)
                if entity.type == .tree {
                    let expectedLowContainerName = "entity_\(entity.prefabId)_low"
                    if container.name != expectedLowContainerName {
                        print("⚠️ ERROR: Tree physics body is being added to WRONG container!")
                        print("   Expected: '\(expectedLowContainerName)' (trunk)")
                        print("   Actual: '\(container.name ?? "unknown")'")
                        print("   This is a BUG - physics and debug boxes will be in wrong location!")
                        // Try to find the correct container
                        if let correctContainer = lowContainer.children.first(where: { ($0.name ?? "") == expectedLowContainerName }) {
                            print("   Found correct container: '\(correctContainer.name ?? "unknown")'")
                            // Use the correct container instead
                            // NOTE: We can't change container here because it's used later
                            // But we can log it for debugging
                        }
                    } else {
                        print("   ✅ Using correct trunk container: '\(container.name ?? "unknown")'")
                    }
                }
                
                if let physicsBody = PrefabFactory.shared.createPhysicsBody(entity, tileSize: tileSize) {
                    physicsBody.isDynamic = false
                    physicsBody.categoryBitMask = 0x1
                    physicsBody.collisionBitMask = 0xFFFFFFFF  // Collide with everything
                    physicsBody.contactTestBitMask = 0x0  // Don't need contact callbacks
                    
                    // Calculate collision box position based on actual sprite positions
                    // This ensures collision boxes align with visual sprites for ALL entity types
                    var collisionX: CGFloat = 0
                    var collisionY: CGFloat = 0
                    var bodySize: CGSize
                    
                    // Get collision size from prefab definition
                    let sourceTileSize: CGFloat = 16.0
                    let scale = tileSize / sourceTileSize
                    
                    if let prefab = PrefabFactory.shared.getPrefab(entity.prefabId) {
                        // Use the prefab's collision spec to get the correct size
                        switch prefab.collisionShape {
                        case .rectangle(let size):
                            bodySize = CGSize(width: size.width * scale, height: size.height * scale)
                        case .circle(let radius):
                            bodySize = CGSize(width: radius * 2 * scale, height: radius * 2 * scale)
                        case .none:
                            bodySize = CGSize(width: 32 * scale, height: 32 * scale) // Default
                        }
                    } else {
                        // Fallback if prefab not found
                        bodySize = CGSize(width: 48 * scale, height: 32 * scale)
                    }
                    
                    // Calculate bounding box from sprites in the container
                    // CRITICAL: Use the actual sprites IN THE CONTAINER, not the lowSprites array
                    // The container sprites have already been converted to container-relative coordinates
                    // at lines 491-502, so their positions are correct for bounding box calculation
                    let spritesToUse = container.children.compactMap { $0 as? SKSpriteNode }
                    
                    // Verify we have sprites and log container info
                    print("🔍 Container '\(container.name ?? "unknown")' has \(container.children.count) children (\(spritesToUse.count) sprites)")
                    if entity.type == .tree {
                        print("   Expected for tree: trunk sprites (low layer) in container")
                        print("   lowSprites count: \(lowSprites.count), container sprites: \(spritesToUse.count)")
                    }
                    
                    if !spritesToUse.isEmpty {
                        // Calculate bounding box from sprites
                        // Sprites use anchorPoint (0, 1) = top-left, so they extend down and right
                        var minX: CGFloat = CGFloat.greatestFiniteMagnitude
                        var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude
                        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
                        var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude
                        
                        print("🔍 Calculating collision box for entity '\(entity.prefabId)' using \(spritesToUse.count) sprites")
                        
                        for (index, sprite) in spritesToUse.enumerated() {
                            // Sprites use anchorPoint (0, 1) = top-left
                            // So sprite.position is the TOP-LEFT corner
                            let spriteLeft = sprite.position.x
                            let spriteRight = sprite.position.x + sprite.size.width
                            let spriteTop = sprite.position.y
                            let spriteBottom = sprite.position.y - sprite.size.height
                            
                            if entity.type == .tree && index < 3 {
                                print("   Tree sprite \(index): pos=(\(sprite.position.x), \(sprite.position.y)), size=(\(sprite.size.width), \(sprite.size.height)), bounds=(\(spriteLeft), \(spriteBottom)) to (\(spriteRight), \(spriteTop))")
                            }
                            
                            minX = min(minX, spriteLeft)
                            maxX = max(maxX, spriteRight)
                            minY = min(minY, spriteBottom)
                            maxY = max(maxY, spriteTop)
                        }
                        
                        print("   Sprite bounds: x=[\(minX), \(maxX)], y=[\(minY), \(maxY)]")
                        print("   Body size: \(bodySize)")
                        
                        // Position collision box at center-bottom of visual sprites
                        collisionX = (minX + maxX) / 2
                        // Position at bottom: since physics body is centered, position its center
                        // at minY + bodySize.height/2 so its bottom edge aligns with sprite bottom
                        // For trees, ensure collision is at the base of the trunk
                        if entity.type == .tree {
                            // For trees, position collision box bottom at minY (bottom of trunk sprites)
                            // Physics body is centered, so position center at minY + bodySize.height/2
                            collisionY = minY + bodySize.height / 2
                            print("   Tree collision Y calculation: minY=\(minY), bodyHeight=\(bodySize.height), collisionY=\(collisionY) (center of box, bottom at \(collisionY - bodySize.height/2))")
                        } else {
                            // For other entities, same calculation
                            collisionY = minY + bodySize.height / 2
                        }
                        
                        print("   Collision box position (local): (\(collisionX), \(collisionY))")
                        print("   Container position: (\(container.position.x), \(container.position.y))")
                        print("   Collision box position (world): (\(container.position.x + collisionX), \(container.position.y + collisionY))")
                        
                        // Create physics node and position it
                        let physicsNode = SKNode()
                        physicsNode.position = CGPoint(x: collisionX, y: collisionY)
                        physicsNode.physicsBody = physicsBody
                        container.addChild(physicsNode)
                    } else {
                        // No sprites found - fallback to attaching directly to container
                        container.physicsBody = physicsBody
                    }
                } else {
                    // Debug: Log when physics body creation fails
                    if entity.type == .tree {
                        print("⚠️ Failed to create physics body for tree '\(entity.prefabId)'")
                    }
                }
            } else if entity.type == .tree {
                print("⚠️ No physics container created for tree '\(entity.prefabId)' (no sprites?)")
            }
        }
    }
    
    /// Get a loaded chunk
    func getChunk(_ chunkKey: ChunkKey) -> ChunkData? {
        return loadedChunks[chunkKey]
    }
    
    /// Check if a chunk is currently loaded
    func isChunkLoaded(_ chunkKey: ChunkKey) -> Bool {
        return loadedChunks[chunkKey] != nil
    }
    
    /// Pre-load a chunk asynchronously (for pre-loading ahead of player movement)
    func loadChunkAsync(_ chunkKey: ChunkKey, completion: (() -> Void)? = nil) {
        // Check if already loaded
        if loadedChunks[chunkKey] != nil {
            completion?()
            return
        }
        
        // Delegate to private async loader
        loadChunkAsyncInternal(chunkKey, completion: completion)
    }
    
    /// Get all currently loaded chunk keys (for cleanup)
    func getAllLoadedChunkKeys() -> [ChunkKey] {
        return Array(loadedChunks.keys)
    }
    
    /// Unload all chunks (for transitions)
    func unloadAllChunks() {
        let keysToUnload = Array(loadedChunks.keys)
        for key in keysToUnload {
            unloadChunk(key)
        }
    }
    
    /// Place an entity at a world position (player building)
    func placeEntity(_ entity: ProceduralEntity, at position: CGPoint) -> Bool {
        let chunkKey = ChunkKey.fromWorldPosition(position, chunkSize: chunkSize, tileSize: tileSize)
        
        // Save delta
        var delta = deltaPersistence?.loadDelta(for: chunkKey) ?? ChunkDelta()
        delta.addEntity(entity)
        deltaPersistence?.saveDelta(delta, for: chunkKey)
        
        // Reload chunk if it's currently loaded
        if isChunkLoaded(chunkKey) {
            unloadChunk(chunkKey)
            loadChunk(chunkKey)
        }
        
        return true
    }
    
    /// Remove an entity (chop tree, mine rock, etc.)
    func removeEntity(_ entityKey: EntityKey) -> Bool {
        let chunkKey = entityKey.chunkKey
        
        // Save delta
        var delta = deltaPersistence?.loadDelta(for: chunkKey) ?? ChunkDelta()
        delta.removeEntity(entityKey)
        deltaPersistence?.saveDelta(delta, for: chunkKey)
        
        // Reload chunk if it's currently loaded
        if isChunkLoaded(chunkKey) {
            unloadChunk(chunkKey)
            loadChunk(chunkKey)
        }
        
        return true
    }
}
