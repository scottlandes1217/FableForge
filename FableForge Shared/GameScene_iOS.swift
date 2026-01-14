//
//  GameScene_iOS.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/7/26.
//

#if os(iOS) || os(tvOS)
import SpriteKit

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
        
        // Check for UI buttons using nodes(at:) for reliable hit-testing
        let touchedNodes = nodes(at: location)
        
        // Helper closure to see if any touched node (or its parent) matches a name
        func didTouch(nodeNamed targetName: String) -> Bool {
            return touchedNodes.contains { node in
                node.name == targetName || node.parent?.name == targetName
            }
        }
        
        if didTouch(nodeNamed: "inventoryButton") {
            print("[GameScene] Inventory button touched")
            showInventory()
            return
        }
        
        if didTouch(nodeNamed: "buildButton") {
            print("[GameScene] Build button touched")
            showBuildMenu()
            return
        }
        
        if didTouch(nodeNamed: "settingsButton") {
            print("[GameScene] Settings button touched")
            showSettings()
            return
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


