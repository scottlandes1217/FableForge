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
        
        print("👆 GameScene_iOS: touchesBegan at \(location), isGamePaused=\(isGamePaused), isInCombat=\(isInCombat), isInDialogue=\(isInDialogue)")
        
        guard let camera = cameraNode else { return }
        
        // Store touch location for potential drag (will start drag if moved in touchesMoved)
        let cameraLocation = convert(location, to: camera)
        touchStartLocation = cameraLocation
        
        // Handle CharacterUI touches FIRST (if visible, it takes priority over everything)
        // Check ALL nodes at this location FIRST to see if any are CharacterUI-related
        let allNodesAtLocation = nodes(at: location)
        var foundCharacterUINode = false
        var characterUINodeNames: [String] = []
        for node in allNodesAtLocation {
            var currentNode: SKNode? = node
            while let current = currentNode {
                if let name = current.name {
                    if name == "characterUIPanel" || 
                       name == "closeCharacterUI" ||
                       name.hasPrefix("tabButton_") ||
                       name.hasPrefix("learnButton_") ||
                       name.hasPrefix("increaseButton_") {
                        foundCharacterUINode = true
                        characterUINodeNames.append(name)
                        break
                    }
                }
                currentNode = current.parent
            }
            if foundCharacterUINode { break }
        }
        
        // If we found any CharacterUI node, process CharacterUI touches and return
        if foundCharacterUINode {
            // Check if the panel still exists (if it was just closed, it might be gone)
            let panelExists = camera.childNode(withName: "characterUIPanel") != nil
            
            if let characterUI = characterUI, characterUI.isVisible && panelExists {
                if characterUI.handleTouch(at: cameraLocation) {
                    return // Touch was handled by CharacterUI
                }
            }
            
            // If panel doesn't exist or CharacterUI isn't visible, allow other buttons to be processed
            // (the CharacterUI was likely just closed)
            if !panelExists {
                // Continue to button processing below
            } else {
                // Panel exists but CharacterUI didn't handle it - block other buttons
                return
            }
        }
        
        // Check if panel exists and contains the touch
        if let panel = camera.childNode(withName: "characterUIPanel") {
            if panel.contains(cameraLocation) {
                // Touch is within CharacterUI panel - only process CharacterUI touches
                if let characterUI = characterUI, characterUI.isVisible {
                    if characterUI.handleTouch(at: cameraLocation) {
                        return // Touch was handled by CharacterUI
                    }
                }
                // Even if not handled or not visible, don't process other buttons if touch is in CharacterUI panel area
                return
            }
        }
        
        // If CharacterUI is visible but touch is outside panel, still don't process other UI buttons
        // (CharacterUI takes full priority when visible)
        if let characterUI = characterUI, characterUI.isVisible {
            return
        }
        
        // Check if touching UI elements (panels are children of camera)
        if let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
            let cameraLocation = convert(location, to: camera)
            if inventoryPanel.contains(cameraLocation) {
                handleInventoryPanelTouch(at: location, in: inventoryPanel)
                return
            }
        }
        
        // Handle BuildUI touches
        if let buildUI = buildUI, buildUI.isVisible {
            if buildUI.handleTouch(at: location) {
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
        
        // Helper function to check if a node is part of CharacterUI
        func isCharacterUINode(_ node: SKNode) -> Bool {
            var currentNode: SKNode? = node
            while let current = currentNode {
                if current.name == "characterUIPanel" || current.name == "closeCharacterUI" {
                    return true
                }
                currentNode = current.parent
            }
            return false
        }
        
        // Filter out any CharacterUI nodes from touched nodes
        let filteredNodes = touchedNodes.filter { !isCharacterUINode($0) }
        
        // Use atPoint to get the SINGLE topmost node at this location
        // This ensures only one button is processed
        let topmostNode = camera.atPoint(cameraLocation)
        
        // Helper function to find button name by traversing up the node tree
        func findButtonName(startingFrom node: SKNode) -> String? {
            var currentNode: SKNode? = node
            while let current = currentNode {
                if let name = current.name, 
                   (name == "characterButton" || name == "inventoryButton" || 
                    name == "buildButton" || name == "settingsButton") {
                    return name
                }
                currentNode = current.parent
            }
            return nil
        }
        
        // Process only the topmost button
        if let buttonName = findButtonName(startingFrom: topmostNode) {
            switch buttonName {
            case "characterButton":
                print("[GameScene] Character button touched (topmost node)")
                if let player = gameState?.player {
                    characterUI?.toggle(player: player)
                }
                return
            case "inventoryButton":
                print("[GameScene] Inventory button touched (topmost node)")
                showInventory()
                return
            case "buildButton":
                print("[GameScene] Build button touched (topmost node)")
                showBuildMenu()
                return
            case "settingsButton":
                print("[GameScene] Settings button touched (topmost node)")
                showSettings()
                return
            default:
                break
            }
        }
        
        // Handle build placement mode touches
        if isBuildPlacementMode {
            // Update placement preview position
            updatePlacementPreview(at: location)
            return
        }
        
        // Check for chest UI interaction first
        if chestUI?.isVisible == true {
            print("📦 GameScene_iOS: Chest UI is visible, handling UI interaction")
            handleChestUIInteraction(at: location)
            return
        }
        
        // Start joystick movement - store initial touch location in screen/camera coordinates
        guard !isGamePaused, !isInCombat, !isInDialogue else { return }
        guard let camera = cameraNode else { return }
        
        // Check for chest clicks BEFORE joystick handling
        // Find nodes at this location to check for chests
        let touchedNodes = nodes(at: location)
        print("🔍 GameScene_iOS: Checking for chests - found \(touchedNodes.count) nodes at \(location)")
        for node in touchedNodes {
            // Check if this is a chest entity container
            if let name = node.name, name.hasPrefix("chest_entity_") {
                print("✅ GameScene_iOS: Found chest node by name: \(name)")
                handleChestClick(node: node, worldPosition: location)
                return  // Don't start joystick movement if clicking a chest
            }
            // Also check userData for chest identification
            if let userData = node.userData, userData["entityType"] as? String == "chest" {
                print("✅ GameScene_iOS: Found chest node by userData")
                handleChestClick(node: node, worldPosition: location)
                return  // Don't start joystick movement if clicking a chest
            }
        }
        
        // Also check for question mark interactions (dialogue objects)
        // Note: This might start joystick movement, but dialogue takes priority
        
        // Convert touch location to camera coordinates (screen space)
        let cameraLocation = convert(location, to: camera)
        touchStartLocation = cameraLocation
        isMoving = true
        
        // Show joystick visual at touch location
        showJoystickVisual(at: cameraLocation)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Handle build placement mode - update preview position
        if isBuildPlacementMode {
            updatePlacementPreview(at: location)
            return
        }
        
        // Handle BuildUI scrolling
        if let buildUI = buildUI, buildUI.isVisible {
            buildUI.handleTouchMoved(at: location)
            return
        }
        
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        
        // Handle drag and drop if already dragging
        if let draggedIndex = draggedItemIndex, let draggedNode = draggedItemNode {
            draggedNode.position = cameraLocation
            return
        }
        
        // Check if we should start a drag (if touching inventory item and moved enough)
        if let startLocation = touchStartLocation, let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
            let delta = CGPoint(
                x: cameraLocation.x - startLocation.x,
                y: cameraLocation.y - startLocation.y
            )
            let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
            
            // If moved more than 10 points, start drag
            if distance > 10.0 {
                let localPoint = inventoryPanel.convert(startLocation, from: camera)
                let touchedNodes = inventoryPanel.nodes(at: localPoint)
                
                // Find item at start location
                for node in touchedNodes {
                    var slotIndex: Int? = nil
                    if let nodeName = node.name {
                        if nodeName.hasPrefix("itemContainer_") {
                            slotIndex = Int(String(nodeName.dropFirst("itemContainer_".count)))
                        } else if nodeName.hasPrefix("itemSprite_") {
                            slotIndex = Int(String(nodeName.dropFirst("itemSprite_".count)))
                        } else if nodeName.hasPrefix("inventorySlot_") {
                            slotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                        }
                    }
                    // Check parent chain
                    if slotIndex == nil {
                        var currentNode: SKNode? = node
                        while let current = currentNode, slotIndex == nil {
                            if let nodeName = current.name {
                                if nodeName.hasPrefix("itemContainer_") {
                                    slotIndex = Int(String(nodeName.dropFirst("itemContainer_".count)))
                                } else if nodeName.hasPrefix("inventorySlot_") {
                                    slotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                                }
                            }
                            currentNode = current.parent
                        }
                    }
                    
                    if let index = slotIndex, let player = gameState?.player, index < player.inventory.count {
                        // Start drag
                        draggedItemIndex = index
                        if let itemContainer = inventoryPanel.childNode(withName: "//itemContainer_\(index)") {
                            draggedItemNode = itemContainer.copy() as? SKNode
                            draggedItemNode?.alpha = 0.7
                            draggedItemNode?.zPosition = 6000 // Above inventory panel (2000), context menu (5000), but below messages (10000)
                            draggedItemNode?.position = cameraLocation
                            camera.addChild(draggedItemNode!)
                        }
                        return
                    }
                }
            }
        }
        
        // Handle joystick movement
        guard isMoving, !isGamePaused, !isInCombat, !isInDialogue else { return }
        guard let startLocation = touchStartLocation else { return }
        
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
        // Handle build placement mode
        if isBuildPlacementMode, let touch = touches.first {
            let location = touch.location(in: self)
            placeStructureAtPosition(location)
            return
        }
        
        // Handle BuildUI touch end
        if let buildUI = buildUI, buildUI.isVisible {
            if buildUI.handleTouchEnded(at: location) {
                return
            }
        }
        
        // Handle drag and drop end
        if let draggedIndex = draggedItemIndex, let draggedNode = draggedItemNode,
           let touch = touches.first, let camera = cameraNode {
            let location = touch.location(in: self)
            let cameraLocation = convert(location, to: camera)
            
            // Clean up drag first (remove visual before checking drop target)
            draggedNode.removeFromParent()
            let savedDraggedIndex = draggedIndex
            
            // Check if dropped on an inventory slot
            if let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
                let localPoint = inventoryPanel.convert(cameraLocation, from: camera)
                let touchedNodes = inventoryPanel.nodes(at: localPoint)
                
                var targetSlotIndex: Int? = nil
                for node in touchedNodes {
                    if let nodeName = node.name, nodeName.hasPrefix("inventorySlot_") {
                        targetSlotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                        print("🎯 Found target slot: \(targetSlotIndex ?? -1) from node name")
                        break
                    }
                    // Check parent chain
                    var currentNode: SKNode? = node
                    while let current = currentNode, targetSlotIndex == nil {
                        if let nodeName = current.name, nodeName.hasPrefix("inventorySlot_") {
                            targetSlotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                            print("🎯 Found target slot: \(targetSlotIndex ?? -1) from parent chain")
                            break
                        }
                        currentNode = current.parent
                    }
                    if targetSlotIndex != nil { break }
                }
                
                // Swap items if dropped on a valid slot
                if let targetIndex = targetSlotIndex {
                    print("🎯 Dropping item from slot \(savedDraggedIndex) to slot \(targetIndex)")
                    swapInventoryItems(from: savedDraggedIndex, to: targetIndex)
                } else {
                    // Fallback: try to find slot by position
                    if let targetIndex = findSlotIndexAtPosition(localPoint, in: inventoryPanel) {
                        print("🎯 Found target slot by position: \(targetIndex)")
                        swapInventoryItems(from: savedDraggedIndex, to: targetIndex)
                    } else {
                        print("⚠️ No target slot found at drop location: \(localPoint)")
                    }
                }
            }
            
            // Clean up drag state
            draggedItemIndex = nil
            draggedItemNode = nil
            return
        }
        
        isMoving = false
        currentMovementDirection = CGPoint.zero
        touchStartLocation = nil
        hideJoystickVisual()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Cancel drag and drop
        if let draggedNode = draggedItemNode {
            draggedNode.removeFromParent()
            draggedItemIndex = nil
            draggedItemNode = nil
        }
        
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
        
        // Check for context menu clicks first
        if let contextMenu = camera.childNode(withName: "inventoryContextMenu") {
            let menuLocalPoint = contextMenu.convert(cameraLocation, from: camera)
            let menuNodes = contextMenu.nodes(at: menuLocalPoint)
            
            if let inspectButton = menuNodes.first(where: { findNodeWithName("contextMenuInspect", startingFrom: $0) != nil }) {
                if findNodeWithName("contextMenuInspect", startingFrom: inspectButton) != nil {
                    handleInventoryContextMenuAction(action: "inspect")
                    return
                }
            }
            if let dropButton = menuNodes.first(where: { findNodeWithName("contextMenuDrop", startingFrom: $0) != nil }) {
                if findNodeWithName("contextMenuDrop", startingFrom: dropButton) != nil {
                    handleInventoryContextMenuAction(action: "drop")
                    return
                }
            }
            if let destroyButton = menuNodes.first(where: { findNodeWithName("contextMenuDestroy", startingFrom: $0) != nil }) {
                if findNodeWithName("contextMenuDestroy", startingFrom: destroyButton) != nil {
                    handleInventoryContextMenuAction(action: "destroy")
                    return
                }
            }
            // Clicked outside context menu, close it
            closeInventoryContextMenu()
            return
        }
        
        // Check for inspect panel close
        if let inspectPanel = camera.childNode(withName: "itemInspectPanel") {
            let inspectLocalPoint = inspectPanel.convert(cameraLocation, from: camera)
            let inspectNodes = inspectPanel.nodes(at: inspectLocalPoint)
            if let closeButton = inspectNodes.first(where: { findNodeWithName("closeInspect", startingFrom: $0) != nil }) {
                if findNodeWithName("closeInspect", startingFrom: closeButton) != nil {
                    inspectPanel.removeFromParent()
                    return
                }
            }
            // Clicked outside inspect panel, close it
            inspectPanel.removeFromParent()
            return
        }
        
        // Use nodes(at:) to get all nodes at the touch point, then traverse parent chain
        let touchedNodes = panel.nodes(at: localPoint)
        
        // Check for close button
        if let closeButton = touchedNodes.first(where: { findNodeWithName("closeInventory", startingFrom: $0) != nil }) {
            if findNodeWithName("closeInventory", startingFrom: closeButton) != nil {
                panel.removeFromParent()
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
                return
            }
        }
        
        // Check for item slot clicks (show context menu)
        // Check both slot background and item container/sprite
        for node in touchedNodes {
            // Check slot background
            if let nodeName = node.name, nodeName.hasPrefix("inventorySlot_") {
                let indexString = String(nodeName.dropFirst("inventorySlot_".count))
                if let slotIndex = Int(indexString) {
                    showInventoryContextMenu(at: cameraLocation, itemIndex: slotIndex)
                    return
                }
            }
            // Check item container
            if let nodeName = node.name, nodeName.hasPrefix("itemContainer_") {
                let indexString = String(nodeName.dropFirst("itemContainer_".count))
                if let slotIndex = Int(indexString) {
                    showInventoryContextMenu(at: cameraLocation, itemIndex: slotIndex)
                    return
                }
            }
            // Check item sprite
            if let nodeName = node.name, nodeName.hasPrefix("itemSprite_") {
                let indexString = String(nodeName.dropFirst("itemSprite_".count))
                if let slotIndex = Int(indexString) {
                    showInventoryContextMenu(at: cameraLocation, itemIndex: slotIndex)
                    return
                }
            }
            // Check parent chain for item-related nodes
            var currentNode: SKNode? = node
            while let current = currentNode {
                if let nodeName = current.name {
                    if nodeName.hasPrefix("inventorySlot_") {
                        let indexString = String(nodeName.dropFirst("inventorySlot_".count))
                        if let slotIndex = Int(indexString) {
                            showInventoryContextMenu(at: cameraLocation, itemIndex: slotIndex)
                            return
                        }
                    }
                    if nodeName.hasPrefix("itemContainer_") {
                        let indexString = String(nodeName.dropFirst("itemContainer_".count))
                        if let slotIndex = Int(indexString) {
                            showInventoryContextMenu(at: cameraLocation, itemIndex: slotIndex)
                            return
                        }
                    }
                }
                currentNode = current.parent
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
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
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
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
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
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
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


