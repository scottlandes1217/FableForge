//
//  GameScene_Collision.swift
//  FableForge Shared
//
//  Collision detection functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    // MARK: - Collision Detection for Tiled Maps
    
    /// Parse collision data from Tiled map layers
    /// Uses layer properties to determine collision:
    /// - Layers with property "collision" = true are used for collision
    /// - Layers without the "collision" property are walkable (collision = false by default)
    /// - Only layers with explicit "collision" = true property will block movement
    func parseCollisionFromTiledMap(_ tiledMap: TiledMap, tileSize: CGSize, yFlipOffset: CGFloat) {
        collisionMap.removeAll()
        collisionLayerMap.removeAll()
        layerProperties.removeAll()
        
        var foundLayers: [String] = []
        var allLayerNames: [String] = []
        
        // First, log all available layers
        for layer in tiledMap.layers {
            allLayerNames.append(layer.name)
        }
        
        // First, find max height of regular layers (for coordinate conversion)
        var maxRegularHeight = 0
        for layer in tiledMap.layers {
            if !layer.isInfinite {
                maxRegularHeight = max(maxRegularHeight, layer.height)
            }
        }
        
        for layer in tiledMap.layers {
            // Store layer properties for door detection
            layerProperties[layer.name] = layer.properties
            
            // Check if this layer has a collision property
            let hasCollisionProperty = layer.properties.keys.contains("collision")
            
            // Only use layers that explicitly have collision = true property
            // If property is not set, the layer is walkable (not collision)
            if !hasCollisionProperty {
                // No collision property = walkable layer (skip)
                continue
            }
            
            // Layer has collision property - check its value
            let isCollisionLayer = layer.boolProperty("collision", default: false)
            
            if isCollisionLayer {
                foundLayers.append(layer.name)
                print("✅ Found collision layer: \(layer.name) (via property: collision = true)")
                
                // Process chunks for infinite maps
                if layer.isInfinite, let chunks = layer.chunks {
                    for chunk in chunks {
                        var index = 0
                        for y in 0..<chunk.height {
                            for x in 0..<chunk.width {
                                guard index < chunk.data.count else { break }
                                
                                let gid = chunk.data[index]
                                index += 1
                                
                                // GID > 0 means there's a tile (non-walkable)
                                if gid > 0 {
                                    // Store tile position as tile coordinates for collision checking
                                    // These are Tiled tile coordinates (chunk.x + x, chunk.y + y)
                                    let tileX = chunk.x + x
                                    let tileY = chunk.y + y
                                    let key = "\(tileX),\(tileY)"
                                    collisionMap.insert(key)
                                    
                                    // Store which layer this collision tile came from
                                    // If multiple layers contribute to same tile, keep the first one
                                    if collisionLayerMap[key] == nil {
                                        collisionLayerMap[key] = layer.name
                                    }
                                    
                                    // Debug: Log first few collision tiles to verify parsing
                                    if collisionMap.count <= 10 {
                                    }
                                }
                            }
                        }
                    }
                } else if let data = layer.data {
                    // Process regular (non-infinite) maps
                    // Regular layers: tile at (x, y) in Tiled coords is at worldY = (layer.height - y - 1) * tileHeight
                    // Store using actual Tiled coordinates (x, y)
                    var index = 0
                    for y in 0..<layer.height {
                        for x in 0..<layer.width {
                            guard index < data.count else { break }
                            
                            let gid = data[index]
                            index += 1
                            
                            if gid > 0 {
                                // Store using actual Tiled coordinates
                                let key = "\(x),\(y)"
                                collisionMap.insert(key)
                                
                                // Store which layer this collision tile came from
                                if collisionLayerMap[key] == nil {
                                    collisionLayerMap[key] = layer.name
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if foundLayers.isEmpty {
        }
    }
    
    /// Update the collision debug overlay to show the collision box
    private func updateCollisionDebugOverlay() {
        guard let player = gameState?.player else { return }
        
        let collisionFrame = getPlayerCollisionFrame(at: player.position)
        
        // Remove existing overlay
        collisionDebugOverlay?.removeFromParent()
        
        // Create new overlay - use rectOf with size and position at center
        let overlay = SKShapeNode(rectOf: collisionFrame.size)
        overlay.strokeColor = .red
        overlay.fillColor = .clear
        overlay.lineWidth = 2.0
        overlay.position = CGPoint(x: collisionFrame.midX, y: collisionFrame.midY)
        overlay.zPosition = 12  // Above player sprite (zPosition 11)
        overlay.name = "collisionDebugOverlay"
        addChild(overlay)
        collisionDebugOverlay = overlay
    }
    
    /// Get the player's collision bounding box from the sprite's actual size
    /// Uses a collision box that matches the character width and is about knee height
    /// This allows the player to get closer to walls and multi-tile objects
    /// Assumes center anchor point (SpriteKit default: 0.5, 0.5)
    func getPlayerCollisionFrame(at position: CGPoint) -> CGRect {
        // Collision box is as wide as the character (sprite is 96x96, use ~24px wide for reasonable collision)
        // and about knee height (10px tall)
        let collisionSize = CGSize(width: 13, height: 12)
        let halfWidth = collisionSize.width / 2
        let halfHeight = collisionSize.height / 2
        // Offset collision box downward to position it around the feet/knees
        // Sprite is 96x96, centered at position
        // Feet are at approximately position.y - 48
        // To position collision box near feet (center around position.y - 42):
        let collisionYOffset: CGFloat = 42.0  // Move collision box down to position around feet
        return CGRect(origin: CGPoint(x: position.x - halfWidth, y: position.y - halfHeight - collisionYOffset), size: collisionSize)
    }
    
    /// Check if player can move to a position on Tiled map
    /// Check if player can move to a position in the procedural world (using physics bodies)
    func canMoveToProceduralWorld(position: CGPoint) -> Bool {
        // Get player's collision frame at target position
        let playerFrame = getPlayerCollisionFrame(at: position)
        
        // Check if any physics bodies intersect with the player's bounding box
        // Use enumerateBodies(in:) to find all physics bodies in the player's area
        var hasCollision = false
        var collisionNode: SKNode? = nil
        
        physicsWorld.enumerateBodies(in: playerFrame) { body, stop in
            // Skip if this is the player's physics body
            if let node = body.node, node == self.playerSprite {
                return
            }
            
            // Check if this is an entity collision body (categoryBitMask 0x1)
            if body.categoryBitMask == 0x1 && !body.isDynamic {
                // This is a static entity (tree, rock, etc.) - collision detected
                hasCollision = true
                collisionNode = body.node
                stop.pointee = true  // Stop enumeration
            }
        }
        
        // If collision detected, identify and log the entity
        if hasCollision, let node = collisionNode {
            // CRITICAL: If auto-walking to a chest and we collide with that chest, trigger completion
            if isAutoWalking, let targetChestNode = autoWalkTargetNode {
                // Check if the collision node is the target chest (or a child/parent of it)
                var isTargetChest = false
                var checkNode: SKNode? = node
                var depth = 0
                while let current = checkNode, depth < 5 {
                    if current == targetChestNode {
                        isTargetChest = true
                        break
                    }
                    checkNode = current.parent
                    depth += 1
                }
                
                // Also check children of target chest
                if !isTargetChest {
                    func checkChildren(_ parent: SKNode) -> Bool {
                        for child in parent.children {
                            if child == node {
                                return true
                            }
                            if checkChildren(child) {
                                return true
                            }
                        }
                        return false
                    }
                    isTargetChest = checkChildren(targetChestNode)
                }
                
                if isTargetChest {
                    print("✅ Auto-walk: Collided with target chest - will trigger completion in update loop")
                    // The update loop will detect the collision intersection and trigger completion
                    // Just return false to prevent movement
                    return false
                }
            }
            
            print("🛑 Movement blocked by entity collision at position (\(Int(position.x)), \(Int(position.y)))")
            
            // Try to identify what kind of entity this is
            var entityInfo: String = "Unknown entity"
            var entityDetails: [String] = []
            
            // Check if it's a sprite node we can identify
            if let sprite = node as? SKSpriteNode {
                // Check if it's an animal
                if let animal = animalSprites[sprite] {
                    entityInfo = "Animal: \(animal.name)"
                    entityDetails.append("Type: \(animal.type.rawValue)")
                    entityDetails.append("HP: \(animal.hitPoints)/\(animal.maxHitPoints)")
                    entityDetails.append("Position: (\(Int(sprite.position.x)), \(Int(sprite.position.y)))")
                }
                // Check if it's an enemy
                else if let enemy = enemySprites[sprite] {
                    entityInfo = "Enemy: \(enemy.name)"
                    entityDetails.append("HP: \(enemy.hitPoints)/\(enemy.maxHitPoints)")
                    entityDetails.append("AC: \(enemy.armorClass)")
                    entityDetails.append("Position: (\(Int(sprite.position.x)), \(Int(sprite.position.y)))")
                }
                // Check if it's an object (TiledObject)
                else if let object = objectSprites[sprite] {
                    entityInfo = "Object: '\(object.name)'"
                    entityDetails.append("ID: \(object.id)")
                    if let type = object.type, !type.isEmpty {
                        entityDetails.append("Type: '\(type)'")
                    }
                    if let objectGroupName = objectGroupNames[sprite] {
                        entityDetails.append("ObjectGroup: '\(objectGroupName)'")
                    }
                    entityDetails.append("Position: (\(Int(object.x)), \(Int(object.y)))")
                    entityDetails.append("Size: \(Int(object.width))x\(Int(object.height))")
                    if let gid = object.gid {
                        entityDetails.append("GID: \(gid)")
                    }
                    if !object.properties.isEmpty {
                        entityDetails.append("Properties: \(object.properties)")
                    }
                }
                // Check if it's a chest
                else if let chestData = chestSprites[node] {
                    entityInfo = "Chest"
                    entityDetails.append("Prefab ID: \(chestData.prefabId)")
                    entityDetails.append("Entity Key: \(chestData.entityKey)")
                    entityDetails.append("Position: (\(Int(chestData.position.x)), \(Int(chestData.position.y)))")
                }
                // Check sprite name for clues
                else if let spriteName = sprite.name {
                    entityInfo = "Sprite: '\(spriteName)'"
                    entityDetails.append("Node type: \(type(of: sprite))")
                    entityDetails.append("Position: (\(Int(sprite.position.x)), \(Int(sprite.position.y)))")
                }
                else {
                    entityInfo = "Sprite node"
                    entityDetails.append("Node type: \(type(of: sprite))")
                    entityDetails.append("Position: (\(Int(sprite.position.x)), \(Int(sprite.position.y)))")
                }
            }
            // Not a sprite, check if it's a named node
            else if let nodeName = node.name {
                entityInfo = "Node: '\(nodeName)'"
                entityDetails.append("Node type: \(type(of: node))")
                entityDetails.append("Position: (\(Int(node.position.x)), \(Int(node.position.y)))")
            }
            else {
                // Check if this is a physics node inside a container (procedural entities)
                // Physics nodes are often children of entity containers
                if let parent = node.parent {
                    let parentName = parent.name ?? "unnamed"
                    
                    // Try to identify entity from container name
                    // Container names follow pattern: "entity_<prefabId>_low" or "entity_<prefabId>_high" or "chest_entity_<prefabId>"
                    var prefabId: String? = nil
                    var entityType: String? = nil
                    
                    if parentName.hasPrefix("chest_entity_") {
                        entityType = "Chest"
                        prefabId = String(parentName.dropFirst(13)) // "chest_entity_".count = 13
                        
                        // NOTE: We no longer auto-open chests on physics collision
                        // Chests should only open when explicitly clicked by the user
                        // This prevents opening the wrong chest when clicking on a distant chest
                        // while standing near another chest
                    } else if parentName.hasPrefix("entity_") && parentName.contains("_low") {
                        entityType = "Procedural Entity (low layer)"
                        let parts = parentName.replacingOccurrences(of: "_low", with: "")
                        prefabId = String(parts.dropFirst(7)) // "entity_".count = 7
                    } else if parentName.hasPrefix("entity_") && parentName.contains("_high") {
                        entityType = "Procedural Entity (high layer)"
                        let parts = parentName.replacingOccurrences(of: "_high", with: "")
                        prefabId = String(parts.dropFirst(7)) // "entity_".count = 7
                    } else if parentName.hasPrefix("entity_") {
                        entityType = "Procedural Entity"
                        prefabId = String(parentName.dropFirst(7)) // "entity_".count = 7
                    }
                    
                    // Check userData for entity information (chests store this)
                    if let userData = parent.userData {
                        if let storedType = userData["entityType"] as? String {
                            entityType = storedType.capitalized
                        }
                        if let storedPrefabId = userData["prefabId"] as? String {
                            prefabId = storedPrefabId
                        }
                    }
                    
                    // Build entity info
                    if let type = entityType, let id = prefabId {
                        entityInfo = "\(type): '\(id)'"
                    } else if let id = prefabId {
                        entityInfo = "Procedural Entity: '\(id)'"
                    } else {
                        entityInfo = "Physics node in container: '\(parentName)'"
                    }
                    
                    entityDetails.append("Container name: '\(parentName)'")
                    entityDetails.append("Node type: \(type(of: node))")
                    entityDetails.append("Parent type: \(type(of: parent))")
                    entityDetails.append("Node position: (\(Int(node.position.x)), \(Int(node.position.y)))")
                    entityDetails.append("Parent position: (\(Int(parent.position.x)), \(Int(parent.position.y)))")
                    if let id = prefabId {
                        entityDetails.append("Prefab ID: '\(id)'")
                    }
                    
                    // Check parent's children for sprites that might identify the entity
                    let sprites = parent.children.compactMap { $0 as? SKSpriteNode }
                    if !sprites.isEmpty {
                        entityDetails.append("Container contains \(sprites.count) sprite(s)")
                        // Try to identify entity type from sprite names or textures
                        for (index, sprite) in sprites.enumerated() {
                            if index < 3 {  // Log first 3 sprites
                                let spriteName = sprite.name ?? "unnamed"
                                let hasTexture = sprite.texture != nil
                                let textureSize = sprite.texture != nil ? sprite.texture!.size() : CGSize.zero
                                entityDetails.append("  Sprite \(index + 1): '\(spriteName)', texture: \(hasTexture ? "\(Int(textureSize.width))x\(Int(textureSize.height))" : "none")")
                            }
                        }
                    }
                }
                else {
                    entityInfo = "Unknown node"
                    entityDetails.append("Node type: \(type(of: node))")
                    entityDetails.append("Position: (\(Int(node.position.x)), \(Int(node.position.y)))")
                    entityDetails.append("No parent found")
                }
            }
            
            // Log the entity information
            print("   📦 Collision with: \(entityInfo)")
            for detail in entityDetails {
                print("      - \(detail)")
            }
            
            // Also log physics body info for debugging
            if let body = node.physicsBody {
                print("      - Physics body categoryBitMask: \(body.categoryBitMask)")
                print("      - Physics body collisionBitMask: \(body.collisionBitMask)")
                print("      - Physics body contactTestBitMask: \(body.contactTestBitMask)")
                print("      - Is dynamic: \(body.isDynamic)")
            }
        }
        
        return !hasCollision
    }
    
    func canMoveToTiledMap(position: CGPoint) -> Bool {
        // If collision map is empty, allow movement (collision not set up)
        guard !collisionMap.isEmpty else {
            return true  // No collision data, allow free movement
        }
        
        // Convert world position to tile coordinates
        // Use the stored tile size from rendering (must match rendering calculation exactly)
        let tileWidth = mapTileSize.width
        let tileHeight = mapTileSize.height
        let yFlipOffset = mapYFlipOffset
        
        // Get player's bounding box from sprite's actual frame
        let playerFrame = getPlayerCollisionFrame(at: position)
        
        // Player bounding box corners (in world coordinates)
        let playerLeft = playerFrame.minX
        let playerRight = playerFrame.maxX
        let playerBottom = playerFrame.minY
        let playerTop = playerFrame.maxY
        
        // Convert to Tiled tile coordinates
        // X is the same for both coordinate systems
        let minTileX = Int(floor(playerLeft / tileWidth))
        let maxTileX = Int(floor(playerRight / tileWidth))
        
        // Y coordinate conversion depends on layer type
        let (minTileY, maxTileY): (Int, Int)
        if hasInfiniteLayers {
            // Infinite layers (chunks): 
            // Tiles are rendered at: worldY = yFlipOffset - tiledY, where tiledY = tileY * tileHeight
            // Tile at tileY has bottom at worldY = yFlipOffset - (tileY * tileHeight)
            // Tile at tileY has top at worldY = yFlipOffset - (tileY * tileHeight) + tileHeight
            // To find which tiles the player overlaps:
            // - Player top (highest Y) overlaps tiles whose bottom is <= playerTop
            // - Player bottom (lowest Y) overlaps tiles whose top is >= playerBottom
            // Converting: tileY = (yFlipOffset - worldY) / tileHeight
            // For playerTop: find tiles with tileY >= (yFlipOffset - playerTop) / tileHeight
            // For playerBottom: find tiles with tileY <= (yFlipOffset - playerBottom) / tileHeight
            // But we need to account for tile height - tile at tileY spans from (yFlipOffset - tileY*tileHeight) to (yFlipOffset - tileY*tileHeight + tileHeight)
            // So for player at worldY, we check tileY where: (yFlipOffset - tileY*tileHeight) <= worldY < (yFlipOffset - tileY*tileHeight + tileHeight)
            // Solving: tileY = floor((yFlipOffset - worldY) / tileHeight)
            // But we need to check all tiles that overlap, so:
            // Convert player world Y coordinates to Tiled tile Y coordinates
            // Tiles are rendered at: worldY = yFlipOffset - (tileY * tileHeight)
            // Tile at tileY spans from worldY = yFlipOffset - (tileY * tileHeight) to worldY = yFlipOffset - (tileY * tileHeight) + tileHeight
            // To find which tile contains a worldY: tileY = (yFlipOffset - worldY) / tileHeight
            // But we need to account for the tile's full height when checking overlap
            // If collision is 20px too high, we need to adjust by checking tiles that are 20px lower
            // 20px / 32px per tile = 0.625 tiles, so we need to subtract ~1 from tileY
            let playerTiledYTop = (yFlipOffset - playerTop) / tileHeight
            let playerTiledYBottom = (yFlipOffset - playerBottom) / tileHeight
            // Convert to tile coordinates
            // Collision is detected 20px too high, so we need to check tiles that are 20px lower
            // Since higher tileY = lower worldY, we need to ADD 1 to tileY (20px ≈ 1 tile at 32px/tile)
            let rawMinTileY = Int(floor(min(playerTiledYTop, playerTiledYBottom))) + 1
            let rawMaxTileY = Int(floor(max(playerTiledYTop, playerTiledYBottom))) + 1
            minTileY = rawMinTileY
            maxTileY = rawMaxTileY
        } else {
            // Regular layers: worldY = (layer.height - y - 1) * tileHeight
            // So: y = layer.height - 1 - (worldY / tileHeight)
            // But wait - regular layers position at worldY = (layer.height - y - 1) * tileHeight
            // This means y=0 (top row) is at worldY = (layer.height - 1) * tileHeight (highest Y)
            // And y=layer.height-1 (bottom row) is at worldY = 0 (lowest Y)
            // To convert worldY back: y = layer.height - 1 - Int(worldY / tileHeight)
            let height = regularLayerHeight
            if height > 0 {
                let regularYTop = height - 1 - Int(floor(playerTop / tileHeight))
                let regularYBottom = height - 1 - Int(floor(playerBottom / tileHeight))
                minTileY = min(regularYTop, regularYBottom)
                maxTileY = max(regularYTop, regularYBottom)
            } else {
                // Fallback: use chunk-style conversion if height not set
                let playerLeftTiledY = yFlipOffset - playerTop
                let playerRightTiledY = yFlipOffset - playerBottom
                minTileY = Int(floor(playerLeftTiledY / tileHeight))
                maxTileY = Int(floor(playerRightTiledY / tileHeight))
            }
        }
        
        // Debug: Print collision check details (only first few times to avoid spam)
        collisionDebugCount += 1
        if collisionDebugCount <= 10 {
            // Collision check (debug log removed for performance)
            // Check a few sample keys and print what we're checking
            for tileX in minTileX...min(maxTileX, minTileX + 2) {
                for tileY in minTileY...min(maxTileY, minTileY + 2) {
                    let key = "\(tileX),\(tileY)"
                    let hasColl = collisionMap.contains(key)
                    print("  Checking tile (\(tileX), \(tileY)): key='\(key)', found=\(hasColl)")
                    if hasColl {
                        print("  ✅ Found collision at tile (\(tileX), \(tileY))")
                    }
                }
            }
        }
        
        // Check all tiles that the player's bounding box overlaps
        // Use precise rectangle intersection instead of just tile membership
        // This allows the player to fit through narrow gaps even if the collision box
        // is in a tile that contains a collision tile, as long as it doesn't actually overlap
        var hasCollision = false
        var collisionKey: String? = nil
        var collisionLayer: String? = nil
        
        for tileX in minTileX...maxTileX {
            for tileY in minTileY...maxTileY {
                let key = "\(tileX),\(tileY)"
                if collisionMap.contains(key) {
                    // Calculate the collision tile's world rectangle
                    // Tiles are positioned based on their bottom-left corner
                    let tileWorldX = CGFloat(tileX) * tileWidth
                    let tileWorldY: CGFloat
                    if hasInfiniteLayers {
                        // Infinite layers: tile at tileY has bottom at worldY = yFlipOffset - (tileY * tileHeight)
                        let tileTiledY = CGFloat(tileY) * tileHeight
                        tileWorldY = yFlipOffset - tileTiledY
                    } else {
                        // Regular layers: tile at tileY (0 = top row) is at worldY = (height - 1 - tileY) * tileHeight
                        let height = regularLayerHeight
                        if height > 0 {
                            tileWorldY = CGFloat(height - 1 - tileY) * tileHeight
                        } else {
                            // Fallback
                            let tileTiledY = CGFloat(tileY) * tileHeight
                            tileWorldY = yFlipOffset - tileTiledY
                        }
                    }
                    let tileRect = CGRect(x: tileWorldX, y: tileWorldY, width: tileWidth, height: tileHeight)
                    
                    // Check if the player's collision box intersects the collision tile
                    // This is a standard rectangle intersection check
                    if playerFrame.intersects(tileRect) {
                    hasCollision = true
                    collisionKey = key
                    collisionLayer = collisionLayerMap[key]
                    // Always log collisions with debug info
                        print("🚫 COLLISION! Player at world=(\(Int(position.x)), \(Int(position.y)))")
                        print("   Player collision box: (\(String(format: "%.1f", playerLeft)),\(String(format: "%.1f", playerBottom)))-\(String(format: "%.1f", playerRight)),\(String(format: "%.1f", playerTop))) size=\(String(format: "%.1f", playerFrame.width))x\(String(format: "%.1f", playerFrame.height))")
                        print("   Collision tile=(\(tileX), \(tileY)) at world=(\(String(format: "%.1f", tileWorldX)),\(String(format: "%.1f", tileWorldY))) size=\(String(format: "%.1f", tileWidth))x\(String(format: "%.1f", tileHeight))")
                        print("   Tile rect: (\(String(format: "%.1f", tileRect.minX)),\(String(format: "%.1f", tileRect.minY)))-\(String(format: "%.1f", tileRect.maxX)),\(String(format: "%.1f", tileRect.maxY)))")
                        print("   Layer=\(collisionLayer ?? "unknown")")
                        
                        // Find objects at this collision position
                        var foundObjects: [(TiledObject, String)] = [] // (object, objectGroupName)
                        for (sprite, object) in objectSprites {
                            // Check if object sprite overlaps with the collision tile
                            // Use the sprite's actual frame for accurate collision detection
                            let objectFrame = sprite.frame
                            
                            // Check if object rectangle intersects with collision tile
                            if tileRect.intersects(objectFrame) {
                                let objectGroupName = objectGroupNames[sprite] ?? "unknown"
                                foundObjects.append((object, objectGroupName))
                            }
                        }
                        
                        // Log object information if found
                        if foundObjects.isEmpty {
                            print("   📦 No objects found at collision tile")
                        } else {
                            print("   📦 Found \(foundObjects.count) object(s) at collision tile:")
                            for (index, (object, objectGroupName)) in foundObjects.enumerated() {
                                print("      [\(index + 1)] Object ID: \(object.id)")
                                print("          Name: '\(object.name)'")
                                if let type = object.type, !type.isEmpty {
                                    print("          Type: '\(type)'")
                                }
                                print("          ObjectGroup: '\(objectGroupName)'")
                                print("          Position: (\(String(format: "%.1f", object.x)), \(String(format: "%.1f", object.y)))")
                                print("          Size: \(String(format: "%.1f", object.width))x\(String(format: "%.1f", object.height))")
                                if let gid = object.gid {
                                    print("          GID: \(gid)")
                                }
                                if !object.properties.isEmpty {
                                    print("          Properties: \(object.properties)")
                                }
                            }
                        }
                    break
                    }
                }
            }
            if hasCollision { break }
        }
        
        return !hasCollision
    }
    
    /// Find a safe spawn point near the given position (not in a collision tile)
    func findSafeSpawnPoint(near position: CGPoint) -> CGPoint? {
        guard !collisionMap.isEmpty else {
            // No collision data, any position is safe
            return position
        }
        
        let tileWidth = mapTileSize.width
        let tileHeight = mapTileSize.height
        
        // Convert starting position to tile coordinates
        let startTileX = Int(floor(position.x / tileWidth))
        let startTileY = Int(floor((mapYFlipOffset - position.y) / tileHeight))
        
        // Debug: log starting position for search
        print("   🔍 Starting safe spawn search from world position (\(Int(position.x)), \(Int(position.y))) -> tile (\(startTileX), \(startTileY))")
        
        // Helper to check if a tile coordinate is safe (not in collision map)
        // This checks the center tile AND adjacent tiles that the player's collision box might overlap
        // Player collision box is 13px wide, so it can span multiple tiles
        func isSafeTile(_ tileX: Int, _ tileY: Int) -> Bool {
            // Check the center tile
            let centerKey = "\(tileX),\(tileY)"
            if collisionMap.contains(centerKey) {
                return false
            }
            
            // Also check horizontal neighbors since player collision box is 13px wide (tiles are 32px)
            // The collision box can overlap with adjacent tiles when positioned at tile center
            let leftKey = "\(tileX - 1),\(tileY)"
            let rightKey = "\(tileX + 1),\(tileY)"
            if collisionMap.contains(leftKey) || collisionMap.contains(rightKey) {
                // If adjacent tiles are collision, this position might not be safe
                // But we'll let canMoveToTiledMap make the final decision since it checks the actual collision box
                // For now, return true to allow canMoveToTiledMap to check
            }
            
            return true
        }
        
        // Convert tile coordinates back to world position (center of tile)
        func tileToWorld(_ tileX: Int, _ tileY: Int) -> CGPoint {
            let worldX = CGFloat(tileX) * tileWidth + tileWidth / 2
            let tiledY = CGFloat(tileY) * tileHeight
            let worldY = mapYFlipOffset - tiledY - tileHeight / 2
            return CGPoint(x: worldX, y: worldY)
        }
        
        // Helper to check if a world position is walkable
        func isWalkableWorldPosition(_ worldPos: CGPoint) -> Bool {
            return canMoveToTiledMap(position: worldPos)
        }
        
        // Search in expanding pattern: check cardinal directions first, then expand
        // Priority: 1 tile north, south, east, west, then 2 tiles in each direction, etc.
        // NOTE: In Tiled's coordinate system (with yFlipOffset), higher tileY = lower worldY (south)
        // So north (positive world Y) = lower tileY, south (negative world Y) = higher tileY
        let maxSearchRadius = 10  // Maximum tiles to search in each direction
        
        for radius in 1...maxSearchRadius {
            // Check the 4 cardinal directions at this radius
            // Prioritize north first (positive world Y), then south, east, west
            // For Tiled coordinates: north = tileY - radius, south = tileY + radius
            let directions: [(Int, Int)] = [
                (0, -radius),  // North (positive world Y) = lower tileY - CHECK FIRST
                (0, radius),   // South (negative world Y) = higher tileY
                (radius, 0),   // East (positive X)
                (-radius, 0)   // West (negative X)
            ]
            
            for (dx, dy) in directions {
                        let testTileX = startTileX + dx
                        let testTileY = startTileY + dy
                        
                // Debug: log what we're checking
                // Note: In Tiled coordinates, north = dy < 0 (lower tileY), south = dy > 0 (higher tileY)
                let directionName = dx > 0 ? "east" : (dx < 0 ? "west" : (dy < 0 ? "north" : "south"))
                
                // First check if the center tile itself is a collision - if so, skip it entirely
                // This must be done BEFORE converting to world coordinates to avoid checking walkability on collision tiles
                let centerTileIsSafe = isSafeTile(testTileX, testTileY)
                
                if !centerTileIsSafe {
                    if radius <= 3 {
                        print("   ⛔ Skipping tile(\(testTileX), \(testTileY)) at radius \(radius) (\(directionName)): center tile is collision (in collision map)")
                    }
                    continue  // Skip this tile, it's a collision tile
                }
                
                // Now convert to world position and check if player can actually move there with their collision box
                // This accounts for the player's actual collision box size (13px wide, 12px tall, offset downward)
                // Try multiple positions within the tile - not just the center, to account for collision box overlaps
                let tileCenterPos = tileToWorld(testTileX, testTileY)
                let tileWidth = mapTileSize.width
                let tileHeight = mapTileSize.height
                
                // Try positions offset from center to avoid collision box overlaps with adjacent door tiles
                // Try larger offsets (up to 45% of tile size) to push away from door tiles
                // Also try diagonal offsets to move away from door tiles in both directions
                let testPositions: [CGPoint] = [
                    tileCenterPos,  // Try center first
                    // Horizontal offsets (to avoid door tiles on sides)
                    CGPoint(x: tileCenterPos.x + tileWidth * 0.35, y: tileCenterPos.y),  // Right
                    CGPoint(x: tileCenterPos.x - tileWidth * 0.35, y: tileCenterPos.y),  // Left
                    // Vertical offsets (to avoid door tiles above/below) - prioritize north (away from door below)
                    CGPoint(x: tileCenterPos.x, y: tileCenterPos.y + tileHeight * 0.35), // North (higher priority)
                    CGPoint(x: tileCenterPos.x, y: tileCenterPos.y - tileHeight * 0.35), // South
                    // Diagonal offsets (to maximize distance from door tiles)
                    CGPoint(x: tileCenterPos.x + tileWidth * 0.3, y: tileCenterPos.y + tileHeight * 0.3), // Northeast
                    CGPoint(x: tileCenterPos.x - tileWidth * 0.3, y: tileCenterPos.y + tileHeight * 0.3), // Northwest
                    // Even larger offsets as last resort
                    CGPoint(x: tileCenterPos.x + tileWidth * 0.45, y: tileCenterPos.y),  // Far right
                    CGPoint(x: tileCenterPos.x - tileWidth * 0.45, y: tileCenterPos.y),  // Far left
                ]
                
                var walkablePos: CGPoint?
                for testWorldPos in testPositions {
                    // Now check if player can actually move there with their collision box
                    if isWalkableWorldPosition(testWorldPos) {
                        walkablePos = testWorldPos
                        break
                    }
                }
                
                if let foundPos = walkablePos {
                    // This tile is walkable - return it
                    if radius <= 3 {
                        print("   ✅ Found safe tile at distance \(radius) (\(directionName)): tile(\(testTileX), \(testTileY)) -> world(\(Int(foundPos.x)), \(Int(foundPos.y)))")
                    }
                    return foundPos
                } else {
                    // Tile is not walkable - player collision box overlaps nearby collision tiles
                    // This happens because the collision box (13px wide) can overlap adjacent tiles
                    // when positioned at the center of a tile that's next to a door/collision tile
                    if radius <= 3 {
                        // Debug: show which collision tiles the player's collision box overlaps
                        let collisionFrame = getPlayerCollisionFrame(at: tileCenterPos)
                        let minTileX = Int(floor(collisionFrame.minX / tileWidth))
                        let maxTileX = Int(floor(collisionFrame.maxX / tileWidth))
                        let minTileY = Int(floor((mapYFlipOffset - collisionFrame.maxY) / tileHeight))
                        let maxTileY = Int(floor((mapYFlipOffset - collisionFrame.minY) / tileHeight))
                        
                        var overlappingTiles: [String] = []
                        for tx in minTileX...maxTileX {
                            for ty in minTileY...maxTileY {
                                let key = "\(tx),\(ty)"
                                if collisionMap.contains(key) {
                                    overlappingTiles.append("(\(tx),\(ty))")
                                }
                            }
                        }
                        
                        if !overlappingTiles.isEmpty {
                            print("   ⚠️ Tile(\(testTileX), \(testTileY)) at radius \(radius) (\(directionName)): centerTileIsSafe=\(centerTileIsSafe), but collision box overlaps tiles: \(overlappingTiles.joined(separator: ", "))")
                        } else {
                            print("   ⚠️ Tile(\(testTileX), \(testTileY)) at radius \(radius) (\(directionName)): centerTileIsSafe=\(centerTileIsSafe), but not walkable (unknown reason)")
                        }
                    }
                }
            }
        }
        
        // If cardinal directions didn't work, try diagonal directions as fallback
        for radius in 1...maxSearchRadius {
            let diagonals: [(Int, Int)] = [
                (radius, radius),    // Northeast
                (radius, -radius),   // Southeast
                (-radius, radius),   // Northwest
                (-radius, -radius)   // Southwest
            ]
            
            for (dx, dy) in diagonals {
                let testTileX = startTileX + dx
                let testTileY = startTileY + dy
                
                if isSafeTile(testTileX, testTileY) {
                    let safeWorldPos = tileToWorld(testTileX, testTileY)
                    if isWalkableWorldPosition(safeWorldPos) {
                        print("   Found safe tile at diagonal distance \(radius): tile(\(testTileX), \(testTileY)) -> world(\(Int(safeWorldPos.x)), \(Int(safeWorldPos.y)))")
                    return safeWorldPos
                    }
                }
            }
        }
        
        return nil
    }

    // MARK: - Chest Collision

    func getChestCollisionBox(node: SKNode) -> CGRect? {
        // Get chest prefab ID from userData
        guard let userData = node.userData,
              let prefabId = userData["prefabId"] as? String,
              let chestPrefab = PrefabFactory.shared.getChestPrefab(prefabId) else {
            print("⚠️ getChestCollisionBox: Could not get chest prefab for node \(node.name ?? "nil")")
            return nil
        }
        
        // Get collision size from prefab
        let collisionSize = chestPrefab.collision.size
        
        // Get the actual entity position from userData (this is the world position where the chest was placed)
        // This is more reliable than trying to calculate from node hierarchy
        var chestWorldPos: CGPoint
        if let positionValue = userData["position"] as? NSValue {
            chestWorldPos = positionValue.pointValue
        } else {
            // Fallback: try to get position from node hierarchy
            // Convert the node's origin (0,0) to scene coordinates
            chestWorldPos = node.convert(CGPoint.zero, to: self)
            print("⚠️ getChestCollisionBox: No position in userData, using converted position: \(chestWorldPos)")
        }
        
        // Create collision box centered at chest position
        // Collision box is centered at the chest's position
        let collisionBox = CGRect(
            x: chestWorldPos.x - collisionSize.width / 2,
            y: chestWorldPos.y - collisionSize.height / 2,
            width: collisionSize.width,
            height: collisionSize.height
        )
        
        print("📦 getChestCollisionBox: chest '\(prefabId)' - world pos from userData: \(chestWorldPos), collision size: \(collisionSize), final box: \(collisionBox)")
        
        return collisionBox
    }
}
