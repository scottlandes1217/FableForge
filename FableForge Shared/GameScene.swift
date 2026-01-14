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
    var objectSprites: [SKSpriteNode: TiledObject] = [:]  // Map of object sprites to their TiledObject data
    var objectGroupNames: [SKSpriteNode: String] = [:]  // Map of object sprites to their objectgroup name
    var questionMarkIndicators: [Int: SKNode] = [:]  // Map of object ID to question mark indicator node
    var gameUI: GameUI?
    var combatUI: CombatUI?
    var cameraNode: SKCameraNode?
    
    // Debug overlay for collision box visualization
    private var collisionDebugOverlay: SKShapeNode?
    
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
    private var hasInfiniteLayers: Bool = false  // Track if map uses infinite layers (chunks) or regular layers
    private var regularLayerHeight: Int = 0  // Height of regular layers (for coordinate conversion)
    private var collisionDebugCount: Int = 0  // Debug counter for collision checks
    
    // Player collision box - calculated from sprite's actual frame
    // This ensures the collision box perfectly matches the sprite's visual bounds
    
    var currentCharacterId: UUID? // Track which character is currently playing
    var label: SKLabelNode? // Label property (may be used by Actions.sks)
    
    // Frame animation properties
    private var idleFrameTextures: [String: SKTexture] = [:] // ["south": texture, "west": texture, ...]
    private var walkFrameTextures: [String: [SKTexture]] = [:] // ["south": [texture0, texture1, ...], ...]
    private var currentAnimationFrame: Int = 0 // Current frame index for walk animation
    private var animationTimer: TimeInterval = 0 // Timer for frame animation
    private let animationFrameDuration: TimeInterval = 0.15 // 150ms per frame
    private var lastFacingDirection: String = "south" // Track last facing direction for idle state
    private var playerSpriteSize: CGSize = CGSize(width: 96, height: 96) // Store sprite size
    
    // Track last animation state to only update when it changes
    private var lastAnimationFrame: Int = -1
    private var lastAnimationDirection: String = ""
    private var lastAnimationIsMoving: Bool = false
    
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
        
        // Clear existing object sprites
        for (sprite, _) in objectSprites {
            sprite.removeFromParent()
        }
        objectSprites.removeAll()
        objectGroupNames.removeAll()
        
        // Clear question mark indicators
        for (_, questionMark) in questionMarkIndicators {
            questionMark.removeFromParent()
        }
        questionMarkIndicators.removeAll()
        
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
            renderTiledLayer(layer, tileSize: tileSize, zPosition: tileZPosition, yFlipOffset: yFlipOffset, container: mapContainer)
        }
        
        // Third pass: Render object groups (object layers)
        // Objects are rendered above tiles but below player/entities
        let objectZPosition: CGFloat = 70  // Above tiles (0-60) but below player (100)
        print("📦 Rendering \(tiledMap.objectGroups.count) object groups...")
        if tiledMap.objectGroups.isEmpty {
            print("⚠️ WARNING: No object groups found in Tiled map!")
        }
        for objectGroup in tiledMap.objectGroups {
            renderTiledObjectGroup(objectGroup, tileSize: tileSize, zPosition: objectZPosition, yFlipOffset: yFlipOffset, container: mapContainer)
        }
        print("📦 Finished rendering all object groups. Total object sprites: \(objectSprites.count)")
        
        
        
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
            hasInfiniteLayers = tiledMap.layers.contains { $0.isInfinite }
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
                cameraNode?.position = player.position
            }
        }
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
            for y in 0..<layer.height {
                for x in 0..<layer.width {
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
                        sprite.position = CGPoint(
                            x: CGFloat(x) * tileSize.width,
                            y: CGFloat(layer.height - y - 1) * tileSize.height
                        )
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
                    
                    sprite.position = CGPoint(x: worldX, y: worldY)
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
    
    func createPlayerSprite() {
        guard let player = gameState?.player else { return }
        
        // Remove existing player sprite if it exists
        playerSprite?.removeFromParent()
        playerSprite = nil
        
        // Clear texture dictionaries to ensure fresh textures are loaded
        idleFrameTextures.removeAll()
        walkFrameTextures.removeAll()
        
        var sprite: SKSpriteNode
        
        // Try to load sprite from generated sprite sheet
        if let characterId = currentCharacterId,
           let character = SaveManager.getAllCharacters().first(where: { $0.id == characterId }),
           let framePaths = character.framePaths {
            
            // Load idle frames
            let directions = ["south", "west", "east", "north"]
            print("🔍 Loading frames from \(framePaths.count) frame paths")
            for direction in directions {
                if let path = framePaths.first(where: { $0.contains("idle_\(direction)") }),
                   let texture = SpriteGenerationService.shared.loadFrameTexture(from: path) {
                    // Validate texture
                    let texSize = texture.size()
                    guard texSize.width > 0 && texSize.height > 0 else {
                        print("   ⚠️ Invalid texture size for idle_\(direction): \(texSize)")
                        continue
                    }
                    // Preload texture to ensure it's ready
                    texture.preload { }
                    texture.filteringMode = .nearest
                    idleFrameTextures[direction] = texture
                    let textureAddr = String(format: "%p", texture)
                    print("   ✅ Loaded idle_\(direction) from: \(path), size: \(texSize), texture object: \(textureAddr)")
                } else {
                    print("   ❌ Failed to load idle_\(direction)")
                    if let path = framePaths.first(where: { $0.contains("idle_\(direction)") }) {
                        print("      Path found: \(path) but texture loading failed")
                    } else {
                        print("      No path found matching 'idle_\(direction)'")
                        print("      Available paths: \(framePaths.filter { $0.contains("idle") })")
                    }
                }
            }
            
            // Load walk frames (1 frame per direction)
            // Walk frames are saved as "walk_south", "walk_west", etc. (no frame numbers)
            for direction in directions {
                // Look for paths that contain "walk_<direction>" but don't have frame numbers
                // Frame numbers would be like "_0", "_1", "_2", "_3" which we want to exclude
                let walkFrameName = "walk_\(direction)"
                let matchingPaths = framePaths.filter { path in
                    path.contains(walkFrameName) && 
                    !path.contains("_0") && 
                    !path.contains("_1") && 
                    !path.contains("_2") && 
                    !path.contains("_3")
                }
                
                if let path = matchingPaths.first,
                   let texture = SpriteGenerationService.shared.loadFrameTexture(from: path) {
                    // Validate texture
                    let texSize = texture.size()
                    guard texSize.width > 0 && texSize.height > 0 else {
                        print("   ⚠️ Invalid texture size for walk_\(direction): \(texSize)")
                        continue
                    }
                    // Preload texture to ensure it's ready
                    texture.preload { }
                    texture.filteringMode = .nearest
                    walkFrameTextures[direction] = [texture]  // Single frame as array for compatibility
                    let textureAddr = String(format: "%p", texture)
                    print("   ✅ Loaded walk_\(direction) from: \(path), size: \(texSize), texture object: \(textureAddr)")
                } else {
                    print("   ❌ Failed to load walk_\(direction)")
                    if !matchingPaths.isEmpty {
                        print("      Found matching paths but texture loading failed: \(matchingPaths)")
                    } else {
                        print("      No path found matching '\(walkFrameName)' (excluding numbered frames)")
                        let allWalkPaths = framePaths.filter { $0.contains("walk") }
                        print("      All walk paths: \(allWalkPaths)")
                    }
                }
            }
            
            // Use first idle frame (south) as initial sprite
            guard let firstFrameTexture = idleFrameTextures["south"] else {
                print("⚠️ Failed to load idle frames")
                sprite = SKSpriteNode(color: .blue, size: CGSize(width: 96, height: 96))
                addChild(sprite)
                playerSprite = sprite
                return
            }
            
            // Sprites are stored at 128x128, display at 96x96 (0.75x scale) for same visual size
            // This gives us better quality than the old 32x32 -> 96x96 scaling
            let scaleFactor: CGFloat = 0.75  // 128 * 0.75 = 96
            let frameWidthPixels = CGFloat(SpriteSheetConstants.frameWidth)
            let frameHeightPixels = CGFloat(SpriteSheetConstants.frameHeight)
            let scaledSpriteSize = CGSize(width: frameWidthPixels * scaleFactor, height: frameHeightPixels * scaleFactor)
            playerSpriteSize = scaledSpriteSize // Store for later use
            
            sprite = SKSpriteNode(texture: firstFrameTexture)
            sprite.size = scaledSpriteSize
            
            // Ensure sprite is properly configured for rendering
            sprite.alpha = 1.0
            sprite.isHidden = false
            sprite.colorBlendFactor = 0.0  // Don't blend with color, use texture as-is
            sprite.color = .white  // Ensure color is white (no tinting)
            sprite.blendMode = .alpha  // Use alpha blending for transparency
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)  // Center anchor
            
            // Preload the initial texture
            firstFrameTexture.preload { }
            firstFrameTexture.filteringMode = .nearest
            
            // Initialize animation state
            currentAnimationFrame = 0
            animationTimer = 0
            
            print("✅ Loaded player sprite from individual frames")
            print("   Idle frames loaded: \(idleFrameTextures.count)/4")
            print("   Walk frames loaded: \(walkFrameTextures.count)/4 directions")
            print("   Sprite size: \(scaledSpriteSize), texture size: \(firstFrameTexture.size())")
        } else {
            // Fall back to simple colored square
            sprite = SKSpriteNode(color: .blue, size: CGSize(width: 24, height: 24))
            print("⚠️ Using default blue square sprite (no sprite sheet found)")
        }
        
        sprite.position = player.position
        // Ensure center anchor point (default, but make explicit)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Player should be above ground/terrain layers but below objects, fences, and roofs
        // Ground layers are typically at index 0-10, objects at 10-30+
        // Using zPosition = 10 keeps player above ground but below objects
        sprite.zPosition = 11
        sprite.name = "player"
        sprite.alpha = 1.0
        sprite.isHidden = false
        addChild(sprite)
        playerSprite = sprite
        print("✅ Player sprite added to scene at position: \(player.position), size: \(sprite.size), texture: \(sprite.texture != nil ? "present" : "nil")")
        
        // Create companion sprites for all companions
        for companion in player.companions {
            createCompanionSprite(companion: companion)
        }
        
        // Initialize position history with current player position
        playerPositionHistory = [player.position]
        
        // Collision debug overlay disabled - remove call to updateCollisionDebugOverlay()
        // updateCollisionDebugOverlay()
    }
    
    /// Update player sprite animation based on movement state
    func updatePlayerSpriteAnimation(isMoving: Bool) {
        guard let sprite = playerSprite else {
            print("⚠️ updatePlayerSpriteAnimation: No player sprite")
            return
        }
        
        // Determine direction based on movement
        let x = currentMovementDirection.x
        let y = currentMovementDirection.y
        
        // Determine primary direction
        // Note: In SpriteKit, Y increases upward, so y > 0 means moving up (north)
        let direction: String
        if abs(y) > abs(x) {
            // Primarily vertical movement
            if y > 0 {
                direction = "north"  // Moving up
            } else if y < 0 {
                direction = "south"  // Moving down
            } else {
                // y is 0, use last direction or default
                direction = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
            }
        } else if abs(x) > abs(y) {
            // Primarily horizontal movement
            // East sprite faces RIGHT, West sprite faces LEFT (side profile)
            // Moving right should use east (faces right), moving left should use west (faces left)
            if x > 0 {
                direction = "east"  // Moving right - use east sprite (faces right)
            } else if x < 0 {
                direction = "west"  // Moving left - use west sprite (faces left)
            } else {
                // x is 0, use last direction or default
                direction = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
            }
        } else {
            // Both are equal or zero, use last direction or default
            direction = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
        }
        
        // Only update animation if direction or moving state changed
        let animationChanged = direction != lastAnimationDirection || isMoving != lastAnimationIsMoving
        
        if animationChanged {
            // Remove all existing actions only when we need to change
            sprite.removeAllActions()
            
            if isMoving {
                // Store the last facing direction
                lastFacingDirection = direction
                
                // Update tracking
                lastAnimationDirection = direction
                lastAnimationIsMoving = true
                
                print("🔄 Animation direction changed to: \(direction)")
            } else {
                // When idle, use the idle frame for the last facing direction
                let idleDirection = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
                
                // Update tracking
                lastAnimationDirection = idleDirection
                lastAnimationIsMoving = false
                
                print("🔄 Set idle for direction: \(idleDirection)")
            }
        }
        
        // Check if this is a colored sprite (fallback) or textured sprite
        let hasTextures = !idleFrameTextures.isEmpty && !walkFrameTextures.isEmpty
        
        if hasTextures {
            // Always update texture based on current state (manual texture switching)
            if isMoving {
                // Use the direction we just calculated (the current direction)
                let textureDirection = direction
                // Get idle and walk textures for current direction
                guard let idleTexture = idleFrameTextures[textureDirection],
                      let walkFrames = walkFrameTextures[textureDirection],
                      let walkTexture = walkFrames.first else {
                    print("⚠️ Missing textures for direction: \(textureDirection), available: \(idleFrameTextures.keys.joined(separator: ", "))")
                    return
                }
                
                // Alternate between idle (even frames) and walk (odd frames)
                let isWalkFrame = (currentAnimationFrame % 2) == 1
                let textureToUse = isWalkFrame ? walkTexture : idleTexture
                
                // Debug: Log texture info
                let currentTextureAddr = sprite.texture != nil ? String(format: "%p", sprite.texture!) : "nil"
                let newTextureAddr = String(format: "%p", textureToUse)
                if currentTextureAddr != newTextureAddr {
                    print("🔄 Updating texture: direction=\(textureDirection), frame=\(currentAnimationFrame), isWalk=\(isWalkFrame), texture changed: \(currentTextureAddr) -> \(newTextureAddr)")
                }
                
                // Always update texture directly (no SKAction for per-frame updates)
                textureToUse.filteringMode = .nearest
                sprite.texture = textureToUse
                sprite.size = playerSpriteSize
            } else {
                // When idle, use the idle frame
                let idleDirection = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
                if let idleTexture = idleFrameTextures[idleDirection] {
                    // Always update texture directly
                    idleTexture.filteringMode = .nearest
                    sprite.texture = idleTexture
                    sprite.size = playerSpriteSize
                }
            }
            
            // Ensure sprite is visible and properly configured (for textured sprites)
            sprite.alpha = 1.0
            sprite.isHidden = false
            sprite.colorBlendFactor = 0.0
            sprite.color = .white
            sprite.xScale = 1.0
            sprite.yScale = 1.0
            sprite.zRotation = 0.0
        } else {
            // Fallback: colored sprite - change color based on direction
            let colorForDirection: SKColor
            switch direction {
            case "north":
                colorForDirection = .green
            case "south":
                colorForDirection = .blue
            case "east":
                colorForDirection = .yellow
            case "west":
                colorForDirection = .orange
            default:
                colorForDirection = .blue
            }
            
            // For colored sprites (no texture), update the color property directly
            sprite.color = colorForDirection
            sprite.alpha = 1.0
            sprite.isHidden = false
            sprite.xScale = 1.0
            sprite.yScale = 1.0
            sprite.zRotation = 0.0
        }
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
        // Enable user interaction for object clicking
        self.isUserInteractionEnabled = true
        
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
            if !canMove {
                print("🛑 Movement blocked at position (\(Int(newPosition.x)), \(Int(newPosition.y)))")
            }
        } else {
            canMove = gameState?.world.canMoveTo(position: newPosition) ?? false
        }
        
        if canMove {
            let oldPosition = player.position
            player.position = newPosition
            playerSprite?.position = newPosition
            
            // Animation is updated in update() loop based on timer, not here
            
            // Add position to history for companions to follow
            playerPositionHistory.append(newPosition)
            if playerPositionHistory.count > maxPositionHistory {
                playerPositionHistory.removeFirst()
            }
            
            // Update companion positions (each follows the player's previous positions)
            updateCompanionPositions()
            
            // Update camera to follow player when near screen edges
            updateCamera()
            
            // Collision debug overlay disabled
            // updateCollisionDebugOverlay()
            
            // Check for object collisions (collectables, etc.)
            checkObjectCollisions(at: newPosition)
            
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
    
    func checkObjectCollisions(at position: CGPoint) {
        guard let player = gameState?.player else { return }
        
        // Get player collision frame
        let playerFrame = getPlayerCollisionFrame(at: position)
        
        // Check all object sprites for collision
        var objectsToRemove: [SKSpriteNode] = []
        
        for (sprite, object) in objectSprites {
            // Get object's bounding box
            let objectFrame = CGRect(
                x: sprite.position.x,
                y: sprite.position.y,
                width: sprite.size.width,
                height: sprite.size.height
            )
            
            // Check if player collides with object
            if playerFrame.intersects(objectFrame) {
                // Check if object is collectable
                // Objects are collectable if:
                // 1. They have the "collectable" property set to true, OR
                // 2. They are in an objectgroup named "Collectables" (case-insensitive)
                let objectGroupName = objectGroupNames[sprite] ?? ""
                let isCollectable = object.boolProperty("collectable", default: false) || objectGroupName.lowercased().contains("collectable")
                
                // Only collect items on collision (not dialogue objects)
                if isCollectable {
                    // Use the collectObject function which handles stacking and GID
                    // Note: collectObject already removes the sprite, so don't add to objectsToRemove
                    collectObject(object, sprite: sprite)
                }
                // Dialogue objects are handled via question mark interaction, not collision
            }
        }
        
        // Remove collected objects from scene
        for sprite in objectsToRemove {
            if let object = objectSprites[sprite] {
                // Remove question mark if it exists
                if let questionMark = questionMarkIndicators[object.id] {
                    questionMark.removeFromParent()
                    questionMarkIndicators.removeValue(forKey: object.id)
                }
            }
            sprite.removeFromParent()
            objectSprites.removeValue(forKey: sprite)
            objectGroupNames.removeValue(forKey: sprite)
        }
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
        
        // Update question mark indicators for dialogue objects
        updateQuestionMarkIndicators()
        
        // Continuous movement if direction is set
        if currentMovementDirection != CGPoint.zero {
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
        } else {
            // Player is not moving - update to idle animation
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
    
    /// Render an object group (object layer) from a Tiled map
    private func renderTiledObjectGroup(_ objectGroup: TiledObjectGroup, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat = 0, container: SKNode? = nil) {
        let parentNode = container ?? self
        
        print("🎯 Rendering object group '\(objectGroup.name)' with \(objectGroup.objects.count) objects")
        
        if objectGroup.objects.isEmpty {
            print("⚠️ WARNING: Object group '\(objectGroup.name)' has no objects!")
            return
        }
        
        for object in objectGroup.objects {
            // Calculate world position
            // Tiled uses top-left origin (Y increases downward)
            // SpriteKit uses bottom-left origin (Y increases upward)
            // We need to flip the Y coordinate: newY = yFlipOffset - oldY
            let tiledY = object.y
            let worldY = yFlipOffset - tiledY
            let worldX = object.x
            
            // Create sprite for object
            var sprite: SKSpriteNode?
            
            if let gid = object.gid {
                // Object uses a tile (has a GID)
                // Use the object's width/height if specified, otherwise use tile size
                let objectSize = CGSize(
                    width: object.width > 0 ? object.width : tileSize.width,
                    height: object.height > 0 ? object.height : tileSize.height
                )
                sprite = TileManager.shared.createSprite(for: gid, size: objectSize)
                if sprite == nil {
                    print("⚠️ WARNING: Failed to create sprite for object '\(object.name)' with GID \(gid). Creating fallback sprite.")
                    // Create a fallback visible sprite so we can see the object
                    sprite = SKSpriteNode(color: .red, size: objectSize)
                    sprite?.alpha = 0.8
                    // Add a border to make it more visible
                    let border = SKShapeNode(rect: CGRect(origin: .zero, size: objectSize))
                    border.strokeColor = .magenta
                    border.lineWidth = 2.0
                    border.fillColor = .clear
                    sprite?.addChild(border)
                }
            } else {
                // Object doesn't use a tile - create a colored rectangle or use a default sprite
                // Make it more visible with a border
                let objectSize = CGSize(
                    width: object.width > 0 ? object.width : tileSize.width,
                    height: object.height > 0 ? object.height : tileSize.height
                )
                sprite = SKSpriteNode(color: .yellow, size: objectSize)
                sprite?.alpha = 0.7  // More visible
                
                // Add a border to make it more visible
                let border = SKShapeNode(rect: CGRect(origin: .zero, size: objectSize))
                border.strokeColor = .orange
                border.lineWidth = 2.0
                border.fillColor = .clear
                sprite?.addChild(border)
            }
            
            guard let objectSprite = sprite else {
                print("⚠️ Failed to create sprite for object '\(object.name)' (id: \(object.id))")
                continue
            }
            
            // Position the sprite
            // In Tiled, object Y coordinate is typically the top of the object (in Tiled's coordinate system)
            // In SpriteKit with anchorPoint (0,0), position is the bottom-left corner
            // So we need to adjust: if object has height, we need to account for it in the Y conversion
            // Tiled Y is top of object, SpriteKit Y (with anchor 0,0) is bottom of object
            // After Y flip: worldY = yFlipOffset - tiledY gives us the top in SpriteKit coords
            // But we want the bottom, so subtract object height
            let adjustedWorldY: CGFloat
            if object.height > 0 {
                // Account for object height: Tiled Y is top, we need bottom
                adjustedWorldY = worldY - object.height
            } else {
                adjustedWorldY = worldY
            }
            
            objectSprite.position = CGPoint(x: worldX, y: adjustedWorldY)
            objectSprite.anchorPoint = CGPoint(x: 0, y: 0)  // Bottom-left corner
            objectSprite.zPosition = zPosition
            
            // Set object name for debugging
            objectSprite.name = "object_\(object.id)_\(object.name)"
            
            // Store the object data with the sprite for collision detection
            objectSprites[objectSprite] = object
            objectGroupNames[objectSprite] = objectGroup.name
            
            // Add visual indicator for dialogue objects (subtle glow)
            // Collectables don't need glow since they auto-collect on collision
            let isCollectable = object.boolProperty("collectable", default: false) || objectGroup.name.lowercased().contains("collectable")
            let hasDialogue = object.boolProperty("dialogue", default: false) || 
                             object.type?.lowercased() == "npc" ||
                             object.type?.lowercased() == "dialogue"
            
            if hasDialogue {
                // Add a subtle glow effect for dialogue objects
                let glow = SKShapeNode(rect: CGRect(origin: CGPoint(x: -2, y: -2), size: CGSize(width: objectSprite.size.width + 4, height: objectSprite.size.height + 4)), cornerRadius: 4)
                glow.strokeColor = .blue
                glow.lineWidth = 1.5
                glow.fillColor = .clear
                glow.alpha = 0.6
                glow.zPosition = -1  // Behind the object
                objectSprite.addChild(glow)
                
                // Make object slightly more visible
                objectSprite.alpha = 1.0
            }
            
            // Ensure objects with GIDs are fully visible
            if object.gid != nil {
                objectSprite.alpha = 1.0
                objectSprite.isHidden = false
            }
            
            // Ensure sprite is visible before adding
            objectSprite.alpha = 1.0
            objectSprite.isHidden = false
            
            // Add to scene
            parentNode.addChild(objectSprite)
            
            print("✅ Added object '\(object.name)' (id: \(object.id)) at Tiled(\(Int(object.x)), \(Int(object.y))) -> SpriteKit(\(Int(worldX)), \(Int(adjustedWorldY))), size: \(objectSprite.size), zPosition: \(zPosition), hasGID: \(object.gid?.description ?? "nil")")
            
            // Log collectable objects
            if isCollectable {
                print("   → Collectable object")
            }
            
            // Log dialogue objects
            if hasDialogue {
                print("   → Dialogue object")
            }
            
            // Note: Question mark indicators will be added/removed dynamically based on player proximity
        }
        
        print("✅ Finished rendering object group '\(objectGroup.name)': \(objectGroup.objects.count) objects added")
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
        
        // First, find max height of regular layers (for coordinate conversion)
        var maxRegularHeight = 0
        for layer in tiledMap.layers {
            if !layer.isInfinite {
                maxRegularHeight = max(maxRegularHeight, layer.height)
            }
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
    /// Uses a slightly smaller collision box than the sprite for better gameplay feel
    /// This allows the player to get closer to walls and multi-tile objects
    /// Assumes center anchor point (SpriteKit default: 0.5, 0.5)
    private func getPlayerCollisionFrame(at position: CGPoint) -> CGRect {
        // Use a smaller collision box than the sprite (18x18 instead of 24x24)
        // This creates a 3px buffer on all sides, allowing closer approach to walls
        // The sprite is 24x24, so 18x18 gives 6px total reduction (3px per side)
        let collisionSize = CGSize(width: 10, height: 10)
        let halfWidth = collisionSize.width / 2
        let halfHeight = collisionSize.height / 2
        // Offset collision box downward to position it around the feet
        // Sprite is 96x96 (32px * 3 scale), centered at position
        // Feet are at approximately position.y - 48
        // To position 10x10 collision box near feet (center around position.y - 40):
        // offset = 40 - halfHeight = 40 - 5 = 35
        let collisionYOffset: CGFloat = 35.0  // Move collision box down to position around feet
        return CGRect(origin: CGPoint(x: position.x - halfWidth, y: position.y - halfHeight - collisionYOffset), size: collisionSize)
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
            print("🔍 Collision check #\(collisionDebugCount): pos=(\(Int(position.x)), \(Int(position.y))), frame=(\(Int(playerLeft)),\(Int(playerBottom)))-\(Int(playerRight)),\(Int(playerTop))), tiles=X[\(minTileX)...\(maxTileX)] Y[\(minTileY)...\(maxTileY)], hasInfinite=\(hasInfiniteLayers), height=\(regularLayerHeight), yFlipOffset=\(yFlipOffset)")
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
                    // Calculate where this tile should be in world coordinates for debugging
                    let tileTiledY = CGFloat(tileY) * tileHeight
                    let tileWorldY = yFlipOffset - tileTiledY
                    let tileWorldX = CGFloat(tileX) * tileWidth
                    // Always log collisions with debug info
                    print("🚫 COLLISION! Player at world=(\(Int(position.x)), \(Int(position.y))), checking tile=(\(tileX), \(tileY)) which should be at world=(\(Int(tileWorldX)), \(Int(tileWorldY))), playerFrame=(\(Int(playerLeft)),\(Int(playerBottom))-\(Int(playerRight)),\(Int(playerTop))), layer=\(collisionLayer ?? "unknown")")
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

// Shared UI functions available on all platforms
extension GameScene {
    func showInventory() {
        // Pause the game
        isGamePaused = true
        
        // Create inventory UI (relative to camera)
        guard let camera = cameraNode, let player = gameState?.player else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Panel dimensions
        let panelWidth = min(size.width * 0.9, isLandscape ? 800 : 600)
        let panelHeight = min(size.height * 0.8, isLandscape ? 600 : 700)
        
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        panel.name = "inventoryPanel"
        camera.addChild(panel)
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panelWidth * 0.9, height: 50), cornerRadius: 8)
        titleBg.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.95)
        titleBg.strokeColor = .cyan
        titleBg.lineWidth = 2
        titleBg.position = CGPoint(x: 0, y: panelHeight / 2 - 40)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "Inventory"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        titleBg.addChild(title)
        
        // Inventory slots configuration
        let slotsPerRow = isLandscape ? 8 : 6
        let numRows = isLandscape ? 6 : 8
        let totalSlots = slotsPerRow * numRows
        
        let slotSize: CGFloat = isLandscape ? 60 : 50
        let slotSpacing: CGFloat = 8
        let slotsAreaWidth = CGFloat(slotsPerRow) * slotSize + CGFloat(slotsPerRow - 1) * slotSpacing
        let slotsAreaHeight = CGFloat(numRows) * slotSize + CGFloat(numRows - 1) * slotSpacing
        
        // Slots container background
        let slotsBg = SKShapeNode(rectOf: CGSize(width: slotsAreaWidth + 20, height: slotsAreaHeight + 20), cornerRadius: 8)
        slotsBg.fillColor = SKColor(white: 0.1, alpha: 0.95)
        slotsBg.strokeColor = .white
        slotsBg.lineWidth = 2
        slotsBg.position = CGPoint(x: 0, y: 0)
        panel.addChild(slotsBg)
        
        // Create inventory slots
        let startX = -slotsAreaWidth / 2 + slotSize / 2
        let startY = slotsAreaHeight / 2 - slotSize / 2
        
        for row in 0..<numRows {
            for col in 0..<slotsPerRow {
                let slotIndex = row * slotsPerRow + col
                
                // Calculate slot position
                let x = startX + CGFloat(col) * (slotSize + slotSpacing)
                let y = startY - CGFloat(row) * (slotSize + slotSpacing)
                
                // Create slot background
                let slotBg = SKShapeNode(rectOf: CGSize(width: slotSize, height: slotSize), cornerRadius: 4)
                slotBg.fillColor = SKColor(white: 0.2, alpha: 0.8)
                slotBg.strokeColor = SKColor(white: 0.5, alpha: 0.6)
                slotBg.lineWidth = 1
                slotBg.position = CGPoint(x: x, y: y)
                slotBg.name = "inventorySlot_\(slotIndex)"
                slotsBg.addChild(slotBg)
                
                // If we have an item for this slot, display it
                if slotIndex < player.inventory.count {
                    let item = player.inventory[slotIndex]
                    
                    // Create item sprite from GID if available
                    if let gid = item.gid {
                        let itemSize = CGSize(width: slotSize * 0.85, height: slotSize * 0.85)
                        if let itemSprite = TileManager.shared.createSprite(for: gid, size: itemSize) {
                            itemSprite.position = CGPoint(x: 0, y: 0)
                            itemSprite.zPosition = 1
                            itemSprite.name = "itemSprite_\(slotIndex)"
                            slotBg.addChild(itemSprite)
                        }
                    } else {
                        // Fallback: create a colored square with item name
                        let fallbackSprite = SKSpriteNode(color: SKColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 0.8), size: CGSize(width: slotSize * 0.7, height: slotSize * 0.7))
                        fallbackSprite.position = CGPoint(x: 0, y: 0)
                        fallbackSprite.zPosition = 1
                        slotBg.addChild(fallbackSprite)
                        
                        // Add item name label (small)
                        let nameLabel = SKLabelNode(fontNamed: "Arial")
                        nameLabel.text = String(item.name.prefix(4)) // First 4 chars
                        nameLabel.fontSize = 8
                        nameLabel.fontColor = .white
                        nameLabel.position = CGPoint(x: 0, y: 0)
                        nameLabel.verticalAlignmentMode = .center
                        nameLabel.zPosition = 2
                        slotBg.addChild(nameLabel)
                    }
                    
                    // Show quantity if > 1 or if stackable
                    if item.quantity > 1 || item.stackable {
                        let quantityLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
                        quantityLabel.text = "\(item.quantity)"
                        quantityLabel.fontSize = 12
                        quantityLabel.fontColor = .white
                        quantityLabel.position = CGPoint(x: slotSize / 2 - 8, y: -slotSize / 2 + 8)
                        quantityLabel.horizontalAlignmentMode = .right
                        quantityLabel.verticalAlignmentMode = .bottom
                        quantityLabel.zPosition = 3
                        
                        // Add background for quantity label
                        let quantityBg = SKShapeNode(rectOf: CGSize(width: 20, height: 16), cornerRadius: 3)
                        quantityBg.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.7)
                        quantityBg.strokeColor = .white
                        quantityBg.lineWidth = 1
                        quantityBg.position = CGPoint(x: slotSize / 2 - 10, y: -slotSize / 2 + 10)
                        quantityBg.zPosition = 2
                        slotBg.addChild(quantityBg)
                        slotBg.addChild(quantityLabel)
                    }
                }
            }
        }
        
        // Close button
        let closeButton = SKShapeNode(rectOf: CGSize(width: 120, height: 50), cornerRadius: 8)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        closeButton.strokeColor = .white
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: 0, y: -panelHeight / 2 + 40)
        closeButton.name = "closeInventory"
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Close"
        closeLabel.fontSize = 20
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    // Helper function to get view size (for inventory UI)
    private func getViewSize() -> CGSize {
        guard let view = self.view else {
            return size
        }
        return view.bounds.size
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
    
    // MARK: - Object Interaction
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Check if touching a dialogue button first
        if isInDialogue {
            handleDialogueInteraction(at: location)
        } else {
            handleQuestionMarkInteraction(at: location)
        }
    }
    #endif
    
    /// Handle dialogue button interactions
    private func handleDialogueInteraction(at location: CGPoint) {
        guard let camera = cameraNode else { return }
        let touchedNodes = nodes(at: location)
        
        for node in touchedNodes {
            if let name = node.name {
                if name == "closeDialogue" {
                    closeDialogue()
                    return
                } else if name.hasPrefix("dialogueResponse_") {
                    if let indexString = name.components(separatedBy: "_").last,
                       let index = Int(indexString) {
                        handleDialogueResponse(index: index)
                        return
                    }
                }
            }
        }
    }
    
    /// Handle interaction with question mark indicators
    private func handleQuestionMarkInteraction(at location: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        // Find nodes at this location
        let touchedNodes = nodes(at: location)
        
        // Check if clicking on a question mark
        for node in touchedNodes {
            if let name = node.name, name.hasPrefix("questionMark_") {
                // Extract object ID from question mark name
                let objectIdString = String(name.dropFirst("questionMark_".count))
                if let objectId = Int(objectIdString) {
                    // Find the object sprite with this ID
                    for (sprite, object) in objectSprites {
                        if object.id == objectId {
                            startDialogueWithObject(object)
                            return
                        }
                    }
                }
            }
        }
    }
    
    /// Collect an object and add it to player inventory (called from collision detection)
    private func collectObject(_ object: TiledObject, sprite: SKSpriteNode) {
        guard let player = gameState?.player else { return }
        
        // Create an item from the object
        let itemName = object.name.isEmpty ? "Item" : object.name
        let itemType: ItemType
        
        // Try to get item type from object properties
        if let typeString = object.stringProperty("itemType"),
           let parsedType = ItemType(rawValue: typeString) {
            itemType = parsedType
        } else {
            // Default to food if not specified
            itemType = .food
        }
        
        // Get quantity from properties (default 1)
        let quantity = Int(object.floatProperty("quantity", default: 1))
        
        // Get stackable property from Tiled object (default false)
        let stackable = object.boolProperty("stackable", default: false)
        
        // Get GID from object (for displaying tile image)
        let gid = object.gid
        
        // Create the item
        let item = Item(
            name: itemName,
            type: itemType,
            quantity: quantity,
            description: object.stringProperty("description") ?? "",
            value: Int(object.floatProperty("value", default: 0)),
            gid: gid,
            stackable: stackable
        )
        
        // If stackable, try to merge with existing item of same type and GID
        if stackable {
            // Find existing item with same type and GID
            if let existingIndex = player.inventory.firstIndex(where: { existingItem in
                existingItem.type == itemType && existingItem.gid == gid && existingItem.stackable
            }) {
                // Merge quantities
                player.inventory[existingIndex].quantity += quantity
                print("✅ Stacked item: \(itemName) (type: \(itemType), total quantity: \(player.inventory[existingIndex].quantity))")
                showMessage("Collected: \(itemName) x\(quantity) (Total: \(player.inventory[existingIndex].quantity))")
            } else {
                // No existing stackable item found, add as new item
                player.inventory.append(item)
                print("✅ Collected item: \(itemName) (type: \(itemType), quantity: \(quantity), stackable: true)")
                showMessage("Collected: \(itemName) x\(quantity)")
            }
        } else {
            // Not stackable, always add as new item
            player.inventory.append(item)
            print("✅ Collected item: \(itemName) (type: \(itemType), quantity: \(quantity), stackable: false)")
            showMessage("Collected: \(itemName) x\(quantity)")
        }
        
        // Remove object from scene
        sprite.removeFromParent()
        objectSprites.removeValue(forKey: sprite)
        objectGroupNames.removeValue(forKey: sprite)
    }
    
    /// Start dialogue with an object
    func startDialogueWithObject(_ object: TiledObject) {
        guard let player = gameState?.player else { return }
        
        print("💬 Starting dialogue with object '\(object.name)'")
        
        // Pause the game
        isGamePaused = true
        isInDialogue = true
        
        // Get dialogue text from object properties
        let dialogueText = object.stringProperty("dialogueText") ?? 
                          object.stringProperty("text") ?? 
                          "Hello! I'm \(object.name.isEmpty ? "an object" : object.name)."
        
        // Create a simple dialogue node
        let dialogueNode = DialogueNode(
            text: dialogueText,
            responses: [
                DialogueResponse(text: "Goodbye", nextNodeId: nil)
            ]
        )
        
        // Show dialogue UI
        showDialogueUI(dialogueNode, objectName: object.name.isEmpty ? "Object" : object.name)
    }
    
    /// Show dialogue UI
    private func showDialogueUI(_ dialogueNode: DialogueNode, objectName: String) {
        guard let camera = cameraNode else { return }
        
        // Remove any existing dialogue UI
        camera.childNode(withName: "dialoguePanel")?.removeFromParent()
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Create dialogue panel
        let panelContainer = MenuStyling.createModernPanel(size: CGSize(width: dims.panelWidth * 0.9, height: dims.panelHeight * 0.4))
        panelContainer.position = CGPoint(x: 0, y: -size.height * 0.25) // Bottom of screen
        panelContainer.zPosition = 200
        panelContainer.name = "dialoguePanel"
        camera.addChild(panelContainer)
        
        // Get the actual panel node
        guard let panel = panelContainer.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode else { return }
        
        // Object name label
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = objectName
        nameLabel.fontSize = isLandscape ? 24 : 28
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: panel.frame.height / 2 - 40)
        nameLabel.zPosition = 10
        panelContainer.addChild(nameLabel)
        
        // Dialogue text
        let textLabel = SKLabelNode(fontNamed: "Arial")
        textLabel.text = dialogueNode.text
        textLabel.fontSize = isLandscape ? 18 : 20
        textLabel.fontColor = .white
        textLabel.position = CGPoint(x: 0, y: 0)
        textLabel.zPosition = 10
        textLabel.preferredMaxLayoutWidth = panel.frame.width * 0.8
        textLabel.numberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.verticalAlignmentMode = .center
        panelContainer.addChild(textLabel)
        
        // Response buttons
        var buttonY: CGFloat = -panel.frame.height / 2 + 60
        for (index, response) in dialogueNode.responses.enumerated() {
            let button = MenuStyling.createModernButton(
                text: response.text,
                size: CGSize(width: panel.frame.width * 0.8, height: 40),
                color: MenuStyling.primaryColor,
                position: CGPoint(x: 0, y: buttonY),
                name: "dialogueResponse_\(index)",
                fontSize: isLandscape ? 16 : 18
            )
            button.zPosition = 10
            panelContainer.addChild(button)
            buttonY -= 50
        }
        
        // Close button (if no responses)
        if dialogueNode.responses.isEmpty {
            let closeButton = MenuStyling.createModernButton(
                text: "Close",
                size: CGSize(width: 120, height: 40),
                color: MenuStyling.dangerColor,
                position: CGPoint(x: 0, y: -panel.frame.height / 2 + 50),
                name: "closeDialogue",
                fontSize: isLandscape ? 16 : 18
            )
            closeButton.zPosition = 10
            panelContainer.addChild(closeButton)
        }
    }
    
    /// Show a brief message to the player
    private func showMessage(_ message: String) {
        guard let camera = cameraNode else { return }
        
        // Remove any existing message
        camera.childNode(withName: "messageLabel")?.removeFromParent()
        
        let messageLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        messageLabel.text = message
        messageLabel.fontSize = 24
        messageLabel.fontColor = .white
        messageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
        messageLabel.zPosition = 300
        messageLabel.name = "messageLabel"
        
        // Add background
        let background = SKShapeNode(rectOf: CGSize(width: messageLabel.frame.width + 40, height: messageLabel.frame.height + 20), cornerRadius: 8)
        background.fillColor = SKColor(white: 0, alpha: 0.7)
        background.strokeColor = .white
        background.lineWidth = 2
        background.position = CGPoint(x: 0, y: 0)
        messageLabel.addChild(background)
        messageLabel.insertChild(background, at: 0)
        
        camera.addChild(messageLabel)
        
        // Fade out after 2 seconds
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let remove = SKAction.removeFromParent()
        messageLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            fadeOut,
            remove
        ]))
    }
    
    /// Handle dialogue response selection
    func handleDialogueResponse(index: Int) {
        // For now, just close the dialogue
        // You can extend this to handle multiple dialogue nodes
        closeDialogue()
    }
    
    /// Close the dialogue UI
    func closeDialogue() {
        guard let camera = cameraNode else { return }
        camera.childNode(withName: "dialoguePanel")?.removeFromParent()
        isGamePaused = false
        isInDialogue = false
    }
    
    /// Update question mark indicators for dialogue objects based on player proximity
    private func updateQuestionMarkIndicators() {
        guard let player = gameState?.player else { return }
        
        let playerPosition = player.position
        let interactionRange: CGFloat = mapTileSize.width * 3.0  // 3 tiles away
        
        // Track which objects should have question marks
        var objectsNeedingQuestionMarks: Set<Int> = []
        
        // Check all objects for dialogue capability
        for (sprite, object) in objectSprites {
            // Check if object has dialogue
            let objectGroupName = objectGroupNames[sprite] ?? ""
            let hasDialogue = object.boolProperty("dialogue", default: false) || 
                             object.type?.lowercased() == "npc" ||
                             object.type?.lowercased() == "dialogue"
            
            if hasDialogue {
                // Calculate distance to player
                let distance = sqrt(pow(sprite.position.x - playerPosition.x, 2) + pow(sprite.position.y - playerPosition.y, 2))
                
                if distance <= interactionRange {
                    // Player is close enough - show question mark
                    objectsNeedingQuestionMarks.insert(object.id)
                    
                    // Create or update question mark indicator
                    if questionMarkIndicators[object.id] == nil {
                        createQuestionMarkIndicator(for: object, sprite: sprite)
                    } else {
                        // Update position if it exists
                        if let questionMark = questionMarkIndicators[object.id] {
                            questionMark.position = CGPoint(x: sprite.position.x, y: sprite.position.y + sprite.size.height + 20)
                        }
                    }
                }
            }
        }
        
        // Remove question marks for objects that are too far away
        for (objectId, questionMark) in questionMarkIndicators {
            if !objectsNeedingQuestionMarks.contains(objectId) {
                questionMark.removeFromParent()
                questionMarkIndicators.removeValue(forKey: objectId)
            }
        }
    }
    
    /// Create a question mark indicator above an object
    private func createQuestionMarkIndicator(for object: TiledObject, sprite: SKSpriteNode) {
        // Create question mark label
        let questionMark = SKLabelNode(fontNamed: "Arial-BoldMT")
        questionMark.text = "?"
        questionMark.fontSize = 32
        questionMark.fontColor = .yellow
        questionMark.position = CGPoint(x: sprite.position.x, y: sprite.position.y + sprite.size.height + 20)
        questionMark.zPosition = sprite.zPosition + 1
        questionMark.name = "questionMark_\(object.id)"
        
        // Add a background circle for visibility
        let background = SKShapeNode(circleOfRadius: 20)
        background.fillColor = SKColor(white: 0, alpha: 0.6)
        background.strokeColor = .yellow
        background.lineWidth = 2
        background.position = CGPoint(x: 0, y: 0)
        background.zPosition = -1
        questionMark.addChild(background)
        questionMark.insertChild(background, at: 0)
        
        // Add pulsing animation
        let pulseUp = SKAction.scale(to: 1.2, duration: 0.5)
        let pulseDown = SKAction.scale(to: 1.0, duration: 0.5)
        let pulse = SKAction.sequence([pulseUp, pulseDown])
        questionMark.run(SKAction.repeatForever(pulse))
        
        // Add to scene
        addChild(questionMark)
        questionMarkIndicators[object.id] = questionMark
    }
}

