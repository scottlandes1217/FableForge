//
//  GameScene_macOS.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/7/26.
//

#if os(macOS)
import SpriteKit
import AppKit

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
    
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        
        // Check for UI buttons and panel buttons using nodes(at:) for reliable hit-testing
        let clickedNodes = nodes(at: location)
        
        // Helper closure to see if any clicked node (or its parent) matches a name
        func didClick(nodeNamed targetName: String) -> Bool {
            return clickedNodes.contains { node in
                node.name == targetName || node.parent?.name == targetName
            }
        }
        
        // Check for panel buttons first (they're on top)
        guard let camera = cameraNode else { return }
        
        if didClick(nodeNamed: "closeInventory") {
            print("[GameScene] Close inventory button clicked")
            if let panel = camera.childNode(withName: "inventoryPanel") {
                panel.removeFromParent()
                isGamePaused = false
            }
            return
        }
        
        if didClick(nodeNamed: "closeBuild") {
            print("[GameScene] Close build button clicked")
            if let panel = camera.childNode(withName: "buildPanel") {
                panel.removeFromParent()
                isGamePaused = false
            }
            return
        }
        
        if didClick(nodeNamed: "closeSettings") {
            print("[GameScene] Close settings button clicked")
            if let panel = camera.childNode(withName: "settingsPanel") {
                panel.removeFromParent()
                isGamePaused = false
            }
            return
        }
        
        if didClick(nodeNamed: "saveGame") {
            print("[GameScene] Save game button clicked")
            if let panel = camera.childNode(withName: "settingsPanel") {
                panel.removeFromParent()
            }
            saveGame()
            return
        }
        
        if didClick(nodeNamed: "loadGame") {
            print("[GameScene] Load game button clicked")
            if let panel = camera.childNode(withName: "settingsPanel") {
                panel.removeFromParent()
            }
            loadGame()
            return
        }
        
        if didClick(nodeNamed: "quitToMenu") {
            print("[GameScene] Quit to menu button clicked")
            if let panel = camera.childNode(withName: "settingsPanel") {
                panel.removeFromParent()
            }
            quitToMainMenu()
            return
        }
        
        // Check for build structure buttons
        for structureType in StructureType.allCases {
            let buttonName = "build_\(structureType.rawValue)"
            if didClick(nodeNamed: buttonName) {
                print("[GameScene] Build structure button clicked: \(structureType.rawValue)")
                if let panel = camera.childNode(withName: "buildPanel") {
                    panel.removeFromParent()
                }
                attemptBuildStructure(type: structureType)
                isGamePaused = false
                return
            }
        }
        
        // Check for save slot buttons
        for slotNum in 1...SaveManager.maxSlots {
            let buttonName = "saveSlot_\(slotNum)"
            if didClick(nodeNamed: buttonName) {
                print("[GameScene] Save slot \(slotNum) button clicked")
                if let panel = camera.childNode(withName: "saveSlotPanel") {
                    panel.removeFromParent()
                }
                saveGame(toSlot: slotNum)
                isGamePaused = false
                return
            }
        }
        
        // Check for load slot buttons
        for slotNum in 1...SaveManager.maxSlots {
            let buttonName = "loadSlot_\(slotNum)"
            if didClick(nodeNamed: buttonName) {
                print("[GameScene] Load slot \(slotNum) button clicked")
                if let panel = camera.childNode(withName: "loadSlotPanel") {
                    panel.removeFromParent()
                }
                loadGame(fromSlot: slotNum)
                isGamePaused = false
                return
            }
        }
        
        if didClick(nodeNamed: "closeSaveSlot") {
            print("[GameScene] Close save slot button clicked")
            if let panel = camera.childNode(withName: "saveSlotPanel") {
                panel.removeFromParent()
                isGamePaused = false
            }
            return
        }
        
        if didClick(nodeNamed: "closeLoadSlot") {
            print("[GameScene] Close load slot button clicked")
            if let panel = camera.childNode(withName: "loadSlotPanel") {
                panel.removeFromParent()
                isGamePaused = false
            }
            return
        }
        
        // Check for main UI buttons (inventory, build, settings)
        if didClick(nodeNamed: "inventoryButton") {
            print("[GameScene] Inventory button clicked")
            showInventory()
            return
        }
        
        if didClick(nodeNamed: "buildButton") {
            print("[GameScene] Build button clicked")
            showBuildMenu()
            return
        }
        
        if didClick(nodeNamed: "settingsButton") {
            print("[GameScene] Settings button clicked")
            showSettings()
            return
        }
        
        // Check for question mark interaction (dialogue objects)
        if !isInDialogue {
            handleQuestionMarkInteraction(at: location)
        } else {
            // Check for dialogue button clicks
            handleDialogueInteraction(at: location)
        }
    }
    
    private func handleQuestionMarkInteraction(at location: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        // Find nodes at this location
        let clickedNodes = nodes(at: location)
        
        // Check if clicking on a question mark
        for node in clickedNodes {
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
    
    private func handleDialogueInteraction(at location: CGPoint) {
        guard let camera = cameraNode else { return }
        let clickedNodes = nodes(at: location)
        
        for node in clickedNodes {
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
        // Try to find character by matching player name and class
        if currentCharacterId == nil {
            let characters = SaveManager.getAllCharacters()
            if let gameState = gameState {
                currentCharacterId = characters.first(where: {
                    $0.name == gameState.player.name && $0.characterClass == gameState.player.characterClass
                })?.id
            }
        }
        
        // If we have a character ID, use it; otherwise fall back to legacy load
        let loadedState: GameState?
        if let characterId = currentCharacterId {
            loadedState = SaveManager.loadGame(characterId: characterId, fromSlot: slot)
        } else {
            // Legacy load (for backward compatibility)
            loadedState = SaveManager.loadGame(fromSlot: slot)
        }
        
        guard let loadedState = loadedState else {
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

