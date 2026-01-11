//
//  GameScene.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit

class GameScene: SKScene {
    
    var gameState: GameState?
    var playerSprite: SKSpriteNode?
    var companionSprites: [UUID: SKSpriteNode] = [:]  // Map of companion ID to sprite
    var worldTiles: [SKSpriteNode] = []
    var animalSprites: [SKSpriteNode: Animal] = [:]
    var enemySprites: [SKSpriteNode: Enemy] = [:]
    var gameUI: GameUI?
    var combatUI: CombatUI?
    var cameraNode: SKCameraNode?
    
    // Player position history for companions to follow
    private var playerPositionHistory: [CGPoint] = []
    private let maxPositionHistory = 30  // Keep last 30 positions
    
    // Flag to determine if we should use Tiled map or generated world
    // When false, tilesets are still loaded from TMX for use with procedural generation
    var useTiledMap: Bool = true  // Use TMX file instead of procedural generation
    var tiledMapFileName: String = "Exterior"
    
    // Collision detection for Tiled maps
    // Use (Int, Int) tuple for tile coordinates instead of CGPoint (CGPoint is not Hashable)
    private var collisionMap: Set<String> = []  // Set of non-walkable tile positions as "x,y" strings
    private var collisionLayerMap: [String: String] = [:]  // Map of "x,y" -> layer name that created the collision
    private var mapBounds: CGRect = .zero  // Map bounds for collision checking
    private var mapYFlipOffset: CGFloat = 0  // Y flip offset for coordinate conversion
    private var mapTileSize: CGSize = .zero  // Tile size used for rendering (for collision checks)
    
    // Player collision box (matches sprite size exactly)
    // Sprite is 24x24 pixels with center anchor (extends from -12 to +12 in both axes)
    // Collision box: 24x24 pixels, matches sprite perfectly
    private let playerCollisionSize: CGSize = CGSize(width: 24, height: 24)  // Width: 24px, Height: 24px (matches sprite)
    private let playerCollisionOffsetY: CGFloat = 0.0  // No offset - collision box is centered on sprite
    
    var currentCharacterId: UUID? // Track which character is currently playing
    var label: SKLabelNode? // Label property (may be used by Actions.sks)
    
    var isInCombat: Bool = false
    var isInDialogue: Bool = false
    // Use a separate flag to track game logic pause state to avoid
    // conflicting with SKScene/SKNode's built-in `isPaused` property.
    var isGamePaused: Bool = false
    var movementSpeed: CGFloat = 2.0
    let encounterDistance: CGFloat = 40.0 // Distance to trigger encounter
    
    // Touch handling properties (moved from extension)
    var touchStartLocation: CGPoint? // Screen coordinates where touch began
    var isMoving: Bool = false
    var currentMovementDirection: CGPoint = CGPoint.zero
    var joystickVisual: SKNode? // Visual joystick indicator
    
    // Keyboard handling properties (macOS)
    #if os(macOS)
    var pressedKeys: Set<UInt16> = [] // Track which keys are currently pressed
    #endif
    
    // Camera following properties
    let cameraFollowThresholdPercent: CGFloat = 0.25 // Percentage of screen dimension (25% from edge)
    let cameraFollowSpeed: CGFloat = 5.0 // Speed multiplier for camera following
    
    class func newGameScene() -> GameScene {
        // Create scene programmatically (no .sks file needed)
        let scene = GameScene()
        scene.scaleMode = .aspectFill
        scene.backgroundColor = SKColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        return scene
    }
    
