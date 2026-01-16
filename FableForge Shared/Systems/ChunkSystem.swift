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
            print("📊 Chunk (\(chunkData.chunkKey.x), \(chunkData.chunkKey.y)) rendered: \(tilesRendered) tiles, \(tilesFailed) failed")
            if !gidCounts.isEmpty {
                let topGIDs = gidCounts.sorted { $0.value > $1.value }.prefix(5)
                print("   Top GIDs used: \(topGIDs.map { "GID \($0.key): \($0.value)" }.joined(separator: ", "))")
            }
        }
        
        // Render entities below player
        renderEntities(chunkData.entitiesBelow, in: entitiesBelowNode, tileSize: tileSize)
        
        // Render entities above player
        renderEntities(chunkData.entitiesAbove, in: entitiesAboveNode, tileSize: tileSize)
    }
    
    /// Render entities using PrefabFactory
    private func renderEntities(_ entities: [ProceduralEntity], in container: SKNode, tileSize: CGFloat) {
        let containerName = container.name ?? "unknown"
        let containerZPos = container.zPosition
        for entity in entities {
            let sprites = PrefabFactory.shared.createEntitySprites(entity, tileSize: tileSize)
            for sprite in sprites {
                container.addChild(sprite)
                
                // Add physics body if needed (for collision)
                if let physicsBody = PrefabFactory.shared.createPhysicsBody(entity, tileSize: tileSize) {
                    physicsBody.isDynamic = false  // Static collision
                    physicsBody.categoryBitMask = 0x1  // Collision category (can be customized)
                    sprite.physicsBody = physicsBody
                }
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
