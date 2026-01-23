//
//  GameScene_WorldRendering.swift
//  FableForge Shared
//
//  World rendering and map loading functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    func setupHybridWorldSystem() {
        print("🌍 Setting up hybrid world system (chunk-based)")
        
        guard let world = gameState?.world else {
            print("❌ No world in gameState for hybrid system")
            return
        }
        
        // Use TMX tile size (16x16 base tiles scaled by 2.0 = 32.0) to match TMX maps
        let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
        let chunkSize = ChunkManager.defaultChunkSize
        
        // CRITICAL: Reload world config from JSON to ensure we're using the latest config
        // Determine which prefabs file to load based on:
        // 1. Stored currentProceduralWorldPrefab (if we've entered this world before)
        // 2. Existing world config ID (if config is already loaded)
        // 3. Default to "prefabs_grassland"
        let prefabsFileName: String
        if let storedPrefab = currentProceduralWorldPrefab {
            prefabsFileName = storedPrefab
            print("🔄 Reloading world config from stored prefab file '\(prefabsFileName).json'")
        } else if let existingConfig = PrefabFactory.shared.getWorldConfig() {
            // Use the ID from existing config (e.g., "prefabs_grassland")
            prefabsFileName = existingConfig.id
            print("🔄 Reloading world config from existing config ID '\(prefabsFileName).json'")
        } else {
            // Default to grassland if no config exists
            prefabsFileName = "prefabs_grassland"
            print("🔄 Loading default world config from '\(prefabsFileName).json'")
        }
        
        // Reload the prefabs file to get fresh world config from JSON
        PrefabFactory.shared.loadPrefabsFromFile(prefabsFileName)
        
        // Store the prefab file name for future reference
        currentProceduralWorldPrefab = prefabsFileName
        
        // Get world config from PrefabFactory (now freshly loaded from JSON)
        let worldConfig = PrefabFactory.shared.getWorldConfig()
        guard let config = worldConfig else {
            print("❌ CRITICAL: No world config found after reloading '\(prefabsFileName).json'")
            print("   This will cause inconsistent world generation. Please check the JSON file.")
            return
        }
        
        // CRITICAL: Always use seed from world config (JSON) for deterministic generation
        // Do NOT use world.seed as fallback - it's from the old system and may be different
        let worldSeed = config.seed
        
        // Log config details for debugging
        print("✅ Using world config: '\(config.name)' (seed: \(worldSeed), id: \(config.id))")
        print("   This seed ensures deterministic world generation - same seed = same world")
        
        // Clean up existing chunk manager if it exists (when re-entering the world)
        if let existingChunkManager = chunkManager {
            print("🧹 Cleaning up existing chunk manager before recreating...")
            existingChunkManager.unloadAllChunks()
            // Remove any remaining chunk nodes from the scene
            enumerateChildNodes(withName: "chunk_") { node, _ in
                node.removeFromParent()
            }
        }
        
        // Load standalone tilesets needed for procedural generation (terrain1, water1, outside_objects1, etc.)
        // These are referenced in the prefabs JSON but not loaded from TMX files
        print("🔍 Loading standalone tilesets for procedural generation...")
        let terrain1Loaded = TileManager.shared.loadStandaloneTileset(fileName: "terrain1", firstGID: 10000)
        let water1Loaded = TileManager.shared.loadStandaloneTileset(fileName: "water1", firstGID: 20000)
        let outsideObjects1Loaded = TileManager.shared.loadStandaloneTileset(fileName: "outside_objects1", firstGID: 30000)
        
        if !outsideObjects1Loaded {
            print("❌ Failed to load outside_objects1 tileset - check console above for details")
        } else {
            print("✅ Successfully loaded outside_objects1 tileset")
        }
        
        // Initialize components with world config
        // CRITICAL: Always recreate WorldGenerator to ensure it uses the correct seed from config
        // This ensures deterministic generation - same seed always produces same world
        worldGenerator = WorldGenerator(seed: worldSeed, config: worldConfig)
        print("   ✅ Created WorldGenerator with seed: \(worldSeed)")
        
        deltaPersistence = DeltaPersistence()
        // Use smaller load radius initially (1 = 3x3 chunks = 9 chunks) to improve load time
        // Can increase to 2 or 3 later if needed, but 1 is much faster for initial load
        chunkManager = ChunkManager(chunkSize: chunkSize, loadRadius: 1, tileSize: tileSize, scene: self)
        
        chunkManager?.setWorldGenerator(worldGenerator!)
        chunkManager?.setDeltaPersistence(deltaPersistence!)
        
        // Register a TMX instance example: Town_01 at world tile (100, 100)
        // This is a placeholder - you would load actual TMX instances from a config file
        let townInstance = TMXInstance(
            fileName: "Town_01",  // TODO: Create or reference actual TMX file
            worldTileOrigin: (x: 100, y: 100),
            worldBounds: nil,
            tiledMap: nil
        )
        chunkManager?.registerTMXInstance(townInstance)
        
        // Load initial chunks around player
        if let player = gameState?.player {
            chunkManager?.updateChunks(around: player.position)
            lastPlayerChunk = ChunkKey.fromWorldPosition(player.position, chunkSize: chunkSize, tileSize: tileSize)
        }
        
        print("✅ Hybrid world system initialized")
    }
    
    func renderWorld() {
        print("🔵 renderWorld() called")
        guard let world = gameState?.world else {
            print("❌ No world in gameState")
            return
        }
        
        print("🔵 Rendering world: \(world.width)x\(world.height) tiles")
        
        // Clear existing tiles
        worldTiles.forEach { $0.removeFromParent() }
        worldTiles.removeAll()
        
        // Scale tiles to match Tiled map scale (16x16 -> 32x32)
        let scaleFactor: CGFloat = 2.0
        let scaledTileSize = world.tileSize * scaleFactor
        let tileSize = CGSize(
            width: scaledTileSize,
            height: scaledTileSize
        )
        
        // Render visible tiles (simple implementation - render all for now)
        var spriteCount = 0
        for y in 0..<Int(world.height) {
            for x in 0..<Int(world.width) {
                let tile = world.tiles[y][x]
                // Use tilesets from TMX if available, otherwise fall back to old system
                let sprite = TileManager.shared.createTileSpriteFromTilesets(
                    for: tile.type,
                    size: tileSize
                )
                // CRITICAL: Position tiles using SCALED tile size, not original tileSize
                // The tile.position is based on original 32px, but we're rendering at 64px
                let scaledX = CGFloat(x) * scaledTileSize
                let scaledY = CGFloat(y) * scaledTileSize
                sprite.position = CGPoint(x: scaledX, y: scaledY)
                sprite.anchorPoint = CGPoint(x: 0, y: 0)
                sprite.zPosition = 0
                
                // CRITICAL: Ensure sprite is visible and properly configured
                sprite.alpha = 1.0
                sprite.isHidden = false
                
                // CRITICAL: Verify sprite has texture before adding
                if sprite.texture == nil {
                    print("⚠️ WARNING: Sprite for \(tile.type) at (\(scaledX), \(scaledY)) has no texture!")
                }
                
                addChild(sprite)
                worldTiles.append(sprite)
                spriteCount += 1
                
                // Debug first few sprites
                if spriteCount <= 5 {
                    print("🎨 Created sprite #\(spriteCount) for \(tile.type) at position (\(scaledX), \(scaledY)), size: \(sprite.size), texture: \(sprite.texture != nil ? "present" : "nil")")
                    if let texture = sprite.texture {
                        print("   Texture size: \(texture.size()), filtering: \(texture.filteringMode.rawValue)")
                    }
                }
                
                // Render structures
                if let structureId = tile.structureId,
                   let structure = gameState?.structures.first(where: { $0.id == structureId }) {
                    let structureSprite = SKSpriteNode(color: .brown, size: structure.size)
                    structureSprite.position = tile.position
                    structureSprite.zPosition = 1
                    addChild(structureSprite)
                }
            }
        }
    }
    
    /// Load tilesets from a TMX file without rendering the map
    /// This allows procedural generation to use tileset images
    /// - Parameters:
    ///   - fileName: Name of the TMX file (without extension)
    ///   - preParsedMap: Optional pre-parsed TiledMap to avoid re-parsing (for performance)
    /// - Returns: The parsed TiledMap (or nil if parsing failed), for reuse
    @discardableResult
    func loadTilesetsFromTMX(fileName: String, preParsedMap: TiledMap? = nil) -> TiledMap? {
        print("\n🔵🔵🔵 loadTilesetsFromTMX CALLED with fileName: \(fileName)")
        print(String(repeating: "=", count: 50))
        print("LOADING TILESETS FROM TMX: \(fileName)")
        print(String(repeating: "=", count: 50))
        
        // Use pre-parsed map if provided, otherwise parse it
        let tiledMap: TiledMap
        if let preParsed = preParsedMap {
            tiledMap = preParsed
            print("✓ Using pre-parsed TiledMap (skip parsing for performance)")
        } else {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "tmx") else {
            print("❌ ERROR: Could not find '\(fileName).tmx' to load tilesets")
                return nil
        }
        
        print("✓ Found TMX file at: \(url.path)")
        
            guard let parsedMap = TiledMapParser.parse(fileName: fileName) else {
            print("❌ ERROR: Could not parse '\(fileName).tmx' to load tilesets")
                return nil
            }
            tiledMap = parsedMap
        }
        
        print("✓ Parsed TMX file, found \(tiledMap.tilesets.count) tilesets")
        
        if !tiledMap.tilesets.isEmpty {
            TileManager.shared.loadTiledTilesets(from: tiledMap)
            print("✓ Successfully loaded \(tiledMap.tilesets.count) tilesets from \(fileName).tmx for procedural generation")
            for tileset in tiledMap.tilesets {
                print("  - \(tileset.name): GIDs \(tileset.firstGID)-\(tileset.firstGID + tileset.tileCount - 1)")
            }
        } else {
            print("❌ ERROR: No tilesets found in TMX file!")
        }
        
        return tiledMap
    }
    
    /// Load and render a Tiled map
    /// Call this instead of renderWorld() if you want to use a Tiled map
    /// - Parameters:
    ///   - fileName: Name of the TMX file (without extension)
    ///   - preParsedMap: Optional pre-parsed TiledMap to avoid re-parsing (for performance)
    func loadAndRenderTiledMap(fileName: String, preParsedMap: TiledMap? = nil) {
        // Clear existing tiles
        worldTiles.forEach { $0.removeFromParent() }
        worldTiles.removeAll()
        
        // Clear existing object sprites
        for (sprite, _) in objectSprites {
            sprite.removeFromParent()
        }
        objectSprites.removeAll()
        objectGroupNames.removeAll()
        
        print(String(repeating: "=", count: 50))
        print("ATTEMPTING TO LOAD TILED MAP: \(fileName)")
        print(String(repeating: "=", count: 50))
        
        // Use pre-parsed map if provided, otherwise parse it
        let tiledMap: TiledMap
        if let preParsed = preParsedMap {
            tiledMap = preParsed
            print("✓ Using pre-parsed TiledMap (skip parsing for performance)")
        } else {
            // Check if file exists in bundle first
            if Bundle.main.url(forResource: fileName, withExtension: "tmx") == nil {
                print("❌ CRITICAL ERROR: '\(fileName).tmx' NOT FOUND IN APP BUNDLE!")
                print("   Steps to fix:")
                print("   1. Select 'Exterior.tmx' in Xcode")
                print("   2. Open File Inspector (right panel)")
                print("   3. Check 'Target Membership' - ensure your app target is checked")
                print("   4. Clean build folder (Cmd+Shift+K) and rebuild")
                // Fall back to generated world if Tiled map fails
                if let world = gameState?.world {
                    print("   Falling back to generated world...")
                    renderWorld()
                }
                return
            }
            
            // Parse the Tiled map
            guard let parsedMap = TiledMapParser.parse(fileName: fileName) else {
                print("❌ ERROR: Failed to parse Tiled map '\(fileName).tmx'")
                print("   Make sure the file is valid XML and added to the target")
                // Fall back to generated world if Tiled map fails
                if let world = gameState?.world {
                    print("   Falling back to generated world...")
                    renderWorld()
                }
                return
            }
            tiledMap = parsedMap
        }
        
        // Check if we have tilesets
        guard !tiledMap.tilesets.isEmpty else {
            print("❌ ERROR: No tilesets found in Tiled map!")
            print("   This usually means the tileset <image> tags weren't parsed correctly.")
            print("   Falling back to generated world...")
            if let world = gameState?.world {
                renderWorld()
            }
            return
        }
        
        // Load tilesets into TileManager (only if not already loaded)
        TileManager.shared.loadTiledTilesets(from: tiledMap)
        
        // First pass: Calculate map bounds using base tile size to determine optimal scale
        let baseTileSize = CGFloat(tiledMap.tileWidth)
        var tempMinX: CGFloat = CGFloat.greatestFiniteMagnitude
        var tempMinY: CGFloat = CGFloat.greatestFiniteMagnitude
        var tempMaxX: CGFloat = -CGFloat.greatestFiniteMagnitude
        var tempMaxY: CGFloat = -CGFloat.greatestFiniteMagnitude
        
        for layer in tiledMap.layers {
            if layer.isInfinite, let chunks = layer.chunks {
                for chunk in chunks {
                    let chunkMinX = CGFloat(chunk.x) * baseTileSize
                    let chunkMinY = CGFloat(chunk.y) * baseTileSize
                    let chunkMaxX = chunkMinX + CGFloat(chunk.width) * baseTileSize
                    let chunkMaxY = chunkMinY + CGFloat(chunk.height) * baseTileSize
                    tempMinX = min(tempMinX, chunkMinX)
                    tempMinY = min(tempMinY, chunkMinY)
                    tempMaxX = max(tempMaxX, chunkMaxX)
                    tempMaxY = max(tempMaxY, chunkMaxY)
                }
            }
        }
        
        // Calculate optimal scale factor to fill the scene
        let mapWidth = tempMaxX - tempMinX
        let mapHeight = tempMaxY - tempMinY
        let sceneWidth = size.width
        let sceneHeight = size.height
        
        // Calculate scale factors for both dimensions
        let scaleX = sceneWidth / max(mapWidth, 1.0)
        let scaleY = sceneHeight / max(mapHeight, 1.0)
        
        // Use the smaller scale to ensure map fits in both dimensions
        // Add a multiplier to make it fill more of the screen (1.2 = 20% larger)
        let scaleFactor = min(scaleX, scaleY) * 1.2
        
        // Ensure minimum scale of 2.0 for visibility, and cap at reasonable maximum
        let finalScaleFactor = max(2.0, min(scaleFactor, 10.0))
        
        let tileSize = CGSize(
            width: CGFloat(tiledMap.tileWidth) * finalScaleFactor,
            height: CGFloat(tiledMap.tileHeight) * finalScaleFactor
        )
        print("Rendering \(tiledMap.layers.count) layers with tile size: \(tileSize) (scaled from \(tiledMap.tileWidth)x\(tiledMap.tileHeight) by factor \(finalScaleFactor))")
        print("Map dimensions: \(mapWidth)x\(mapHeight) base tiles, Scene: \(sceneWidth)x\(sceneHeight) points")
        
        // Second pass: Calculate bounds with scaled tile size for Y flip offset
        // Include BOTH infinite and regular layers in bounds calculation
        var minX: CGFloat = CGFloat.greatestFiniteMagnitude
        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude
        
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            if layer.isInfinite, let chunks = layer.chunks {
                // Infinite map with chunks
                for chunk in chunks {
                    let chunkMinX = CGFloat(chunk.x) * tileSize.width
                    let chunkMinY = CGFloat(chunk.y) * tileSize.height
                    let chunkMaxX = chunkMinX + CGFloat(chunk.width) * tileSize.width
                    let chunkMaxY = chunkMinY + CGFloat(chunk.height) * tileSize.height
                    minX = min(minX, chunkMinX)
                    minY = min(minY, chunkMinY)
                    maxX = max(maxX, chunkMaxX)
                    maxY = max(maxY, chunkMaxY)
                }
            } else if let data = layer.data {
                // Regular (non-infinite) map - include in bounds
                let layerMinX: CGFloat = 0
                let layerMinY: CGFloat = 0
                let layerMaxX = CGFloat(layer.width) * tileSize.width
                let layerMaxY = CGFloat(layer.height) * tileSize.height
                minX = min(minX, layerMinX)
                minY = min(minY, layerMinY)
                maxX = max(maxX, layerMaxX)
                maxY = max(maxY, layerMaxY)
            }
        }
        
        // Calculate Y flip offset: In Tiled, Y increases downward. In SpriteKit, Y increases upward.
        // To flip: worldY = maxY - (tiledY - minY) = (maxY + minY) - tiledY
        // So offset = maxY + minY, and worldY = offset - tiledY
        let yFlipOffset: CGFloat
        if maxY != -CGFloat.greatestFiniteMagnitude && minY != CGFloat.greatestFiniteMagnitude {
            yFlipOffset = maxY + minY
        } else {
            yFlipOffset = 0
        }
        
        // Store for collision detection
        self.mapYFlipOffset = yFlipOffset
        
        // OPTIMIZATION: Batch sprite additions by using a container node per layer
        // This reduces the number of addChild calls to the scene from thousands to just a few
        let mapContainer = SKNode()
        mapContainer.name = "tiledMapContainer"
        addChild(mapContainer)
        
        // Second pass: Render layers
        // Find which layer has the "characterLayer" or "characterIndex" property
        // This determines where the character should be positioned relative to layers
        // Layers before this index render behind character, layers after render in front
        // Example: If layer 3 has "characterLayer" property:
        //   - Layers 0, 1, 2, 3 render behind character (z-position 0, 1, 2, 3)
        //   - Layers 4, 5, ... render in front of character (z-position 4, 5, ...)
        //   - Character renders at z-position 3.5 (between layer 3 and 4)
        var characterLayerIndex: Int? = nil
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            // Check for "characterLayer" or "characterIndex" property (boolean or float)
            let hasCharacterProperty = layer.boolProperty("characterLayer", default: false) || 
                                     layer.boolProperty("characterIndex", default: false) ||
                                     layer.floatProperty("characterLayer", default: -1) >= 0 ||
                                     layer.floatProperty("characterIndex", default: -1) >= 0
            if hasCharacterProperty {
                characterLayerIndex = layerIndex
                print("📍 Found characterLayer property on layer \(layerIndex) '\(layer.name)' - character will be positioned after this layer")
                break
            }
        }
        
        // Set character z-position: if a layer has the property, place character between that layer and the next
        // Otherwise default to 100 (which will be above most layers)
        // IMPORTANT: When calculating characterZPosition, we need to ensure it's higher than ALL layers
        // that come BEFORE the characterLayer in layer order, even if those layers have zOffset values.
        // This ensures layers with low zOffset (but coming before characterLayer) stay behind the character.
        if let charLayerIndex = characterLayerIndex {
            // Find the maximum zPosition of all layers that come before (or at) the characterLayer
            var maxZPositionBeforeCharacter: CGFloat = 0
            for layerIndex in 0...charLayerIndex {
                let layer = tiledMap.layers[layerIndex]
                let zOffset = CGFloat(layer.floatProperty("zOffset", default: 0))
                let layerZPosition = CGFloat(layerIndex) + zOffset
                if layerZPosition > maxZPositionBeforeCharacter {
                    maxZPositionBeforeCharacter = layerZPosition
                }
            }
            // Place character slightly above the highest zPosition before/at the characterLayer
            characterZPosition = maxZPositionBeforeCharacter + 0.5
            print("📍 Character z-position set to \(characterZPosition) (after layer \(charLayerIndex), max zPosition before character: \(maxZPositionBeforeCharacter))")
        } else {
            // Default: character appears above all layers (z-position 100)
            // But we should check if any layer has a zOffset that would push it above 100
            var maxLayerZPosition: CGFloat = 100
            for (layerIndex, layer) in tiledMap.layers.enumerated() {
                let zOffset = CGFloat(layer.floatProperty("zOffset", default: 0))
                let layerZPosition = CGFloat(layerIndex) + zOffset
                if layerZPosition > maxLayerZPosition {
                    maxLayerZPosition = layerZPosition
                }
            }
            // Place character slightly above the highest layer zPosition
            characterZPosition = max(100, maxLayerZPosition + 0.5)
            print("📍 No characterLayer property found - character z-position set to \(characterZPosition) (based on max layer zPosition \(maxLayerZPosition))")
        }
        
        // Render layers using natural order (layer index) to maintain proper layer ordering
        // Layers maintain their relative order, character appears at characterZPosition
        // Layers can have a "zOffset" property to adjust their zPosition relative to the layer index
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            // Z-Position hierarchy:
            // - Background: -100000 (far behind)
            // - Tiles: base layer index + zOffset (if specified) - maintains natural layer order with offset
            // - Characters: based on "characterZPosition" property (default 100)
            //   - Layers with zPosition < characterZPosition appear behind character
            //   - Layers with zPosition >= characterZPosition appear in front of character
            // - UI: 200+ (above everything)
            let baseZPosition = CGFloat(layerIndex)
            let zOffset = CGFloat(layer.floatProperty("zOffset", default: 0))
            let tileZPosition = baseZPosition + zOffset
            if zOffset != 0 {
                print("📍 Layer '\(layer.name)' (index \(layerIndex)) has zOffset \(zOffset) → zPosition \(tileZPosition)")
            }
            renderTiledLayer(layer, tileSize: tileSize, zPosition: tileZPosition, yFlipOffset: yFlipOffset, container: mapContainer)
        }
        
        // Update player and companion sprites' zPosition based on calculated characterZPosition
        // This ensures correct layering when switching maps
        if let playerSprite = playerSprite {
            playerSprite.zPosition = characterZPosition
            print("📍 Updated player sprite zPosition to \(characterZPosition)")
        }
        // Update companion sprites' zPosition (slightly below player)
        for (_, companionSprite) in companionSprites {
            companionSprite.zPosition = characterZPosition - 1
        }
        
        // Third pass: Render object groups (object layers)
        // Objects are rendered above tiles but below player/entities
        let objectZPosition: CGFloat = 70  // Above tiles (0-60) but below player (100)
        print("📦 Rendering \(tiledMap.objectGroups.count) object groups...")
        if tiledMap.objectGroups.isEmpty {
            print("⚠️ WARNING: No object groups found in Tiled map!")
            print("   → Make sure your Tiled map has at least one Object Layer (not a Tile Layer)")
            print("   → Object Layers are created by right-clicking in the Layers panel and selecting 'Add Object Layer'")
        } else {
            for objectGroup in tiledMap.objectGroups {
                print("   📋 Found object group: '\(objectGroup.name)' with \(objectGroup.objects.count) objects")
            }
        }
        for objectGroup in tiledMap.objectGroups {
            renderTiledObjectGroup(objectGroup, tileSize: tileSize, zPosition: objectZPosition, yFlipOffset: yFlipOffset, container: mapContainer)
        }
        print("📦 Finished rendering all object groups. Total object sprites: \(objectSprites.count)")
        if objectSprites.isEmpty && !tiledMap.objectGroups.isEmpty {
            print("⚠️ WARNING: No object sprites were created despite having object groups!")
            print("   → Check console logs above for individual object rendering errors")
            print("   → Make sure objects have valid positions (x, y) within the map bounds")
            print("   → Objects without GIDs will appear as yellow rectangles")
            print("   → Objects with GIDs will show the tile image from your tileset")
        }
        
        
        
        // Adjust scene size to match map bounds and position player/camera
        if minX != CGFloat.greatestFiniteMagnitude {
            let mapWidth = maxX - minX
            let mapHeight = maxY - minY
            let mapCenterX = (minX + maxX) / 2
            let mapCenterY = (minY + maxY) / 2
            
            print("Map bounds: (\(minX), \(minY)) to (\(maxX), \(maxY))")
            print("Map size: \(mapWidth) x \(mapHeight)")
            print("Map center: (\(mapCenterX), \(mapCenterY))")
            
            // CRITICAL: Set scene background color to dark grey (removes gray areas when no tiles are present)
            self.backgroundColor = SKColor(red: 0x30/255.0, green: 0x29/255.0, blue: 0x29/255.0, alpha: 1.0)  // #302929
            
            // Remove any existing background sprites first
            self.enumerateChildNodes(withName: "mapBackground") { node, _ in
                node.removeFromParent()
            }
            
            // Add a HUGE background sprite that covers everything (larger than screen + map)
            // Make it cover at least 4x the screen size to ensure no gray areas
            let screenSize = self.size
            let bgWidth = max(mapWidth * 2, screenSize.width * 4)
            let bgHeight = max(mapHeight * 2, screenSize.height * 4)
            let bgSize = CGSize(width: bgWidth, height: bgHeight)
            
            let backgroundSprite = SKSpriteNode(color: self.backgroundColor, size: bgSize)
            backgroundSprite.position = CGPoint(x: mapCenterX, y: mapCenterY)
            backgroundSprite.zPosition = -100000  // Far behind everything
            backgroundSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            backgroundSprite.name = "mapBackground"
            addChild(backgroundSprite)
            
            
            // Store map bounds and rendering info for collision detection
            self.mapBounds = CGRect(x: minX, y: minY, width: mapWidth, height: mapHeight)
            self.mapTileSize = tileSize
            
            // Parse collision layers from TMX and create collision map
            // Layers with "collision" in the name or properties will be used for collision
            hasInfiniteLayers = tiledMap.layers.contains { $0.isInfinite }
            
            // Constrain camera to map bounds to prevent seeing empty areas
            // BUT: Skip constraints for infinite maps - they should scroll freely
            if let camera = cameraNode, !hasInfiniteLayers {
                // Calculate camera bounds - ensure camera doesn't go outside map
                let halfScreenWidth = size.width / 2
                let halfScreenHeight = size.height / 2
                let xMin = minX + halfScreenWidth
                let xMax = maxX - halfScreenWidth
                let yMin = minY + halfScreenHeight
                let yMax = maxY - halfScreenHeight
                
                // Only add constraints if map is larger than screen
                if xMax > xMin && yMax > yMin {
                    let xRange = SKRange(lowerLimit: CGFloat(xMin), upperLimit: CGFloat(xMax))
                    let yRange = SKRange(lowerLimit: CGFloat(yMin), upperLimit: CGFloat(yMax))
                    camera.constraints = [
                        SKConstraint.positionX(xRange),
                        SKConstraint.positionY(yRange)
                    ]
                    print("Camera constrained to map bounds: X(\(xMin)-\(xMax)), Y(\(yMin)-\(yMax))")
                }
            } else if hasInfiniteLayers {
                // For infinite maps, remove any existing constraints to allow free scrolling
                if let camera = cameraNode {
                    camera.constraints = []
                    print("Camera constraints removed for infinite map - free scrolling enabled")
                }
            }
            let maxRegularHeight = tiledMap.layers.filter { !$0.isInfinite }.map { $0.height }.max() ?? 0
            regularLayerHeight = maxRegularHeight
            print("🗺️ Map info: hasInfiniteLayers=\(hasInfiniteLayers), regularLayerHeight=\(maxRegularHeight), yFlipOffset=\(yFlipOffset), tileSize=\(tileSize)")
            parseCollisionFromTiledMap(tiledMap, tileSize: tileSize, yFlipOffset: yFlipOffset)
            print("🗺️ Collision map created with \(collisionMap.count) collision tiles")
            // Print first 10 collision tile keys and their world positions for debugging
            let first10Keys = Array(collisionMap.prefix(10))
            print("🗺️ First 10 collision tiles with world positions:")
            for key in first10Keys {
                let parts = key.split(separator: ",")
                if parts.count == 2, let tileX = Int(parts[0]), let tileY = Int(parts[1]) {
                    let tileTiledY = CGFloat(tileY) * tileSize.height
                    let tileWorldY = yFlipOffset - tileTiledY
                    let tileWorldX = CGFloat(tileX) * tileSize.width
                    print("  Tile (\(tileX), \(tileY)) -> world=(\(Int(tileWorldX)), \(Int(tileWorldY)))")
                }
            }
            
            // Note: Player position will be set to safe location after map center calculation
            // Note: Animations will be handled separately for animated tilesets
            // Animated tilesets (Smoke_animation, Doors_windows_animation, etc.) need to cycle through frames
            // This will be implemented after basic collision detection is working
            
            // Update player position to map center, but ensure it's in a safe (non-collision) location
            if let player = gameState?.player {
                var targetPosition = CGPoint(x: mapCenterX, y: mapCenterY)
                
                // Check if the target position is safe (not in a collision tile)
                if !collisionMap.isEmpty && !canMoveToTiledMap(position: targetPosition) {
                    print("⚠️ Map center position is in a collision tile, finding safe spawn point...")
                    if let safePosition = findSafeSpawnPoint(near: targetPosition) {
                        targetPosition = safePosition
                        print("✅ Found safe spawn point: (\(Int(safePosition.x)), \(Int(safePosition.y)))")
                    } else {
                        print("⚠️ WARNING: Could not find safe spawn point near map center!")
                        print("   Player may be stuck. Trying fallback position...")
                        // Fallback: try a position slightly offset from center
                        targetPosition = CGPoint(x: mapCenterX + mapTileSize.width * 5, y: mapCenterY + mapTileSize.height * 5)
                    }
                }
                
                player.position = targetPosition
                playerSprite?.position = player.position
                // Snap camera position to pixel boundaries to prevent tile seams
                let snappedCameraX = round(targetPosition.x * 2.0) / 2.0
                let snappedCameraY = round(targetPosition.y * 2.0) / 2.0
                cameraNode?.position = CGPoint(x: snappedCameraX, y: snappedCameraY)
            }
        }
        
        // CRITICAL: Snap all tile positions to pixel boundaries after map is fully loaded
        // This prevents seams between tiles on initial load
        reSnapTilePositions()
    }
    
    /// Render a single layer from a Tiled map
    private func renderTiledLayer(_ layer: TiledLayer, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0, container: SKNode? = nil) {
        let parentNode = container ?? self
        
        if layer.isInfinite, let chunks = layer.chunks {
            // Render infinite map with chunks
            for chunk in chunks {
                renderTiledChunk(chunk, tileSize: tileSize, zPosition: zPosition, yFlipOffset: yFlipOffset, container: parentNode)
            }
        } else if let data = layer.data {
            // Render regular (non-infinite) map
            var index = 0
            let expectedDataCount = layer.width * layer.height
            for y in 0..<layer.height {
                for x in 0..<layer.width {
                    guard index < data.count else {
                        // Data exhausted, skip remaining tiles
                        break
                    }
                    
                    let gid = data[index]
                    index += 1
                    
                    guard gid > 0 else { continue }
                    
                    if let sprite = TileManager.shared.createSprite(for: gid, size: tileSize) {
                        // Verify sprite has valid texture
                        if sprite.texture == nil {
                            continue  // Skip sprites without textures (removed print for performance)
                        }
                        
                        // Regular layers use different Y positioning than chunks
                        // Position: worldY = (layer.height - y - 1) * tileHeight
                        // This means y=0 (top row) is at highest worldY
                        let worldX = CGFloat(x) * tileSize.width
                        let worldY = CGFloat(layer.height - y - 1) * tileSize.height
                        
                        // CRITICAL FIX: Snap positions to pixel boundaries to prevent sub-pixel rendering gaps
                        // Round to nearest 0.5 pixel (half-pixel precision) to avoid floating-point precision errors
                        // This eliminates seams between tiles caused by sub-pixel rendering
                        let snappedX = round(worldX * 2.0) / 2.0
                        let snappedY = round(worldY * 2.0) / 2.0
                        
                        sprite.position = CGPoint(x: snappedX, y: snappedY)
                        sprite.anchorPoint = CGPoint(x: 0, y: 0)
                        sprite.zPosition = zPosition
                        
                        // Ensure sprite is visible
                        sprite.alpha = 1.0
                        sprite.isHidden = false
                        
                        parentNode.addChild(sprite)
                        worldTiles.append(sprite)
                    }
                }
            }
        }
    }
    
    /// Render a chunk from an infinite map
    private func renderTiledChunk(_ chunk: TiledChunk, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0, container: SKNode? = nil) {
        let parentNode = container ?? self
        let expectedDataCount = chunk.width * chunk.height
        if chunk.data.count != expectedDataCount {
            // Removed print for performance - only log if critical
        }
        
        var index = 0
        for y in 0..<chunk.height {
            for x in 0..<chunk.width {
                guard index < chunk.data.count else {
                    // Data exhausted, skip remaining tiles
                    break
                }
                
                let gid = chunk.data[index]
                index += 1
                
                guard gid > 0 else { continue }
                
                if let sprite = TileManager.shared.createSprite(for: gid, size: tileSize) {
                    // Verify sprite has valid texture
                    if sprite.texture == nil {
                        continue  // Skip sprites without textures (removed print for performance)
                    }
                    
                    // Calculate world position: chunk coordinates are in tile units
                    // Tiled uses top-left origin (Y increases downward)
                    // SpriteKit uses bottom-left origin (Y increases upward)
                    // We need to flip the Y coordinate: newY = yFlipOffset - oldY
                    // where oldY = (chunk.y + y) * tileSize.height (Tiled coordinate)
                    let worldX = CGFloat(chunk.x + x) * tileSize.width
                    let tiledY = CGFloat(chunk.y + y) * tileSize.height
                    let worldY = yFlipOffset - tiledY
                    
                    // CRITICAL FIX: Snap positions to pixel boundaries to prevent sub-pixel rendering gaps
                    // Round to nearest 0.5 pixel (half-pixel precision) to avoid floating-point precision errors
                    // This eliminates seams between tiles caused by sub-pixel rendering
                    let snappedX = round(worldX * 2.0) / 2.0
                    let snappedY = round(worldY * 2.0) / 2.0
                    
                    sprite.position = CGPoint(x: snappedX, y: snappedY)
                    sprite.anchorPoint = CGPoint(x: 0, y: 0)  // Bottom-left corner
                    sprite.zPosition = zPosition
                    
                    // Ensure sprite is visible
                    sprite.alpha = 1.0
                    sprite.isHidden = false
                    
                    parentNode.addChild(sprite)
                    worldTiles.append(sprite)
                }
            }
        }
    }
    
    
    /// Check if the player is colliding with a door tile (from a collision layer with interior property)
    func checkDoorCollision(at position: CGPoint) {
        guard !collisionMap.isEmpty else { return }
        
        // Get player's collision frame
        let playerFrame = getPlayerCollisionFrame(at: position)
        
        // Convert player position to tile coordinates
        let tileWidth = mapTileSize.width
        let tileHeight = mapTileSize.height
        let yFlipOffset = mapYFlipOffset
        
        // Check tiles that the player's collision box overlaps
        let playerLeft = playerFrame.minX
        let playerRight = playerFrame.maxX
        let playerBottom = playerFrame.minY
        let playerTop = playerFrame.maxY
        
        // Convert to tile coordinates
        let minTileX = Int(floor(playerLeft / tileWidth))
        let maxTileX = Int(floor(playerRight / tileWidth))
        
        let (minTileY, maxTileY): (Int, Int)
        if hasInfiniteLayers {
            let playerTiledYTop = (yFlipOffset - playerTop) / tileHeight
            let playerTiledYBottom = (yFlipOffset - playerBottom) / tileHeight
            let rawMinTileY = Int(floor(min(playerTiledYTop, playerTiledYBottom))) + 1
            let rawMaxTileY = Int(floor(max(playerTiledYTop, playerTiledYBottom))) + 1
            minTileY = rawMinTileY
            maxTileY = rawMaxTileY
        } else {
            let height = regularLayerHeight
            if height > 0 {
                let regularYTop = height - 1 - Int(floor(playerTop / tileHeight))
                let regularYBottom = height - 1 - Int(floor(playerBottom / tileHeight))
                minTileY = min(regularYTop, regularYBottom)
                maxTileY = max(regularYTop, regularYBottom)
            } else {
                return
            }
        }
        
        // Check all tiles the player overlaps
        // Use precise rectangle intersection for door detection too
        for tileX in minTileX...maxTileX {
            for tileY in minTileY...maxTileY {
                let key = "\(tileX),\(tileY)"
                
                // If this is a collision tile, check if it's from a door layer
                if collisionMap.contains(key), let layerName = collisionLayerMap[key] {
                    // Calculate the door tile's world rectangle for precise intersection
                    let tileWorldX = CGFloat(tileX) * tileWidth
                    let tileWorldY: CGFloat
                    if hasInfiniteLayers {
                        let tileTiledY = CGFloat(tileY) * tileHeight
                        tileWorldY = yFlipOffset - tileTiledY
                    } else {
                        let height = regularLayerHeight
                        if height > 0 {
                            tileWorldY = CGFloat(height - 1 - tileY) * tileHeight
                        } else {
                            let tileTiledY = CGFloat(tileY) * tileHeight
                            tileWorldY = yFlipOffset - tileTiledY
                        }
                    }
                    let tileRect = CGRect(x: tileWorldX, y: tileWorldY, width: tileWidth, height: tileHeight)
                    
                    // Only trigger door if the player's collision box actually intersects the door tile
                    if playerFrame.intersects(tileRect) {
                        // Check if this layer has an interior property
                        if let layerProps = layerProperties[layerName],
                           let interiorMap = layerProps["interior"] {
                            let doorId = layerProps["doorId"] ?? layerProps["door_id"] ?? layerName
                            print("🚪 Door tile collision detected: layer '\(layerName)', interior=\(interiorMap), doorId=\(doorId)")
                            enterBuilding(interiorMapName: interiorMap, doorPosition: position, doorLayerName: layerName, doorId: doorId)
                            return
                        }
                        
                        // Check if this layer has an exit property
                        if let layerProps = layerProperties[layerName] {
                            let exitValue = layerProps["exit"]?.lowercased()
                            if exitValue == "true" || exitValue == "1" {
                                let doorId = layerProps["doorId"] ?? layerProps["door_id"] ?? layerName
                                print("🚪 Exit door tile collision detected: layer '\(layerName)', doorId=\(doorId)")
                                exitBuilding(exitDoorPosition: position, exitDoorLayerName: layerName, exitDoorId: doorId)
                                return
                            }
                        }
                        
                        // Check if this layer triggers transition to procedural world
                        if let layerProps = layerProperties[layerName] {
                            let triggerValue = layerProps["proceduralWorldTrigger"]?.lowercased()
                            if triggerValue == "true" || triggerValue == "1" {
                                // Check if player has moved away from trigger tile first (prevents immediate re-trigger)
                                // If triggerTilePosition is nil, this is the first time, so allow trigger
                                if let _ = triggerTilePosition, !hasMovedAwayFromTrigger {
                                    print("⏱️ Player on trigger tile but hasn't moved away yet, ignoring trigger")
                                    return
                                }
                                
                                // Get optional prefabs file name from layer properties
                                // Default to "prefabs_grassland" if not specified (since "prefabs.json" no longer exists)
                                let prefabsFile = layerProps["prefabsFile"] ?? "prefabs_grassland"
                                print("🌍 Procedural world trigger tile detected: layer '\(layerName)', using prefabs file: \(prefabsFile).json")
                                transitionToProceduralWorld(from: position, prefabsFile: prefabsFile)
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    
    func checkObjectCollisions(at position: CGPoint) {
        guard let player = gameState?.player else { return }
        
        // Get player collision frame
        let playerFrame = getPlayerCollisionFrame(at: position)
        
        // Check all object sprites for collision
        var objectsToRemove: [SKSpriteNode] = []
        
        for (sprite, object) in objectSprites {
            // Get object's bounding box (accounting for scale)
            let scaleX = sprite.xScale
            let scaleY = sprite.yScale
            let objectFrame = CGRect(
                x: sprite.position.x,
                y: sprite.position.y,
                width: sprite.size.width * scaleX,
                height: sprite.size.height * scaleY
            )
            
            // Check if player collides with object
            if playerFrame.intersects(objectFrame) {
                
                // Check if object is collectable
                // Objects are collectable if:
                // Only mark as collectible if the property is explicitly set to true
                let isCollectable = object.boolProperty("collectable", default: false)
                
                // Debug: Log collision and collectable status
                print("🔍 Object collision detected: '\(object.name)' (id: \(object.id)), collectable=\(isCollectable)")
                if let collectableValue = object.stringProperty("collectable") {
                    print("   📋 Raw collectable property value: '\(collectableValue)'")
                } else {
                    print("   ⚠️ No 'collectable' property found on object")
                }
                
                // Only collect items on collision (not dialogue objects)
                if isCollectable {
                    print("   ✅ Collecting object '\(object.name)'")
                    // Use the collectObject function which handles stacking and GID
                    // Note: collectObject already removes the sprite, so don't add to objectsToRemove
                    collectObject(object, sprite: sprite)
                } else {
                    print("   ❌ Object is not collectable (property not set or false)")
                }
                // Dialogue objects are handled via question mark interaction, not collision
            }
        }
        
        // Remove collected objects from scene
        for sprite in objectsToRemove {
            sprite.removeFromParent()
            objectSprites.removeValue(forKey: sprite)
            objectGroupNames.removeValue(forKey: sprite)
        }
    }
    
    /// Enter a building by switching to the interior map
    /// - Parameters:
    ///   - interiorMapName: Name of the interior map file (without .tmx extension)
    ///   - doorPosition: Position of the door object (used to find spawn point in interior)
    ///   - doorLayerName: Name of the door layer (for door linking)
    ///   - doorId: ID of the door for matching with exit doors
    func enterBuilding(interiorMapName: String, doorPosition: CGPoint, doorLayerName: String, doorId: String) {
        guard let player = gameState?.player else {
            print("❌ Cannot enter building: no player in gameState")
            return
        }
        
        // Store current map, position, and door info for linking
        previousMapFileName = tiledMapFileName
        previousPlayerPosition = player.position
        entryDoorPosition = doorPosition
        entryDoorLayerName = doorLayerName
        entryDoorId = doorId
        
        print("🏠 Entering building: \(interiorMapName)")
        print("   Previous map: \(previousMapFileName ?? "none")")
        print("   Entry door: layer '\(doorLayerName)' at (\(Int(doorPosition.x)), \(Int(doorPosition.y))), doorId=\(doorId)")
        
        // Switch to interior map
        tiledMapFileName = interiorMapName
        
        // Update GameState with new map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = !useTiledMap
        }
        
        // Reload the map
        reloadCurrentMap()
        
        // Find exit door position in interior map (matching door ID)
        var spawnPosition: CGPoint
        if let exitDoorPos = findExitDoorPosition(matchingDoorId: doorId) {
            // Spawn above the exit door (inside the building, above the door tile)
            // Offset: +110px north (higher Y in SpriteKit)
            spawnPosition = CGPoint(x: exitDoorPos.x, y: exitDoorPos.y + 110)
            print("   Found exit door (doorId=\(doorId)) at (\(Int(exitDoorPos.x)), \(Int(exitDoorPos.y))), spawning above: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y)))")
        } else {
            // No matching exit door found, use map center
            let centerX = mapBounds.midX
            let centerY = mapBounds.midY
            if let safePosition = findSafeSpawnPoint(near: CGPoint(x: centerX, y: centerY)) {
                spawnPosition = safePosition
                print("   No matching exit door found (doorId=\(doorId)), using safe position near map center: (\(Int(safePosition.x)), \(Int(safePosition.y)))")
            } else {
                spawnPosition = CGPoint(x: centerX, y: centerY)
                print("   No matching exit door found (doorId=\(doorId)), using map center: (\(Int(centerX)), \(Int(centerY)))")
            }
        }
        
        // Update player position
        player.position = spawnPosition
        playerSprite?.position = spawnPosition
        
        // Center camera on the interior map
        // Use the background sprite's position which is already centered on the map
        var mapCenterX = mapBounds.midX
        var mapCenterY = mapBounds.midY
        
        if let backgroundSprite = childNode(withName: "mapBackground") as? SKSpriteNode {
            mapCenterX = backgroundSprite.position.x
            mapCenterY = backgroundSprite.position.y
        }
        
        cameraNode?.position = CGPoint(x: mapCenterX, y: mapCenterY)
        
        print("✅ Entered building. Player at: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y))), Camera centered at: (\(Int(mapCenterX)), \(Int(mapCenterY)))")
    }
    
    /// Find the position of the exit door in the current map matching the given door ID
    /// - Parameter doorId: The door ID to match
    private func findExitDoorPosition(matchingDoorId: String) -> CGPoint? {
        // Debug: list all available door layers
        print("🔍 Searching for door with doorId='\(matchingDoorId)'")
        var foundDoors: [String] = []
        for (layerName, props) in layerProperties {
            let doorId = props["doorId"] ?? props["door_id"] ?? layerName
            if props["collision"]?.lowercased() == "true" || props["collision"]?.lowercased() == "1" {
                foundDoors.append("\(layerName) (doorId=\(doorId))")
            }
        }
        if !foundDoors.isEmpty {
            print("   Available door layers: \(foundDoors.joined(separator: ", "))")
        }
        
        // Look for any layer with matching door ID (not just exit doors)
        for (layerName, props) in layerProperties {
            // Check if door ID matches (try both with and without exit property)
            let doorId = props["doorId"] ?? props["door_id"] ?? layerName
            if doorId == matchingDoorId {
                // Check if this layer has exit property, or just match by doorId
                let hasExit = props["exit"]?.lowercased() == "true" || props["exit"]?.lowercased() == "1"
                // If no exit property, we'll still match by doorId (for backwards compatibility)
                
                    // Find a collision tile from this layer to get its position
                    // If there are multiple door tiles, return the first one found
                    // (In the future, we could find the closest one to the entry point)
                    var foundDoorPosition: CGPoint?
                    for (tileKey, layer) in collisionLayerMap where layer == layerName {
                        // Parse tile coordinates
                        let components = tileKey.components(separatedBy: ",")
                        guard components.count == 2,
                              let tileX = Int(components[0]),
                              let tileY = Int(components[1]) else { continue }
                        
                        // Convert tile coordinates to world position
                        let tileWidth = mapTileSize.width
                        let tileHeight = mapTileSize.height
                        let yFlipOffset = mapYFlipOffset
                        
                        let worldX = CGFloat(tileX) * tileWidth + tileWidth / 2
                        let worldY: CGFloat
                        if hasInfiniteLayers {
                            let tiledY = CGFloat(tileY) * tileHeight
                            worldY = yFlipOffset - tiledY - tileHeight / 2
                        } else {
                            let height = regularLayerHeight
                            let tiledY = CGFloat(height - 1 - tileY) * tileHeight
                            worldY = tiledY + tileHeight / 2
                        }
                        
                        let doorPos = CGPoint(x: worldX, y: worldY)
                        print("   Found door tile (doorId=\(doorId)) at tile (\(tileX), \(tileY)) -> world (\(Int(worldX)), \(Int(worldY)))")
                        
                        // Return the first door tile found
                        // TODO: If multiple door tiles exist, find the closest one to entry point
                        foundDoorPosition = doorPos
                        break  // Use first door tile found
                    }
                    
                    if let doorPos = foundDoorPosition {
                        print("   ✅ Using door (doorId=\(doorId), hasExit=\(hasExit)) at world (\(Int(doorPos.x)), \(Int(doorPos.y)))")
                        return doorPos
                    }
                }
            }
        print("   ❌ No door found with doorId='\(matchingDoorId)'")
        return nil
    }
    
    /// Exit the current building and return to the previous map
    /// - Parameters:
    ///   - exitDoorPosition: Position of the exit door (for door linking)
    ///   - exitDoorLayerName: Name of the exit door layer
    ///   - exitDoorId: ID of the exit door for matching with entry door
    func exitBuilding(exitDoorPosition: CGPoint, exitDoorLayerName: String, exitDoorId: String) {
        guard let player = gameState?.player else {
            print("❌ Cannot exit building: no player in gameState")
            return
        }
        
        guard let previousMap = previousMapFileName else {
            print("⚠️ Cannot exit building: no previous map stored")
            return
        }
        
        print("🚪 Exiting building, returning to: \(previousMap)")
        print("   Exit door: layer '\(exitDoorLayerName)' at (\(Int(exitDoorPosition.x)), \(Int(exitDoorPosition.y))), doorId=\(exitDoorId)")
        
        // Store exit door ID for matching
        let matchingDoorId = exitDoorId
        
        // Restore previous map
        tiledMapFileName = previousMap
        
        // Update GameState with restored map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = !useTiledMap
        }
        
        // Reload the map
        reloadCurrentMap()
        
        // Find entry door position in previous map (matching door ID)
        var spawnPosition: CGPoint
        if let entryDoorPos = findEntryDoorPosition(matchingDoorId: matchingDoorId) {
            // Spawn right in front of the entry door (outside the building, close to door)
            // Offset: +20px north (higher Y) and -5px west (lower X)
            spawnPosition = CGPoint(x: entryDoorPos.x + 0.25, y: entryDoorPos.y + 30)
            print("   Found entry door (doorId=\(matchingDoorId)) at (\(Int(entryDoorPos.x)), \(Int(entryDoorPos.y))), spawning in front: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y)))")
        } else if let entryDoorPos = entryDoorPosition {
            // Fallback: use stored entry door position, offset in front
            spawnPosition = CGPoint(x: entryDoorPos.x + 0.25, y: entryDoorPos.y + 30)
            print("   Using stored entry door position, spawning in front: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y)))")
        } else if let previousPosition = previousPlayerPosition {
            // Fallback to previous position
            if canMoveToTiledMap(position: previousPosition) {
                spawnPosition = previousPosition
            } else if let safePosition = findSafeSpawnPoint(near: previousPosition) {
                spawnPosition = safePosition
            } else {
                spawnPosition = previousPosition
            }
            print("   Using previous position: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y)))")
        } else {
            // Last resort: use map center
            let centerX = mapBounds.midX
            let centerY = mapBounds.midY
            spawnPosition = CGPoint(x: centerX, y: centerY)
            print("   No entry door or previous position, using map center: (\(Int(centerX)), \(Int(centerY)))")
        }
        
        // Update player position
        player.position = spawnPosition
        playerSprite?.position = spawnPosition
        cameraNode?.position = spawnPosition
        
        // Clear stored previous map info (we're back outside)
        previousMapFileName = nil
        previousPlayerPosition = nil
        entryDoorPosition = nil
        entryDoorLayerName = nil
        entryDoorId = nil
        
        print("✅ Exited building. Player at: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y)))")
    }
    
    /// Transition to a procedural world (from TMX map or another procedural world)
    /// - Parameters:
    ///   - position: Current position (entry point in current world)
    ///   - prefabsFile: Prefab file to load for the target world
    ///   - entryOffset: Optional offset from entry point where player should spawn in target world
    func transitionToProceduralWorld(from position: CGPoint, prefabsFile: String = "prefabs_grassland", entryOffset: ExitOffset? = nil) {
        guard let player = gameState?.player else {
            print("❌ Cannot transition to procedural world: no player")
            return
        }
        
        // Cooldown check to prevent immediate re-triggering
        let currentTime = CACurrentMediaTime()
        if currentTime - lastTransitionTime < transitionCooldown {
            print("⏱️ Transition on cooldown, ignoring trigger")
            return
        }
        lastTransitionTime = currentTime
        
        let sourceWorld = useTiledMap ? "TMX map" : "procedural world"
        print("🌍 Transitioning to procedural world from \(sourceWorld) (using prefabs: \(prefabsFile).json)")
        
        // CRITICAL: Set currentProceduralWorldPrefab BEFORE calling setupHybridWorldSystem()
        // This ensures setupHybridWorldSystem() loads the correct prefabs file
        currentProceduralWorldPrefab = prefabsFile
        
        // Store the entry position for returning
        // If we're coming from TMX map, store it; otherwise store current procedural world position
        if useTiledMap {
        tmxMapEntryPosition = position
            triggerTilePosition = position
        } else {
            // Coming from another procedural world - store current position for potential return
            proceduralWorldExitPosition = position
            // Keep tmxMapEntryPosition if it exists (for ultimate return to TMX)
        }
        hasMovedAwayFromTrigger = false  // Reset trigger state
        
        // Clear exit tiles from previous transition
        exitTileSprites.forEach { $0.removeFromParent() }
        exitTileSprites.removeAll()
        exitTilePositions.removeAll()
        exitTileData.removeAll()
        
        // If transitioning from another procedural world, clear its chunks and exit tiles
        if !useTiledMap, let chunkManager = chunkManager {
            chunkManager.unloadAllChunks()
            // Also remove any remaining chunk nodes from the scene
            enumerateChildNodes(withName: "chunk_") { node, _ in
                node.removeFromParent()
            }
            // Clear exit tiles from previous procedural world
            exitTileSprites.forEach { $0.removeFromParent() }
            exitTileSprites.removeAll()
            exitTilePositions.removeAll()
            exitTileData.removeAll()
            // Also remove any exit tile nodes that might still be in the scene
            enumerateChildNodes(withName: "exitTile") { node, _ in
                node.removeFromParent()
            }
        }
        
        // Clear TMX map rendering (only if we were using TMX)
        if useTiledMap {
        worldTiles.forEach { $0.removeFromParent() }
        worldTiles.removeAll()
        
        // Clear object sprites
        for (sprite, _) in objectSprites {
            sprite.removeFromParent()
        }
        objectSprites.removeAll()
        objectGroupNames.removeAll()
        }
        
        // Switch to procedural world
        useTiledMap = false
        
        // Update GameState with map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = true
        }
        
        // Show loading screen
        showLoadingScreen(message: "Generating World...")
        
        // CRITICAL: Always reload world config and recreate WorldGenerator when entering procedural world
        // This ensures deterministic generation - same seed always produces same world
        // Even if chunkManager exists, we need to reload config and recreate generator to ensure consistency
        setupHybridWorldSystem()
        
        // Create exit tiles if configured (after setupHybridWorldSystem loads the config)
        if let worldConfig = PrefabFactory.shared.getWorldConfig(),
           let exitConfig = worldConfig.exitConfig,
           exitConfig.hasExit {
            createExitTiles(entryPosition: position, exitConfig: exitConfig)
        }
        
        // Calculate spawn position
        // If entryOffset is provided, use it; otherwise spawn slightly forward to avoid immediate re-trigger
        let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
        let spawnPosition: CGPoint
        if let offset = entryOffset {
            // Use specified offset from entry point
            spawnPosition = CGPoint(
                x: position.x + CGFloat(offset.x) * tileSize,
                y: position.y + CGFloat(offset.y) * tileSize
            )
        } else {
            // Default: spawn 2 tiles north (positive Y) from entry to avoid immediate re-trigger
        let spawnOffset = CGPoint(x: 0, y: tileSize * 2)  // 2 tiles forward
            spawnPosition = CGPoint(x: position.x + spawnOffset.x, y: position.y + spawnOffset.y)
        }
        
        // Set character zPosition to 100 for procedural world (between entitiesBelow at 40 and entitiesAbove at 110)
        characterZPosition = 100
        playerSprite?.zPosition = characterZPosition
        
        // Load initial chunks around player asynchronously, then verify spawn position is safe
        if let chunkManager = chunkManager {
            chunkManager.updateChunksAsync(around: spawnPosition) { [weak self] in
                // After chunks are loaded, check if spawn position is walkable
                guard let self = self else { return }
                
                // Check if spawn position is safe, if not find a nearby safe position
                let finalSpawnPosition: CGPoint
                if self.canMoveToProceduralWorld(position: spawnPosition) {
                    finalSpawnPosition = spawnPosition
                } else {
                    // Try nearby positions in a spiral pattern
                    let tileSize: CGFloat = 32.0
                    var foundSafe = false
                    var safePos = spawnPosition
                    
                    // Search in expanding spiral pattern
                    for radius in 1...5 {
                        for dx in -radius...radius {
                            for dy in -radius...radius {
                                if abs(dx) == radius || abs(dy) == radius {
                                    let testPos = CGPoint(
                                        x: spawnPosition.x + CGFloat(dx) * tileSize,
                                        y: spawnPosition.y + CGFloat(dy) * tileSize
                                    )
                                    if self.canMoveToProceduralWorld(position: testPos) {
                                        safePos = testPos
                                        foundSafe = true
                                        break
                                    }
                                }
                            }
                            if foundSafe { break }
                        }
                        if foundSafe { break }
                    }
                    
                    if foundSafe {
                        print("⚠️ Spawn position at (\(Int(spawnPosition.x)), \(Int(spawnPosition.y))) was blocked, using safe position: (\(Int(safePos.x)), \(Int(safePos.y)))")
                        finalSpawnPosition = safePos
                    } else {
                        print("⚠️ Could not find safe spawn position near (\(Int(spawnPosition.x)), \(Int(spawnPosition.y))), using original position")
                        finalSpawnPosition = spawnPosition
                    }
                }
                
                // Update player position to safe spawn position
                if let player = self.gameState?.player {
                    player.position = finalSpawnPosition
                    self.playerSprite?.position = finalSpawnPosition
                    self.cameraNode?.position = finalSpawnPosition
                }
                
                // Hide loading screen when chunks are loaded
                DispatchQueue.main.async {
                    self.hideLoadingScreen()
                    print("✅ Transitioned to procedural world. Player at: (\(Int(finalSpawnPosition.x)), \(Int(finalSpawnPosition.y))), entry point was: (\(Int(position.x)), \(Int(position.y)))")
                }
            }
            lastPlayerChunk = ChunkKey.fromWorldPosition(
                spawnPosition,
                chunkSize: ChunkManager.defaultChunkSize,
                tileSize: tileSize
            )
        } else {
            // Fallback if chunkManager is nil
            hideLoadingScreen()
        }
    }
    
    /// Transition from procedural world back to TMX map
    /// - Parameters:
    ///   - tmxFileName: Optional TMX file name to load. If nil, uses the stored tmxMapEntryPosition's file
    ///   - doorId: Optional door/exit ID to use for spawning. If nil, uses the stored entry position
    func transitionToTiledMap(tmxFileName: String? = nil, doorId: String? = nil) {
        guard let player = gameState?.player else {
            print("❌ Cannot transition to TMX map: no player")
            return
        }
        
        // Determine which TMX file to load
        let targetTmxFile = tmxFileName ?? tiledMapFileName
        
        // Store exit position in procedural world (for returning later if needed)
        proceduralWorldExitPosition = player.position
        
        // Clear exit tiles from procedural world
        exitTileSprites.forEach { $0.removeFromParent() }
        exitTileSprites.removeAll()
        exitTilePositions.removeAll()
        exitTileData.removeAll()
        
        // Clear procedural world chunks
        if let chunkManager = chunkManager {
            chunkManager.unloadAllChunks()
        }
        
        // Also remove any remaining chunk nodes from the scene
        enumerateChildNodes(withName: "chunk_") { node, _ in
            node.removeFromParent()
        }
        
        // Also remove any exit tile nodes that might still be in the scene
        enumerateChildNodes(withName: "exitTile") { node, _ in
            node.removeFromParent()
        }
        
        // Switch back to TMX map
        useTiledMap = true
        
        // Update TMX file name if different
        if targetTmxFile != tiledMapFileName {
            tiledMapFileName = targetTmxFile
        }
        
        // Update GameState with map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = false
        }
        
        // Reload the TMX map (this loads layerProperties and collisionLayerMap)
        reloadCurrentMap()
        
        // Now that the map is loaded, find the exit door position if doorId was specified
        var doorPosition: CGPoint?  // The actual door tile position (for search reference)
        var spawnPosition: CGPoint?  // Where we want to spawn (may be offset from door)
        
        if let doorId = doorId {
            // Find the exit door position using the loaded map data
            doorPosition = findExitDoorPosition(matchingDoorId: doorId)
            if let doorPos = doorPosition {
                print("🚪 Found exit door (doorId=\(doorId)) at (\(Int(doorPos.x)), \(Int(doorPos.y)))")
                // Spawn 1 full tile north of the door in TILE coordinates, then convert to world
                // This ensures we're in the correct tile, not just offset by world coordinates
                let tileWidth = mapTileSize.width
                let tileHeight = mapTileSize.height
                let yFlipOffset = mapYFlipOffset
                
                // Convert door world position back to tile coordinates
                let doorTileX = Int(floor(doorPos.x / tileWidth))
                let doorTileY: Int
                if hasInfiniteLayers {
                    doorTileY = Int(floor((yFlipOffset - doorPos.y) / tileHeight))
                } else {
                    let height = regularLayerHeight
                    if height > 0 {
                        doorTileY = height - 1 - Int(floor(doorPos.y / tileHeight))
                    } else {
                        doorTileY = Int(floor((yFlipOffset - doorPos.y) / tileHeight))
                    }
                }
                
                print("   Door at tile (\(doorTileX), \(doorTileY)) -> world (\(Int(doorPos.x)), \(Int(doorPos.y)))")
                
                // Spawn 2 tiles north of door to avoid collision box overlap with door tile
                // (lower tileY = north in Tiled coordinates)
                let spawnTileX = doorTileX
                let spawnTileY = doorTileY - 2  // North = lower tileY (spawn 2 tiles north for safety)
                
                // Convert spawn tile coordinates back to world position
                let spawnWorldX = CGFloat(spawnTileX) * tileWidth + tileWidth / 2
                let spawnWorldY: CGFloat
                if hasInfiniteLayers {
                    let tiledY = CGFloat(spawnTileY) * tileHeight
                    spawnWorldY = yFlipOffset - tiledY - tileHeight / 2
                } else {
                    let height = regularLayerHeight
                    if height > 0 {
                        let tiledY = CGFloat(height - 1 - spawnTileY) * tileHeight
                        spawnWorldY = tiledY + tileHeight / 2
                    } else {
                        let tiledY = CGFloat(spawnTileY) * tileHeight
                        spawnWorldY = yFlipOffset - tiledY - tileHeight / 2
                    }
                }
                
                spawnPosition = CGPoint(x: spawnWorldX, y: spawnWorldY)
                print("   Spawn at tile (\(spawnTileX), \(spawnTileY)) -> world (\(Int(spawnWorldX)), \(Int(spawnWorldY)))")
            } else {
                print("⚠️ Could not find exit door with doorId=\(doorId), falling back to entry position")
            }
        }
        
        // Fallback to stored entry position if door not found or not specified
        let baseSpawnPosition = spawnPosition ?? tmxMapEntryPosition
        
        guard let finalSpawnPosition = baseSpawnPosition else {
            print("❌ Cannot transition to TMX map: no entry position or door found")
            return
        }
        
        print("🏠 Transitioning back to TMX map: '\(targetTmxFile)' at (\(Int(finalSpawnPosition.x)), \(Int(finalSpawnPosition.y)))")
        
        // Ensure spawn position is walkable (not on a collision tile)
        // Search from the offset spawn position (where we want to be), not from the door
        // This ensures we prioritize positions near the intended spawn point
        let safeSpawnPosition: CGPoint
        if canMoveToTiledMap(position: finalSpawnPosition) {
            safeSpawnPosition = finalSpawnPosition
            print("✅ Spawn position at (\(Int(finalSpawnPosition.x)), \(Int(finalSpawnPosition.y))) is walkable")
        } else {
            // The offset spawn position is blocked, search from there (not from door)
            // This will prioritize positions near where we want to spawn (north of door)
            print("🔍 Spawn position at (\(Int(finalSpawnPosition.x)), \(Int(finalSpawnPosition.y))) is blocked, searching for safe position nearby...")
            if let safePosition = findSafeSpawnPoint(near: finalSpawnPosition) {
                safeSpawnPosition = safePosition
                print("✅ Found safe spawn position near intended spawn: (\(Int(safePosition.x)), \(Int(safePosition.y)))")
            } else {
                // Last resort: search from door position
                if let doorPos = doorPosition, let safePosition = findSafeSpawnPoint(near: doorPos) {
                    safeSpawnPosition = safePosition
                    print("⚠️ Could not find safe position near spawn, using position near door: (\(Int(safePosition.x)), \(Int(safePosition.y)))")
                } else {
                    print("⚠️ Could not find safe spawn position, using original position")
                    safeSpawnPosition = finalSpawnPosition
                }
            }
        }
        
        // Position player at the safe spawn position
        player.position = safeSpawnPosition
        playerSprite?.position = safeSpawnPosition
        cameraNode?.position = safeSpawnPosition
        
        // Update stored entry position for future returns
        tmxMapEntryPosition = safeSpawnPosition
        
        // Clear procedural world tracking (keep tmxMapEntryPosition in case we want to go back)
        // proceduralWorldExitPosition is kept for potential return
        
        // Debug: verify player position was set correctly
        print("✅ Transitioned back to TMX map. Player position set to: (\(Int(safeSpawnPosition.x)), \(Int(safeSpawnPosition.y)))")
        print("   Door was at: (\(Int(doorPosition?.x ?? 0)), \(Int(doorPosition?.y ?? 0)))")
        print("   Distance from door: \(Int(safeSpawnPosition.y - (doorPosition?.y ?? 0)))px (positive = north, negative = south)")
        
        // Reset trigger state - player must move away before re-triggering
        hasMovedAwayFromTrigger = false
    }
    
    /// Find exit door position in a TMX map by door ID
    private func findExitDoorPositionInMap(tiledMap: TiledMap, matchingDoorId: String) -> CGPoint? {
        // Look for a layer with exit property and matching door ID
        for layer in tiledMap.layers {
            // Check layer properties
            if let exitValue = layer.properties["exit"]?.lowercased(),
               exitValue == "true" || exitValue == "1" {
                // Check if door ID matches
                let exitDoorId = layer.properties["doorId"] ?? layer.properties["door_id"] ?? layer.name
                if exitDoorId == matchingDoorId {
                    // Find a tile from this layer to get its position
                    // For infinite layers, check chunks
                    if layer.isInfinite, let chunks = layer.chunks {
                        for chunk in chunks {
                            // Find first non-zero tile in chunk
                            for (index, gid) in chunk.data.enumerated() where gid > 0 {
                                let x = index % chunk.width
                                let y = index / chunk.width
                                let tileWidth = CGFloat(tiledMap.tileWidth)
                                let tileHeight = CGFloat(tiledMap.tileHeight)
                                let worldX = CGFloat(chunk.x + x) * tileWidth + tileWidth / 2
                                let worldY = CGFloat(chunk.y + y) * tileHeight + tileHeight / 2
                                return CGPoint(x: worldX, y: worldY)
                            }
                        }
                    } else if let data = layer.data {
                        // Regular layer
                        let tileWidth = CGFloat(tiledMap.tileWidth)
                        let tileHeight = CGFloat(tiledMap.tileHeight)
                        var index = 0
                        for y in 0..<layer.height {
                            for x in 0..<layer.width {
                                if index < data.count && data[index] > 0 {
                                    let worldX = CGFloat(x) * tileWidth + tileWidth / 2
                                    let worldY = CGFloat(layer.height - 1 - y) * tileHeight + tileHeight / 2
                                    return CGPoint(x: worldX, y: worldY)
                                }
                                index += 1
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    /// Create exit tiles in the procedural world based on exit configuration
    private func createExitTiles(entryPosition: CGPoint, exitConfig: ExitConfig) {
        let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
        
        // Determine exit tile positions and definitions
        var exitDefinitions: [ExitDefinition] = []
        
        if let exits = exitConfig.exits, !exits.isEmpty {
            // Use new exits array format
            exitDefinitions = exits
        } else if let exitTiles = exitConfig.exitTiles, !exitTiles.isEmpty {
            // Legacy format: convert ExitTileConfig to ExitDefinition
            for exitTile in exitTiles {
                exitDefinitions.append(ExitDefinition(
                    x: exitTile.x,
                    y: exitTile.y,
                    tileGID: exitTile.tileGID,
                    targetPrefabFile: nil,  // Legacy exits return to TMX
                    targetEntryOffset: nil,
                    targetTmxFile: nil,  // Use current TMX file
                    targetDoorId: nil  // Use entry position
                ))
            }
        } else if let defaultOffset = exitConfig.defaultExitOffset {
            // Legacy default offset
            exitDefinitions.append(ExitDefinition(
                x: defaultOffset.x,
                y: defaultOffset.y,
                tileGID: nil,
                targetPrefabFile: nil,  // Legacy exits return to TMX
                targetEntryOffset: nil,
                targetTmxFile: nil,  // Use current TMX file
                targetDoorId: nil  // Use entry position
            ))
        } else {
            // Default: place exit 2 tiles south of entry, returns to TMX
            exitDefinitions.append(ExitDefinition(
                x: 0,
                y: -2,
                tileGID: nil,
                targetPrefabFile: nil,  // Returns to TMX
                targetEntryOffset: nil,
                targetTmxFile: nil,  // Use current TMX file
                targetDoorId: nil  // Use entry position
            ))
        }
        
        // Create visual sprites for exit tiles
        for exitDef in exitDefinitions {
            let exitX = entryPosition.x + CGFloat(exitDef.x) * tileSize
            let exitY = entryPosition.y + CGFloat(exitDef.y) * tileSize
            let exitPos = CGPoint(x: exitX, y: exitY)
            
            // Try to create a tile sprite if a GID is specified
            var sprite: SKSpriteNode? = nil
            
            if let gidString = exitDef.tileGID {
                // Try to parse GID string (format: "tilesetName-tileNumber" or just a number)
                if let gidInt = Int(gidString) {
                    sprite = TileManager.shared.createSprite(for: gidInt, size: CGSize(width: tileSize, height: tileSize))
                } else {
                    // Try to parse format like "exterior-257" - extract the number part
                    let components = gidString.components(separatedBy: "-")
                    if components.count > 1, let lastComponent = components.last, let gidInt = Int(lastComponent) {
                        sprite = TileManager.shared.createSprite(for: gidInt, size: CGSize(width: tileSize, height: tileSize))
                    }
                }
            }
            
            // If tile creation failed or no GID specified, use a black oval
            if sprite == nil {
                // Create a black oval using SKShapeNode with an ellipse path
                // Make it slightly smaller than the tile for better visibility
                let ovalWidth = tileSize * 0.8
                let ovalHeight = tileSize * 0.5
                // Create the oval path centered at origin (SKShapeNode uses center-based coordinates)
                let ovalRect = CGRect(
                    x: -ovalWidth / 2,
                    y: -ovalHeight / 2,
                    width: ovalWidth,
                    height: ovalHeight
                )
                let ovalPath = CGPath(ellipseIn: ovalRect, transform: nil)
                let ovalShape = SKShapeNode(path: ovalPath)
                ovalShape.fillColor = .black
                ovalShape.strokeColor = .black
                ovalShape.lineWidth = 1.0
                ovalShape.alpha = 0.8
                
                // Position the oval lower in the tile to match collision detection
                // Move it down by about 60% from center to align better with ground level
                let verticalOffset = tileSize * 1.0
                ovalShape.position = CGPoint(x: tileSize / 2, y: tileSize / 2 - verticalOffset)
                
                // Wrap the shape node in a container sprite for consistency
                let spriteContainer = SKSpriteNode(color: .clear, size: CGSize(width: tileSize, height: tileSize))
                spriteContainer.addChild(ovalShape)
                sprite = spriteContainer
            }
            
            if let exitSprite = sprite {
                exitSprite.position = exitPos
                exitSprite.anchorPoint = CGPoint(x: 0, y: 0)
                exitSprite.zPosition = 1  // Slightly above ground tiles
                exitSprite.name = "exitTile"
                addChild(exitSprite)
                exitTileSprites.append(exitSprite)
                let exitKey = "\(Int(exitPos.x)),\(Int(exitPos.y))"
                exitTilePositions.insert(exitKey)
                exitTileData[exitKey] = exitDef  // Store exit definition for this position
                
                let targetDesc = exitDef.targetPrefabFile ?? "TMX map"
                print("🚪 Created exit tile at (\(Int(exitPos.x)), \(Int(exitPos.y))) -> \(targetDesc)")
            }
        }
    }
    
    /// Find the position of the entry door in the current map matching the given door ID
    /// - Parameter doorId: The door ID to match
    private func findEntryDoorPosition(matchingDoorId: String) -> CGPoint? {
        // Look for a layer with interior property and matching door ID
        for (layerName, props) in layerProperties {
            if let _ = props["interior"] {
                // Check if door ID matches
                let entryDoorId = props["doorId"] ?? props["door_id"] ?? layerName
                if entryDoorId == matchingDoorId {
                    // Find ALL collision tiles from this layer to calculate center
                    var doorTilePositions: [CGPoint] = []
                    let tileWidth = mapTileSize.width
                    let tileHeight = mapTileSize.height
                    let yFlipOffset = mapYFlipOffset
                    
                    for (tileKey, layer) in collisionLayerMap where layer == layerName {
                        // Parse tile coordinates
                        let components = tileKey.components(separatedBy: ",")
                        guard components.count == 2,
                              let tileX = Int(components[0]),
                              let tileY = Int(components[1]) else { continue }
                        
                        // Convert tile coordinates to world position
                        let worldX = CGFloat(tileX) * tileWidth + tileWidth / 2
                        let worldY: CGFloat
                        if hasInfiniteLayers {
                            let tiledY = CGFloat(tileY) * tileHeight
                            worldY = yFlipOffset - tiledY - tileHeight / 2
                        } else {
                            let height = regularLayerHeight
                            let tiledY = CGFloat(height - 1 - tileY) * tileHeight
                            worldY = tiledY + tileHeight / 2
                        }
                        
                        doorTilePositions.append(CGPoint(x: worldX, y: worldY))
                    }
                    
                    if !doorTilePositions.isEmpty {
                        // Calculate center point of all door tiles
                        let avgX = doorTilePositions.map { $0.x }.reduce(0, +) / CGFloat(doorTilePositions.count)
                        let avgY = doorTilePositions.map { $0.y }.reduce(0, +) / CGFloat(doorTilePositions.count)
                        let centerPos = CGPoint(x: avgX, y: avgY)
                        
                        print("   Found entry door (doorId=\(entryDoorId)) with \(doorTilePositions.count) tiles, center at: (\(Int(centerPos.x)), \(Int(centerPos.y)))")
                        return centerPos
                    }
                }
            }
        }
        return nil
    }
    
    /// Reload the current map (used when switching between maps)
    private func reloadCurrentMap() {
        guard let player = gameState?.player else { return }
        
        // Clear exit tiles from procedural world (if any)
        exitTileSprites.forEach { $0.removeFromParent() }
        exitTileSprites.removeAll()
        exitTilePositions.removeAll()
        exitTileData.removeAll()
        
        // Also remove any exit tile nodes that might still be in the scene
        enumerateChildNodes(withName: "exitTile") { node, _ in
            node.removeFromParent()
        }
        
        // Clear existing sprites
        playerSprite?.removeFromParent()
        companionSprites.values.forEach { $0.removeFromParent() }
        companionSprites.removeAll()
        
        // Clear map container
        enumerateChildNodes(withName: "tiledMapContainer") { node, _ in
            node.removeFromParent()
        }
        worldTiles.removeAll()
        
        // Clear object sprites
        objectSprites.forEach { $0.key.removeFromParent() }
        objectSprites.removeAll()
        objectGroupNames.removeAll()
        
        // Clear animal and enemy sprites
        animalSprites.forEach { $0.key.removeFromParent() }
        animalSprites.removeAll()
        enemySprites.forEach { $0.key.removeFromParent() }
        enemySprites.removeAll()
        
        // Parse and load the new map
        let parsedTiledMap = TiledMapParser.parse(fileName: tiledMapFileName)
        
        // Load tilesets
        if let tiledMap = parsedTiledMap {
            _ = loadTilesetsFromTMX(fileName: tiledMapFileName, preParsedMap: tiledMap)
        } else {
            _ = loadTilesetsFromTMX(fileName: tiledMapFileName)
        }
        
        // Render the new map
        if useTiledMap {
            loadAndRenderTiledMap(fileName: tiledMapFileName, preParsedMap: parsedTiledMap)
        } else {
            renderWorld()
        }
        
        // Recreate player sprite
        createPlayerSprite()
        
        // Recreate companion sprites
        for companion in player.companions {
            createCompanionSprite(companion: companion)
        }
        
        // Update camera
        cameraNode?.position = player.position
    }
    
    func checkForProximityEncounter() {
        guard let player = gameState?.player, !isInCombat else { return }
        
        let playerPosition = player.position
        
        // Check for nearby animals
        for (sprite, animal) in animalSprites {
            let distance = sqrt(pow(sprite.position.x - playerPosition.x, 2) + pow(sprite.position.y - playerPosition.y, 2))
            if distance <= encounterDistance {
                // Remove sprite from world
                sprite.removeFromParent()
                animalSprites.removeValue(forKey: sprite)
                
                // Show animal encounter UI
                showAnimalEncounter(animal: animal)
                return // Only one encounter at a time
            }
        }
        
        // Check for nearby enemies
        for (sprite, enemy) in enemySprites {
            let distance = sqrt(pow(sprite.position.x - playerPosition.x, 2) + pow(sprite.position.y - playerPosition.y, 2))
            if distance <= encounterDistance {
                // Remove sprite from world
                sprite.removeFromParent()
                enemySprites.removeValue(forKey: sprite)
                
                // Start combat
                startCombat(enemy: enemy)
                return // Only one encounter at a time
            }
        }
    }
    
    func showAnimalEncounter(animal: Animal) {
        // Capture a strong reference to the current SKView and self before presenting
        // another scene, since `self.view` will change once we switch scenes.
        guard let gameState = gameState, let skView = self.view else { return }
        
        // Stop any movement
        currentMovementDirection = CGPoint.zero
        isMoving = false
        #if os(macOS)
        pressedKeys.removeAll() // Clear any pressed keys to prevent stuck movement
        #endif
        hideJoystickVisual()
        
        // Pause the game
        isGamePaused = true
        isInDialogue = true
        
        // Store strong reference to self so it doesn't get deallocated
        let gameScene = self
        
        // Create and present encounter scene
        let encounterScene = AnimalEncounterScene(
            size: size,
            animal: animal,
            gameState: gameState,
            completionHandler: { wasBefriended in
                print("[GameScene] Completion handler called, wasBefriended: \(wasBefriended)")
                
                print("[GameScene] Presenting GameScene back, view: \(skView)")
                
                if wasBefriended {
                    // Update companion sprite if befriended
                    // Update companion sprites for all companions
                    for companion in gameState.player.companions {
                        gameScene.createCompanionSprite(companion: companion)
                    }
                    gameScene.gameUI?.updateCompanionStats(companion: gameState.player.companions.first)
                }
                
                // Resume the game
                gameScene.isGamePaused = false
                gameScene.isInDialogue = false
                
                // Stop any movement that might have been happening
                gameScene.currentMovementDirection = CGPoint.zero
                gameScene.isMoving = false
                #if os(macOS)
                gameScene.pressedKeys.removeAll() // Clear any pressed keys to prevent stuck movement
                #endif
                
                // Update player sprite position to match player's current position
                // Remove any duplicate player sprites first
                gameScene.children.forEach { child in
                    if child.name == "player" && child != gameScene.playerSprite {
                        child.removeFromParent()
                    }
                }
                
                // Update existing player sprite or create if missing
                if let playerSprite = gameScene.playerSprite {
                    playerSprite.position = gameState.player.position
                } else {
                    gameScene.createPlayerSprite()
                }
                
                // Update companion positions (they follow player's path)
                gameScene.updateCompanionPositions()
                
                // Ensure camera is properly set up
                if let camera = gameScene.cameraNode {
                    // Make sure the scene's camera property points to our camera
                    gameScene.camera = camera
                    // Position camera at player
                    camera.position = gameState.player.position
                } else {
                    // Recreate camera if it's missing
                    gameScene.cameraNode = SKCameraNode()
                    gameScene.camera = gameScene.cameraNode
                    gameScene.addChild(gameScene.cameraNode!)
                    gameScene.cameraNode?.position = gameState.player.position
                }
                
                // Clean up UI - it will be recreated in didMove(to:) after scene is presented
                // This ensures the view size is correct when positioning UI elements
                if let camera = gameScene.cameraNode {
                    // Clean up any orphaned UI elements from camera first
                    camera.children.forEach { child in
                        if child.name == "playerStatsBg" || child.name == "companionStatsBg" ||
                           child.name == "inventoryButton" || child.name == "buildButton" || child.name == "settingsButton" {
                            child.removeFromParent()
                        }
                    }
                    
                    // Clean up existing UI object if it exists
                    if let existingUI = gameScene.gameUI {
                        existingUI.cleanup()
                        gameScene.gameUI = nil
                    }
                }
                
                // Return to game scene - use the captured view reference
                // UI will be recreated in didMove(to:) with correct view size
                skView.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.3))
            }
        )
        
        // Present encounter scene with transition
        skView.presentScene(encounterScene, transition: SKTransition.fade(withDuration: 0.3))
    }
    
    func startCombat(enemy: Enemy) {
        guard let gameState = gameState, let skView = self.view else { return }
        
        // Stop any movement
        currentMovementDirection = CGPoint.zero
        isMoving = false
        #if os(macOS)
        pressedKeys.removeAll() // Clear any pressed keys to prevent stuck movement
        #endif
        hideJoystickVisual()
        
        // Pause the game
        isGamePaused = true
        isInCombat = true
        let combat = CombatSystem.initiateCombat(player: gameState.player, enemy: enemy)
        gameState.currentCombat = combat
        
        // Store strong reference to self
        let gameScene = self
        
        // Create and present combat scene
        let combatScene = CombatScene(
            size: size,
            combat: combat,
            gameState: gameState,
            completionHandler: { winner in
                // Return to game scene
                
                // Handle combat results
                if winner == .player {
                    // Victory - already handled in CombatScene (XP gained)
                    gameScene.gameUI?.updatePlayerStats(player: gameState.player)
                } else if winner == .enemy {
                    // Defeat - reset player HP
                    gameState.player.hitPoints = max(1, gameState.player.maxHitPoints / 2)
                    gameScene.gameUI?.updatePlayerStats(player: gameState.player)
                }
                
                // Resume the game
                gameScene.isGamePaused = false
                gameScene.isInCombat = false
                gameState.currentCombat = nil
                
                // Stop any movement
                gameScene.currentMovementDirection = CGPoint.zero
                gameScene.isMoving = false
                #if os(macOS)
                gameScene.pressedKeys.removeAll() // Clear any pressed keys to prevent stuck movement
                #endif
                
                // Update player sprite position to match player's current position
                // Remove any duplicate player sprites first
                gameScene.children.forEach { child in
                    if child.name == "player" && child != gameScene.playerSprite {
                        child.removeFromParent()
                    }
                }
                
                // Update existing player sprite or create if missing
                if let playerSprite = gameScene.playerSprite {
                    playerSprite.position = gameState.player.position
                } else {
                    gameScene.createPlayerSprite()
                }
                
                // Update companion positions (they follow player's path)
                gameScene.updateCompanionPositions()
                
                // Ensure camera is positioned correctly
                if let camera = gameScene.cameraNode {
                    camera.position = gameState.player.position
                    
                    // Clean up any orphaned UI elements from camera first
                    camera.children.forEach { child in
                        if child.name == "playerStatsBg" || child.name == "companionStatsBg" ||
                           child.name == "inventoryButton" || child.name == "buildButton" || child.name == "settingsButton" {
                            child.removeFromParent()
                        }
                    }
                    
                    // Clean up existing UI object if it exists
                    // UI will be recreated in didMove(to:) after scene is presented
                    if let existingUI = gameScene.gameUI {
                        existingUI.cleanup()
                        gameScene.gameUI = nil
                    }
                }
                
                // Return to game scene
                // UI will be recreated in didMove(to:) with correct view size
                skView.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.3))
            }
        )
        
        // Present combat scene with transition
        skView.presentScene(combatScene, transition: SKTransition.fade(withDuration: 0.3))
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered
        guard let player = gameState?.player, !isGamePaused, !isInCombat, !isInDialogue else { return }
        
        // Check if view size has changed (fallback detection)
        if let view = self.view {
            let currentViewSize = view.bounds.size
            if previousViewSize != currentViewSize && previousViewSize != .zero {
                // View size changed, update UI
                updateUIForSizeChange()
            }
            previousViewSize = currentViewSize
        }
        
        // Update chunk loading/unloading for hybrid world system
        if !useTiledMap, let chunkManager = chunkManager, let player = gameState?.player {
            // Use TMX tile size to match TMX maps
            let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
            
            let currentChunk = ChunkKey.fromWorldPosition(
                player.position,
                chunkSize: ChunkManager.defaultChunkSize,
                tileSize: tileSize
            )
            
            // Check if player moved to a new chunk
            if lastPlayerChunk != currentChunk {
                // Use async chunk loading to prevent freezes
                chunkManager.updateChunks(around: player.position)
                lastPlayerChunk = currentChunk
                
                // Pre-load chunks ahead of player movement direction to prevent future freezes
                // Calculate movement direction from last position
                if let lastChunk = lastPlayerChunk {
                    let dx = currentChunk.x - lastChunk.x
                    let dy = currentChunk.y - lastChunk.y
                    
                    // Pre-load chunks in the direction of movement
                    if dx != 0 || dy != 0 {
                        let preloadChunk = ChunkKey(x: currentChunk.x + dx, y: currentChunk.y + dy)
                        // Check if chunk needs loading (not already loaded)
                        if !chunkManager.isChunkLoaded(preloadChunk) {
                            chunkManager.loadChunkAsync(preloadChunk)
                        }
                    }
                }
            }
            
            // Check for transition via exit tiles (can go to TMX or another procedural world)
            // Only check if cooldown has passed and exit is configured
            let currentTime = CACurrentMediaTime()
            if currentTime - lastTransitionTime >= transitionCooldown {
                // Check if player is standing on an exit tile
                let playerTileX = Int(player.position.x / 32.0)
                let playerTileY = Int(player.position.y / 32.0)
                let playerTilePos = CGPoint(x: CGFloat(playerTileX) * 32.0, y: CGFloat(playerTileY) * 32.0)
                
                // Check if player is on any exit tile (within 1 tile distance)
                for exitKey in exitTilePositions {
                    // Parse exit position from string key (this is the bottom-left corner of the tile)
                    let components = exitKey.components(separatedBy: ",")
                    guard components.count == 2,
                          let exitX = Int(components[0]),
                          let exitY = Int(components[1]) else { continue }
                    
                    // Calculate the center of the exit tile (exit position is bottom-left, so add half tile size)
                    let exitTileCenter = CGPoint(
                        x: CGFloat(exitX) + tileSize / 2,
                        y: CGFloat(exitY) + tileSize / 2
                    )
                    let distance = sqrt(pow(player.position.x - exitTileCenter.x, 2) + pow(player.position.y - exitTileCenter.y, 2))
                    // Check if player is within half a tile of the center (more accurate for centered ovals)
                    if distance < tileSize / 2 {
                        // Use the original exit position (bottom-left) for transition and logging
                        let exitPos = CGPoint(x: CGFloat(exitX), y: CGFloat(exitY))
                        
                        // Find the exit definition for this position
                        if let exitDef = exitTileData[exitKey] {
                            if let targetPrefab = exitDef.targetPrefabFile {
                                // Transition to another procedural world
                                print("🚪 Player stepped on exit tile at (\(Int(exitPos.x)), \(Int(exitPos.y))), transitioning to world: \(targetPrefab)")
                                transitionToProceduralWorld(from: exitPos, prefabsFile: targetPrefab, entryOffset: exitDef.targetEntryOffset)
                            } else {
                                // Transition back to TMX map
                                let targetTmx = exitDef.targetTmxFile
                                let targetDoorId = exitDef.targetDoorId
                                print("🚪 Player stepped on exit tile at (\(Int(exitPos.x)), \(Int(exitPos.y))), transitioning back to TMX map: '\(targetTmx ?? "current")', doorId: \(targetDoorId ?? "none")")
                                transitionToTiledMap(tmxFileName: targetTmx, doorId: targetDoorId)
                            }
                            return
                        } else {
                            // Fallback: no exit definition found, return to TMX
                            print("🚪 Player stepped on exit tile at (\(Int(exitPos.x)), \(Int(exitPos.y))), transitioning back to TMX map (no exit definition)")
                    transitionToTiledMap()
                    return
                        }
                    }
                }
            }
        }
        
        // Handle auto-walking if active
        if isAutoWalking, let targetPos = autoWalkTarget {
            // Check if we've reached the target
            var reachedTarget = false
            
            // If we have a target node (e.g., chest), check collision intersection
            if let targetNode = autoWalkTargetNode {
                // CRITICAL: Check if player's collision frame intersects with chest's collision box
                // This is more reliable than distance checks
                let playerFrame = getPlayerCollisionFrame(at: player.position)
                
                // Get chest collision box using the same method as click detection
                if let chestCollisionBox = getChestCollisionBox(node: targetNode) {
                    if playerFrame.intersects(chestCollisionBox) {
                        reachedTarget = true
                        print("✅ Auto-walk: Player collision with chest detected - opening chest")
                    }
                } else {
                    // Fallback: use bounding box check
                    let targetBoundingBox = calculateBoundingBox(for: targetNode)
                    if playerFrame.intersects(targetBoundingBox) {
                        reachedTarget = true
                        print("✅ Auto-walk: Player collision with target detected (fallback)")
                    }
                }
            } else {
                // Fallback to distance check if no target node
            let distance = sqrt(pow(targetPos.x - player.position.x, 2) + pow(targetPos.y - player.position.y, 2))
                if distance <= autoWalkInteractionRadius {
                    reachedTarget = true
                }
            }
            
            if reachedTarget {
                // Reached target - stop walking and call completion handler
                isAutoWalking = false
                autoWalkTarget = nil
                autoWalkTargetNode = nil
                autoWalkLastPosition = nil
                autoWalkStuckCounter = 0
                autoWalkLastDirection = CGPoint.zero
                autoWalkObstacleAvoidance = nil
                currentMovementDirection = CGPoint.zero  // Reset movement direction
                isMoving = false
                
                // Call completion handler if provided
                if let completion = autoWalkCompletion {
                    completion()
                    autoWalkCompletion = nil
                }
            } else {
                // Check if we're stuck (not making progress)
                if let lastPos = autoWalkLastPosition {
                    let progressDistance = sqrt(pow(player.position.x - lastPos.x, 2) + pow(player.position.y - lastPos.y, 2))
                    if progressDistance < 1.0 {  // Moved less than 1 pixel
                        autoWalkStuckCounter += 1
                    } else {
                        autoWalkStuckCounter = 0  // Reset if we're making progress
                    }
                } else {
                    autoWalkLastPosition = player.position
                }
                
                // Calculate desired direction toward target
                let dx = targetPos.x - player.position.x
                let dy = targetPos.y - player.position.y
                let distance = sqrt(pow(dx, 2) + pow(dy, 2))
                let desiredDir = CGPoint(x: dx / distance, y: dy / distance)
                
                // Determine movement direction (with obstacle avoidance if needed)
                var movementDir: CGPoint
                
                // If we have an obstacle avoidance direction, use it temporarily
                if let avoidance = autoWalkObstacleAvoidance {
                    movementDir = avoidance
                    // Check if we can move in the desired direction again (we've cleared the obstacle)
                    let testPos = CGPoint(
                        x: player.position.x + desiredDir.x * movementSpeed,
                        y: player.position.y + desiredDir.y * movementSpeed
                    )
                    let canMoveDirect = useTiledMap ? canMoveToTiledMap(position: testPos) : canMoveToProceduralWorld(position: testPos)
                    
                    if canMoveDirect {
                        // Clear obstacle avoidance - we can go direct again
                        autoWalkObstacleAvoidance = nil
                        movementDir = desiredDir
                    }
                } else {
                    // Try direct path first
                    let testPos = CGPoint(
                        x: player.position.x + desiredDir.x * movementSpeed,
                        y: player.position.y + desiredDir.y * movementSpeed
                    )
                    let canMoveDirect = useTiledMap ? canMoveToTiledMap(position: testPos) : canMoveToProceduralWorld(position: testPos)
                    
                    if canMoveDirect {
                        movementDir = desiredDir
                    } else {
                        // Direct path blocked - try obstacle avoidance with smoother pathfinding
                        // First, try to find the best perpendicular direction that gets us closer to target
                        let perpendicular1 = CGPoint(x: -desiredDir.y, y: desiredDir.x)  // 90 degrees left
                        let perpendicular2 = CGPoint(x: desiredDir.y, y: -desiredDir.x)   // 90 degrees right
                        
                        // Test both perpendicular directions
                        let testPos1 = CGPoint(
                            x: player.position.x + perpendicular1.x * movementSpeed,
                            y: player.position.y + perpendicular1.y * movementSpeed
                        )
                        let testPos2 = CGPoint(
                            x: player.position.x + perpendicular2.x * movementSpeed,
                            y: player.position.y + perpendicular2.y * movementSpeed
                        )
                        
                        let canMove1 = useTiledMap ? canMoveToTiledMap(position: testPos1) : canMoveToProceduralWorld(position: testPos1)
                        let canMove2 = useTiledMap ? canMoveToTiledMap(position: testPos2) : canMoveToProceduralWorld(position: testPos2)
                        
                        // If we're already avoiding an obstacle, continue in that direction if possible
                        if let currentAvoidance = autoWalkObstacleAvoidance {
                            let avoidanceLength = sqrt(currentAvoidance.x * currentAvoidance.x + currentAvoidance.y * currentAvoidance.y)
                            if avoidanceLength > 0.001 {
                                let currentAvoidanceNormalized = CGPoint(
                                    x: currentAvoidance.x / avoidanceLength,
                                    y: currentAvoidance.y / avoidanceLength
                                )
                                
                                // Check if current avoidance direction is still valid
                                let testCurrentAvoidance = CGPoint(
                                    x: player.position.x + currentAvoidanceNormalized.x * movementSpeed,
                                    y: player.position.y + currentAvoidanceNormalized.y * movementSpeed
                                )
                                let canMoveCurrent = useTiledMap ? canMoveToTiledMap(position: testCurrentAvoidance) : canMoveToProceduralWorld(position: testCurrentAvoidance)
                                
                                if canMoveCurrent {
                                    // Continue in current avoidance direction for smoother movement
                                    movementDir = currentAvoidanceNormalized
                                } else if canMove1 {
                                    // Switch to perpendicular1
                                    movementDir = perpendicular1
                                    autoWalkObstacleAvoidance = perpendicular1
                                } else if canMove2 {
                                    // Switch to perpendicular2
                                    movementDir = perpendicular2
                                    autoWalkObstacleAvoidance = perpendicular2
                                } else {
                                    // Try diagonal directions (combinations of perpendicular and desired)
                                    let diagonal1 = CGPoint(
                                        x: (perpendicular1.x + desiredDir.x) / 2,
                                        y: (perpendicular1.y + desiredDir.y) / 2
                                    )
                                    let diagonal2 = CGPoint(
                                        x: (perpendicular2.x + desiredDir.x) / 2,
                                        y: (perpendicular2.y + desiredDir.y) / 2
                                    )
                                    
                                    let testDiag1 = CGPoint(
                                        x: player.position.x + diagonal1.x * movementSpeed,
                                        y: player.position.y + diagonal1.y * movementSpeed
                                    )
                                    let testDiag2 = CGPoint(
                                        x: player.position.x + diagonal2.x * movementSpeed,
                                        y: player.position.y + diagonal2.y * movementSpeed
                                    )
                                    
                                    let canMoveDiag1 = useTiledMap ? canMoveToTiledMap(position: testDiag1) : canMoveToProceduralWorld(position: testDiag1)
                                    let canMoveDiag2 = useTiledMap ? canMoveToTiledMap(position: testDiag2) : canMoveToProceduralWorld(position: testDiag2)
                                    
                                    if canMoveDiag1 {
                                        movementDir = diagonal1
                                        autoWalkObstacleAvoidance = diagonal1
                                    } else if canMoveDiag2 {
                                        movementDir = diagonal2
                                        autoWalkObstacleAvoidance = diagonal2
                                    } else {
                                        // Completely stuck - try going backward slightly
                                        let backwardDir = CGPoint(x: -desiredDir.x, y: -desiredDir.y)
                                        let testPosBack = CGPoint(
                                            x: player.position.x + backwardDir.x * movementSpeed * 0.5,
                                            y: player.position.y + backwardDir.y * movementSpeed * 0.5
                                        )
                                        let canMoveBack = useTiledMap ? canMoveToTiledMap(position: testPosBack) : canMoveToProceduralWorld(position: testPosBack)
                                        
                                        if canMoveBack && autoWalkStuckCounter < 10 {
                                            // Back up slightly to try a different angle
                                            movementDir = backwardDir
                                            autoWalkObstacleAvoidance = backwardDir
                                        } else {
                                            // Completely stuck - just try to move in desired direction anyway
                                            movementDir = desiredDir
                                            autoWalkObstacleAvoidance = nil
                                            if autoWalkStuckCounter > 30 {
                                                // Been stuck too long - cancel auto-walk
                                                print("⚠️ Auto-walk stuck for too long, cancelling")
                                                isAutoWalking = false
                                                autoWalkTarget = nil
                                                autoWalkLastPosition = nil
                                                autoWalkStuckCounter = 0
                                                autoWalkLastDirection = CGPoint.zero
                                                autoWalkObstacleAvoidance = nil
                                                currentMovementDirection = CGPoint.zero
                                                isMoving = false
                                            }
                                        }
                                    }
                                }
                            } else {
                                // Avoidance vector is too small, reset it and try perpendicular directions
                        if canMove1 {
                                    movementDir = perpendicular1
                                    autoWalkObstacleAvoidance = perpendicular1
                                } else if canMove2 {
                                    movementDir = perpendicular2
                                    autoWalkObstacleAvoidance = perpendicular2
                                } else {
                                    movementDir = desiredDir
                                    autoWalkObstacleAvoidance = nil
                                }
                            }
                        } else {
                            // No current avoidance - choose best perpendicular direction
                            if canMove1 && canMove2 {
                                // Both work - choose the one that gets us closer to target
                                let dist1 = sqrt(pow(testPos1.x - targetPos.x, 2) + pow(testPos1.y - targetPos.y, 2))
                                let dist2 = sqrt(pow(testPos2.x - targetPos.x, 2) + pow(testPos2.y - targetPos.y, 2))
                                if dist1 < dist2 {
                                    movementDir = perpendicular1
                                    autoWalkObstacleAvoidance = perpendicular1
                                } else {
                                    movementDir = perpendicular2
                                    autoWalkObstacleAvoidance = perpendicular2
                                }
                            } else if canMove1 {
                            movementDir = perpendicular1
                            autoWalkObstacleAvoidance = perpendicular1
                        } else if canMove2 {
                            movementDir = perpendicular2
                            autoWalkObstacleAvoidance = perpendicular2
                        } else {
                            // Both perpendicular directions blocked - try going backward slightly
                            let backwardDir = CGPoint(x: -desiredDir.x, y: -desiredDir.y)
                            let testPosBack = CGPoint(
                                x: player.position.x + backwardDir.x * movementSpeed * 0.5,
                                y: player.position.y + backwardDir.y * movementSpeed * 0.5
                            )
                            let canMoveBack = useTiledMap ? canMoveToTiledMap(position: testPosBack) : canMoveToProceduralWorld(position: testPosBack)
                            
                            if canMoveBack && autoWalkStuckCounter < 10 {
                                // Back up slightly to try a different angle
                                movementDir = backwardDir
                                autoWalkObstacleAvoidance = backwardDir
                            } else {
                                // Completely stuck - just try to move in desired direction anyway
                                movementDir = desiredDir
                                autoWalkObstacleAvoidance = nil
                                if autoWalkStuckCounter > 30 {
                                    // Been stuck too long - cancel auto-walk
                                    print("⚠️ Auto-walk stuck for too long, cancelling")
                                    isAutoWalking = false
                                    autoWalkTarget = nil
                                    autoWalkLastPosition = nil
                                    autoWalkStuckCounter = 0
                                    autoWalkLastDirection = CGPoint.zero
                                    autoWalkObstacleAvoidance = nil
                                    currentMovementDirection = CGPoint.zero
                                    isMoving = false
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Update last position for stuck detection
                autoWalkLastPosition = player.position
                autoWalkLastDirection = movementDir
                
                // Update movement direction for sprite animation
                currentMovementDirection = movementDir
                isMoving = true
                
                // Move player
                movePlayer(direction: movementDir)
                
                // Update sprite animation during auto-walk
                // Initialize timer if needed (first frame of auto-walk)
                if animationTimer < 0 {
                    animationTimer = currentTime
                }
                
                // Advance animation frame based on timer
                if currentTime - animationTimer > animationFrameDuration {
                    let animationFrameCount = 4  // 4 frames per walk animation
                    currentAnimationFrame = (currentAnimationFrame + 1) % animationFrameCount
                    animationTimer = currentTime
                }
                
                // Determine direction for sprite facing
                let x = movementDir.x
                let y = movementDir.y
                let direction: String
                if abs(y) > abs(x) {
                    direction = y > 0 ? "north" : "south"
                } else if abs(x) > abs(y) {
                    direction = x > 0 ? "east" : "west"
                } else {
                    direction = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
                }
                
                // Update last facing direction BEFORE calling updatePlayerSpriteAnimation
                // This ensures the animation function has the correct direction
                lastFacingDirection = direction
                
                // Update sprite animation - this will use currentAnimationFrame to alternate textures
                updatePlayerSpriteAnimation(isMoving: true)
            }
        }
        
        // Continuous movement if direction is set (only if not auto-walking)
        if currentMovementDirection != CGPoint.zero && !isAutoWalking {
            movePlayer(direction: currentMovementDirection)
            
            // Only advance frame based on timer
            if currentTime - animationTimer > animationFrameDuration {
                // Advance animation frame
                let animationFrameCount = 4  // 4 frames per walk animation
                currentAnimationFrame = (currentAnimationFrame + 1) % animationFrameCount
                animationTimer = currentTime
            }
            
            // Determine current direction
            let x = currentMovementDirection.x
            let y = currentMovementDirection.y
            let direction: String
            if abs(y) > abs(x) {
                direction = y > 0 ? "north" : "south"
            } else if abs(x) > abs(y) {
                // East sprite faces RIGHT, West sprite faces LEFT (side profile)
                // Moving right (x > 0) should use EAST (faces right), moving left (x < 0) should use WEST (faces left)
                direction = x > 0 ? "east" : "west"
            } else {
                direction = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
            }
            
            // Always update animation when moving - let the function handle texture changes
            updatePlayerSpriteAnimation(isMoving: true)
        } else if !isAutoWalking {
            // Player is not moving and not auto-walking - update to idle animation
            // Don't set to idle during auto-walk (auto-walk handles its own animation)
            if lastAnimationIsMoving != false {
                updatePlayerSpriteAnimation(isMoving: false)
                lastAnimationIsMoving = false
                lastAnimationFrame = 0
            }
            animationTimer = currentTime  // Reset timer when stopped
            currentAnimationFrame = 0  // Reset frame when stopped
            // Update camera even when not moving (in case player stops near edge)
            updateCamera()
        }
        
        // Update UI
        gameUI?.updatePlayerStats(player: player)
        gameUI?.updateCompanionStats(companion: player.companions.first)
    }
    
    func restoreGameFromState() {
        print("🟢 restoreGameFromState() called")
        guard let gameState = gameState else {
            print("❌ No gameState in restoreGameFromState")
            return
        }
        
        // Try to find and set the current character ID
        if currentCharacterId == nil {
            let characters = SaveManager.getAllCharacters()
            currentCharacterId = characters.first(where: {
                $0.name == gameState.player.name && $0.characterClass == gameState.player.characterClass
            })?.id
        }
        
        // Clear existing sprites
        playerSprite?.removeFromParent()
        companionSprites.values.forEach { $0.removeFromParent() }
        companionSprites.removeAll()
        
        // OPTIMIZATION: Remove map container node if it exists (much faster than removing individual tiles)
        enumerateChildNodes(withName: "tiledMapContainer") { node, _ in
            node.removeFromParent()
        }
        worldTiles.removeAll()
        
        // Clear animal and enemy sprites
        animalSprites.forEach { $0.key.removeFromParent() }
        animalSprites.removeAll()
        enemySprites.forEach { $0.key.removeFromParent() }
        enemySprites.removeAll()
        
        // CRITICAL: Restore map information from saved game state
        tiledMapFileName = gameState.currentMapFileName
        useTiledMap = !gameState.useProceduralWorld
        print("🗺️ Restoring map from save: fileName='\(tiledMapFileName)', useProceduralWorld=\(gameState.useProceduralWorld), useTiledMap=\(useTiledMap)")
        
        // OPTIMIZATION: Parse TMX file once and reuse for both tileset loading and map rendering
        // This avoids double-parsing which was causing slow save loading
        let parsedTiledMap: TiledMap?
        if useTiledMap {
            // Parse the TMX file once
            parsedTiledMap = TiledMapParser.parse(fileName: tiledMapFileName)
            
            // Load tilesets using the parsed map
            if let tiledMap = parsedTiledMap {
                _ = loadTilesetsFromTMX(fileName: tiledMapFileName, preParsedMap: tiledMap)
            } else {
                // Fallback: try parsing in loadTilesetsFromTMX if pre-parsing failed
                _ = loadTilesetsFromTMX(fileName: tiledMapFileName)
            }
        } else {
            // For procedural generation, we still need tilesets but don't need the full map
            _ = loadTilesetsFromTMX(fileName: tiledMapFileName)
            parsedTiledMap = nil
        }
        
        // Re-render the world (reuse parsed map if available)
        if useTiledMap {
            loadAndRenderTiledMap(fileName: tiledMapFileName, preParsedMap: parsedTiledMap)
        } else {
            renderWorld()
        }
        
        // Recreate player sprite at current position (may have been adjusted by map loading)
        createPlayerSprite()
        
        // Recreate companion sprites for all companions
        for companion in gameState.player.companions {
            createCompanionSprite(companion: companion)
        }
        
        // Update camera position (use current position, which may have been adjusted by map)
        // If using Tiled map, ensure player is in a safe position (not in collision tile)
        if useTiledMap && !collisionMap.isEmpty {
            if !canMoveToTiledMap(position: gameState.player.position) {
                print("⚠️ Saved player position is in a collision tile, finding safe position...")
                if let safePosition = findSafeSpawnPoint(near: gameState.player.position) {
                    gameState.player.position = safePosition
                    print("✅ Moved player to safe position: (\(Int(safePosition.x)), \(Int(safePosition.y)))")
                } else {
                    print("⚠️ WARNING: Could not find safe position for saved player location!")
                }
            }
        }
        
        cameraNode?.position = gameState.player.position
        
        // Update UI
        gameUI?.updatePlayerStats(player: gameState.player)
        gameUI?.updateCompanionStats(companion: gameState.player.companions.first)
        
        // Re-spawn animals and enemies only for auto-generated worlds, not TMX maps
        // (they're not saved, so we'll need to regenerate them)
        if !useTiledMap {
            spawnInitialAnimals()
        }
        
        print("Game state restored - Player at: \(gameState.player.position)")
    }
    
    func makeSpinny(at pos: CGPoint, color: SKColor) -> SKShapeNode {
        // Create a simple spinning shape node
        let shape = SKShapeNode(circleOfRadius: 10)
        shape.fillColor = color
        shape.strokeColor = color
        shape.position = pos
        shape.lineWidth = 2
        
        let spin = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 1)
        shape.run(SKAction.repeatForever(spin))
        
        return shape
    }
    
    /// Render an object group (object layer) from a Tiled map
    private func renderTiledObjectGroup(_ objectGroup: TiledObjectGroup, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0, container: SKNode? = nil) {
        let parentNode = container ?? self
        
        print("🎯 Rendering object group '\(objectGroup.name)' with \(objectGroup.objects.count) objects")
        
        if objectGroup.objects.isEmpty {
            print("⚠️ WARNING: Object group '\(objectGroup.name)' has no objects!")
            return
        }
        
            for object in objectGroup.objects {
            // Check if this object should spawn an enemy, animal, or NPC from a prefab
            if let enemyId = object.stringProperty("enemyId"),
               let enemyPrefab = PrefabFactory.shared.getEnemyPrefab(enemyId) {
                spawnEnemyFromPrefab(enemyPrefab, at: object, tileSize: tileSize, yFlipOffset: yFlipOffset, container: parentNode)
                continue  // Skip normal object rendering for prefab entities
            }
            
            if let animalId = object.stringProperty("animalId"),
               let animalPrefab = PrefabFactory.shared.getAnimalPrefab(animalId) {
                spawnAnimalFromPrefab(animalPrefab, at: object, tileSize: tileSize, yFlipOffset: yFlipOffset, container: parentNode)
                continue  // Skip normal object rendering for prefab entities
            }
            
            if let npcId = object.stringProperty("npcId"),
               let npcPrefab = PrefabFactory.shared.getNPCPrefab(npcId) {
                spawnNPCFromPrefab(npcPrefab, at: object, tileSize: tileSize, yFlipOffset: yFlipOffset, container: parentNode)
                continue  // Skip normal object rendering for prefab entities
            }
            
            // Calculate world position
            // Tiled uses top-left origin (Y increases downward)
            // Object coordinates in Tiled are in BASE tile pixel coordinates (e.g., 16x16)
            // But we're rendering at SCALED tile size (e.g., 32x32 with scale factor 2.0)
            // So we need to scale the object coordinates by the same factor
            // Scale factor = tileSize.width / baseTileWidth (typically 16)
            let baseTileWidth: CGFloat = 16.0  // Base tile size in Tiled
            let scaleFactor = tileSize.width / baseTileWidth
            
            // Scale object coordinates to match the rendered tile size
            let scaledX = object.x * scaleFactor
            let scaledY = object.y * scaleFactor
            
            // Convert to SpriteKit coordinates (Y flip)
            // For infinite maps with yFlipOffset=0, tiles use: worldY = -tiledY
            // Objects should align with tiles, so we use the same calculation
            let worldX = scaledX
            let worldY = yFlipOffset - scaledY
            
            print("   📍 Object coordinate conversion: Tiled base coords (\(Int(object.x)), \(Int(object.y))) -> scaled (\(Int(scaledX)), \(Int(scaledY))) -> SpriteKit world (\(Int(worldX)), \(Int(worldY))), scaleFactor=\(scaleFactor), yFlipOffset=\(yFlipOffset)")
            
        }
    }
}