    func setUpScene() {
        // Create camera
        cameraNode = SKCameraNode()
        camera = cameraNode
        addChild(cameraNode!)
        
        // Initialize game state with default player
        let abilityScores = AbilityScores(strength: 15, dexterity: 14, constitution: 13, intelligence: 12, wisdom: 10, charisma: 8)
        let player = Player(name: "Hero", characterClass: .ranger, abilityScores: abilityScores)
        
        // Give player some initial items and skills for testing
        player.inventory.append(Material(materialType: .wood, quantity: 20))
        player.inventory.append(Material(materialType: .stone, quantity: 15))
        player.inventory.append(Material(materialType: .iron, quantity: 10))
        player.inventory.append(Item(name: "Meat", type: .meat, quantity: 3))
        player.inventory.append(Item(name: "Berries", type: .berries, quantity: 5))
        
        // Initialize some building skills
        player.buildingSkills[.carpentry] = 2
        player.buildingSkills[.farming] = 1
        player.buildingSkills[.animalHusbandry] = 1
        
        // Use a fixed seed for consistent world generation
        // You can change this seed to generate different worlds, but it will be consistent across sessions
        let worldSeed = 12345 // Fixed seed for deterministic world generation
        let world = WorldMap(width: 50, height: 50, seed: worldSeed)
        gameState = GameState(player: player, world: world)
        
        // Set player position to center of world (in world coordinates)
        // Use scaled tile size to match renderWorld() scaling
        let scaleFactor: CGFloat = 2.0
        let scaledTileSize = world.tileSize * scaleFactor
        let worldCenterX = CGFloat(world.width) * scaledTileSize / 2
        let worldCenterY = CGFloat(world.height) * scaledTileSize / 2
        player.position = CGPoint(x: worldCenterX, y: worldCenterY)
        
        // Create combat UI (doesn't need camera)
        combatUI = CombatUI(scene: self)
        
        // Load tilesets from TMX file for use with procedural generation
        // This gives us access to all the tileset images even when generating procedurally
        loadTilesetsFromTMX(fileName: tiledMapFileName)
        
        // Load and render Tiled map (or use renderWorld() for generated world)
        if useTiledMap {
            loadAndRenderTiledMap(fileName: tiledMapFileName)
        } else {
            renderWorld()
        }
        
        // Create player sprite
        createPlayerSprite()
        
        // Center camera on player
        cameraNode?.position = player.position
        
        // UI will be created in didMove(to:) after view is available
        
        // Spawn some initial animals
        spawnInitialAnimals()
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
        var minX: CGFloat = CGFloat.greatestFiniteMagnitude
        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude
        
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            if layer.isInfinite, let chunks = layer.chunks {
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
        
        // Second pass: Render layers
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            // Z-Position hierarchy:
            // - Background: -100000 (far behind)
            // - Tiles: 0 to ~60 (based on layer index or zOffset property - layers are typically 0-60)
            // - Animals/Enemies: 50 (above tiles, below entities)
            // - Companion: 99 (above animals/enemies)
            // - Player: 100 (always on top of world objects)
            // - UI: 200+ (above everything)
            // Use zOffset property if set, otherwise use layer index
            let baseZPosition = CGFloat(layerIndex)
            let zOffset = layer.floatProperty("zOffset", default: 0)
            let tileZPosition = baseZPosition + CGFloat(zOffset)
            renderTiledLayer(layer, tileSize: tileSize, zPosition: tileZPosition, yFlipOffset: yFlipOffset)
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
            
            // CRITICAL: Set scene background color to green grass (removes gray areas)
            // Use the same color as the grass tiles in your map
            self.backgroundColor = SKColor(red: 0.4, green: 0.7, blue: 0.4, alpha: 1.0)  // Bright green grass color
            
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
            
            
            // Constrain camera to map bounds to prevent seeing empty areas
            if let camera = cameraNode {
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
            }
            
            // Store map bounds and rendering info for collision detection
            self.mapBounds = CGRect(x: minX, y: minY, width: mapWidth, height: mapHeight)
            self.mapTileSize = tileSize
            
            // Parse collision layers from TMX and create collision map
            // Layers with "collision" in the name or properties will be used for collision
            parseCollisionFromTiledMap(tiledMap, tileSize: tileSize, yFlipOffset: yFlipOffset)
            
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
                cameraNode?.position = player.position
            }
        }
    }
    
    /// Render a single layer from a Tiled map
    private func renderTiledLayer(_ layer: TiledLayer, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0) {
        if layer.isInfinite, let chunks = layer.chunks {
            // Render infinite map with chunks
            for chunk in chunks {
                renderTiledChunk(chunk, tileSize: tileSize, zPosition: zPosition, yFlipOffset: yFlipOffset)
            }
        } else if let data = layer.data {
            // Render regular (non-infinite) map
            var index = 0
            for y in 0..<layer.height {
                for x in 0..<layer.width {
                    let gid = data[index]
                    index += 1
                    
                    guard gid > 0 else { continue }
                    
                    if let sprite = TileManager.shared.createSprite(for: gid, size: tileSize) {
                        // Verify sprite has valid texture
                        if sprite.texture == nil {
                            print("⚠️ WARNING: Sprite created for GID \(gid) but has no texture!")
                            continue
                        }
                        
                        sprite.position = CGPoint(
                            x: CGFloat(x) * tileSize.width,
                            y: CGFloat(layer.height - y - 1) * tileSize.height // Flip Y (Tiled uses top-left origin)
                        )
                        sprite.anchorPoint = CGPoint(x: 0, y: 0)
                        sprite.zPosition = zPosition
                        
                        // Ensure sprite is visible
                        sprite.alpha = 1.0
                        sprite.isHidden = false
                        
                        addChild(sprite)
                        worldTiles.append(sprite)
                        
                    } else {
                        // Failed to create sprite - continue
                    }
                }
            }
        }
    }
    
    /// Render a chunk from an infinite map
    private func renderTiledChunk(_ chunk: TiledChunk, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0) {
        let expectedDataCount = chunk.width * chunk.height
        if chunk.data.count != expectedDataCount {
            print("Warning: Chunk data count (\(chunk.data.count)) doesn't match expected (\(expectedDataCount)) - will render what we have")
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
                        print("⚠️ WARNING: Sprite created for GID \(gid) but has no texture!")
                        continue
                    }
                    
                    // Calculate world position: chunk coordinates are in tile units
                    // Tiled uses top-left origin (Y increases downward)
                    // SpriteKit uses bottom-left origin (Y increases upward)
                    // We need to flip the Y coordinate: newY = yFlipOffset - oldY
                    // where oldY = (chunk.y + y) * tileSize.height (Tiled coordinate)
                    let worldX = CGFloat(chunk.x + x) * tileSize.width
                    let tiledY = CGFloat(chunk.y + y) * tileSize.height
                    let worldY = yFlipOffset - tiledY
                    
                    sprite.position = CGPoint(x: worldX, y: worldY)
                    sprite.anchorPoint = CGPoint(x: 0, y: 0)  // Bottom-left corner
                    sprite.zPosition = zPosition
                    
                    // Ensure sprite is visible
                    sprite.alpha = 1.0
                    sprite.isHidden = false
                    
                    addChild(sprite)
                    worldTiles.append(sprite)
                    
                    // Debug: Log first few sprites (disabled to improve performance)
                    // if worldTiles.count <= 5 {
                    //     print("✅ Created sprite #\(worldTiles.count) for GID \(gid) at (\(Int(worldX)), \(Int(worldY)))")
                    // }
                }
            }
        }
    }
    
    func createPlayerSprite() {
        guard let player = gameState?.player else { return }
        
        // Create simple colored square for player (replace with sprite later)
        let sprite = SKSpriteNode(color: .blue, size: CGSize(width: 24, height: 24))
        sprite.position = player.position
        // Player should be above ground/terrain layers but below objects, fences, and roofs
        // Ground layers are typically at index 0-10, objects at 10-30+
        // Using zPosition = 10 keeps player above ground but below objects
        sprite.zPosition = 11
        sprite.name = "player"
        addChild(sprite)
        playerSprite = sprite
        
        // Create companion sprites for all companions
        for companion in player.companions {
            createCompanionSprite(companion: companion)
        }
        
        // Initialize position history with current player position
        playerPositionHistory = [player.position]
    }
    
    func createCompanionSprite(companion: Animal) {
        // Remove existing sprite for this companion if it exists
        if let existingSprite = companionSprites[companion.id] {
            existingSprite.removeFromParent()
        }
        
        let sprite = SKSpriteNode(color: .orange, size: CGSize(width: 20, height: 20))
        sprite.position = playerSprite?.position ?? CGPoint.zero
        // Companion should be slightly below player, but still above ground layers
        sprite.zPosition = 99
        sprite.name = "companion"
        addChild(sprite)
        companionSprites[companion.id] = sprite
    }
    
    func removeCompanionSprite(companionId: UUID) {
        if let sprite = companionSprites[companionId] {
            sprite.removeFromParent()
            companionSprites.removeValue(forKey: companionId)
        }
    }
    
    /// Update companion positions - each companion follows the player's previous positions
    func updateCompanionPositions() {
        guard let player = gameState?.player else { return }
        
        let companionFollowDistance: CGFloat = 25.0  // Distance between companions
        let followSpeed: CGFloat = 2.5  // Speed at which companions move toward their target
        
        for (index, companion) in player.companions.enumerated() {
            guard let sprite = companionSprites[companion.id] else {
                // Sprite doesn't exist yet, create it
                createCompanionSprite(companion: companion)
                continue
            }
            
            // Calculate target position: each companion follows a position from history
            // Companion 0 follows position from 5 steps ago, companion 1 from 10 steps ago, etc.
            let stepsBack = (index + 1) * 5
            let targetPosition: CGPoint
            
            if stepsBack < playerPositionHistory.count {
                // Use historical position
                targetPosition = playerPositionHistory[playerPositionHistory.count - stepsBack - 1]
            } else if !playerPositionHistory.isEmpty {
                // Not enough history, use oldest position
                targetPosition = playerPositionHistory[0]
            } else {
                // No history yet, follow behind player
                let offset = CGFloat(index + 1) * companionFollowDistance
                targetPosition = CGPoint(
                    x: player.position.x,
                    y: player.position.y - offset
                )
            }
            
            // Move sprite toward target position
            let currentPos = sprite.position
            let dx = targetPosition.x - currentPos.x
            let dy = targetPosition.y - currentPos.y
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance > 1.0 {
                // Normalize direction and move
                let moveX = (dx / distance) * followSpeed
                let moveY = (dy / distance) * followSpeed
                sprite.position = CGPoint(
                    x: currentPos.x + moveX,
                    y: currentPos.y + moveY
                )
            } else {
                // Close enough, snap to target
                sprite.position = targetPosition
            }
        }
    }
    
    func spawnInitialAnimals() {
        guard let world = gameState?.world else { return }
        
        // Spawn a few animals randomly
        for _ in 0..<10 {
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            let animalTypes = AnimalType.allCases
            if let randomType = animalTypes.randomElement() {
                let animal = Animal(type: randomType)
                animal.position = position
                _ = world.spawnAnimal(animal, at: position)
                
                // Create visual representation
                let sprite = SKSpriteNode(color: .red, size: CGSize(width: 16, height: 16))
                sprite.position = position
                // Animals should be above tiles but below player
                sprite.zPosition = 50
                sprite.name = "animal"
                addChild(sprite)
                
                // Store reference to animal
                animalSprites[sprite] = animal
            }
        }
        
        // Spawn some enemies too
        for _ in 0..<5 {
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            guard let player = gameState?.player else { continue }
            let enemy = EncounterSystem.generateRandomEnemy(level: player.level)
            
            // Create visual representation for enemy
            let sprite = SKSpriteNode(color: .purple, size: CGSize(width: 18, height: 18))
            sprite.position = position
            // Enemies should be above tiles but below player
            sprite.zPosition = 50
            sprite.name = "enemy"
            addChild(sprite)
            
            // Store reference to enemy
            enemySprites[sprite] = enemy
        }
    }
    
    override func didMove(to view: SKView) {
        // Always update scene size from view bounds to ensure correct rendering
        // This is critical for proper texture positioning and scaling
        size = view.bounds.size
        print("🔵 GameScene: didMove - Scene size set to view bounds: \(size), view.bounds: \(view.bounds)")
        
        // Only set up scene if it hasn't been set up yet
        if gameState == nil {
            self.setUpScene()
        }
        
        // Create or recreate UI after view is available so we can use accurate view size
        // This ensures UI elements are positioned correctly relative to the camera
        // We recreate it here (even if it exists) to fix positioning after scene transitions
        if let camera = cameraNode, let player = gameState?.player {
            // Clean up existing UI if it exists (e.g., after returning from encounter)
            if let existingUI = gameUI {
                existingUI.cleanup()
                gameUI = nil
            }
            
            // Clean up any orphaned UI elements from camera
            camera.children.forEach { child in
                if child.name == "playerStatsBg" || child.name == "companionStatsBg" ||
                   child.name == "inventoryButton" || child.name == "buildButton" || child.name == "settingsButton" {
                    child.removeFromParent()
                }
            }
            
            // Create fresh UI with correct view size
            gameUI = GameUI(scene: self, camera: camera)
            gameUI?.updatePlayerStats(player: player)
            gameUI?.updateCompanionStats(companion: player.companions.first)
        }
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Update UI layout when view size changes (orientation change)
        updateUIForSizeChange()
    }
    
    func updateUIForSizeChange() {
        print("GameScene: updateUIForSizeChange called - Scene size: \(size), View size: \(view?.bounds.size ?? .zero)")
        
        // Update UI layout when view size changes (orientation change)
        gameUI?.updateLayout()
        
        // Restore UI stats after layout update
        if let player = gameState?.player {
            gameUI?.updatePlayerStats(player: player)
            gameUI?.updateCompanionStats(companion: player.companions.first)
        }
    }

    func movePlayer(direction: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        let newPosition = CGPoint(
            x: player.position.x + direction.x * movementSpeed,
            y: player.position.y + direction.y * movementSpeed
        )
        
        // Check movement: if using Tiled map, use collision map
        // Otherwise use the WorldMap collision system
        let canMove: Bool
        if useTiledMap {
            // Check collision map for Tiled maps
            canMove = canMoveToTiledMap(position: newPosition)
        } else {
            canMove = gameState?.world.canMoveTo(position: newPosition) ?? false
        }
        
        if canMove {
            let oldPosition = player.position
            player.position = newPosition
            playerSprite?.position = newPosition
            
            // Add position to history for companions to follow
            playerPositionHistory.append(newPosition)
            if playerPositionHistory.count > maxPositionHistory {
                playerPositionHistory.removeFirst()
            }
            
            // Update companion positions (each follows the player's previous positions)
            updateCompanionPositions()
            
            // Update camera to follow player when near screen edges
            updateCamera()
            
            // Check for encounters based on proximity to sprites
            checkForProximityEncounter()
        }
    }
    
    func updateCamera() {
        guard let player = gameState?.player, let camera = cameraNode else { return }
        
        // Use view size if available, otherwise fall back to scene size
        // This ensures we have the correct dimensions for the current orientation
        let screenWidth: CGFloat
        let screenHeight: CGFloat
        if let view = self.view {
            screenWidth = view.bounds.size.width
            screenHeight = view.bounds.size.height
        } else {
            screenWidth = size.width
            screenHeight = size.height
        }
        
        // Calculate player position relative to camera center (in world coordinates)
        let playerWorldPos = player.position
        let cameraWorldPos = camera.position
        
        // Calculate offset from camera center
        let offsetX = playerWorldPos.x - cameraWorldPos.x
        let offsetY = playerWorldPos.y - cameraWorldPos.y
        
        // Get screen bounds (half dimensions)
        let halfWidth = screenWidth / 2
        let halfHeight = screenHeight / 2
        
        // Calculate threshold as percentage of screen size (works for both portrait and landscape)
        let thresholdX = screenWidth * cameraFollowThresholdPercent
        let thresholdY = screenHeight * cameraFollowThresholdPercent
        
        // Calculate desired camera position to keep player within threshold zone
        var newCameraX = cameraWorldPos.x
        var newCameraY = cameraWorldPos.y
        
        // Check horizontal boundaries
        // Left edge: if player is closer than thresholdX to left edge, move camera left
        if offsetX < -halfWidth + thresholdX {
            // Calculate where camera should be to keep player at thresholdX from left edge
            newCameraX = playerWorldPos.x + halfWidth - thresholdX
        }
        // Right edge: if player is closer than thresholdX to right edge, move camera right
        else if offsetX > halfWidth - thresholdX {
            // Calculate where camera should be to keep player at thresholdX from right edge
            newCameraX = playerWorldPos.x - halfWidth + thresholdX
        }
        
        // Check vertical boundaries
        // Bottom edge: if player is closer than thresholdY to bottom edge, move camera down
        if offsetY < -halfHeight + thresholdY {
            newCameraY = playerWorldPos.y + halfHeight - thresholdY
        }
        // Top edge: if player is closer than thresholdY to top edge, move camera up
        else if offsetY > halfHeight - thresholdY {
            newCameraY = playerWorldPos.y - halfHeight + thresholdY
        }
        
        // Update camera position immediately
        if abs(newCameraX - cameraWorldPos.x) > 0.01 || abs(newCameraY - cameraWorldPos.y) > 0.01 {
            camera.position = CGPoint(x: newCameraX, y: newCameraY)
        }
    }
    
    func createJoystickVisual(at position: CGPoint) -> SKNode {
        let joystickContainer = SKNode()
        joystickContainer.position = position
        joystickContainer.zPosition = 1000 // High z-position to appear above other elements
        joystickContainer.alpha = 0.6 // Translucent
        
        // Create outer circle
        let circleRadius: CGFloat = 40.0
        let circle = SKShapeNode(circleOfRadius: circleRadius)
        circle.fillColor = SKColor(white: 0.3, alpha: 0.5)
        circle.strokeColor = SKColor(white: 0.7, alpha: 0.8)
        circle.lineWidth = 2.0
        joystickContainer.addChild(circle)
        
        // Create arrow indicators (up, down, left, right)
        let arrowLength: CGFloat = 15.0
        let arrowWidth: CGFloat = 3.0
        let arrowDistance: CGFloat = circleRadius + 5.0
        
        // Up arrow
        let upArrow = createArrow(direction: .up, length: arrowLength, width: arrowWidth)
        upArrow.position = CGPoint(x: 0, y: arrowDistance)
        joystickContainer.addChild(upArrow)
        
        // Down arrow
        let downArrow = createArrow(direction: .down, length: arrowLength, width: arrowWidth)
        downArrow.position = CGPoint(x: 0, y: -arrowDistance)
        joystickContainer.addChild(downArrow)
        
        // Left arrow
        let leftArrow = createArrow(direction: .left, length: arrowLength, width: arrowWidth)
        leftArrow.position = CGPoint(x: -arrowDistance, y: 0)
        joystickContainer.addChild(leftArrow)
        
        // Right arrow
        let rightArrow = createArrow(direction: .right, length: arrowLength, width: arrowWidth)
        rightArrow.position = CGPoint(x: arrowDistance, y: 0)
        joystickContainer.addChild(rightArrow)
        
        return joystickContainer
    }
    
    enum ArrowDirection {
        case up, down, left, right
    }
    
    func createArrow(direction: ArrowDirection, length: CGFloat, width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        let arrowHeadSize: CGFloat = width * 1.5
        
        switch direction {
        case .up:
            // Arrow pointing up: triangle shape
            path.move(to: CGPoint(x: 0, y: length / 2)) // Tip
            path.addLine(to: CGPoint(x: -arrowHeadSize, y: -length / 2 + arrowHeadSize))
            path.addLine(to: CGPoint(x: arrowHeadSize, y: -length / 2 + arrowHeadSize))
            path.closeSubpath()
        case .down:
            // Arrow pointing down: triangle shape
            path.move(to: CGPoint(x: 0, y: -length / 2)) // Tip
            path.addLine(to: CGPoint(x: -arrowHeadSize, y: length / 2 - arrowHeadSize))
            path.addLine(to: CGPoint(x: arrowHeadSize, y: length / 2 - arrowHeadSize))
            path.closeSubpath()
        case .left:
            // Arrow pointing left: triangle shape
            path.move(to: CGPoint(x: -length / 2, y: 0)) // Tip
            path.addLine(to: CGPoint(x: length / 2 - arrowHeadSize, y: -arrowHeadSize))
            path.addLine(to: CGPoint(x: length / 2 - arrowHeadSize, y: arrowHeadSize))
            path.closeSubpath()
        case .right:
            // Arrow pointing right: triangle shape
            path.move(to: CGPoint(x: length / 2, y: 0)) // Tip
            path.addLine(to: CGPoint(x: -length / 2 + arrowHeadSize, y: -arrowHeadSize))
            path.addLine(to: CGPoint(x: -length / 2 + arrowHeadSize, y: arrowHeadSize))
            path.closeSubpath()
        }
        
        let arrow = SKShapeNode(path: path)
        arrow.fillColor = SKColor(white: 0.8, alpha: 0.9)
        arrow.strokeColor = SKColor(white: 1.0, alpha: 1.0)
        arrow.lineWidth = 1.0
        return arrow
    }
    
    func showJoystickVisual(at position: CGPoint) {
        guard let camera = cameraNode else { return }
        
        // Remove existing joystick if any
        hideJoystickVisual()
        
        // Create and add joystick visual
        let joystick = createJoystickVisual(at: position)
        camera.addChild(joystick)
        joystickVisual = joystick
    }
    
    func updateJoystickVisual(direction: CGPoint) {
        guard let joystick = joystickVisual else { return }
        
        // Optionally highlight the arrow in the direction of movement
        // For now, we'll just keep it static at the touch location
        // You could add visual feedback here if desired
    }
    
    func hideJoystickVisual() {
        joystickVisual?.removeFromParent()
        joystickVisual = nil
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
    
    // Track previous view size to detect changes
    private var previousViewSize: CGSize = .zero
    
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
        
        // Continuous movement if direction is set
        if currentMovementDirection != CGPoint.zero {
            movePlayer(direction: currentMovementDirection)
        } else {
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
        worldTiles.forEach { $0.removeFromParent() }
        worldTiles.removeAll()
        
        // Clear animal and enemy sprites
        animalSprites.forEach { $0.key.removeFromParent() }
        animalSprites.removeAll()
        enemySprites.forEach { $0.key.removeFromParent() }
        enemySprites.removeAll()
        
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
        
        // Re-spawn animals and enemies (they're not saved, so we'll need to regenerate them)
        // For now, we'll just clear them. You might want to save/load these too in the future
        spawnInitialAnimals()
        
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
    
    // MARK: - Collision Detection for Tiled Maps
    
    /// Parse collision data from Tiled map layers
    /// Uses layer properties to determine collision:
    /// - Layers with property "collision" = true are used for collision
    /// - Layers without the "collision" property are walkable (collision = false by default)
    /// - Only layers with explicit "collision" = true property will block movement
    func parseCollisionFromTiledMap(_ tiledMap: TiledMap, tileSize: CGSize, yFlipOffset: CGFloat) {
        collisionMap.removeAll()
        collisionLayerMap.removeAll()
        
        var foundLayers: [String] = []
        var allLayerNames: [String] = []
        
        // First, log all available layers
        for layer in tiledMap.layers {
            allLayerNames.append(layer.name)
        }
        
        for layer in tiledMap.layers {
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
                    var index = 0
                    for y in 0..<layer.height {
                        for x in 0..<layer.width {
                            guard index < data.count else { break }
                            
                            let gid = data[index]
                            index += 1
                            
                            if gid > 0 {
                                // Store tile position as tile coordinates for collision checking
                                let key = "\(x),\(y)"
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
            }
        }
        
        if foundLayers.isEmpty {
        }
    }
    
    /// Check if player can move to a position on Tiled map
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
        
        // Calculate player's bounding box (matches sprite size exactly)
        // Player sprite: 24x24 pixels, anchor at center (0.5, 0.5)
        // Collision box: 24x24 pixels, centered on sprite position
        let playerHalfWidth = playerCollisionSize.width / 2
        let playerHalfHeight = playerCollisionSize.height / 2
        
        // Collision box is centered on sprite position (no offset)
        let collisionCenterY = position.y + playerCollisionOffsetY
        
        // Player bounding box corners (in world coordinates)
        let playerLeft = position.x - playerHalfWidth
        let playerRight = position.x + playerHalfWidth
        let playerBottom = collisionCenterY - playerHalfHeight
        let playerTop = collisionCenterY + playerHalfHeight
        
        // Convert to Tiled tile coordinates
        // Y coordinates: During rendering, worldY = yFlipOffset - tiledY
        // So: tiledY = yFlipOffset - worldY, and tileY = tiledY / tileHeight
        let playerLeftTiledY = yFlipOffset - playerTop    // Top of player in Tiled coords
        let playerRightTiledY = yFlipOffset - playerBottom // Bottom of player in Tiled coords
        
        // Calculate which tiles the player's bounding box overlaps
        let minTileX = Int(floor(playerLeft / tileWidth))
        let maxTileX = Int(floor(playerRight / tileWidth))
        let minTileY = Int(floor(playerLeftTiledY / tileHeight))
        let maxTileY = Int(floor(playerRightTiledY / tileHeight))
        
        // Check all tiles that the player's bounding box overlaps
        var hasCollision = false
        var collisionKey: String? = nil
        var collisionLayer: String? = nil
        
        for tileX in minTileX...maxTileX {
            for tileY in minTileY...maxTileY {
                let key = "\(tileX),\(tileY)"
                if collisionMap.contains(key) {
                    hasCollision = true
                    collisionKey = key
                    collisionLayer = collisionLayerMap[key]
                    break
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
        
        // Search in expanding square pattern (faster than spiral)
        let maxSearchRadius = 100  // Maximum tiles to search in each direction
        var checkedTiles = Set<String>()
        
        // Helper to check if a tile coordinate is safe (not in collision map)
        func isSafeTile(_ tileX: Int, _ tileY: Int) -> Bool {
            let key = "\(tileX),\(tileY)"
            if checkedTiles.contains(key) {
                return false  // Already checked this tile
            }
            checkedTiles.insert(key)
            
            // Check if this tile and immediate neighbors are clear
            // (Player sprite might span multiple tiles, so we need a small clear area)
            let checkOffsets: [(Int, Int)] = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
            for (dx, dy) in checkOffsets {
                let checkKey = "\(tileX + dx),\(tileY + dy)"
                if collisionMap.contains(checkKey) {
                    return false
                }
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
        
        // Search in expanding square pattern
        for radius in 1..<maxSearchRadius {
            // Check all positions at this radius distance
            for dx in -radius...radius {
                for dy in -radius...radius {
                    // Only check positions on the perimeter (at exactly this radius)
                    let dist = max(abs(dx), abs(dy))
                    if dist == radius {
                        let testTileX = startTileX + dx
                        let testTileY = startTileY + dy
                        
                        if isSafeTile(testTileX, testTileY) {
                            let safeWorldPos = tileToWorld(testTileX, testTileY)
                            print("   Found safe tile at radius \(radius): tile(\(testTileX), \(testTileY)) -> world(\(Int(safeWorldPos.x)), \(Int(safeWorldPos.y)))")
                            return safeWorldPos
                        }
                    }
                }
            }
        }
        
        // Fallback: try some positions near the map bounds (might be safer areas)
        print("⚠️ Exhaustive search failed, trying positions near map bounds...")
        let mapCenterTileX = Int(floor((mapBounds.minX + mapBounds.maxX) / 2 / tileWidth))
        let mapCenterTileY = Int(floor((mapYFlipOffset - (mapBounds.minY + mapBounds.maxY) / 2) / tileHeight))
        
        for offset in 1..<20 {
            let testPositions: [(Int, Int)] = [
                (mapCenterTileX + offset, mapCenterTileY),
                (mapCenterTileX - offset, mapCenterTileY),
                (mapCenterTileX, mapCenterTileY + offset),
                (mapCenterTileX, mapCenterTileY - offset)
            ]
            
            for (tileX, tileY) in testPositions {
                if isSafeTile(tileX, tileY) {
                    let safeWorldPos = tileToWorld(tileX, tileY)
                    print("   Found safe tile near map center: tile(\(tileX), \(tileY)) -> world(\(Int(safeWorldPos.x)), \(Int(safeWorldPos.y)))")
                    return safeWorldPos
                }
            }
        }
        
        return nil
    }
}

#if os(iOS) || os(tvOS)
// Touch-based event handling
extension GameScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let camera = cameraNode else { return }
        
        // Check if touching UI elements (panels are children of camera)
        if let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
            let cameraLocation = convert(location, to: camera)
            if inventoryPanel.contains(cameraLocation) {
                handleInventoryPanelTouch(at: location, in: inventoryPanel)
                return
            }
        }
        
        if let buildPanel = camera.childNode(withName: "buildPanel") {
            let cameraLocation = convert(location, to: camera)
            if buildPanel.contains(cameraLocation) {
                handleBuildPanelTouch(at: location, in: buildPanel)
                return
            }
        }
        
        if let settingsPanel = camera.childNode(withName: "settingsPanel") {
            let cameraLocation = convert(location, to: camera)
            if settingsPanel.contains(cameraLocation) {
                handleSettingsPanelTouch(at: location, in: settingsPanel)
                return
            }
        }
        
        if let saveSlotPanel = camera.childNode(withName: "saveSlotPanel") {
            let cameraLocation = convert(location, to: camera)
            if saveSlotPanel.contains(cameraLocation) {
                handleSaveSlotPanelTouch(at: location, in: saveSlotPanel)
                return
            }
        }
        
        if let loadSlotPanel = camera.childNode(withName: "loadSlotPanel") {
            let cameraLocation = convert(location, to: camera)
            if loadSlotPanel.contains(cameraLocation) {
                handleLoadSlotPanelTouch(at: location, in: loadSlotPanel)
                return
            }
        }
        
        // Check for UI buttons (convert to camera coordinates)
        if let inventoryButton = gameUI?.inventoryButton, let camera = cameraNode {
            let cameraLocation = convert(location, to: camera)
            if inventoryButton.contains(cameraLocation) {
                showInventory()
                return
            }
        }
        
        if let buildButton = gameUI?.buildButton, let camera = cameraNode {
            let cameraLocation = convert(location, to: camera)
            if buildButton.contains(cameraLocation) {
                showBuildMenu()
                return
            }
        }
        
        if let settingsButton = gameUI?.settingsButton, let camera = cameraNode {
            let cameraLocation = convert(location, to: camera)
            if settingsButton.contains(cameraLocation) {
                showSettings()
                return
            }
        }
        
        // Start joystick movement - store initial touch location in screen/camera coordinates
        guard !isGamePaused, !isInCombat, !isInDialogue else { return }
        guard let camera = cameraNode else { return }
        
        // Convert touch location to camera coordinates (screen space)
        let cameraLocation = convert(location, to: camera)
        touchStartLocation = cameraLocation
        isMoving = true
        
        // Show joystick visual at touch location
        showJoystickVisual(at: cameraLocation)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isMoving, !isGamePaused, !isInCombat, !isInDialogue else { return }
        guard let startLocation = touchStartLocation, let camera = cameraNode else { return }
        
        let location = touch.location(in: self)
        // Convert current touch location to camera coordinates (screen space)
        let cameraLocation = convert(location, to: camera)
        
        // Calculate delta from initial touch point (joystick-style)
        let delta = CGPoint(
            x: cameraLocation.x - startLocation.x,
            y: cameraLocation.y - startLocation.y
        )
        
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
        let deadZone: CGFloat = 10.0 // Minimum distance to register movement
        
        if distance > deadZone {
            // Normalize direction
            let normalized = CGPoint(
                x: delta.x / distance,
                y: delta.y / distance
            )
            currentMovementDirection = normalized
            updateJoystickVisual(direction: normalized)
        } else {
            currentMovementDirection = CGPoint.zero
            updateJoystickVisual(direction: CGPoint.zero)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isMoving = false
        currentMovementDirection = CGPoint.zero
        touchStartLocation = nil
        hideJoystickVisual()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isMoving = false
        currentMovementDirection = CGPoint.zero
        touchStartLocation = nil
        hideJoystickVisual()
    }
    
    // Helper function to find a node with a specific name by traversing up the parent chain
    func findNodeWithName(_ name: String, startingFrom node: SKNode) -> SKNode? {
        var currentNode: SKNode? = node
        while let current = currentNode {
            if current.name == name {
                return current
            }
            currentNode = current.parent
        }
        return nil
    }
    
    func handleInventoryPanelTouch(at location: CGPoint, in panel: SKNode) {
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        if let closeButton = touchedNodes.first(where: { findNodeWithName("closeInventory", startingFrom: $0) != nil }) {
            if findNodeWithName("closeInventory", startingFrom: closeButton) != nil {
                panel.removeFromParent()
                isGamePaused = false
            }
        }
    }
    
    func handleBuildPanelTouch(at location: CGPoint, in panel: SKNode) {
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        
        // Check for close button
        if let closeNode = touchedNodes.first(where: { findNodeWithName("closeBuild", startingFrom: $0) != nil }) {
            if findNodeWithName("closeBuild", startingFrom: closeNode) != nil {
                panel.removeFromParent()
                isGamePaused = false
                return
            }
        }
        
        // Check for build buttons
        for structureType in StructureType.allCases {
            let buttonName = "build_\(structureType.rawValue)"
            if let buildNode = touchedNodes.first(where: { findNodeWithName(buttonName, startingFrom: $0) != nil }) {
                if findNodeWithName(buttonName, startingFrom: buildNode) != nil {
                    attemptBuildStructure(type: structureType)
                    panel.removeFromParent()
                    isGamePaused = false
                    return
                }
            }
        }
    }
    
    func handleSettingsPanelTouch(at location: CGPoint, in panel: SKNode) {
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        
        // Check for close button
        if let closeNode = touchedNodes.first(where: { findNodeWithName("closeSettings", startingFrom: $0) != nil }) {
            if findNodeWithName("closeSettings", startingFrom: closeNode) != nil {
                panel.removeFromParent()
                isGamePaused = false
                return
            }
        }
        
        // Check for save game button
        if let saveNode = touchedNodes.first(where: { findNodeWithName("saveGame", startingFrom: $0) != nil }) {
            if findNodeWithName("saveGame", startingFrom: saveNode) != nil {
                panel.removeFromParent()
                saveGame() // This will show the save slot selection
                return
            }
        }
        
        // Check for load game button
        if let loadNode = touchedNodes.first(where: { findNodeWithName("loadGame", startingFrom: $0) != nil }) {
            if findNodeWithName("loadGame", startingFrom: loadNode) != nil {
                panel.removeFromParent()
                loadGame() // This will show the load slot selection
                return
            }
        }
        
        // Check for quit button
        if let quitNode = touchedNodes.first(where: { findNodeWithName("quitToMenu", startingFrom: $0) != nil }) {
            if findNodeWithName("quitToMenu", startingFrom: quitNode) != nil {
                panel.removeFromParent()
                quitToMainMenu()
                return
            }
        }
    }
    
    func handleSaveSlotPanelTouch(at location: CGPoint, in panel: SKNode) {
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        
        // Check for close button
        if let closeNode = touchedNodes.first(where: { findNodeWithName("closeSaveSlot", startingFrom: $0) != nil }) {
            if findNodeWithName("closeSaveSlot", startingFrom: closeNode) != nil {
                panel.removeFromParent()
                isGamePaused = false
                return
            }
        }
        
        // Check for save slot buttons
        for slotNum in 1...SaveManager.maxSlots {
            let buttonName = "saveSlot_\(slotNum)"
            if let slotNode = touchedNodes.first(where: { findNodeWithName(buttonName, startingFrom: $0) != nil }) {
                if findNodeWithName(buttonName, startingFrom: slotNode) != nil {
                    saveGame(toSlot: slotNum)
                    panel.removeFromParent()
                    isGamePaused = false
                    return
                }
            }
        }
    }
    
    func handleLoadSlotPanelTouch(at location: CGPoint, in panel: SKNode) {
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        
        // Check for close button
        if let closeNode = touchedNodes.first(where: { findNodeWithName("closeLoadSlot", startingFrom: $0) != nil }) {
            if findNodeWithName("closeLoadSlot", startingFrom: closeNode) != nil {
                panel.removeFromParent()
                isGamePaused = false
                return
            }
        }
        
        // Check for load slot buttons (only non-empty slots)
        for slotNum in 1...SaveManager.maxSlots {
            let buttonName = "loadSlot_\(slotNum)"
            if let slotNode = touchedNodes.first(where: { findNodeWithName(buttonName, startingFrom: $0) != nil }) {
                if findNodeWithName(buttonName, startingFrom: slotNode) != nil {
                    loadGame(fromSlot: slotNum)
                    panel.removeFromParent()
                    isGamePaused = false
                    return
                }
            }
        }
    }
    
    func saveGame() {
        // Show save slot selection screen
        showSaveSlotSelection()
    }
    
    func saveGame(toSlot slot: Int) {
        guard let gameState = gameState else { return }
        
        // Try to find character by matching player name and class
        if currentCharacterId == nil {
            let characters = SaveManager.getAllCharacters()
            currentCharacterId = characters.first(where: {
                $0.name == gameState.player.name && $0.characterClass == gameState.player.characterClass
            })?.id
        }
        
        // If we have a character ID, use it; otherwise fall back to legacy save
        if let characterId = currentCharacterId {
            if SaveManager.saveGame(gameState: gameState, characterId: characterId, toSlot: slot) {
                showMessage("Game saved to slot \(slot)!", color: .green)
            } else {
                showMessage("Failed to save game", color: .red)
            }
        } else {
            // Legacy save (for backward compatibility)
            if SaveManager.saveGame(gameState: gameState, toSlot: slot) {
                showMessage("Game saved to slot \(slot)!", color: .green)
            } else {
                showMessage("Failed to save game", color: .red)
            }
        }
    }
    
    func showSaveSlotSelection() {
        // Pause the game
        isGamePaused = true
        
        // Create save slot selection UI (relative to camera)
        guard let camera = cameraNode else { return }
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Modern panel
        let panelContainer = MenuStyling.createModernPanel(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panelContainer.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panelContainer.zPosition = 200
        panelContainer.name = "saveSlotPanel"
        camera.addChild(panelContainer)
        
        // Get the actual panel node
        guard let panel = panelContainer.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode else { return }
        
        // Modern title
        let titleY = isLandscape ? dims.panelHeight / 2 - 40 : dims.panelHeight / 2 - 50
        let title = MenuStyling.createModernTitle(text: "Select Save Slot", position: CGPoint(x: 0, y: titleY), fontSize: isLandscape ? 28 : 32)
        title.zPosition = 10
        panelContainer.addChild(title)
        
        // Get all save slots for current character, or all slots if no character
        let saveSlots: [SaveSlot]
        if let characterId = currentCharacterId {
            saveSlots = SaveManager.getAllSaveSlots(characterId: characterId)
        } else {
            // Try to find character
            if let gameState = gameState {
                let characters = SaveManager.getAllCharacters()
                if let character = characters.first(where: {
                    $0.name == gameState.player.name && $0.characterClass == gameState.player.characterClass
                }) {
                    currentCharacterId = character.id
                    saveSlots = SaveManager.getAllSaveSlots(characterId: character.id)
                } else {
                    saveSlots = SaveManager.getAllSaveSlots() // Legacy
                }
            } else {
                saveSlots = SaveManager.getAllSaveSlots() // Legacy
            }
        }
        
        // Create buttons for each slot
        let cardWidth = min(dims.buttonWidth, isLandscape ? 400 : size.width * 0.8)
        let cardHeight: CGFloat = isLandscape ? 65 : 75
        let cardSpacing: CGFloat = isLandscape ? 12 : 15
        var slotY: CGFloat = isLandscape ? 80 : 100
        
        for slot in saveSlots {
            let displayText = slot.isEmpty ? "Slot \(slot.slotNumber) - Empty" : "Slot \(slot.slotNumber) - Overwrite: \(slot.displayName)"
            let slotButton = MenuStyling.createCardButton(
                text: displayText,
                subtitle: nil,
                size: CGSize(width: cardWidth, height: cardHeight),
                position: CGPoint(x: 0.0, y: slotY),
                name: "saveSlot_\(slot.slotNumber)",
                isEmpty: slot.isEmpty
            )
            panelContainer.addChild(slotButton)
            slotY -= (cardHeight + cardSpacing)
        }
        
        // Close button
        let closeY = isLandscape ? -dims.panelHeight / 2 + 50 : -dims.panelHeight / 2 + 60
        let closeButton = MenuStyling.createModernButton(
            text: "Cancel",
            size: CGSize(width: min(150, dims.buttonWidth * 0.6), height: dims.buttonHeight * 0.8),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: 0, y: closeY),
            name: "closeSaveSlot",
            fontSize: isLandscape ? 18 : 20
        )
        panelContainer.addChild(closeButton)
    }
    
    func loadGame() {
        // Show load slot selection screen
        showLoadSlotSelection()
    }
    
    func loadGame(fromSlot slot: Int) {
        guard let loadedState = SaveManager.loadGame(fromSlot: slot) else {
            showMessage("Failed to load game from slot \(slot)", color: .red)
            return
        }
        
        print("Game loaded successfully from slot \(slot)")
        
        // Replace current game state
        gameState = loadedState
        
        // Restore the scene with loaded state
        restoreGameFromState()
        
        showMessage("Game loaded from slot \(slot)!", color: .green)
    }
    
    func showLoadSlotSelection() {
        // Pause the game
        isGamePaused = true
        
        // Create load slot selection UI (relative to camera)
        guard let camera = cameraNode else { return }
        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.9, height: size.height * 0.8), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        panel.name = "loadSlotPanel"
        camera.addChild(panel)
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 50), cornerRadius: 8)
        titleBg.fillColor = SKColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 0.95)
        titleBg.strokeColor = .white
        titleBg.lineWidth = 2
        titleBg.position = CGPoint(x: 0, y: 240)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "Select Save Slot to Load"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        titleBg.addChild(title)
        
        // Get all save slots
        let saveSlots = SaveManager.getAllSaveSlots()
        
        // Create buttons for each slot (only non-empty slots are clickable)
        var slotY: CGFloat = 150
        for slot in saveSlots {
            let slotButton = createSaveSlotButtonForLoading(slot: slot, position: CGPoint(x: 0, y: slotY))
            panel.addChild(slotButton)
            slotY -= 90
        }
        
        // Close button
        let closeButton = SKShapeNode(rectOf: CGSize(width: 120, height: 50), cornerRadius: 8)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        closeButton.strokeColor = .white
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: 0, y: -240)
        closeButton.name = "closeLoadSlot"
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Cancel"
        closeLabel.fontSize = 20
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeLabel.isUserInteractionEnabled = false
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    func createSaveSlotButtonForLoading(slot: SaveSlot, position: CGPoint) -> SKNode {
        let button = SKShapeNode(rectOf: CGSize(width: 400, height: 70), cornerRadius: 12)
        button.fillColor = slot.isEmpty ? SKColor(white: 0.2, alpha: 0.8) : SKColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 1.0)
        button.strokeColor = .white
        button.lineWidth = 2
        button.position = position
        button.name = slot.isEmpty ? "emptySlot_\(slot.slotNumber)" : "loadSlot_\(slot.slotNumber)"
        button.zPosition = 1
        
        // Slot label
        let label = SKLabelNode(fontNamed: slot.isEmpty ? "Arial" : "Arial-BoldMT")
        label.text = slot.displayName
        label.fontSize = slot.isEmpty ? 20 : 22
        label.fontColor = slot.isEmpty ? SKColor(white: 0.6, alpha: 1.0) : .white
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        label.isUserInteractionEnabled = false
        button.addChild(label)
        
        return button
    }
    
    func showMessage(_ text: String, color: SKColor) {
        guard let camera = cameraNode else { return }
        
        // Remove any existing message
        camera.childNode(withName: "saveLoadMessage")?.removeFromParent()
        
        // Create message label
        let message = SKLabelNode(fontNamed: "Arial-BoldMT")
        message.text = text
        message.fontSize = 24
        message.fontColor = color
        message.position = CGPoint(x: 0, y: -size.height / 2 + 100)
        message.zPosition = 2000
        message.name = "saveLoadMessage"
        message.horizontalAlignmentMode = .center
        camera.addChild(message)
        
        // Animate message appearance and fade out
        message.alpha = 0
        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 2.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([fadeIn, wait, fadeOut, remove])
        message.run(sequence)
    }
    
    func attemptBuildStructure(type: StructureType) {
        guard let player = gameState?.player, let world = gameState?.world else { return }
        
        // Check skills
        let requiredSkills = type.requiredSkills
        for (skill, minLevel) in requiredSkills {
            if (player.buildingSkills[skill] ?? 0) < minLevel {
                // Show error message
                return
            }
        }
        
        // Check materials
        let requiredMaterials = type.requiredMaterials
        for (material, quantity) in requiredMaterials {
            let hasQuantity = player.inventory
                .compactMap { $0 as? Material }
                .filter { $0.materialType == material }
                .reduce(0) { $0 + $1.quantity }
            
            if hasQuantity < quantity {
                // Show error message - need more materials
                return
            }
        }
        
        // Build structure at player position
        let structure = Structure(type: type, position: player.position)
        if world.placeStructure(structure, at: player.position) {
            gameState?.structures.append(structure)
            // Re-render the world
            if useTiledMap {
                loadAndRenderTiledMap(fileName: tiledMapFileName)
            } else {
            renderWorld()
            }
        }
    }
    
    func showInventory() {
        // Pause the game
        isGamePaused = true
        
        // Create inventory UI (relative to camera)
        guard let camera = cameraNode else { return }
        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.9, height: size.height * 0.8), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        panel.name = "inventoryPanel"
        camera.addChild(panel)
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 50), cornerRadius: 8)
        titleBg.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.95)
        titleBg.strokeColor = .cyan
        titleBg.lineWidth = 2
        titleBg.position = CGPoint(x: 0, y: 240)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "Inventory"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        titleBg.addChild(title)
        
        guard let player = gameState?.player else { return }
        
        // Items list background
        let itemsBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 400), cornerRadius: 8)
        itemsBg.fillColor = SKColor(white: 0.1, alpha: 0.95)
        itemsBg.strokeColor = .white
        itemsBg.lineWidth = 2
        itemsBg.position = CGPoint(x: 0, y: 20)
        panel.addChild(itemsBg)
        
        var yOffset: CGFloat = 180
        for item in player.inventory {
            let itemLabel = SKLabelNode(fontNamed: "Arial")
            itemLabel.text = "\(item.name) x\(item.quantity)"
            itemLabel.fontSize = 18
            itemLabel.fontColor = .white
            itemLabel.position = CGPoint(x: -180, y: yOffset)
            itemLabel.horizontalAlignmentMode = .left
            itemsBg.addChild(itemLabel)
            yOffset -= 35
        }
        
        let closeButton = SKShapeNode(rectOf: CGSize(width: 120, height: 50), cornerRadius: 8)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        closeButton.strokeColor = .white
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: 0, y: -240)
        closeButton.name = "closeInventory"
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Close"
        closeLabel.fontSize = 20
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    func showBuildMenu() {
        // Pause the game
        isGamePaused = true
        
        // Create build menu UI (relative to camera)
        guard let camera = cameraNode else { return }
        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.9, height: size.height * 0.8), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        panel.name = "buildPanel"
        camera.addChild(panel)
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 50), cornerRadius: 8)
        titleBg.fillColor = SKColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 0.95)
        titleBg.strokeColor = .magenta
        titleBg.lineWidth = 2
        titleBg.position = CGPoint(x: 0, y: 240)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "Build Structure"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        titleBg.addChild(title)
        
        guard let player = gameState?.player else { return }
        
        var yOffset: CGFloat = 180
        for structureType in StructureType.allCases {
            // Check if player has required skills
            let requiredSkills = structureType.requiredSkills
            var canBuild = true
            for (skill, minLevel) in requiredSkills {
                if (player.buildingSkills[skill] ?? 0) < minLevel {
                    canBuild = false
                    break
                }
            }
            
            let button = SKShapeNode(rectOf: CGSize(width: 350, height: 45), cornerRadius: 8)
            button.fillColor = canBuild ? SKColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0) : SKColor(white: 0.3, alpha: 0.8)
            button.strokeColor = canBuild ? .white : .gray
            button.lineWidth = 2
            button.position = CGPoint(x: 0, y: yOffset)
            button.name = "build_\(structureType.rawValue)"
            
            let label = SKLabelNode(fontNamed: "Arial-BoldMT")
            label.text = structureType.rawValue
            label.fontSize = 18
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.isUserInteractionEnabled = false
            button.addChild(label)
            panel.addChild(button)
            
            yOffset -= 55
        }
        
        let closeButton = SKShapeNode(rectOf: CGSize(width: 120, height: 50), cornerRadius: 8)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        closeButton.strokeColor = .white
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: 0, y: -240)
        closeButton.name = "closeBuild"
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Close"
        closeLabel.fontSize = 20
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeLabel.isUserInteractionEnabled = false
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    func showSettings() {
        // Pause the game
        isGamePaused = true
        
        // Create settings UI (relative to camera)
        guard let camera = cameraNode else { return }
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Modern panel
        let panelContainer = MenuStyling.createModernPanel(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panelContainer.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panelContainer.zPosition = 200
        panelContainer.name = "settingsPanel"
        camera.addChild(panelContainer)
        
        // Get the actual panel node
        guard let panel = panelContainer.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode else { return }
        
        // Modern title
        let titleY = isLandscape ? dims.panelHeight / 2 - 40 : dims.panelHeight / 2 - 50
        let title = MenuStyling.createModernTitle(text: "Settings", position: CGPoint(x: 0, y: titleY), fontSize: isLandscape ? 28 : 32)
        title.zPosition = 10
        panelContainer.addChild(title)
        
        // Button spacing
        var buttonY: CGFloat = isLandscape ? 60 : 80
        let buttonSpacing = dims.spacing + 10
        
        // Save Game button
        let saveButton = MenuStyling.createModernButton(
            text: "Save Game",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.secondaryColor,
            position: CGPoint(x: 0.0, y: buttonY),
            name: "saveGame",
            fontSize: isLandscape ? 22 : 24
        )
        panelContainer.addChild(saveButton)
        buttonY -= (dims.buttonHeight + buttonSpacing)
        
        // Load Game button
        let loadButton = MenuStyling.createModernButton(
            text: "Load Game",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.accentColor,
            position: CGPoint(x: 0.0, y: buttonY),
            name: "loadGame",
            fontSize: isLandscape ? 22 : 24
        )
        panelContainer.addChild(loadButton)
        buttonY -= (dims.buttonHeight + buttonSpacing)
        
        // Quit to Main Menu button
        let quitButton = MenuStyling.createModernButton(
            text: "Quit to Main Menu",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: 0.0, y: buttonY),
            name: "quitToMenu",
            fontSize: isLandscape ? 20 : 24
        )
        panelContainer.addChild(quitButton)
        
        // Close button
        let closeY = isLandscape ? -dims.panelHeight / 2 + 50 : -dims.panelHeight / 2 + 60
        let closeButton = MenuStyling.createModernButton(
            text: "Close",
            size: CGSize(width: min(150, dims.buttonWidth * 0.6), height: dims.buttonHeight * 0.8),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: 0, y: closeY),
            name: "closeSettings",
            fontSize: isLandscape ? 18 : 20
        )
        panelContainer.addChild(closeButton)
    }
    
    func quitToMainMenu() {
        guard let skView = self.view else { return }
        
        // Clean up game state
        isGamePaused = false
        
        // Transition to start screen
        let startScene = StartScreenScene(size: size)
        startScene.scaleMode = .aspectFill
        skView.presentScene(startScene, transition: SKTransition.fade(withDuration: 0.5))
    }
}
#endif

