//
//  GameUI.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

class GameUI {
    weak var scene: SKScene?
    weak var camera: SKCameraNode?
    var companionStatsLabel: SKLabelNode?
    var inventoryButton: SKNode?
    var buildButton: SKNode?
    var settingsButton: SKNode?
    var menuButton: SKNode?
    var characterButton: SKNode?
    
    // Store references to background nodes for repositioning
    var playerStatsBg: SKNode?
    var companionStatsBg: SKShapeNode?
    
    // Store references to stat bar nodes
    var playerStatsContainer: SKNode?
    var nameLabel: SKLabelNode?
    var levelLabel: SKLabelNode?
    var healthBarBg: SKShapeNode?
    var healthBarFill: SKShapeNode?
    var healthLabel: SKLabelNode?
    var resourceBarBg: SKShapeNode?
    var resourceBarFill: SKShapeNode?
    var resourceLabel: SKLabelNode?
    var expBarBg: SKShapeNode?
    var expBarFill: SKShapeNode?
    var barWidth: CGFloat = 0 // Store health bar width for updates
    var resourceBarWidth: CGFloat = 0 // Store resource bar width (mana/rage/energy)
    var barHeight: CGFloat = 18 // Store bar height for updates
    
    init(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
        setupUI()
    }
    
    func setupUI() {
        guard let scene = scene, let camera = camera else { return }
        
        // Get the view's size for accurate UI positioning
        // Camera coordinate system: (0,0) is at center of viewport
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Get camera scale and scene size for debugging
        let cameraScale = camera.xScale
        let sceneSize = scene.size
        print("GameUI: Setting up UI - View Size: \(viewSize), Scene Size: \(sceneSize), Landscape: \(isLandscape), Camera Scale: \(cameraScale)")
        
        // CRITICAL: If scene size doesn't match view size, the camera coordinate system might be wrong
        // In SpriteKit, the camera's coordinate system is based on the view bounds, not scene size
        // But if scene.size doesn't match view.bounds.size, there might be scaling issues
        if abs(sceneSize.width - viewSize.width) > 1 || abs(sceneSize.height - viewSize.height) > 1 {
            print("⚠️ GameUI: WARNING - Scene size (\(sceneSize)) doesn't match view size (\(viewSize))!")
            print("   This might cause UI positioning issues. Consider updating scene.size to match view.bounds.size")
        }
        
        // Use actual view size - this ensures fullscreen/zoom works correctly
        // View bounds don't change when camera zooms, so UI should always use view bounds
        var screenWidth = viewSize.width
        var screenHeight = viewSize.height
        
        // Fallback to scene size if view size is invalid
        if screenWidth <= 0 || screenHeight <= 0 {
            print("GameUI: Invalid view size, using scene size")
            screenWidth = scene.size.width
            screenHeight = scene.size.height
        }
        
        // Ensure minimum valid dimensions
        if screenWidth <= 0 { screenWidth = 1024 }
        if screenHeight <= 0 { screenHeight = 768 }
        
        // Calculate UI dimensions based on orientation
        // Portrait: Make stats bars narrower so they don't cover buttons
        // Landscape: Increase top margin to prevent cut-off
        let buttonWidth: CGFloat = isLandscape ? 50 : 60
        let buttonHeight: CGFloat = isLandscape ? 50 : 60
        let buttonSpacing: CGFloat = 5
        let topMargin: CGFloat = isLandscape ? 40 : 55 // Increased for landscape to prevent cut-off
        let sideMargin: CGFloat = isLandscape ? 15 : 15
        
        // Calculate bottom margin to ensure all buttons are visible
        // Total height needed: 3 buttons + 2 spacings + margin
        let totalButtonHeight = (buttonHeight * 3) + (buttonSpacing * 2)
        let bottomMargin: CGFloat = max(40, totalButtonHeight / 2 + 20) // Ensure enough space for all buttons plus padding
        
        // Calculate max stats width to avoid overlapping buttons
        let rightButtonArea = buttonWidth + sideMargin + 20 // Button width + margin + padding
        let maxStatsWidth = screenWidth - rightButtonArea * 2 // Leave space for buttons on both sides
        
        let statsWidth: CGFloat = isLandscape ? min(450, viewSize.width * 0.45) : min(maxStatsWidth, viewSize.width * 0.65)
        let statsHeight: CGFloat = isLandscape ? 28 : 32
        let companionHeight: CGFloat = isLandscape ? 24 : 26
        
        // Add UI nodes directly to camera - they should stay fixed on screen
        // Camera's coordinate system: (0,0) is center of viewport
        // Top-left: (-width/2, height/2)
        // Top-right: (width/2, height/2)
        
        // Player stats container (top-left area)
        // Use a fixed aspect ratio based on the health_container image structure
        // The image has an upper narrow panel and a lower wider panel
        // Increased height to accommodate name/level, health bar, and resource bar with proper spacing
        let statsContainerHeight: CGFloat = isLandscape ? 140 : 150
        
        // Calculate the actual width we'll use for the container
        // This will be determined by the image aspect ratio
        let imageAspectRatio: CGFloat = 2.5 // Approximate aspect ratio for health_container (adjust if needed)
        let containerWidth = statsContainerHeight * imageAspectRatio
        
        // CRITICAL FIX: Use camera's current position to convert view coordinates to scene coordinates
        // When UI is attached to camera, we need to account for camera's world position
        // Camera coordinate system: (0,0) is at center of viewport in camera space
        // But we need to position relative to camera's current world position
        let cameraWorldX = camera.position.x
        let cameraWorldY = camera.position.y
        
        // Calculate position in camera's coordinate space (view-relative)
        let leftEdge = -screenWidth / 2
        let topEdge = screenHeight / 2
        // Moved right 10px and up 3px as requested
        let containerX = leftEdge + containerWidth / 2 + sideMargin + 38 // Added 10px to move right
        let containerY = topEdge - statsContainerHeight / 2 - (topMargin - 35) // Added 3px to move up
        
        // For camera-attached nodes, positions are relative to camera's coordinate system
        // Camera coordinate system is always centered at (0,0) with view bounds
        // So we use the view-relative coordinates directly
        let statsContainer = SKNode()
        statsContainer.position = CGPoint(x: containerX, y: containerY)
        statsContainer.zPosition = 1000 // Lower than UI menus (2000+) but visible above game content
        // Note: Children zPositions are relative to parent, so keep them low to ensure menus (2000+) appear on top
        statsContainer.name = "playerStatsContainer"
        
        // CRITICAL: Ensure UI is not affected by camera scale/zoom
        // UI attached to camera should always use view bounds coordinates (unscaled)
        // Set scale to 1.0 to ensure UI doesn't scale with camera zoom
        statsContainer.xScale = 1.0
        statsContainer.yScale = 1.0
        statsContainer.isHidden = false
        statsContainer.alpha = 1.0
        
        // Debug: Log the position we're setting
        print("GameUI: statsContainer position: \(statsContainer.position), screenWidth: \(screenWidth), screenHeight: \(screenHeight), cameraScale: \(cameraScale)")
        print("GameUI: leftEdge: \(leftEdge), topEdge: \(topEdge), containerX: \(containerX), containerY: \(containerY)")
        
        // Ensure the container is within visible bounds
        // Camera coordinate system: visible area is from (-screenWidth/2, -screenHeight/2) to (screenWidth/2, screenHeight/2)
        let minX = -screenWidth / 2
        let maxX = screenWidth / 2
        let minY = -screenHeight / 2
        let maxY = screenHeight / 2
        print("GameUI: Visible bounds - X: [\(minX), \(maxX)], Y: [\(minY), \(maxY)]")
        print("GameUI: Container is within bounds: X=\(containerX >= minX && containerX <= maxX), Y=\(containerY >= minY && containerY <= maxY)")
        
        // CRITICAL FIX: In SpriteKit, when UI is attached to camera, the coordinate system
        // is based on the view bounds, which should update automatically. However, there
        // might be a timing issue where the camera's coordinate system hasn't updated yet.
        // 
        // The camera's coordinate space is always centered at (0,0) with bounds from
        // (-viewWidth/2, -viewHeight/2) to (viewWidth/2, viewHeight/2)
        // 
        // We're using view.bounds.size which should be correct, but let's ensure the
        // camera is aware of the current view size by checking scene.camera setup
        
        // Add to camera - UI will be in camera's coordinate space
        camera.addChild(statsContainer)
        playerStatsContainer = statsContainer
        
        // Force update to ensure visibility
        statsContainer.isHidden = false
        statsContainer.alpha = 1.0
        
        // Verify the node was added and is visible
        print("GameUI: statsContainer added to camera, parent: \(statsContainer.parent?.name ?? "nil"), isHidden: \(statsContainer.isHidden), alpha: \(statsContainer.alpha)")
        print("GameUI: Camera children count: \(camera.children.count)")
        
        // Background image (health_container with ornate gothic frame)
        let backgroundImage = SKSpriteNode(imageNamed: "health_container")
        if backgroundImage.size.width > 0 && backgroundImage.size.height > 0 {
            // Calculate scale to fit the desired height while maintaining aspect ratio
            let imageAspectRatio = backgroundImage.size.width / backgroundImage.size.height
            let targetHeight = statsContainerHeight
            
            // Scale to fit the target height
            let scale = targetHeight / backgroundImage.size.height
            
            backgroundImage.setScale(scale)
            backgroundImage.alpha = 1.0
            backgroundImage.zPosition = 0
            backgroundImage.name = "playerStatsBg"
            statsContainer.addChild(backgroundImage)
            playerStatsBg = backgroundImage
            
            // Update actual container size based on scaled image
            let actualWidth = backgroundImage.size.width * scale
            let actualHeight = backgroundImage.size.height * scale
            
            // Update barWidth to match the actual container width
            // Health bar should be longer on the right, mana bar should match the base width
            // Both bars are now much longer
            let baseBarWidth = actualWidth * 2.5 // Base width for mana/rage/energy bar (much longer)
            let healthBarWidth = actualWidth * 2.5 // Health bar is even longer and extends more to the right
            self.barWidth = healthBarWidth // Store health bar width for updates
            self.resourceBarWidth = baseBarWidth // Store resource bar width for updates
            
            // Position elements within the frame's recessed panels
            // Upper panel (narrower) - for name and level
            // Lower panel (larger) - for health and resource bars
            // Position elements with proper spacing on separate rows
            // The image has two panels: upper (narrow) and lower (wide)
            
            // Row 1: Name and Level (in upper panel) - positioned in upper panel
            // Upper panel is roughly in the top 30% of the image
            // Position near the top of the container, accounting for increased height
            // Moved up more as requested
            let row1Y = actualHeight * 0.35 + 23 // Position in upper panel (35% from center, near top), moved up 25px
            nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            nameLabel?.fontSize = isLandscape ? 15 : 17
            nameLabel?.fontColor = .white
            nameLabel?.horizontalAlignmentMode = .left
            nameLabel?.verticalAlignmentMode = .baseline // Use baseline for consistent vertical alignment
            nameLabel?.position = CGPoint(x: -actualWidth * 0.35, y: row1Y)
            nameLabel?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(nameLabel!)
            
            levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            levelLabel?.fontSize = isLandscape ? 15 : 17
            levelLabel?.fontColor = .white
            levelLabel?.horizontalAlignmentMode = .right
            levelLabel?.verticalAlignmentMode = .baseline // Use baseline for consistent vertical alignment
            levelLabel?.position = CGPoint(x: actualWidth * 0.35, y: row1Y)
            levelLabel?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(levelLabel!)
            
            // Row 2: Health Bar (in lower panel) - separate row with significant spacing
            // Position in the middle section of the container, with spacing from name/level
            // Moved up 5px as requested
            let row2Y = -actualHeight * 0.05 + 7 // Position slightly below center, with spacing from name/level, moved up 5px
            self.barHeight = isLandscape ? 16 : 18
            
            // Health bar background - wider and extends more to the right
            healthBarBg = SKShapeNode(rectOf: CGSize(width: healthBarWidth, height: barHeight), cornerRadius: 3)
            healthBarBg?.fillColor = SKColor(white: 0.2, alpha: 0.9)
            healthBarBg?.strokeColor = SKColor(white: 0.4, alpha: 0.8)
            healthBarBg?.lineWidth = 1.5
            // Position health bar to extend more to the right (shift center to the left)
            healthBarBg?.position = CGPoint(x: -(healthBarWidth - baseBarWidth) / 2, y: row2Y)
            healthBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthBarBg!)
            
            // Health bar fill (green) - positioned to align left with background
            healthBarFill = SKShapeNode(rectOf: CGSize(width: healthBarWidth, height: barHeight), cornerRadius: 3)
            healthBarFill?.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
            healthBarFill?.strokeColor = .clear
            // Position fill to align with background's left edge
            // Background center is at: -(healthBarWidth - baseBarWidth) / 2
            // Fill center should be at: background center - healthBarWidth / 2 (to align left edge)
            let healthBarCenterX = -(healthBarWidth - baseBarWidth) / 2
            healthBarFill?.position = CGPoint(x: healthBarCenterX, y: row2Y)
            healthBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthBarFill!)
            
