//
//  GameScene_PlayerMovement.swift
//  FableForge Shared
//
//  Player movement and animation functionality for GameScene
//

import SpriteKit

extension GameScene {
    
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
                    texture.filteringMode = SKTextureFilteringMode.nearest
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
                    texture.filteringMode = SKTextureFilteringMode.nearest
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
            firstFrameTexture.filteringMode = SKTextureFilteringMode.nearest
            
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
        
        // Check if direction or moving state changed (for tracking purposes)
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
                
                // Animation direction changed (debug log removed for performance)
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
            // Update texture every frame when moving to show alternating animation
            if isMoving {
                // Use the direction we just calculated (the current direction)
                let textureDirection = direction
                // Get idle and walk textures for current direction
                guard let idleTexture = idleFrameTextures[textureDirection],
                      let walkFrames = walkFrameTextures[textureDirection],
                      walkFrames.count > 0 else {
                    print("⚠️ Missing textures for direction: \(textureDirection), available: \(idleFrameTextures.keys.joined(separator: ", "))")
                    return
                }
                
                // Use the current animation frame to select which walk frame to show
                // For walk animation, alternate between frames based on currentAnimationFrame
                // Use modulo to cycle through available walk frames
                let walkFrameIndex = currentAnimationFrame % walkFrames.count
                let walkTexture = walkFrames[walkFrameIndex]
                
                // Alternate between idle (even frames) and walk (odd frames) for smooth animation
                // This creates the walking effect by alternating between idle and walk frames
                let isWalkFrame = (currentAnimationFrame % 2) == 1
                let textureToUse = isWalkFrame ? walkTexture : idleTexture
                
                // CRITICAL: Always update texture every frame when moving to show animation
                // Don't check animationChanged - we need to update every frame to see the alternation
                textureToUse.filteringMode = SKTextureFilteringMode.nearest
                sprite.texture = textureToUse
                sprite.size = playerSpriteSize
            } else {
                // When idle, use the idle frame
                let idleDirection = lastFacingDirection.isEmpty ? "south" : lastFacingDirection
                if let idleTexture = idleFrameTextures[idleDirection] {
                    // Always update texture directly
                    idleTexture.filteringMode = SKTextureFilteringMode.nearest
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
    
    
    /// Create an Animal instance from an AnimalPrefab
    func movePlayer(direction: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        let newPosition = CGPoint(
            x: player.position.x + direction.x * movementSpeed,
            y: player.position.y + direction.y * movementSpeed
        )
        
        // Track if player has moved away from trigger tile (for TMX maps)
        if useTiledMap, let triggerPos = triggerTilePosition, !hasMovedAwayFromTrigger {
            let distance = sqrt(pow(newPosition.x - triggerPos.x, 2) + pow(newPosition.y - triggerPos.y, 2))
            // If player moves more than 1.5 tiles away from trigger, mark as moved away
            if distance > 48.0 {  // 1.5 tiles = 48 pixels
                hasMovedAwayFromTrigger = true
                print("✅ Player has moved away from trigger tile (distance: \(Int(distance)))")
            }
        }
        
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
            // Procedural world: check physics body collisions
            canMove = canMoveToProceduralWorld(position: newPosition)
            if !canMove {
                print("🛑 Movement blocked by entity collision at position (\(Int(newPosition.x)), \(Int(newPosition.y)))")
            }
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
}
