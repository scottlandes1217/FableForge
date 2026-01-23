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
    var gameUI: GameUI?
    var combatUI: CombatUI?
    var characterUI: CharacterUI?
    var buildUI: BuildUI?
    var chestUI: ChestUI?
    var cameraNode: SKCameraNode?
    
    // Chest tracking
    var chestSprites: [SKNode: (entityKey: EntityKey, prefabId: String, position: CGPoint)] = [:]  // Map of chest sprite nodes to entity data
    var chestContents: [EntityKey: [Item]] = [:]  // Map of chest entity keys to their contents
    var lastOpenedChestNode: SKNode? = nil  // Track last chest we tried to open to prevent spam
    var chestCollisionBoxCache: [SKNode: CGRect] = [:]  // Cache collision boxes to avoid recalculating every frame
    
    // Generic auto-walk system (reusable for chests, NPCs, enemies, items, etc.)
    var autoWalkTarget: CGPoint?  // Target position for auto-walking
    var autoWalkInteractionRadius: CGFloat = 64.0  // Interaction distance (default 2 tiles)
    var isAutoWalking: Bool = false
    var autoWalkCompletion: (() -> Void)?  // Callback when auto-walk completes
    var autoWalkLastPosition: CGPoint?  // Track last position for stuck detection
    var autoWalkStuckCounter: Int = 0  // Counter for how long we've been stuck
    var autoWalkLastDirection: CGPoint = CGPoint.zero  // Last attempted direction
    var autoWalkObstacleAvoidance: CGPoint?  // Current obstacle avoidance direction
    var autoWalkTargetNode: SKNode?  // Target node for collision-based completion (e.g., chest)
    
    // Inventory drag and drop state
    var draggedItemIndex: Int? = nil
    var draggedItemNode: SKNode? = nil
    var inventoryContextMenu: SKNode? = nil
    var contextMenuItemIndex: Int? = nil
    
    // Debug overlay for collision box visualization
    var collisionDebugOverlay: SKShapeNode?
    
    // Player position history for companions to follow
    var playerPositionHistory: [CGPoint] = []
    let maxPositionHistory = 30  // Keep last 30 positions
    
    // Flag to determine if we should use Tiled map or generated world
    // When false, tilesets are still loaded from TMX for use with procedural generation
    var useTiledMap: Bool = true  // Use TMX file instead of procedural generation
    var tiledMapFileName: String = "Exterior"
    
    // Hybrid world system (chunk-based procedural + TMX instances)
    var chunkManager: ChunkManager?
    var worldGenerator: WorldGenerator?
    var deltaPersistence: DeltaPersistence?
    var lastPlayerChunk: ChunkKey?
    
    // Building entry/exit tracking
    var previousMapFileName: String?  // Store previous map when entering a building
    var previousPlayerPosition: CGPoint?  // Store player position before entering building
    var entryDoorPosition: CGPoint?  // Store entry door position for linking with exit
    var entryDoorLayerName: String?  // Store entry door layer name
    var entryDoorId: String?  // Store entry door ID for linking with matching exit door
    var currentTiledMap: TiledMap?  // Store the current parsed TiledMap for door finding
    
    // Procedural world transition tracking
    var proceduralWorldExitPosition: CGPoint?  // Position in procedural world to return to TMX map
    var tmxMapEntryPosition: CGPoint?  // Position in TMX map where player entered procedural world
    var lastTransitionTime: TimeInterval = 0  // Time of last transition (to prevent immediate re-trigger)
    let transitionCooldown: TimeInterval = 1.0  // 1 second cooldown between transitions
    var exitTilePositions: Set<String> = []  // Set of exit tile positions (as "x,y" strings) in procedural world
    var exitTileSprites: [SKSpriteNode] = []  // Visual sprites for exit tiles
    var exitTileData: [String: ExitDefinition] = [:]  // Map exit positions (as "x,y" strings) to their definitions
    var hasMovedAwayFromTrigger: Bool = false  // Track if player has moved away from trigger tile
    var triggerTilePosition: CGPoint?  // Position of the trigger tile in TMX map
    var currentProceduralWorldPrefab: String?  // Track which prefab file is currently loaded
    
    // Loading screen overlay
    var loadingScreen: SKNode?
    
    // Collision detection for Tiled maps
    // Use (Int, Int) tuple for tile coordinates instead of CGPoint (CGPoint is not Hashable)
    var collisionMap: Set<String> = []  // Set of non-walkable tile positions as "x,y" strings
    var collisionLayerMap: [String: String] = [:]  // Map of "x,y" -> layer name that created the collision
    var layerProperties: [String: [String: String]] = [:]  // Map of layer name -> properties (for door detection)
    var mapBounds: CGRect = .zero  // Map bounds for collision checking
    var mapYFlipOffset: CGFloat = 0  // Y flip offset for coordinate conversion
    var mapTileSize: CGSize = .zero  // Tile size used for rendering (for collision checks)
    var hasInfiniteLayers: Bool = false  // Track if map uses infinite layers (chunks) or regular layers
    var regularLayerHeight: Int = 0  // Height of regular layers (for coordinate conversion)
    var collisionDebugCount: Int = 0  // Debug counter for collision checks
    
    // Player collision box - calculated from sprite's actual frame
    // This ensures the collision box perfectly matches the sprite's visual bounds
    
    var currentCharacterId: UUID? // Track which character is currently playing
    var label: SKLabelNode? // Label property (may be used by Actions.sks)
    
    // Frame animation properties
    var idleFrameTextures: [String: SKTexture] = [:] // ["south": texture, "west": texture, ...]
    var walkFrameTextures: [String: [SKTexture]] = [:] // ["south": [texture0, texture1, ...], ...]
    var currentAnimationFrame: Int = 0 // Current frame index for walk animation
    var animationTimer: TimeInterval = 0 // Timer for frame animation
    let animationFrameDuration: TimeInterval = 0.15 // 150ms per frame
    var lastFacingDirection: String = "south" // Track last facing direction for idle state
    var playerSpriteSize: CGSize = CGSize(width: 96, height: 96) // Store sprite size
    var playerSpriteScale: CGFloat = 1.5 // Slight visual scale to match prefabs
    var playerCollisionYOffset: CGFloat = 30.0 // Move collision box toward feet (pre-scale)
    
    // Track last animation state to only update when it changes
    var lastAnimationFrame: Int = -1
    var lastAnimationDirection: String = ""
    var lastAnimationIsMoving: Bool = false
    
    var isInCombat: Bool = false
    var isInDialogue: Bool = false
    // Use a separate flag to track game logic pause state to avoid
    // conflicting with SKScene/SKNode's built-in `isPaused` property.
    var isGamePaused: Bool = false
    var movementSpeed: CGFloat = 2.0
    let encounterDistance: CGFloat = 40.0 // Distance to trigger encounter
    
    // Build placement mode
    var isBuildPlacementMode: Bool = false
    var selectedStructureType: StructureType?
    var selectedStructureData: StructureData? // JSON-based structure data
    var placementPreview: SKShapeNode?  // Preview sprite for placement
    var originalCameraScale: CGFloat = 1.0  // Store original camera scale before zooming out
    
    // Prevent infinite loop when updating scene size
    var isUpdatingUISize: Bool = false
    
    // Track previous view size to detect changes
    var previousViewSize: CGSize = .zero
    
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
        
        // Determine which world mode to load (same logic as reload)
        configureMapMode(from: parsedTiledMap)
        
        // Load and render Tiled map (or use chunk-based procedural world)
        loadMapFromCurrentMode(preParsedMap: parsedTiledMap)
        
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
        
        // Spawn some initial animals and enemies only for auto-generated worlds, not TMX maps
        if !useTiledMap {
            spawnInitialAnimals()
        }
    }
    
    override func didMove(to view: SKView) {
        // Enable user interaction for object clicking
        self.isUserInteractionEnabled = true
        
        // Always update scene size from view bounds to ensure correct rendering
        // This is critical for proper texture positioning and scaling
        size = view.bounds.size
        print("🔵 GameScene: didMove - Scene size set to view bounds: \(size), view.bounds: \(view.bounds)")
        print("🔵 GameScene: didMove - isUserInteractionEnabled=\(isUserInteractionEnabled), isPaused=\(isPaused), view=\(view)")
        print("🔵 GameScene: didMove - Scene type: \(type(of: self))")
        
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
            characterUI = CharacterUI(scene: self, camera: camera)
            buildUI = BuildUI(scene: self, camera: camera)
            chestUI = ChestUI(scene: self, camera: camera)
            gameUI?.updatePlayerStats(player: player)
            gameUI?.updateCompanionStats(companion: player.companions.first)
        }
        
        // Note: Tile snapping is now handled in loadAndRenderTiledMap() after map loads
        // This ensures tiles are snapped immediately after rendering, preventing seams on first load
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Prevent infinite loop - if we're already updating, don't call again
        guard !isUpdatingUISize else { return }
        
        // Update UI layout when view size changes (orientation change)
        updateUIForSizeChange()
    }
    
    func updateUIForSizeChange() {
        // Prevent infinite loop
        guard !isUpdatingUISize else {
            print("GameScene: updateUIForSizeChange called while already updating - skipping to prevent infinite loop")
            return
        }
        
        isUpdatingUISize = true
        defer { isUpdatingUISize = false }
        
        let currentViewSize = view?.bounds.size ?? .zero
        print("GameScene: updateUIForSizeChange called - Scene size: \(size), View size: \(currentViewSize)")
        
        // CRITICAL FIX: Update scene size to match view size
        // In SpriteKit, the camera's coordinate system is based on scene.size, not view.bounds.size
        // When UI is attached to the camera, it uses scene.size for its coordinate system
        // So we must update scene.size to match view.bounds.size for UI to work correctly in fullscreen
        // BUT: We need to be careful not to trigger didChangeSize again, so we only update if different
        if currentViewSize.width > 0 && currentViewSize.height > 0 {
            let oldSize = size
            // Only update if significantly different (more than 1 point) to avoid triggering didChangeSize unnecessarily
            if abs(oldSize.width - currentViewSize.width) > 1 || abs(oldSize.height - currentViewSize.height) > 1 {
                // Temporarily disable the guard to allow the size change
                // But didChangeSize will check the guard and return early
                size = currentViewSize
                print("GameScene: Updated scene size from \(oldSize) to \(size) to match view size")
            }
        }
        
        // CRITICAL: Re-snap all tile positions to pixel boundaries when scene size changes
        // This prevents seams between tiles when switching between windowed and fullscreen
        reSnapTilePositions()
        
        // Update UI layout when view size changes (orientation change)
        gameUI?.updateLayout()
        
        // Restore UI stats after layout update
        if let player = gameState?.player {
            gameUI?.updatePlayerStats(player: player)
            gameUI?.updateCompanionStats(companion: player.companions.first)
        }
    }
    
    /// Re-snap all tile positions to pixel boundaries to prevent seams when scene size changes
    func reSnapTilePositions() {
        // Re-snap all world tiles
        for tileSprite in worldTiles {
            let currentPos = tileSprite.position
            let snappedX = round(currentPos.x)
            let snappedY = round(currentPos.y)
            tileSprite.position = CGPoint(x: snappedX, y: snappedY)
        }
        
        // Re-snap object sprites
        for (sprite, _) in objectSprites {
            let currentPos = sprite.position
            let snappedX = round(currentPos.x)
            let snappedY = round(currentPos.y)
            sprite.position = CGPoint(x: snappedX, y: snappedY)
        }
    }
}

// Shared UI functions available on all platforms
extension GameScene {
    func closeAllUIPanels() {
        guard let camera = cameraNode else { return }
        
        // Close chest UI if open
        chestUI?.hide()
        lastOpenedChestNode = nil  // Reset so player can open chests again
        
        // Use recursive search with // prefix to find panels anywhere in the tree
        let panelNames = [
            "inventoryPanel",
            "buildPanel",
            "settingsPanel",
            "saveSlotPanel",
            "loadSlotPanel",
            "inventoryContextMenu",
            "itemInspectPanel",
            "chestPanel"
        ]
        
        for panelName in panelNames {
            // Use // prefix for recursive search
            if let panel = camera.childNode(withName: "//\(panelName)") {
                panel.removeFromParent()
            }
            // Also try direct child search as fallback
            if let panel = camera.childNode(withName: panelName) {
                panel.removeFromParent()
            }
        }
    }
    
    func showBuildMenu() {
        guard let player = gameState?.player else { return }
        buildUI?.toggle(player: player)
    }
    
    func showSettings() {
        // Close CharacterUI if open
        characterUI?.hide()
        
        // Close other UIs
        closeAllUIPanels()
        
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
}

