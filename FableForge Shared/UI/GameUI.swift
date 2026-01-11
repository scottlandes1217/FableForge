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
    var playerStatsLabel: SKLabelNode?
    var companionStatsLabel: SKLabelNode?
    var inventoryButton: SKNode?
    var buildButton: SKNode?
    var settingsButton: SKNode?
    var menuButton: SKNode?
    
    // Store references to background nodes for repositioning
    var playerStatsBg: SKShapeNode?
    var companionStatsBg: SKShapeNode?
    
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
        
        print("GameUI: Setting up UI - Size: \(viewSize), Landscape: \(isLandscape)")
        
        let screenWidth = viewSize.width
        let screenHeight = viewSize.height
        
        // Calculate UI dimensions based on orientation
        // Portrait: Make stats bars narrower so they don't cover buttons
        // Landscape: Increase top margin to prevent cut-off
        let buttonWidth: CGFloat = isLandscape ? 50 : 60
        let buttonHeight: CGFloat = isLandscape ? 50 : 60
        let buttonSpacing: CGFloat = 5
        let topMargin: CGFloat = isLandscape ? 40 : 55 // Increased for landscape to prevent cut-off
        let sideMargin: CGFloat = isLandscape ? 15 : 15
        
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
        
        // Player stats background (top-left area)
        playerStatsBg = SKShapeNode(rectOf: CGSize(width: statsWidth, height: statsHeight), cornerRadius: 5)
        playerStatsBg?.fillColor = SKColor(white: 0.1, alpha: 0.95)
        playerStatsBg?.strokeColor = .white
        playerStatsBg?.lineWidth = 2
        // Position: left edge + half width, top edge - margin
        playerStatsBg?.position = CGPoint(x: -screenWidth / 2 + statsWidth / 2 + sideMargin, y: screenHeight / 2 - topMargin)
        playerStatsBg?.zPosition = 1000
        playerStatsBg?.name = "playerStatsBg"
        camera.addChild(playerStatsBg!)
        
        // Player stats display
        playerStatsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        playerStatsLabel?.fontSize = isLandscape ? 14 : 16
        playerStatsLabel?.fontColor = .white
        playerStatsLabel?.position = CGPoint(x: -statsWidth / 2 + 10, y: 0) // Offset left within the background
        playerStatsLabel?.horizontalAlignmentMode = .left
        playerStatsLabel?.verticalAlignmentMode = .center
        playerStatsLabel?.zPosition = 1001
        playerStatsBg?.addChild(playerStatsLabel!)
        
        // Companion stats background (below player stats)
        companionStatsBg = SKShapeNode(rectOf: CGSize(width: statsWidth, height: companionHeight), cornerRadius: 5)
        companionStatsBg?.fillColor = SKColor(red: 0.2, green: 0.1, blue: 0.0, alpha: 0.95)
        companionStatsBg?.strokeColor = .yellow
        companionStatsBg?.lineWidth = 2
        companionStatsBg?.position = CGPoint(x: -screenWidth / 2 + statsWidth / 2 + sideMargin, y: screenHeight / 2 - topMargin - statsHeight - 5)
        companionStatsBg?.zPosition = 1000
        companionStatsBg?.name = "companionStatsBg"
        camera.addChild(companionStatsBg!)
        
        // Companion stats display
        companionStatsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        companionStatsLabel?.fontSize = isLandscape ? 12 : 14
        companionStatsLabel?.fontColor = .yellow
        companionStatsLabel?.position = CGPoint(x: -statsWidth / 2 + 10, y: 0) // Offset left within the background
        companionStatsLabel?.horizontalAlignmentMode = .left
        companionStatsLabel?.verticalAlignmentMode = .center
        companionStatsLabel?.zPosition = 1001
        companionStatsBg?.addChild(companionStatsLabel!)
        
        // Inventory button (top-right area) with icon
        let inventoryBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        inventoryBg.fillColor = SKColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.95)
        inventoryBg.strokeColor = .white
        inventoryBg.lineWidth = 2
        // Position: right edge - half width - margin, top edge - margin
        inventoryBg.position = CGPoint(x: screenWidth / 2 - buttonWidth / 2 - sideMargin, y: screenHeight / 2 - topMargin)
        inventoryBg.zPosition = 1000
        inventoryBg.name = "inventoryButton"
        
        // Create backpack/bag icon for inventory
        let inventoryIcon = createInventoryIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        inventoryIcon.position = CGPoint(x: 0, y: 0)
        inventoryIcon.zPosition = 1001
        inventoryBg.addChild(inventoryIcon)
        
        camera.addChild(inventoryBg)
        inventoryButton = inventoryBg
        
        // Build button (below inventory button) with icon
        let buildBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        buildBg.fillColor = SKColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 0.95)
        buildBg.strokeColor = .white
        buildBg.lineWidth = 2
        buildBg.position = CGPoint(x: screenWidth / 2 - buttonWidth / 2 - sideMargin, y: screenHeight / 2 - topMargin - buttonHeight - buttonSpacing)
        buildBg.zPosition = 1000
        buildBg.name = "buildButton"
        
        // Create hammer/wrench icon for build
        let buildIcon = createBuildIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        buildIcon.position = CGPoint(x: 0, y: 0)
        buildIcon.zPosition = 1001
        buildBg.addChild(buildIcon)
        
        camera.addChild(buildBg)
        buildButton = buildBg
        
        // Settings button (below build button) with icon
        let settingsBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        settingsBg.fillColor = SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.95)
        settingsBg.strokeColor = .white
        settingsBg.lineWidth = 2
        settingsBg.position = CGPoint(x: screenWidth / 2 - buttonWidth / 2 - sideMargin, y: screenHeight / 2 - topMargin - (buttonHeight + buttonSpacing) * 2)
        settingsBg.zPosition = 1000
        settingsBg.name = "settingsButton"
        
        // Create gear/settings icon
        let settingsIcon = createSettingsIcon(size: min(buttonWidth, buttonHeight) * 0.6)
        settingsIcon.position = CGPoint(x: 0, y: 0)
        settingsIcon.zPosition = 1001
        settingsBg.addChild(settingsIcon)
        
        camera.addChild(settingsBg)
        settingsButton = settingsBg
    }
    
    func getViewSize() -> CGSize {
        guard let scene = scene else { return CGSize(width: 375, height: 667) }
        if let view = scene.view {
            return view.bounds.size
        }
        return scene.size
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
        playerStatsBg?.removeFromParent()
        companionStatsBg?.removeFromParent()
        inventoryButton?.removeFromParent()
        buildButton?.removeFromParent()
        settingsButton?.removeFromParent()
        
        // Clear all references
        playerStatsBg = nil
        companionStatsBg = nil
        playerStatsLabel = nil
        companionStatsLabel = nil
        inventoryButton = nil
        buildButton = nil
        settingsButton = nil
    }
    
    func updateLayout() {
        print("GameUI: updateLayout called")
        
        // Save current state
        let savedPlayerText = playerStatsLabel?.text
        let savedCompanionText = companionStatsLabel?.text
        let wasCompanionHidden = companionStatsLabel?.isHidden ?? true
        
        // Clean up old UI
        cleanup()
        
        // Recreate UI with new layout
        setupUI()
        
        // Restore label text and visibility
        playerStatsLabel?.text = savedPlayerText
        companionStatsLabel?.text = savedCompanionText
        companionStatsLabel?.isHidden = wasCompanionHidden
    }
    
    func updatePlayerStats(player: Player) {
        playerStatsLabel?.text = "\(player.name) Lv.\(player.level) | HP: \(player.hitPoints)/\(player.maxHitPoints) | XP: \(player.experiencePoints)"
    }
    
    func updateCompanionStats(companion: Animal?) {
        if let companion = companion {
            companionStatsLabel?.text = "\(companion.name) Lv.\(companion.level) | HP: \(companion.hitPoints)/\(companion.maxHitPoints) | Friendship: \(companion.friendshipLevel)"
            companionStatsLabel?.isHidden = false
        } else {
            companionStatsLabel?.isHidden = true
        }
    }
}

