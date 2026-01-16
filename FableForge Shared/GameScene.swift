//
//  GameScene.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit
import QuartzCore

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
    
    // Inventory drag and drop state
    var draggedItemIndex: Int? = nil
    var draggedItemNode: SKNode? = nil
    var inventoryContextMenu: SKNode? = nil
    var contextMenuItemIndex: Int? = nil
    
    // Debug overlay for collision box visualization
    private var collisionDebugOverlay: SKShapeNode?
    
    // Player position history for companions to follow
    private var playerPositionHistory: [CGPoint] = []
    private let maxPositionHistory = 30  // Keep last 30 positions
    
    // Flag to determine if we should use Tiled map or generated world
    // When false, tilesets are still loaded from TMX for use with procedural generation
    var useTiledMap: Bool = true  // Use TMX file instead of procedural generation
    var tiledMapFileName: String = "Exterior"
    
    // Hybrid world system (chunk-based procedural + TMX instances)
    var chunkManager: ChunkManager?
    var worldGenerator: WorldGenerator?
    var deltaPersistence: DeltaPersistence?
    private var lastPlayerChunk: ChunkKey?
    
    // Building entry/exit tracking
    private var previousMapFileName: String?  // Store previous map when entering a building
    private var previousPlayerPosition: CGPoint?  // Store player position before entering building
    private var entryDoorPosition: CGPoint?  // Store entry door position for linking with exit
    private var entryDoorLayerName: String?  // Store entry door layer name
    private var entryDoorId: String?  // Store entry door ID for linking with matching exit door
    private var currentTiledMap: TiledMap?  // Store the current parsed TiledMap for door finding
    
    // Procedural world transition tracking
    private var proceduralWorldExitPosition: CGPoint?  // Position in procedural world to return to TMX map
    private var tmxMapEntryPosition: CGPoint?  // Position in TMX map where player entered procedural world
    private var lastTransitionTime: TimeInterval = 0  // Time of last transition (to prevent immediate re-trigger)
    private let transitionCooldown: TimeInterval = 1.0  // 1 second cooldown between transitions
    
    // Loading screen overlay
    private var loadingScreen: SKNode?
    
    // Collision detection for Tiled maps
    // Use (Int, Int) tuple for tile coordinates instead of CGPoint (CGPoint is not Hashable)
    private var collisionMap: Set<String> = []  // Set of non-walkable tile positions as "x,y" strings
    private var collisionLayerMap: [String: String] = [:]  // Map of "x,y" -> layer name that created the collision
    private var layerProperties: [String: [String: String]] = [:]  // Map of layer name -> properties (for door detection)
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
    
    // Character zPosition based on max zOffset from layers
    // This allows specific layers to go behind or in front of characters
    // Layers maintain their natural order (by layer index), but character position
    // is determined by zOffset - if a layer has zOffset > characterZPosition, it appears in front
    var characterZPosition: CGFloat = 100 // Default to 100 if no zOffset is set
    
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
        scene.backgroundColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)  // Dark grey
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
        let parsedTiledMap = loadTilesetsFromTMX(fileName: tiledMapFileName)
        
        // Check if TMX map has a property to enable procedural world
        // If the map has "useProceduralWorld" property set to "true", use procedural generation
        if let tiledMap = parsedTiledMap {
            // Debug: Print all map properties
            if !tiledMap.properties.isEmpty {
                print("🔍 TMX Map properties found: \(tiledMap.properties)")
            } else {
                print("⚠️ No map properties found in TMX (property must be on the MAP, not a layer)")
            }
            
            // Check for useProceduralWorld property
            let useProcedural = tiledMap.boolProperty("useProceduralWorld", default: false)
            print("🔍 useProceduralWorld property value: \(useProcedural)")
            
            if useProcedural {
                print("🌍 TMX map property 'useProceduralWorld' is true - using procedural world")
                useTiledMap = false
            } else {
                print("📍 Using Tiled map (useProceduralWorld=false or not set)")
            }
        }
        
        // Load and render Tiled map (or use chunk-based procedural world)
        if useTiledMap {
            loadAndRenderTiledMap(fileName: tiledMapFileName, preParsedMap: parsedTiledMap)
        } else {
            // Initialize hybrid world system (chunk-based procedural)
            setupHybridWorldSystem()
        }
        
        // Update GameState with initial map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = !useTiledMap
        }
        
        // Create player sprite
        createPlayerSprite()
        
        // Center camera on player
        cameraNode?.position = player.position
        
        // UI will be created in didMove(to:) after view is available
        
        // Spawn some initial animals
        spawnInitialAnimals()
    }
    
    /// Setup hybrid world system (chunk-based procedural generation)
    func setupHybridWorldSystem() {
        print("🌍 Setting up hybrid world system (chunk-based)")
        
        guard let world = gameState?.world else {
            print("❌ No world in gameState for hybrid system")
            return
        }
        
        // Use TMX tile size (16x16 base tiles scaled by 2.0 = 32.0) to match TMX maps
        let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
        let chunkSize = ChunkManager.defaultChunkSize
        
        // Get world config from PrefabFactory (loaded from prefabs JSON)
        let worldConfig = PrefabFactory.shared.getWorldConfig()
        
        // Use seed from world config if available, otherwise use world.seed
        let worldSeed = worldConfig?.seed ?? world.seed
        
        // Initialize components with world config
        worldGenerator = WorldGenerator(seed: worldSeed, config: worldConfig)
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
        if let charLayerIndex = characterLayerIndex {
            // Place character between this layer and the next (e.g., if layer 3, character at 3.5)
            characterZPosition = CGFloat(charLayerIndex) + 0.5
            print("📍 Character z-position set to \(characterZPosition) (after layer \(charLayerIndex))")
        } else {
            // Default: character appears above all layers (z-position 100)
            characterZPosition = 100
            print("📍 No characterLayer property found - character z-position defaulting to 100")
        }
        
        // Render layers using natural order (layer index) to maintain proper layer ordering
        // Layers maintain their relative order, character appears at characterZPosition
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            // Z-Position hierarchy:
            // - Background: -100000 (far behind)
            // - Tiles: 0 to ~60 (based on layer index - maintains natural layer order)
            // - Characters: based on "characterZPosition" property (default 100)
            //   - Layers with index < characterZPosition appear behind character
            //   - Layers with index >= characterZPosition appear in front of character
            // - UI: 200+ (above everything)
            let tileZPosition = CGFloat(layerIndex)
            renderTiledLayer(layer, tileSize: tileSize, zPosition: tileZPosition, yFlipOffset: yFlipOffset, container: mapContainer)
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
        // Player zPosition is based on max zOffset from layers
        // This allows specific layers to go behind or in front of characters
        sprite.zPosition = characterZPosition
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
        // Companion uses characterZPosition (slightly below player for layering)
        sprite.zPosition = characterZPosition - 1
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
        
        // Get all available animal prefabs
        let allAnimalPrefabs = PrefabFactory.shared.getAllAnimalPrefabs()
        guard !allAnimalPrefabs.isEmpty else {
            print("⚠️ No animal prefabs loaded, skipping animal spawning")
            return
        }
        
        // Spawn a few animals randomly using prefabs
        for _ in 0..<10 {
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            // Pick random animal prefab
            let prefabArray = Array(allAnimalPrefabs.values)
            if let randomPrefab = prefabArray.randomElement() {
                // Create Animal instance from prefab
                let animal = createAnimalFromPrefab(randomPrefab)
                animal.position = position
                _ = world.spawnAnimal(animal, at: position)
                
                // Create visual representation using prefab's tileGrid
                let sprites = PrefabFactory.shared.createAnimalSprites(randomPrefab, position: position)
                for sprite in sprites {
                    sprite.zPosition = randomPrefab.zPosition
                    sprite.name = "animal"
                    addChild(sprite)
                    
                    // Store reference to animal (use first sprite as primary)
                    if animalSprites[sprite] == nil {
                        animalSprites[sprite] = animal
                    }
                }
            }
        }
        
        // Spawn some enemies too using prefabs
        let allEnemyPrefabs = PrefabFactory.shared.getAllEnemyPrefabs()
        guard !allEnemyPrefabs.isEmpty else {
            print("⚠️ No enemy prefabs loaded, skipping enemy spawning")
            return
        }
        
        guard let player = gameState?.player else { return }
        
        for _ in 0..<5 {
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            // Pick random enemy prefab (filter by level if needed)
            let prefabArray = Array(allEnemyPrefabs.values)
            if let randomPrefab = prefabArray.randomElement() {
                // Create Enemy instance from prefab
                let enemy = createEnemyFromPrefab(randomPrefab, level: player.level)
                
                // Create visual representation using prefab's tileGrid
                let sprites = PrefabFactory.shared.createEnemySprites(randomPrefab, position: position)
                for sprite in sprites {
                    sprite.zPosition = randomPrefab.zPosition
                    sprite.name = "enemy"
                    addChild(sprite)
                    
                    // Store reference to enemy (use first sprite as primary)
                    if enemySprites[sprite] == nil {
                        enemySprites[sprite] = enemy
                    }
                }
            }
        }
    }
    
    /// Create an Animal instance from an AnimalPrefab
    private func createAnimalFromPrefab(_ prefab: AnimalPrefab) -> Animal {
        // Map prefab ID to AnimalType (for backwards compatibility)
        // Try to match by name first
        let animalType: AnimalType
        switch prefab.name.lowercased() {
        case "wolf": animalType = .wolf
        case "bear": animalType = .bear
        case "eagle": animalType = .eagle
        case "deer": animalType = .deer
        case "rabbit": animalType = .rabbit
        case "fox": animalType = .fox
        case "owl": animalType = .owl
        case "boar": animalType = .boar
        case "hawk": animalType = .hawk
        case "stag": animalType = .stag
        default: animalType = .wolf // Fallback
        }
        
        let animal = Animal(type: animalType, name: prefab.name)
        
        // Override stats from prefab
        animal.hitPoints = prefab.hitPoints
        animal.maxHitPoints = prefab.hitPoints
        animal.armorClass = prefab.defensePoints
        animal.attackBonus = prefab.attackPoints
        animal.level = prefab.level ?? 1
        animal.speed = prefab.speed ?? 30
        animal.friendshipLevel = prefab.friendPoints
        
        // Convert skillIds to AnimalMove enum (for backwards compatibility)
        if let skillIds = prefab.skillIds {
            animal.moves = skillIds.compactMap { skillId -> AnimalMove? in
                switch skillId.lowercased() {
                case "bite": return .bite
                case "claw": return .claw
                case "charge": return .charge
                case "pounce": return .pounce
                case "howl": return .howl
                case "roar": return .roar
                case "dive": return .dive
                case "tackle": return .tackle
                default: return nil
                }
            }
        } else if let moves = prefab.moves {
            // Legacy support
            animal.moves = moves.compactMap { moveName -> AnimalMove? in
                AnimalMove(rawValue: moveName.capitalized)
            }
        }
        
        return animal
    }
    
    /// Create an Enemy instance from an EnemyPrefab
    private func createEnemyFromPrefab(_ prefab: EnemyPrefab, level: Int) -> Enemy {
        // Scale stats by level if prefab level is different
        let prefabLevel = prefab.level ?? 1
        let levelMultiplier = level > prefabLevel ? Double(level) / Double(prefabLevel) : 1.0
        
        let enemy = Enemy(
            name: prefab.name,
            hitPoints: Int(Double(prefab.hitPoints) * levelMultiplier),
            armorClass: Int(Double(prefab.defensePoints) * levelMultiplier),
            attackBonus: Int(Double(prefab.attackPoints) * levelMultiplier),
            damageDie: 6, // Default damage die (could be added to prefab later)
            experienceReward: prefab.experienceReward ?? (10 * level),
            goldReward: prefab.goldReward ?? (5 * level)
        )
        
        return enemy
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
        // Otherwise use the WorldMap collision system or chunk collision
        let canMove: Bool
        if useTiledMap {
            // Check collision map for Tiled maps
            canMove = canMoveToTiledMap(position: newPosition)
            if !canMove {
                print("🛑 Movement blocked at position (\(Int(newPosition.x)), \(Int(newPosition.y)))")
                // Check if this is a door collision or procedural world trigger
                checkDoorCollision(at: newPosition)
            }
        } else {
            // Procedural world: check chunk collision (simplified for now)
            // TODO: Implement proper collision checking with chunk entities
            canMove = true  // Allow movement for now, collision will be added later
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
        // Look for a layer with exit property and matching door ID
        for (layerName, props) in layerProperties {
            if let exitValue = props["exit"]?.lowercased(),
               exitValue == "true" || exitValue == "1" {
                // Check if door ID matches
                let exitDoorId = props["doorId"] ?? props["door_id"] ?? layerName
                if exitDoorId == matchingDoorId {
                    // Find a collision tile from this layer to get its position
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
                        
                        print("   Found exit door (doorId=\(exitDoorId)) at tile (\(tileX), \(tileY)) -> world (\(Int(worldX)), \(Int(worldY)))")
                        return CGPoint(x: worldX, y: worldY)
                    }
                }
            }
        }
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
    
    /// Transition from TMX map to procedural world
    func transitionToProceduralWorld(from position: CGPoint, prefabsFile: String = "prefabs_grassland") {
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
        
        print("🌍 Transitioning to procedural world from TMX map (using prefabs: \(prefabsFile).json)")
        
        // Load prefabs from the specified JSON file (if different from current)
        PrefabFactory.shared.loadPrefabsFromFile(prefabsFile)
        
        // Get updated world config and apply to world generator
        if let worldConfig = PrefabFactory.shared.getWorldConfig() {
            // Update world seed from config if specified
            if let world = gameState?.world, worldConfig.seed != world.seed {
                gameState?.world.seed = worldConfig.seed
                print("🌍 World seed updated from config: \(worldConfig.seed)")
            }
            // Update world generator config
            worldGenerator?.setConfig(worldConfig)
            print("🌍 World config loaded: '\(worldConfig.name)' - seed: \(worldConfig.seed)")
        }
        
        // Store the entry position in TMX map for returning
        tmxMapEntryPosition = position
        
        // Clear TMX map rendering
        worldTiles.forEach { $0.removeFromParent() }
        worldTiles.removeAll()
        
        // Clear object sprites
        for (sprite, _) in objectSprites {
            sprite.removeFromParent()
        }
        objectSprites.removeAll()
        objectGroupNames.removeAll()
        
        // Clear question mark indicators
        for (_, indicator) in questionMarkIndicators {
            indicator.removeFromParent()
        }
        questionMarkIndicators.removeAll()
        
        // Switch to procedural world
        useTiledMap = false
        
        // Update GameState with map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = true
        }
        
        // Show loading screen
        showLoadingScreen(message: "Generating World...")
        
        // Setup hybrid world system if not already set up
        if chunkManager == nil {
            setupHybridWorldSystem()
        }
        
        // Spawn player slightly forward from trigger position to avoid immediate re-trigger
        // Move player 2 tiles north (positive Y) from the trigger
        let tileSize: CGFloat = 32.0  // Matches TMX maps: 16x16 base tiles * 2.0 scale factor
        let spawnOffset = CGPoint(x: 0, y: tileSize * 2)  // 2 tiles forward
        let spawnPosition = CGPoint(x: position.x + spawnOffset.x, y: position.y + spawnOffset.y)
        
        player.position = spawnPosition
        playerSprite?.position = spawnPosition
        cameraNode?.position = spawnPosition
        
        // Load initial chunks around player asynchronously
        if let chunkManager = chunkManager {
            chunkManager.updateChunksAsync(around: spawnPosition) { [weak self] in
                // Hide loading screen when chunks are loaded
                DispatchQueue.main.async {
                    self?.hideLoadingScreen()
                    print("✅ Transitioned to procedural world. Player at: (\(Int(spawnPosition.x)), \(Int(spawnPosition.y))), entry point was: (\(Int(position.x)), \(Int(position.y)))")
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
    func transitionToTiledMap() {
        guard let player = gameState?.player, let entryPosition = tmxMapEntryPosition else {
            print("❌ Cannot transition to TMX map: no entry position stored")
            return
        }
        
        print("🏠 Transitioning back to TMX map from procedural world")
        
        // Store exit position in procedural world (for returning later if needed)
        proceduralWorldExitPosition = player.position
        
        // Clear procedural world chunks
        if let chunkManager = chunkManager {
            chunkManager.unloadAllChunks()
        }
        
        // Also remove any remaining chunk nodes from the scene
        enumerateChildNodes(withName: "chunk_") { node, _ in
            node.removeFromParent()
        }
        
        // Switch back to TMX map
        useTiledMap = true
        
        // Update GameState with map information
        if let gameState = gameState {
            gameState.currentMapFileName = tiledMapFileName
            gameState.useProceduralWorld = false
        }
        
        // Reload the TMX map
        reloadCurrentMap()
        
        // Position player at the entry point
        player.position = entryPosition
        playerSprite?.position = entryPosition
        cameraNode?.position = entryPosition
        
        // Clear procedural world tracking (keep tmxMapEntryPosition in case we want to go back)
        // proceduralWorldExitPosition is kept for potential return
        
        print("✅ Transitioned back to TMX map. Player at: (\(Int(entryPosition.x)), \(Int(entryPosition.y)))")
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
        questionMarkIndicators.values.forEach { $0.removeFromParent() }
        questionMarkIndicators.removeAll()
        
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
            
            // Check for transition back to TMX map
            // If player walks back near the entry position, transition back to TMX
            // This allows seamless travel between TMX and procedural worlds
            // Only check if cooldown has passed
            let currentTime = CACurrentMediaTime()
            if currentTime - lastTransitionTime >= transitionCooldown,
               let entryPos = tmxMapEntryPosition {
                let distance = sqrt(pow(player.position.x - entryPos.x, 2) + pow(player.position.y - entryPos.y, 2))
                // If player walks back to the entry position (within 32 pixels = 1 tile), transition back
                if distance < 32.0 {
                    print("🌍 Player walked back to procedural world entry point, transitioning back to TMX map")
                    transitionToTiledMap()
                    return
                }
            }
        }
        
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
            
            // Create sprite for object
            var sprite: SKSpriteNode?
            
            if let gid = object.gid {
                // Object uses a tile (has a GID)
                // Use the object's width/height if specified, otherwise use tile size
                // IMPORTANT: Scale object size by scaleFactor to match rendered tile size
                let baseObjectWidth = object.width > 0 ? object.width : baseTileWidth
                let baseObjectHeight = object.height > 0 ? object.height : baseTileWidth
                let objectSize = CGSize(
                    width: baseObjectWidth * scaleFactor,
                    height: baseObjectHeight * scaleFactor
                )
                print("   🔍 Attempting to create sprite for GID \(gid) with size \(objectSize) (base: \(baseObjectWidth)x\(baseObjectHeight), scale: \(scaleFactor))")
                sprite = TileManager.shared.createSprite(for: gid, size: objectSize)
                if sprite == nil {
                    print("⚠️ WARNING: Failed to create sprite for object '\(object.name)' with GID \(gid). Creating fallback sprite.")
                    // Create a fallback visible sprite so we can see the object
                    sprite = SKSpriteNode(color: .red, size: objectSize)
                    sprite?.alpha = 0.8
                } else {
                    print("   ✅ Successfully created sprite for GID \(gid), sprite size: \(sprite?.size ?? .zero)")
                    // Debug: Check if texture is loaded
                    if let texture = sprite?.texture {
                        print("   ✅ Sprite has texture: size=\(texture.size()), cgImage=\(texture.cgImage() != nil ? "present" : "nil")")
                        // CRITICAL: Ensure no color tinting that could show as yellow
                        sprite?.colorBlendFactor = 0.0
                        sprite?.color = .white
                        // Remove any yellow child nodes (backgrounds, borders, etc.) that might be covering the sprite
                        let childrenToRemove = sprite?.children.filter { child in
                            if let shapeNode = child as? SKShapeNode {
                                return shapeNode.fillColor == .yellow || shapeNode.strokeColor == .yellow
                            }
                            if let spriteChild = child as? SKSpriteNode {
                                return spriteChild.color == .yellow
                            }
                            return false
                        } ?? []
                        for child in childrenToRemove {
                            child.removeFromParent()
                            print("   🗑️ Removed yellow child node from object sprite")
                        }
                    } else {
                        print("   ⚠️ WARNING: Sprite created but has no texture! Creating fallback.")
                        // If sprite has no texture, create a fallback instead
                        sprite = SKSpriteNode(color: .red, size: objectSize)
                        sprite?.alpha = 0.8
                    }
                }
            } else {
                // Object doesn't use a tile - create a colored rectangle or use a default sprite
                // Make it more visible with a border
                let objectSize = CGSize(
                    width: object.width > 0 ? object.width : tileSize.width,
                    height: object.height > 0 ? object.height : tileSize.height
                )
                
                // Ensure minimum size so objects are always visible
                let minSize: CGFloat = max(16, tileSize.width * 0.5) // At least 16px or half tile size
                let finalWidth = max(objectSize.width, minSize)
                let finalHeight = max(objectSize.height, minSize)
                let finalSize = CGSize(width: finalWidth, height: finalHeight)
                
                sprite = SKSpriteNode(color: .yellow, size: finalSize)
                sprite?.alpha = 0.9  // More visible
                
                // Add a label with object name for debugging
                if !object.name.isEmpty {
                    let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
                    nameLabel.text = object.name
                    nameLabel.fontSize = 10
                    nameLabel.fontColor = .black
                    nameLabel.position = CGPoint(x: finalSize.width / 2, y: finalSize.height / 2)
                    nameLabel.verticalAlignmentMode = .center
                    nameLabel.horizontalAlignmentMode = .center
                    nameLabel.zPosition = 1
                    sprite?.addChild(nameLabel)
                }
                
                print("   ℹ️ Object '\(object.name)' has no GID - displaying as yellow rectangle with size \(finalSize)")
            }
            
            // If sprite creation failed, create a fallback sprite
            if sprite == nil {
                print("⚠️ Failed to create sprite for object '\(object.name)' (id: \(object.id))")
                // Create a visible fallback sprite so we can at least see where the object should be
                let fallbackSize = CGSize(width: max(object.width, 32), height: max(object.height, 32))
                let fallbackSprite = SKSpriteNode(color: .cyan, size: fallbackSize)
                fallbackSprite.alpha = 0.9
                sprite = fallbackSprite
                print("   ✅ Created fallback cyan sprite for debugging")
            }
            
            guard let objectSprite = sprite else {
                print("⚠️ CRITICAL: Even fallback sprite creation failed for object '\(object.name)' (id: \(object.id))")
                continue
            }
            
            // Set anchor point and z-position first
            objectSprite.anchorPoint = CGPoint(x: 0, y: 0)  // Bottom-left corner
            objectSprite.zPosition = zPosition
            
            // Make objects more visible - scale them up if they're too small
            // Do this BEFORE calculating position so we can use the final sprite size
            let minVisibleSize: CGFloat = 32.0
            let originalSize = objectSprite.size
            var visibilityScaleFactor: CGFloat = 1.0
            if originalSize.width < minVisibleSize || originalSize.height < minVisibleSize {
                visibilityScaleFactor = max(minVisibleSize / originalSize.width, minVisibleSize / originalSize.height)
                objectSprite.setScale(visibilityScaleFactor)
                print("   📏 Scaled object sprite by \(visibilityScaleFactor)x to make it more visible (original: \(originalSize), scaled: \(CGSize(width: originalSize.width * visibilityScaleFactor, height: originalSize.height * visibilityScaleFactor)))")
            }
            
            // Position the sprite using the EXACT same calculation as chunks
            // Chunks position tiles at: worldY = yFlipOffset - tiledY
            // where tiledY = (chunk.y + y) * tileSize.height
            // The position is the bottom-left corner (anchorPoint 0,0)
            // For objects: Object Y in Tiled is the TOP
            // We calculate: worldY = yFlipOffset - scaledY (this gives us the TOP)
            // But we need the BOTTOM position for anchorPoint (0,0)
            // So: bottomY = topY - height
            // Add 65px offset to align better with tile grid (user feedback: final fine-tuning)
            let actualObjectHeight = objectSprite.size.height * visibilityScaleFactor
            let adjustedWorldY = worldY - actualObjectHeight + 65.0
            
            objectSprite.position = CGPoint(x: worldX, y: adjustedWorldY)
            
            // Debug border removed per user request
            
            // Set object name for debugging
            objectSprite.name = "object_\(object.id)_\(object.name)"
            
            // Store the object data with the sprite for collision detection
            objectSprites[objectSprite] = object
            objectGroupNames[objectSprite] = objectGroup.name
            
            // Add visual indicator for dialogue objects (subtle glow)
            // Collectables don't need glow since they auto-collect on collision
            // Only mark as collectible if the property is explicitly set to true
            let isCollectable = object.boolProperty("collectable", default: false)
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
            
            // Ensure objects with GIDs are fully visible and have no color tint
            if object.gid != nil {
                objectSprite.alpha = 1.0
                objectSprite.isHidden = false
                // Ensure no color tinting (like tiles)
                objectSprite.colorBlendFactor = 0.0
                objectSprite.color = .white
            }
            
            // Ensure sprite is visible before adding
            objectSprite.alpha = 1.0
            objectSprite.isHidden = false
            
            // Add to scene
            parentNode.addChild(objectSprite)
            
            print("✅ Added object '\(object.name)' (id: \(object.id)) at Tiled base(\(Int(object.x)), \(Int(object.y))) -> scaled(\(Int(scaledX)), \(Int(scaledY))) -> SpriteKit(\(Int(worldX)), \(Int(adjustedWorldY))), size: \(objectSprite.size), zPosition: \(zPosition), hasGID: \(object.gid?.description ?? "nil")")
            if !object.properties.isEmpty {
                print("   📋 Object properties: \(object.properties)")
            } else {
                print("   ⚠️ Object has no properties")
            }
            print("   📍 Object sprite position: \(objectSprite.position), size: \(objectSprite.size), anchorPoint: \(objectSprite.anchorPoint)")
            print("   🎯 Object sprite isHidden: \(objectSprite.isHidden), alpha: \(objectSprite.alpha)")
            
            // Debug: Calculate what tile this object should be near (using base tile coordinates)
            let debugObjectTileX = Int(object.x / baseTileWidth)
            let debugObjectTileY = Int(object.y / baseTileWidth)
            let expectedWorldX = CGFloat(debugObjectTileX) * tileSize.width
            let expectedWorldY = yFlipOffset - (CGFloat(debugObjectTileY) * tileSize.height)
            print("   🗺️ Object is at Tiled tile grid approximately: (\(debugObjectTileX), \(debugObjectTileY))")
            print("   🗺️ A tile at grid (\(debugObjectTileX), \(debugObjectTileY)) would be at world position: (\(Int(expectedWorldX)), \(Int(expectedWorldY)))")
            print("   🗺️ Object actual world position: (\(Int(worldX)), \(Int(adjustedWorldY)))")
            
            // Debug: Check if object is within reasonable bounds
            let mapBounds = self.mapBounds
            if mapBounds.width > 0 && mapBounds.height > 0 {
                if !mapBounds.contains(CGPoint(x: worldX, y: adjustedWorldY)) {
                    print("   ⚠️ WARNING: Object position (\(Int(worldX)), \(Int(adjustedWorldY))) is outside map bounds (\(mapBounds))")
                    print("   → Object may not be visible on screen")
                } else {
                    print("   ✅ Object is within map bounds")
                }
            } else {
                print("   ⚠️ Map bounds not yet calculated (will be set after object rendering)")
            }
            
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
    private func getPlayerCollisionFrame(at position: CGPoint) -> CGRect {
        // Collision box is as wide as the character (sprite is 96x96, use ~24px wide for reasonable collision)
        // and about knee height (10px tall)
        let collisionSize = CGSize(width: 8, height: 12)
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
        
        // Reset drag state
        draggedItemIndex = nil
        draggedItemNode = nil
        closeInventoryContextMenu()
        
        // Create inventory UI (relative to camera)
        guard let camera = cameraNode, let player = gameState?.player else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Panel dimensions
        let panelWidth = min(size.width * 0.9, isLandscape ? 800 : 600)
        let panelHeight = min(size.height * 0.8, isLandscape ? 600 : 700)
        
        // Modern panel with gradient-like effect
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 16)
        panel.fillColor = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0)
        panel.lineWidth = 4
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        panel.name = "inventoryPanel"
        camera.addChild(panel)
        
        // Title background with better styling
        let titleBg = SKShapeNode(rectOf: CGSize(width: panelWidth * 0.95, height: 55), cornerRadius: 10)
        titleBg.fillColor = SKColor(red: 0.25, green: 0.45, blue: 0.7, alpha: 0.95)
        titleBg.strokeColor = SKColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        titleBg.lineWidth = 3
        titleBg.position = CGPoint(x: 0, y: panelHeight / 2 - 35)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "Inventory"
        title.fontSize = 32
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        title.zPosition = 1
        titleBg.addChild(title)
        
        // Inventory slots configuration
        let slotsPerRow = isLandscape ? 8 : 6
        let numRows = isLandscape ? 6 : 8
        let totalSlots = slotsPerRow * numRows
        
        let slotSize: CGFloat = isLandscape ? 60 : 50
        let slotSpacing: CGFloat = 10
        let slotsAreaWidth = CGFloat(slotsPerRow) * slotSize + CGFloat(slotsPerRow - 1) * slotSpacing
        let slotsAreaHeight = CGFloat(numRows) * slotSize + CGFloat(numRows - 1) * slotSpacing
        
        // Slots container background with better styling
        let slotsBg = SKShapeNode(rectOf: CGSize(width: slotsAreaWidth + 30, height: slotsAreaHeight + 30), cornerRadius: 10)
        slotsBg.fillColor = SKColor(white: 0.08, alpha: 0.95)
        slotsBg.strokeColor = SKColor(white: 0.4, alpha: 0.8)
        slotsBg.lineWidth = 2
        slotsBg.position = CGPoint(x: 0, y: -10)
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
                
                // Create slot background with better styling
                let slotBg = SKShapeNode(rectOf: CGSize(width: slotSize, height: slotSize), cornerRadius: 6)
                slotBg.fillColor = SKColor(white: 0.25, alpha: 0.9)
                slotBg.strokeColor = SKColor(white: 0.6, alpha: 0.8)
                slotBg.lineWidth = 2
                slotBg.position = CGPoint(x: x, y: y)
                slotBg.name = "inventorySlot_\(slotIndex)"
                slotBg.zPosition = 1
                slotsBg.addChild(slotBg)
                
                // If we have an item for this slot, display it
                if slotIndex < player.inventory.count {
                    let item = player.inventory[slotIndex]
                    
                    // Create item container node for drag support
                    let itemContainer = SKNode()
                    itemContainer.name = "itemContainer_\(slotIndex)"
                    itemContainer.position = CGPoint(x: 0, y: 0)
                    itemContainer.zPosition = 2
                    slotBg.addChild(itemContainer)
                    
                    // Create item sprite from GID if available
                    if let gid = item.gid {
                        let itemSize = CGSize(width: slotSize * 0.8, height: slotSize * 0.8)
                        if let itemSprite = TileManager.shared.createSprite(for: gid, size: itemSize) {
                            itemSprite.position = CGPoint(x: 0, y: 0)
                            itemSprite.zPosition = 1
                            itemSprite.name = "itemSprite_\(slotIndex)"
                            itemContainer.addChild(itemSprite)
                        }
                    } else {
                        // Fallback: create a colored square with item name
                        let fallbackSprite = SKSpriteNode(color: SKColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 0.8), size: CGSize(width: slotSize * 0.7, height: slotSize * 0.7))
                        fallbackSprite.position = CGPoint(x: 0, y: 0)
                        fallbackSprite.zPosition = 1
                        itemContainer.addChild(fallbackSprite)
                        
                        // Add item name label (small)
                        let nameLabel = SKLabelNode(fontNamed: "Arial")
                        nameLabel.text = String(item.name.prefix(4)) // First 4 chars
                        nameLabel.fontSize = 8
                        nameLabel.fontColor = .white
                        nameLabel.position = CGPoint(x: 0, y: 0)
                        nameLabel.verticalAlignmentMode = .center
                        nameLabel.zPosition = 2
                        itemContainer.addChild(nameLabel)
                    }
                    
                    // Show quantity if > 1 or if stackable - improved positioning
                    if item.quantity > 1 || item.stackable {
                        // Quantity background - positioned better to avoid border overlap
                        let quantityBg = SKShapeNode(rectOf: CGSize(width: 24, height: 18), cornerRadius: 4)
                        quantityBg.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.85)
                        quantityBg.strokeColor = SKColor(white: 0.9, alpha: 1.0)
                        quantityBg.lineWidth = 1.5
                        // Position in bottom-right corner, inset from edge
                        quantityBg.position = CGPoint(x: slotSize / 2 - 14, y: -slotSize / 2 + 12)
                        quantityBg.zPosition = 4
                        itemContainer.addChild(quantityBg)
                        
                        // Quantity label
                        let quantityLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
                        quantityLabel.text = "\(item.quantity)"
                        quantityLabel.fontSize = 13
                        quantityLabel.fontColor = .white
                        quantityLabel.position = CGPoint(x: slotSize / 2 - 14, y: -slotSize / 2 + 12)
                        quantityLabel.horizontalAlignmentMode = .center
                        quantityLabel.verticalAlignmentMode = .center
                        quantityLabel.zPosition = 5
                        itemContainer.addChild(quantityLabel)
                    }
                }
            }
        }
        
        // Close button with better styling
        let closeButton = SKShapeNode(rectOf: CGSize(width: 140, height: 55), cornerRadius: 10)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1.0)
        closeButton.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        closeButton.lineWidth = 3
        closeButton.position = CGPoint(x: 0, y: -panelHeight / 2 + 35)
        closeButton.name = "closeInventory"
        closeButton.zPosition = 10
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Close"
        closeLabel.fontSize = 22
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeLabel.zPosition = 1
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    // MARK: - Inventory Context Menu
    
    func showInventoryContextMenu(at position: CGPoint, itemIndex: Int) {
        guard let camera = cameraNode, let player = gameState?.player,
              itemIndex < player.inventory.count else { return }
        
        // Close any existing context menu
        closeInventoryContextMenu()
        
        contextMenuItemIndex = itemIndex
        let item = player.inventory[itemIndex]
        
        // Create context menu panel with better spacing
        let menuWidth: CGFloat = 200
        let menuHeight: CGFloat = 180
        let menu = SKShapeNode(rectOf: CGSize(width: menuWidth, height: menuHeight), cornerRadius: 10)
        menu.fillColor = SKColor(white: 0.2, alpha: 0.98)
        menu.strokeColor = SKColor(white: 0.7, alpha: 1.0)
        menu.lineWidth = 3
        menu.position = position
        menu.zPosition = 300
        menu.name = "inventoryContextMenu"
        camera.addChild(menu)
        inventoryContextMenu = menu
        
        // Item name label with better spacing
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = item.name
        nameLabel.fontSize = 18
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: menuHeight / 2 - 25)
        nameLabel.verticalAlignmentMode = .center
        menu.addChild(nameLabel)
        
        // Inspect button
        let inspectButton = createContextMenuButton(text: "Inspect", color: SKColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0), yOffset: 35)
        inspectButton.name = "contextMenuInspect"
        menu.addChild(inspectButton)
        
        // Drop button
        let dropButton = createContextMenuButton(text: "Drop", color: SKColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0), yOffset: -15)
        dropButton.name = "contextMenuDrop"
        menu.addChild(dropButton)
        
        // Destroy button
        let destroyButton = createContextMenuButton(text: "Destroy", color: SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), yOffset: -65)
        destroyButton.name = "contextMenuDestroy"
        menu.addChild(destroyButton)
    }
    
    func createContextMenuButton(text: String, color: SKColor, yOffset: CGFloat) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 180, height: 40), cornerRadius: 8)
        button.fillColor = color
        button.strokeColor = .white
        button.lineWidth = 2.5
        button.position = CGPoint(x: 0, y: yOffset)
        button.zPosition = 1
        
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = 18
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        button.addChild(label)
        
        return button
    }
    
    func closeInventoryContextMenu() {
        inventoryContextMenu?.removeFromParent()
        inventoryContextMenu = nil
        contextMenuItemIndex = nil
    }
    
    func handleInventoryContextMenuAction(action: String) {
        guard let itemIndex = contextMenuItemIndex,
              let player = gameState?.player,
              itemIndex < player.inventory.count else { return }
        
        let item = player.inventory[itemIndex]
        closeInventoryContextMenu()
        
        switch action {
        case "inspect":
            showItemInspect(item: item)
        case "drop":
            dropItem(itemIndex: itemIndex, item: item)
        case "destroy":
            destroyItem(itemIndex: itemIndex, item: item)
        default:
            break
        }
    }
    
    func showItemInspect(item: Item) {
        guard let camera = cameraNode else { return }
        
        // Create inspect panel
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 300
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = 400
        panel.name = "itemInspectPanel"
        camera.addChild(panel)
        
        // Title
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = item.name
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 40)
        title.verticalAlignmentMode = .center
        panel.addChild(title)
        
        // Description
        let description = SKLabelNode(fontNamed: "Arial")
        description.text = item.itemDescription.isEmpty ? "No description available." : item.itemDescription
        description.fontSize = 18
        description.fontColor = .white
        description.position = CGPoint(x: 0, y: 20)
        description.verticalAlignmentMode = .center
        description.horizontalAlignmentMode = .center
        description.preferredMaxLayoutWidth = panelWidth - 40
        description.numberOfLines = 0
        panel.addChild(description)
        
        // Quantity
        if item.quantity > 1 {
            let quantityLabel = SKLabelNode(fontNamed: "Arial")
            quantityLabel.text = "Quantity: \(item.quantity)"
            quantityLabel.fontSize = 16
            quantityLabel.fontColor = .lightGray
            quantityLabel.position = CGPoint(x: 0, y: -60)
            quantityLabel.verticalAlignmentMode = .center
            panel.addChild(quantityLabel)
        }
        
        // Close button
        let closeButton = SKShapeNode(rectOf: CGSize(width: 120, height: 45), cornerRadius: 8)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1.0)
        closeButton.strokeColor = .white
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: 0, y: -panelHeight / 2 + 35)
        closeButton.name = "closeInspect"
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "Close"
        closeLabel.fontSize = 18
        closeLabel.fontColor = .white
        closeLabel.verticalAlignmentMode = .center
        closeButton.addChild(closeLabel)
        panel.addChild(closeButton)
    }
    
    func dropItem(itemIndex: Int, item: Item) {
        guard let player = gameState?.player, let playerSprite = playerSprite else { return }
        
        // Create a dropped item object at player position
        let dropPosition = player.position
        
        // Remove item from inventory
        if item.quantity > 1 {
            player.inventory[itemIndex].quantity -= 1
        } else {
            player.inventory.remove(at: itemIndex)
        }
        
        // Create a TiledObject-like representation for the dropped item
        // We'll need to create a visual representation on the map
        // For now, just show a message and refresh inventory
        showMessage("Dropped: \(item.name) x1")
        
        // TODO: Actually create a pickupable object on the ground at dropPosition
        // This would require creating a TiledObject and rendering it in the world
        
        // Refresh inventory display
        if let panel = cameraNode?.childNode(withName: "inventoryPanel") {
            panel.removeFromParent()
            showInventory()
        }
    }
    
    func destroyItem(itemIndex: Int, item: Item) {
        guard let player = gameState?.player else { return }
        
        let itemName = item.name
        let quantity = item.quantity
        
        // Remove item from inventory
        player.inventory.remove(at: itemIndex)
        
        showMessage("Destroyed: \(itemName) x\(quantity)")
        
        // Refresh inventory display
        if let panel = cameraNode?.childNode(withName: "inventoryPanel") {
            panel.removeFromParent()
            showInventory()
        }
    }
    
    func swapInventoryItems(from sourceIndex: Int, to targetIndex: Int) {
        guard let player = gameState?.player,
              sourceIndex < player.inventory.count,
              targetIndex >= 0 else {
            print("⚠️ Cannot swap items: sourceIndex=\(sourceIndex), targetIndex=\(targetIndex), inventory.count=\(gameState?.player.inventory.count ?? 0)")
            return
        }
        
        let originalCount = player.inventory.count
        print("🔄 Moving item from slot \(sourceIndex) to slot \(targetIndex), current inventory count: \(originalCount)")
        
        // If moving to the same slot, do nothing
        if sourceIndex == targetIndex {
            print("   ℹ️ Item already in target slot, no change needed")
            return
        }
        
        // If target is within bounds, use swapAt for proper swapping
        if targetIndex < originalCount {
            // Both slots have items - swap them
            player.inventory.swapAt(sourceIndex, targetIndex)
            print("   ✅ Swapped items: slot \(sourceIndex) <-> slot \(targetIndex)")
        } else {
            // Target slot is empty (beyond current array)
            // Remove from source and append to end
            let item = player.inventory.remove(at: sourceIndex)
            player.inventory.append(item)
            print("   ⚠️ Moved item to end: removed from index \(sourceIndex), appended (target was \(targetIndex), but can't have gaps in array)")
            print("   💡 Tip: To move items to specific slots, swap with existing items first")
        }
        
        // Refresh inventory display
        if let panel = cameraNode?.childNode(withName: "inventoryPanel") {
            panel.removeFromParent()
            showInventory()
            print("   ✅ Inventory refreshed, new count: \(player.inventory.count)")
        }
    }
    
    // Helper function to find slot index by position (fallback for drag and drop)
    func findSlotIndexAtPosition(_ position: CGPoint, in panel: SKNode) -> Int? {
        // Find the slots container by searching for any slot node
        var slotsBg: SKNode? = nil
        panel.enumerateChildNodes(withName: "//inventorySlot_*") { node, _ in
            slotsBg = node.parent
            return
        }
        guard let slotsContainer = slotsBg else { return nil }
        
        // Get slot configuration from panel
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        let slotsPerRow = isLandscape ? 8 : 6
        let numRows = isLandscape ? 6 : 8
        let slotSize: CGFloat = isLandscape ? 60 : 50
        let slotSpacing: CGFloat = 10
        let slotsAreaWidth = CGFloat(slotsPerRow) * slotSize + CGFloat(slotsPerRow - 1) * slotSpacing
        let slotsAreaHeight = CGFloat(numRows) * slotSize + CGFloat(numRows - 1) * slotSpacing
        
        // Convert position to slots container coordinates
        let slotsLocalPoint = slotsContainer.convert(position, from: panel)
        let startX = -slotsAreaWidth / 2 + slotSize / 2
        let startY = slotsAreaHeight / 2 - slotSize / 2
        
        // Calculate which slot this position is in
        let relativeX = slotsLocalPoint.x - startX
        let relativeY = startY - slotsLocalPoint.y
        
        let col = Int(round(relativeX / (slotSize + slotSpacing)))
        let row = Int(round(relativeY / (slotSize + slotSpacing)))
        
        if col >= 0 && col < slotsPerRow && row >= 0 && row < numRows {
            let slotIndex = row * slotsPerRow + col
            print("   📍 Position-based slot detection: col=\(col), row=\(row), index=\(slotIndex)")
            return slotIndex
        }
        
        return nil
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
        
        // First, try to load item from prefab if itemId is specified
        if let itemId = object.stringProperty("itemId"),
           let itemPrefab = PrefabFactory.shared.getItemPrefab(itemId) {
            // Create item from prefab
            let item = createItemFromPrefab(itemPrefab, quantity: Int(object.floatProperty("quantity", default: 1)), gid: object.gid)
            player.inventory.append(item)
            print("✅ Collected item from prefab: \(itemPrefab.name) (id: \(itemId))")
            showMessage("Collected: \(itemPrefab.name) x\(item.quantity)")
        } else {
            // Fall back to creating item from object properties (backwards compatible)
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
        }
        
        // Remove object from scene
        sprite.removeFromParent()
        objectSprites.removeValue(forKey: sprite)
        objectGroupNames.removeValue(forKey: sprite)
    }
    
    /// Create an Item instance from an ItemPrefab
    private func createItemFromPrefab(_ prefab: ItemPrefab, quantity: Int = 1, gid: Int? = nil) -> Item {
        // Parse GID from prefab if not provided
        // Priority: 1) provided gid parameter, 2) first tile from parts array, 3) legacy gid property
        let finalGID: Int?
        if let gid = gid {
            finalGID = gid
        } else if let firstPart = prefab.parts.first,
                  let firstRow = firstPart.tileGrid.first,
                  let firstTile = firstRow.first,
                  let gidString = firstTile {
            // Try to parse from first tile in parts array
            if let directGID = Int(gidString) {
                finalGID = directGID
            } else if let parsedGID = PrefabFactory.shared.parseGIDSpec(gidString) {
                finalGID = parsedGID
            } else {
                finalGID = nil
            }
        } else if let gidString = prefab.gid {
            // Fallback to legacy gid property
            if let directGID = Int(gidString) {
                finalGID = directGID
            } else if let parsedGID = PrefabFactory.shared.parseGIDSpec(gidString) {
                finalGID = parsedGID
            } else {
                finalGID = nil
            }
        } else {
            finalGID = nil
        }
        
        // Create item based on type
        switch prefab.type {
        case .weapon:
            guard let weaponData = prefab.weaponData,
                  let weaponType = WeaponType(rawValue: weaponData.weaponType.capitalized) else {
                // Fallback to basic item
                return Item(
                    name: prefab.name,
                    type: .weapon,
                    quantity: quantity,
                    description: prefab.description,
                    value: prefab.value,
                    gid: finalGID,
                    stackable: prefab.stackable
                )
            }
            let weapon = Weapon(
                name: prefab.name,
                weaponType: weaponType,
                isMagical: weaponData.isMagical ?? false,
                value: prefab.value
            )
            weapon.damageDie = weaponData.damageDie
            weapon.range = weaponData.range
            weapon.gid = finalGID
            weapon.quantity = quantity
            weapon.itemDescription = prefab.description
            weapon.stackable = prefab.stackable
            return weapon
            
        case .armor:
            guard let armorData = prefab.armorData,
                  let armorType = ArmorType(rawValue: armorData.armorType.capitalized + " Armor") else {
                return Item(
                    name: prefab.name,
                    type: .armor,
                    quantity: quantity,
                    description: prefab.description,
                    value: prefab.value,
                    gid: finalGID,
                    stackable: prefab.stackable
                )
            }
            let armor = Armor(name: prefab.name, armorType: armorType, value: prefab.value)
            armor.gid = finalGID
            armor.quantity = quantity
            armor.itemDescription = prefab.description
            armor.stackable = prefab.stackable
            return armor
            
        case .consumable:
            guard let consumableData = prefab.consumableData else {
                return Item(
                    name: prefab.name,
                    type: .healthPotion,
                    quantity: quantity,
                    description: prefab.description,
                    value: prefab.value,
                    gid: finalGID,
                    stackable: prefab.stackable
                )
            }
            let effectType = consumableData.effectType.lowercased()
            let effect: ConsumableEffect
            if effectType.contains("mana") {
                effect = .restoreMana(consumableData.effectValue)
            } else {
                effect = .heal(consumableData.effectValue)
            }
            let consumable = Consumable(
                name: prefab.name,
                type: .healthPotion,
                effect: effect,
                quantity: quantity,
                value: prefab.value
            )
            consumable.gid = finalGID
            consumable.itemDescription = prefab.description
            consumable.stackable = prefab.stackable
            return consumable
            
        case .material:
            guard let materialData = prefab.materialData,
                  let materialType = MaterialType(rawValue: materialData.materialType) else {
                return Item(
                    name: prefab.name,
                    type: .wood,
                    quantity: quantity,
                    description: prefab.description,
                    value: prefab.value,
                    gid: finalGID,
                    stackable: prefab.stackable
                )
            }
            let material = Material(materialType: materialType, quantity: quantity)
            material.gid = finalGID
            material.itemDescription = prefab.description
            return material
            
        case .befriending:
            // Treat as consumable for now
            let consumableData = prefab.consumableData ?? ConsumableData(effectType: "heal", effectValue: 2, duration: nil)
            let effect: ConsumableEffect = .heal(consumableData.effectValue)
            let consumable = Consumable(
                name: prefab.name,
                type: ItemType(rawValue: prefab.name) ?? .food,
                effect: effect,
                quantity: quantity,
                value: prefab.value
            )
            consumable.gid = finalGID
            consumable.itemDescription = prefab.description
            consumable.stackable = prefab.stackable
            return consumable
            
        default:
            return Item(
                name: prefab.name,
                type: .food,
                quantity: quantity,
                description: prefab.description,
                value: prefab.value,
                gid: finalGID,
                stackable: prefab.stackable
            )
        }
    }
    
    /// Spawn an enemy from a prefab at a TMX object position
    private func spawnEnemyFromPrefab(_ prefab: EnemyPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createEnemySprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            container.addChild(sprite)
        }
        
        // TODO: Create Enemy instance and add to game state
        print("✅ Spawned enemy from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
    }
    
    /// Spawn an animal from a prefab at a TMX object position
    private func spawnAnimalFromPrefab(_ prefab: AnimalPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createAnimalSprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            container.addChild(sprite)
        }
        
        // TODO: Create Animal instance and add to game state
        print("✅ Spawned animal from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
    }
    
    /// Spawn an NPC from a prefab at a TMX object position
    private func spawnNPCFromPrefab(_ prefab: NPCPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createNPCSprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            container.addChild(sprite)
        }
        
        // TODO: Create NPC instance and add to game state
        print("✅ Spawned NPC from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
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
    
    // MARK: - Loading Screen
    
    /// Show loading screen overlay (camera-relative, centered on view)
    func showLoadingScreen(message: String = "Loading...") {
        // Remove existing loading screen if any
        hideLoadingScreen()
        
        guard let camera = cameraNode else {
            print("⚠️ Cannot show loading screen: no camera node")
            return
        }
        
        // Get view size (what's actually visible on screen)
        let viewSize: CGSize
        if let view = self.view {
            viewSize = view.bounds.size
        } else {
            viewSize = size  // Fallback to scene size
        }
        
        // Create loading screen overlay (add to camera so it stays centered)
        let overlay = SKNode()
        overlay.name = "loadingScreen"
        // Position relative to camera (camera is at (0,0) in its own coordinate space)
        overlay.position = CGPoint(x: 0, y: 0)
        overlay.zPosition = 10000  // Above everything
        
        // Semi-transparent dark background covering entire view
        let background = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.9), size: viewSize)
        background.position = CGPoint(x: 0, y: 0)
        background.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        overlay.addChild(background)
        
        // Create a nicer container for text and spinner
        let contentContainer = SKNode()
        contentContainer.position = CGPoint(x: 0, y: 0)
        overlay.addChild(contentContainer)
        
        // Loading text with shadow
        let loadingLabelShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        loadingLabelShadow.text = message
        loadingLabelShadow.fontSize = 36
        loadingLabelShadow.fontColor = SKColor(white: 0, alpha: 0.5)
        loadingLabelShadow.position = CGPoint(x: 2, y: -2)
        contentContainer.addChild(loadingLabelShadow)
        
        let loadingLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        loadingLabel.text = message
        loadingLabel.fontSize = 36
        loadingLabel.fontColor = .white
        loadingLabel.position = CGPoint(x: 0, y: 50)
        contentContainer.addChild(loadingLabel)
        
        // Better spinning indicator (circle with segments)
        let spinnerRadius: CGFloat = 25
        let spinner = SKNode()
        spinner.position = CGPoint(x: 0, y: -20)
        
        // Create 8 segments for a nice spinner
        for i in 0..<8 {
            let segment = SKShapeNode(circleOfRadius: spinnerRadius / 3)
            let angle = CGFloat(i) * .pi * 2 / 8
            let x = cos(angle) * spinnerRadius
            let y = sin(angle) * spinnerRadius
            segment.position = CGPoint(x: x, y: y)
            segment.fillColor = SKColor(white: 1.0, alpha: 0.3 + CGFloat(i) * 0.7 / 8)
            segment.strokeColor = .clear
            spinner.addChild(segment)
        }
        
        contentContainer.addChild(spinner)
        
        // Smooth rotation animation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 1.5)
        spinner.run(SKAction.repeatForever(rotate))
        
        // Add overlay to camera so it follows camera position
        camera.addChild(overlay)
        loadingScreen = overlay
    }
    
    /// Hide loading screen overlay
    func hideLoadingScreen() {
        loadingScreen?.removeFromParent()
        loadingScreen = nil
    }
}