            // Health label - centered on the health bar
            healthLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            healthLabel?.fontSize = isLandscape ? 11 : 13
            healthLabel?.fontColor = .white
            healthLabel?.horizontalAlignmentMode = .center
            healthLabel?.verticalAlignmentMode = .center
            healthLabel?.position = CGPoint(x: -(healthBarWidth - baseBarWidth) / 2, y: row2Y)
            healthLabel?.zPosition = 3 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthLabel!)
            
            // Row 3: Resource Bar (Mana/Rage/Energy) (in lower panel, lower section) - separate row with spacing
            // Position right under the health bar with minimal spacing
            // Calculate spacing based on bar height plus a small gap
            let barSpacing: CGFloat = 5 // Small gap between health and resource bars
            let row3Y = row2Y - barHeight - barSpacing // Position directly under health bar
            
            // Resource bar background - same size as base width (matching original health bar size)
            resourceBarBg = SKShapeNode(rectOf: CGSize(width: baseBarWidth, height: barHeight), cornerRadius: 3)
            resourceBarBg?.fillColor = SKColor(white: 0.2, alpha: 0.9)
            resourceBarBg?.strokeColor = SKColor(white: 0.4, alpha: 0.8)
            resourceBarBg?.lineWidth = 1.5
            resourceBarBg?.position = CGPoint(x: 0, y: row3Y)
            resourceBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceBarBg!)
            
            // Resource bar fill (color depends on resource type) - positioned to align left
            resourceBarFill = SKShapeNode(rectOf: CGSize(width: baseBarWidth, height: barHeight), cornerRadius: 3)
            resourceBarFill?.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // Default blue for mana
            resourceBarFill?.strokeColor = .clear
            resourceBarFill?.position = CGPoint(x: -baseBarWidth / 2, y: row3Y)
            resourceBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceBarFill!)
            
            // Resource label
            resourceLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            resourceLabel?.fontSize = isLandscape ? 11 : 13
            resourceLabel?.fontColor = .white
            resourceLabel?.horizontalAlignmentMode = .center
            resourceLabel?.verticalAlignmentMode = .center
            resourceLabel?.position = CGPoint(x: 0, y: row3Y)
            resourceLabel?.zPosition = 3 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceLabel!)
            
            // Row 4: Experience Bar (tiny white bar below resource bar)
            let expBarSpacing: CGFloat = 3 // Small gap between resource bar and exp bar
            let row4Y = row3Y - barHeight - expBarSpacing // Position directly under resource bar
            let expBarHeight: CGFloat = 4 // Tiny bar height
            let expBarWidth = baseBarWidth // Same width as resource bar
            
            // Experience bar background (very subtle)
            expBarBg = SKShapeNode(rectOf: CGSize(width: expBarWidth, height: expBarHeight), cornerRadius: 2)
            expBarBg?.fillColor = SKColor(white: 0.1, alpha: 0.8)
            expBarBg?.strokeColor = SKColor(white: 0.3, alpha: 0.6)
            expBarBg?.lineWidth = 0.5
            expBarBg?.position = CGPoint(x: 0, y: row4Y)
            expBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(expBarBg!)
            
            // Experience bar fill (white)
            expBarFill = SKShapeNode(rectOf: CGSize(width: expBarWidth, height: expBarHeight), cornerRadius: 2)
            expBarFill?.fillColor = SKColor(white: 0.9, alpha: 1.0) // White fill
            expBarFill?.strokeColor = .clear
            expBarFill?.position = CGPoint(x: -expBarWidth / 2, y: row4Y)
            expBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(expBarFill!)
        } else {
            // Fallback to shape node if image not found
            let fallbackBg = SKShapeNode(rectOf: CGSize(width: statsWidth, height: statsContainerHeight), cornerRadius: 5)
            fallbackBg.fillColor = SKColor(white: 0.1, alpha: 0.95)
            fallbackBg.strokeColor = .white
            fallbackBg.lineWidth = 2
            fallbackBg.zPosition = 0
            fallbackBg.name = "playerStatsBg"
            statsContainer.addChild(fallbackBg)
            playerStatsBg = fallbackBg
            
            // Fallback layout (original layout)
            let row1Y: CGFloat = statsContainerHeight / 2 - 15
            nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            nameLabel?.fontSize = isLandscape ? 16 : 18
            nameLabel?.fontColor = MenuStyling.inkColor
            nameLabel?.horizontalAlignmentMode = .left
            nameLabel?.verticalAlignmentMode = .center
            nameLabel?.position = CGPoint(x: -statsWidth / 2 + 10, y: row1Y)
            nameLabel?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(nameLabel!)
            
            levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            levelLabel?.fontSize = isLandscape ? 16 : 18
            levelLabel?.fontColor = MenuStyling.inkColor
            levelLabel?.horizontalAlignmentMode = .right
            levelLabel?.verticalAlignmentMode = .center
            levelLabel?.position = CGPoint(x: statsWidth / 2 - 10, y: row1Y)
            levelLabel?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(levelLabel!)
            
            let row2Y: CGFloat = row1Y - 25
            self.barHeight = isLandscape ? 18 : 20
            self.barWidth = statsWidth - 20
            
            healthBarBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
            healthBarBg?.fillColor = SKColor(white: 0.3, alpha: 0.8)
            healthBarBg?.strokeColor = MenuStyling.inkColor
            healthBarBg?.lineWidth = 1.5
            healthBarBg?.position = CGPoint(x: 0, y: row2Y)
            healthBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthBarBg!)
            
            healthBarFill = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
            healthBarFill?.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
            healthBarFill?.strokeColor = .clear
            healthBarFill?.position = CGPoint(x: -barWidth / 2, y: row2Y)
            healthBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthBarFill!)
            
            healthLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            healthLabel?.fontSize = isLandscape ? 12 : 14
            healthLabel?.fontColor = .white
            healthLabel?.horizontalAlignmentMode = .center
            healthLabel?.verticalAlignmentMode = .center
            healthLabel?.position = CGPoint(x: 0, y: row2Y)
            healthLabel?.zPosition = 3 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(healthLabel!)
            
            let row3Y: CGFloat = row2Y - 25
            resourceBarBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
            resourceBarBg?.fillColor = SKColor(white: 0.3, alpha: 0.8)
            resourceBarBg?.strokeColor = MenuStyling.inkColor
            resourceBarBg?.lineWidth = 1.5
            resourceBarBg?.position = CGPoint(x: 0, y: row3Y)
            resourceBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceBarBg!)
            
            resourceBarFill = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
            resourceBarFill?.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
            resourceBarFill?.strokeColor = .clear
            resourceBarFill?.position = CGPoint(x: -barWidth / 2, y: row3Y)
            resourceBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceBarFill!)
            
            resourceLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            resourceLabel?.fontSize = isLandscape ? 12 : 14
            resourceLabel?.fontColor = .white
            resourceLabel?.horizontalAlignmentMode = .center
            resourceLabel?.verticalAlignmentMode = .center
            resourceLabel?.position = CGPoint(x: 0, y: row3Y)
            resourceLabel?.zPosition = 3 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(resourceLabel!)
            
            // Row 4: Experience Bar (tiny white bar below resource bar) - fallback section
            let expBarSpacing: CGFloat = 3 // Small gap between resource bar and exp bar
            let row4Y = row3Y - barHeight - expBarSpacing // Position directly under resource bar
            let expBarHeight: CGFloat = 4 // Tiny bar height
            let expBarWidth = barWidth // Same width as resource bar
            
            // Experience bar background (very subtle)
            expBarBg = SKShapeNode(rectOf: CGSize(width: expBarWidth, height: expBarHeight), cornerRadius: 2)
            expBarBg?.fillColor = SKColor(white: 0.1, alpha: 0.8)
            expBarBg?.strokeColor = SKColor(white: 0.3, alpha: 0.6)
            expBarBg?.lineWidth = 0.5
            expBarBg?.position = CGPoint(x: 0, y: row4Y)
            expBarBg?.zPosition = 1 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(expBarBg!)
            
            // Experience bar fill (white)
            expBarFill = SKShapeNode(rectOf: CGSize(width: expBarWidth, height: expBarHeight), cornerRadius: 2)
            expBarFill?.fillColor = SKColor(white: 0.9, alpha: 1.0) // White fill
            expBarFill?.strokeColor = .clear
            expBarFill?.position = CGPoint(x: -expBarWidth / 2, y: row4Y)
            expBarFill?.zPosition = 2 // Low zPosition relative to parent to ensure menus appear on top
            statsContainer.addChild(expBarFill!)
        }
        
        // Companion stats background (below player stats)
        // Position from top-left corner
        let companionY = topEdge - statsContainerHeight - companionHeight / 2 - topMargin - 5
        companionStatsBg = SKShapeNode(rectOf: CGSize(width: statsWidth, height: companionHeight), cornerRadius: 5)
        companionStatsBg?.fillColor = SKColor(red: 0.2, green: 0.1, blue: 0.0, alpha: 0.95)
        companionStatsBg?.strokeColor = .yellow
        companionStatsBg?.lineWidth = 2
        companionStatsBg?.position = CGPoint(x: leftEdge + statsWidth / 2 + sideMargin, y: companionY)
        companionStatsBg?.zPosition = 1000
        companionStatsBg?.name = "companionStatsBg"
        companionStatsBg?.isHidden = true // Hide by default, show only when companion exists
        camera.addChild(companionStatsBg!)
        
        // Companion stats display
        companionStatsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        companionStatsLabel?.fontSize = isLandscape ? 12 : 14
        companionStatsLabel?.fontColor = .yellow
        companionStatsLabel?.position = CGPoint(x: -statsWidth / 2 + 10, y: 0) // Offset left within the background
        companionStatsLabel?.horizontalAlignmentMode = .left
        companionStatsLabel?.verticalAlignmentMode = .center
        companionStatsLabel?.zPosition = 1001
        companionStatsLabel?.isHidden = true // Hide by default
        companionStatsBg?.addChild(companionStatsLabel!)
        
        // Settings button (top-right area) with icon - stays at top right
        // Position from top-right corner
        // Use the same edge variables declared earlier
        let rightEdge = screenWidth / 2
        // topEdge already declared above, reuse it
        let settingsBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        settingsBg.fillColor = SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.95)
        settingsBg.strokeColor = .white
        settingsBg.lineWidth = 2
        // Moved further toward the top by reducing topMargin offset
        settingsBg.position = CGPoint(x: rightEdge - buttonWidth / 2 - sideMargin, y: topEdge - buttonHeight / 2 - topMargin + 20)
        settingsBg.zPosition = 1000
        settingsBg.name = "settingsButton"
        // Ensure button is not affected by camera scale
        settingsBg.xScale = 1.0
        settingsBg.yScale = 1.0
        settingsBg.isHidden = false
        settingsBg.alpha = 1.0
        
        // Create gear/settings icon
        let settingsIcon = createSettingsIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        settingsIcon.position = CGPoint(x: 0, y: 0)
        settingsIcon.zPosition = 1001
        settingsBg.addChild(settingsIcon)
        
        camera.addChild(settingsBg)
        settingsButton = settingsBg
        
        // Bottom-right button group: Character (first), Inventory (second), Build (third)
        // Calculate positions from bottom up to ensure they're always visible
        // Bottom edge of screen in camera coordinates: -screenHeight / 2
        // We'll position buttons starting from the bottom with proper margin
        
        let bottomEdge = -screenHeight / 2
        let buttonPadding: CGFloat = 20 // Padding from screen edge
        
        // Build button (bottom-right, third button - bottommost) with icon
        let buildBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        buildBg.fillColor = SKColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 0.95)
        buildBg.strokeColor = .white
        buildBg.lineWidth = 2
        // Position: right edge - half width - margin, bottom edge + padding + half button height
        buildBg.position = CGPoint(x: rightEdge - buttonWidth / 2 - sideMargin, y: bottomEdge + buttonPadding + buttonHeight / 2)
        buildBg.zPosition = 1000
        buildBg.name = "buildButton"
        // Ensure button is not affected by camera scale
        buildBg.xScale = 1.0
        buildBg.yScale = 1.0
        buildBg.isHidden = false
        buildBg.alpha = 1.0
        
        // Create hammer/wrench icon for build
        let buildIcon = createBuildIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        buildIcon.position = CGPoint(x: 0, y: 0)
        buildIcon.zPosition = 1001
        buildBg.addChild(buildIcon)
        
        camera.addChild(buildBg)
        buildButton = buildBg
        
        // Inventory button (bottom-right, second button - middle) with icon
        let inventoryBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        inventoryBg.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.95)
        inventoryBg.strokeColor = .white
        inventoryBg.lineWidth = 2
        // Position: right edge - half width - margin, above build button
        inventoryBg.position = CGPoint(x: rightEdge - buttonWidth / 2 - sideMargin, y: bottomEdge + buttonPadding + buttonHeight / 2 + buttonHeight + buttonSpacing)
        inventoryBg.zPosition = 1000
        inventoryBg.name = "inventoryButton"
        // Ensure button is not affected by camera scale
        inventoryBg.xScale = 1.0
        inventoryBg.yScale = 1.0
        inventoryBg.isHidden = false
        inventoryBg.alpha = 1.0
        
        // Create backpack/bag icon for inventory
        let inventoryIcon = createInventoryIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        inventoryIcon.position = CGPoint(x: 0, y: 0)
        inventoryIcon.zPosition = 1001
        inventoryBg.addChild(inventoryIcon)
        
        camera.addChild(inventoryBg)
        inventoryButton = inventoryBg
        
        // Character button (bottom-right, first button - topmost) with icon
        let characterBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        characterBg.fillColor = SKColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 0.95)
        characterBg.strokeColor = .white
        characterBg.lineWidth = 2
        // Position: right edge - half width - margin, above inventory button
        characterBg.position = CGPoint(x: rightEdge - buttonWidth / 2 - sideMargin, y: bottomEdge + buttonPadding + buttonHeight / 2 + (buttonHeight + buttonSpacing) * 2)
        characterBg.zPosition = 1000
        characterBg.name = "characterButton"
        // Ensure button is not affected by camera scale
        characterBg.xScale = 1.0
        characterBg.yScale = 1.0
        characterBg.isHidden = false
        characterBg.alpha = 1.0
        
        // Create character/person icon
        let characterIcon = createCharacterIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        characterIcon.position = CGPoint(x: 0, y: 0)
        characterIcon.zPosition = 1001
        characterBg.addChild(characterIcon)
        
        camera.addChild(characterBg)
        characterButton = characterBg
    }
    
    func getViewSize() -> CGSize {
        guard let scene = scene else { return CGSize(width: 375, height: 667) }
        // Always prefer the view's bounds size as it reflects the actual visible area
        // This is critical for fullscreen mode and camera zoom
        // View bounds stay constant regardless of camera scale/zoom
        if let view = scene.view {
            // Use bounds.size which gives the actual viewport size in points
            // This is NOT affected by camera zoom/scale
            let viewSize = view.bounds.size
            print("GameUI: getViewSize - view.bounds.size: \(viewSize)")
            
            // Ensure we have valid dimensions
            if viewSize.width > 0 && viewSize.height > 0 {
                return viewSize
            } else {
                print("GameUI: Warning - view.bounds.size is invalid: \(viewSize)")
            }
        } else {
            print("GameUI: Warning - scene.view is nil")
        }
        
        // Fallback to scene size if view is not available
        let sceneSize = scene.size
        print("GameUI: getViewSize - falling back to scene.size: \(sceneSize)")
        if sceneSize.width > 0 && sceneSize.height > 0 {
            return sceneSize
        }
        
        // Final fallback
        print("GameUI: getViewSize - using final fallback size")
        return CGSize(width: 375, height: 667)
    }
    
    // Create a simple backpack/bag icon for inventory
    func createInventoryIcon(size: CGFloat) -> SKNode {
        let container = SKNode()
        
        // Main bag body (rounded rectangle)
        let bagBody = SKShapeNode(rectOf: CGSize(width: size * 0.7, height: size * 0.8), cornerRadius: size * 0.1)
        bagBody.fillColor = .white
        bagBody.strokeColor = .clear
        bagBody.position = CGPoint(x: 0, y: -size * 0.05)
        container.addChild(bagBody)
        
        // Bag flap/cover (top part)
        let bagFlap = SKShapeNode(rectOf: CGSize(width: size * 0.7, height: size * 0.25), cornerRadius: size * 0.1)
        bagFlap.fillColor = SKColor(white: 0.9, alpha: 1.0)
        bagFlap.strokeColor = .clear
        bagFlap.position = CGPoint(x: 0, y: size * 0.3)
        container.addChild(bagFlap)
        
        // Strap/handle (top)
        let strap = SKShapeNode(rectOf: CGSize(width: size * 0.15, height: size * 0.2), cornerRadius: size * 0.05)
        strap.fillColor = .white
        strap.strokeColor = .clear
        strap.position = CGPoint(x: 0, y: size * 0.5)
        container.addChild(strap)
        
        return container
    }
    
    // Create a simple hammer/wrench icon for build
    func createBuildIcon(size: CGFloat) -> SKNode {
        let container = SKNode()
        
        // Hammer handle (vertical line)
        let handle = SKShapeNode(rectOf: CGSize(width: size * 0.15, height: size * 0.6))
        handle.fillColor = SKColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0) // Brown wood color
        handle.strokeColor = .clear
        handle.position = CGPoint(x: -size * 0.15, y: -size * 0.1)
        container.addChild(handle)
        
        // Hammer head (horizontal rectangle)
        let head = SKShapeNode(rectOf: CGSize(width: size * 0.5, height: size * 0.3), cornerRadius: size * 0.05)
        head.fillColor = SKColor(white: 0.7, alpha: 1.0) // Gray metal
        head.strokeColor = .clear
        head.position = CGPoint(x: size * 0.1, y: size * 0.2)
        container.addChild(head)
        
        // Claw part (small triangle/rectangle on the back)
        let claw = SKShapeNode(rectOf: CGSize(width: size * 0.2, height: size * 0.15))
        claw.fillColor = SKColor(white: 0.7, alpha: 1.0)
        claw.strokeColor = .clear
        claw.position = CGPoint(x: size * 0.35, y: size * 0.2)
        container.addChild(claw)
        
        return container
    }
    
    // Create a simple character/person icon
    func createCharacterIcon(size: CGFloat) -> SKNode {
        let container = SKNode()
        
        // Head (circle)
        let head = SKShapeNode(circleOfRadius: size * 0.2)
        head.fillColor = .white
        head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: size * 0.15)
        container.addChild(head)
        
        // Body (rounded rectangle)
        let body = SKShapeNode(rectOf: CGSize(width: size * 0.4, height: size * 0.5), cornerRadius: size * 0.05)
        body.fillColor = .white
        body.strokeColor = .clear
        body.position = CGPoint(x: 0, y: -size * 0.1)
        container.addChild(body)
        
        return container
    }
    
    // Create a simple gear/settings icon
    func createSettingsIcon(size: CGFloat) -> SKNode {
        let container = SKNode()
        
        // Create a gear shape using multiple rectangles rotated around a center
        let gearRadius = size * 0.4
        let toothWidth = size * 0.15
        let toothHeight = size * 0.2
        let numTeeth = 8
        
        // Outer gear teeth
        for i in 0..<numTeeth {
            let angle = CGFloat(i) * (2 * .pi / CGFloat(numTeeth))
            let tooth = SKShapeNode(rectOf: CGSize(width: toothWidth, height: toothHeight))
            tooth.fillColor = .white
            tooth.strokeColor = .clear
            let x = cos(angle) * gearRadius
            let y = sin(angle) * gearRadius
            tooth.position = CGPoint(x: x, y: y)
            tooth.zRotation = angle
            container.addChild(tooth)
        }
        
        // Center circle
        let center = SKShapeNode(circleOfRadius: size * 0.25)
        center.fillColor = .white
        center.strokeColor = .clear
        center.position = CGPoint(x: 0, y: 0)
        container.addChild(center)
        
        // Inner circle (hole)
        let hole = SKShapeNode(circleOfRadius: size * 0.12)
        hole.fillColor = SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        hole.strokeColor = .clear
        hole.position = CGPoint(x: 0, y: 0)
        container.addChild(hole)
        
        return container
    }
    
    func cleanup() {
        // Remove all UI elements from their parents
        playerStatsContainer?.removeFromParent()
        companionStatsBg?.removeFromParent()
        inventoryButton?.removeFromParent()
        buildButton?.removeFromParent()
        settingsButton?.removeFromParent()
        characterButton?.removeFromParent()
        
        // Clear all references
        playerStatsContainer = nil
        playerStatsBg = nil
        companionStatsBg = nil
        companionStatsLabel = nil
        nameLabel = nil
        levelLabel = nil
        healthBarBg = nil
        healthBarFill = nil
        healthLabel = nil
        resourceBarBg = nil
        resourceBarFill = nil
        resourceLabel = nil
        expBarBg = nil
        expBarFill = nil
        inventoryButton = nil
        buildButton = nil
        settingsButton = nil
        characterButton = nil
    }
    
    func updateLayout() {
        print("GameUI: updateLayout called")
        
        // Save current state
        let savedNameText = nameLabel?.text
        let savedLevelText = levelLabel?.text
        let savedHealthText = healthLabel?.text
        let savedResourceText = resourceLabel?.text
        let savedCompanionText = companionStatsLabel?.text
        let wasCompanionHidden = companionStatsLabel?.isHidden ?? true
        
        // Clean up old UI
        cleanup()
        
        // Recreate UI with new layout
        setupUI()
        
        // Restore label text and visibility
        nameLabel?.text = savedNameText
        levelLabel?.text = savedLevelText
        healthLabel?.text = savedHealthText
        resourceLabel?.text = savedResourceText
        companionStatsLabel?.text = savedCompanionText
        companionStatsLabel?.isHidden = wasCompanionHidden
    }
    
    func updatePlayerStats(player: Player) {
        // Update name and level
        nameLabel?.text = player.name
        levelLabel?.text = "Level \(player.level)"
        
        // Update health bar
        let healthPercent = player.maxHitPoints > 0 ? CGFloat(player.hitPoints) / CGFloat(player.maxHitPoints) : 0.0
        let fillWidth = barWidth * max(0, min(1, healthPercent))
        
        // Update health bar fill size and position
        // Health bar is wider and extends to the right
        // The fill is positioned at the health bar center, so we use -barWidth/2 for the left edge
        if let fill = healthBarFill {
            fill.path = CGPath(roundedRect: CGRect(x: -barWidth / 2, y: -barHeight / 2, width: fillWidth, height: barHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
        }
        healthLabel?.text = "HP: \(player.hitPoints)/\(player.maxHitPoints)"
        
        // Update resource bar based on class
        let resourceType = player.characterClass.resourceType
        var currentResource: Int = 0
        var maxResource: Int = 0
        var resourceName: String = ""
        var resourceColor: SKColor = SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // Default blue
        
        switch resourceType {
        case .mana:
            currentResource = player.mana
            maxResource = player.maxMana
            resourceName = "Mana"
            resourceColor = SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // Blue
        case .rage:
            currentResource = player.rage
            maxResource = player.maxRage
            resourceName = "Rage"
            resourceColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0) // Red
        case .energy:
            currentResource = player.energy
            maxResource = player.maxEnergy
            resourceName = "Energy"
            resourceColor = SKColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1.0) // Yellow
        }
        
        let resourcePercent = maxResource > 0 ? CGFloat(currentResource) / CGFloat(maxResource) : 0.0
        let resourceFillWidth = resourceBarWidth * max(0, min(1, resourcePercent))
        
        // Update resource bar fill size and position
        if let fill = resourceBarFill {
            fill.path = CGPath(roundedRect: CGRect(x: -resourceBarWidth / 2, y: -barHeight / 2, width: resourceFillWidth, height: barHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
            fill.fillColor = resourceColor
        }
        resourceLabel?.text = "\(resourceName): \(currentResource)/\(maxResource)"
        
        // Update experience bar
        // Calculate experience percentage for current level
        func experienceForLevel(_ level: Int) -> Int {
            // D&D 5e experience table (same as Player model)
            switch level {
            case 1: return 0
            case 2: return 300
            case 3: return 900
            case 4: return 2700
            case 5: return 6500
            case 6: return 14000
            case 7: return 23000
            case 8: return 34000
            case 9: return 48000
            case 10: return 64000
            default: return 64000 + (level - 10) * 20000
            }
        }
        
        let currentLevelExp = experienceForLevel(player.level)
        let nextLevelExp = experienceForLevel(player.level + 1)
        let expNeededForNextLevel = nextLevelExp - currentLevelExp
        let currentExpInLevel = player.experiencePoints - currentLevelExp
        let expPercent = expNeededForNextLevel > 0 ? CGFloat(currentExpInLevel) / CGFloat(expNeededForNextLevel) : 0.0
        let expFillWidth = resourceBarWidth * max(0, min(1, expPercent))
        
        // Update experience bar fill
        if let expFill = expBarFill {
            expFill.path = CGPath(roundedRect: CGRect(x: -resourceBarWidth / 2, y: -2, width: expFillWidth, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
        }
    }
    
    func updateCompanionStats(companion: Animal?) {
        if let companion = companion {
            companionStatsLabel?.text = "\(companion.name) Lv.\(companion.level) | HP: \(companion.hitPoints)/\(companion.maxHitPoints) | Friendship: \(companion.friendshipLevel)"
            companionStatsBg?.isHidden = false
            companionStatsLabel?.isHidden = false
        } else {
            companionStatsBg?.isHidden = true
            companionStatsLabel?.isHidden = true
        }
    }
}