#if os(macOS)
// Keyboard and mouse-based event handling
extension GameScene {
    override func keyDown(with event: NSEvent) {
        guard !isGamePaused, !isInCombat, !isInDialogue else { return }
        
        let keyCode = event.keyCode
        pressedKeys.insert(keyCode)
        updateMovementFromKeys()
    }
    
    override func keyUp(with event: NSEvent) {
        let keyCode = event.keyCode
        pressedKeys.remove(keyCode)
        updateMovementFromKeys()
    }
    
    func updateMovementFromKeys() {
        var direction = CGPoint.zero
        
        // Arrow key codes on macOS:
        // 0x7B = Left Arrow
        // 0x7C = Right Arrow
        // 0x7D = Down Arrow
        // 0x7E = Up Arrow
        // Also support WASD:
        // 0x00 = A (left)
        // 0x02 = D (right)
        // 0x01 = S (down)
        // 0x0D = W (up)
        
        if pressedKeys.contains(0x7E) || pressedKeys.contains(0x0D) { // Up Arrow or W
            direction.y += 1.0
        }
        if pressedKeys.contains(0x7D) || pressedKeys.contains(0x01) { // Down Arrow or S
            direction.y -= 1.0
        }
        if pressedKeys.contains(0x7C) || pressedKeys.contains(0x02) { // Right Arrow or D
            direction.x += 1.0
        }
        if pressedKeys.contains(0x7B) || pressedKeys.contains(0x00) { // Left Arrow or A
            direction.x -= 1.0
        }
        
        // Normalize direction if diagonal
        let length = sqrt(direction.x * direction.x + direction.y * direction.y)
        if length > 0 {
            currentMovementDirection = CGPoint(x: direction.x / length, y: direction.y / length)
        } else {
            currentMovementDirection = CGPoint.zero
        }
    }
}
#endif

