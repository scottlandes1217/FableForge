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
        let keyCode = event.keyCode
        
        // Handle escape key to exit build placement mode
        if keyCode == 53 { // ESC key
            if isBuildPlacementMode {
                exitBuildPlacementMode()
                return
            }
        }
        
        guard !isGamePaused, !isInCombat, !isInDialogue else { return }
        
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
        
        // If any movement key is pressed, cancel auto-walk
        if direction.x != 0 || direction.y != 0 {
            if isAutoWalking {
                print("🚶‍♂️ Auto-walk cancelled by arrow key input")
                isAutoWalking = false
                autoWalkTarget = nil
                autoWalkTargetNode = nil
                autoWalkLastPosition = nil
                autoWalkStuckCounter = 0
                autoWalkLastDirection = CGPoint.zero
                autoWalkObstacleAvoidance = nil
                autoWalkCompletion = nil
            }
        }
        
        // Normalize direction if diagonal
        let length = sqrt(direction.x * direction.x + direction.y * direction.y)
        if length > 0 {
            currentMovementDirection = CGPoint(x: direction.x / length, y: direction.y / length)
        } else {
            currentMovementDirection = CGPoint.zero
        }
    }
    
    // NOTE: mouseDown is now in the main GameScene class, not in this extension
    // This prevents duplicate method errors
    /*override func mouseDown(with event: NSEvent) {
        // CRITICAL: This log should appear for EVERY mouse click on the game screen
        print("🖱️🖱️🖱️🖱️🖱️🖱️🖱️ GameScene_macOS: mouseDown CALLED - THIS SHOULD APPEAR FOR EVERY CLICK")
        let location = event.location(in: self)
        
        print("🖱️🖱️🖱️ GameScene_macOS: mouseDown at \(location)")
        print("   isGamePaused=\(isGamePaused), isInCombat=\(isInCombat), isInDialogue=\(isInDialogue)")
        print("   isUserInteractionEnabled=\(isUserInteractionEnabled), isPaused=\(isPaused), view=\(view != nil ? "exists" : "nil")")
        print("   event.locationInWindow=\(event.locationInWindow)")
        
        // Check if clicking a chest UI button first
        if chestUI?.isVisible == true {
            print("📦 GameScene_macOS: Chest UI is visible, handling UI interaction")
            handleChestUIInteraction(at: location)
            return
        }
        
        // Check for chest clicks BEFORE other UI handling (even if paused - we want to detect them)
        // Find nodes at this location to check for chests
        let touchedNodes = nodes(at: location)
        print("🔍 GameScene_macOS: Checking for chests - found \(touchedNodes.count) nodes at \(location)")
        for (index, node) in touchedNodes.enumerated() {
            let nodeName = node.name ?? "nil"
            let entityType = node.userData?["entityType"] as? String ?? "nil"
            print("   Node \(index): name=\(nodeName), type=\(type(of: node)), userData.entityType=\(entityType)")
            // Also check parent chain
            var parent = node.parent
            var depth = 0
            while parent != nil && depth < 5 {
                let parentName = parent?.name ?? "nil"
                let parentEntityType = parent?.userData?["entityType"] as? String ?? "nil"
                print("     Parent \(depth): name=\(parentName), userData.entityType=\(parentEntityType)")
                parent = parent?.parent
                depth += 1
            }
        }
        
        // Check for chests even if paused (so we can detect them)
        // First check direct nodes
        for node in touchedNodes {
            // Check if this is a chest entity container
            if let name = node.name, name.hasPrefix("chest_entity_") {
                print("✅✅✅ GameScene_macOS: Found chest node by name: \(name)")
                handleChestClick(node: node, worldPosition: location)
                return  // Don't process other UI if clicking a chest
            }
            // Also check userData for chest identification
            if let userData = node.userData, userData["entityType"] as? String == "chest" {
                print("✅✅✅ GameScene_macOS: Found chest node by userData")
                handleChestClick(node: node, worldPosition: location)
                return  // Don't process other UI if clicking a chest
            }
        }
        
        // Also search through parent chains - chest containers might not be directly hit
        for node in touchedNodes {
            var currentNode: SKNode? = node
            var depth = 0
            while let current = currentNode, depth < 10 {
                if let name = current.name, name.hasPrefix("chest_entity_") {
                    print("✅✅✅ GameScene_macOS: Found chest node in parent chain (depth \(depth)): \(name)")
                    handleChestClick(node: current, worldPosition: location)
                    return
                }
                if let userData = current.userData, userData["entityType"] as? String == "chest" {
                    print("✅✅✅ GameScene_macOS: Found chest node in parent chain by userData (depth \(depth))")
                    handleChestClick(node: current, worldPosition: location)
                    return
                }
                currentNode = current.parent
                depth += 1
            }
        }
        
        // Also search all children of entitiesBelow/chunk nodes that were hit
        // Chest containers are children of entitiesBelow, but might not be directly hit-tested
        // because they're just container nodes without frames
        for node in touchedNodes {
            if node.name == "entitiesBelow" || node.name?.hasPrefix("chunk_") == true {
                print("🔍 GameScene_macOS: Searching children of \(node.name ?? "nil") for chests")
                // Search all descendants for chest containers
                node.enumerateChildNodes(withName: "//chest_entity_*") { [weak self] chestNode, _ in
                    guard let self = self else { return }
                    // Check if click is near this chest (within reasonable distance)
                    let chestWorldPos = chestNode.position
                    // Convert chest position to scene coordinates by traversing parent chain
                    var worldPos = chestWorldPos
                    var parent = chestNode.parent
                    while parent != nil && parent !== self {
                        worldPos = CGPoint(x: worldPos.x + parent!.position.x, y: worldPos.y + parent!.position.y)
                        parent = parent!.parent
                    }
                    let distance = sqrt(pow(location.x - worldPos.x, 2) + pow(location.y - worldPos.y, 2))
                    if distance < 100 {  // Within 100 pixels
                        print("✅✅✅ GameScene_macOS: Found chest node via enumerateChildNodes: \(chestNode.name ?? "nil") at distance \(distance)")
                        self.handleChestClick(node: chestNode, worldPosition: location)
                    }
                }
            }
        }
        
        // Also search all children of entitiesBelow/chunk nodes that were hit
        // Chest containers are children of entitiesBelow, but might not be directly hit-tested
        // because they're just container nodes without frames
        for node in touchedNodes {
            if node.name == "entitiesBelow" || node.name?.hasPrefix("chunk_") == true {
                print("🔍 GameScene_macOS: Searching children of \(node.name ?? "nil") for chests")
                // Search all descendants for chest containers using recursive search
                node.enumerateChildNodes(withName: "//chest_entity_*") { [weak self] chestNode, _ in
                    guard let self = self else { return }
                    // Check if click is near this chest (within reasonable distance)
                    let chestLocalPos = chestNode.position
                    // Convert chest position to scene coordinates by traversing parent chain
                    var worldPos = chestLocalPos
                    var parent = chestNode.parent
                    while parent != nil && parent !== self {
                        worldPos = CGPoint(x: worldPos.x + parent!.position.x, y: worldPos.y + parent!.position.y)
                        parent = parent!.parent
                    }
                    let distance = sqrt(pow(location.x - worldPos.x, 2) + pow(location.y - worldPos.y, 2))
                    print("   🔍 Found chest '\(chestNode.name ?? "nil")' at world pos \(worldPos), distance: \(distance)")
                    if distance < 100 {  // Within 100 pixels
                        print("✅✅✅ GameScene_macOS: Found chest node via enumerateChildNodes: \(chestNode.name ?? "nil") at distance \(distance)")
                        self.handleChestClick(node: chestNode, worldPosition: location)
                    }
                }
            }
        }
        
        // Always check for UI (inventory, settings, panels, etc.) even when paused.
        // When paused, UI like inventory is open and must receive clicks.
        // Only world interactions (movement, world objects) are skipped via isGamePaused elsewhere.
        
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
        
        // Convert location to camera coordinates for CharacterUI check
        let cameraLocation = convert(location, to: camera)
        
        // Handle CharacterUI clicks FIRST (if visible, it takes priority over everything)
        // Check ALL nodes at this location FIRST to see if any are CharacterUI-related
        let allNodesAtLocation = nodes(at: location)
        var foundCharacterUINode = false
        for node in allNodesAtLocation {
            var currentNode: SKNode? = node
            while let current = currentNode {
                if current.name == "characterUIPanel" || 
                   current.name == "closeCharacterUI" ||
                   current.name?.hasPrefix("tabButton_") == true ||
                   current.name?.hasPrefix("learnButton_") == true ||
                   current.name?.hasPrefix("increaseButton_") == true {
                    foundCharacterUINode = true
                    break
                }
                currentNode = current.parent
            }
            if foundCharacterUINode { break }
        }
        
        // If we found any CharacterUI node, process CharacterUI clicks and return
        if foundCharacterUINode {
            // Check if the panel still exists (if it was just closed, it might be gone)
            let panelExists = camera.childNode(withName: "characterUIPanel") != nil
            
            if let characterUI = characterUI, characterUI.isVisible && panelExists {
                if characterUI.handleTouch(at: cameraLocation) {
                    return // Click was handled by CharacterUI
                }
            }
            
            // If panel doesn't exist or CharacterUI isn't visible, allow other buttons to be processed
            // (the CharacterUI was likely just closed)
            if !panelExists {
                print("[GameScene] CharacterUI panel doesn't exist - allowing other buttons")
                // Continue to button processing below
            } else {
                // Panel exists but CharacterUI didn't handle it - block other buttons
                return
            }
        }
        
        // Check if panel exists and contains the click (fallback check)
        if let panel = camera.childNode(withName: "characterUIPanel") {
            if panel.contains(cameraLocation) {
                print("[GameScene] Click is within CharacterUI panel - processing CharacterUI touch")
                // Click is within CharacterUI panel - only process CharacterUI clicks
                if let characterUI = characterUI, characterUI.isVisible {
                    if characterUI.handleTouch(at: cameraLocation) {
                        return // Click was handled by CharacterUI
                    }
                }
                // Even if not handled or not visible, don't process other buttons if click is in CharacterUI panel area
                return
            }
        }
        
        // If CharacterUI is visible but click is outside panel, still don't process other UI buttons
        // (CharacterUI takes full priority when visible)
        if let characterUI = characterUI, characterUI.isVisible {
            return
        }
        
        // Check for context menu clicks
        if didClick(nodeNamed: "contextMenuInspect") {
            handleInventoryContextMenuAction(action: "inspect")
            return
        }
        if didClick(nodeNamed: "contextMenuDrop") {
            handleInventoryContextMenuAction(action: "drop")
            return
        }
        if didClick(nodeNamed: "contextMenuDestroy") {
            handleInventoryContextMenuAction(action: "destroy")
            return
        }
        
        // Check for inspect panel close
        if didClick(nodeNamed: "closeInspect") {
            if let panel = camera.childNode(withName: "itemInspectPanel") {
                panel.removeFromParent()
            }
            return
        }
        
        // Check for inventory slot/item clicks (show context menu or start drag)
        if let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
            let cameraLocation = convert(location, to: camera)
            let localPoint = inventoryPanel.convert(cameraLocation, from: camera)
            let clickedNodes = inventoryPanel.nodes(at: localPoint)
            
            for node in clickedNodes {
                var slotIndex: Int? = nil
                if let nodeName = node.name {
                    if nodeName.hasPrefix("inventorySlot_") {
                        slotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                    } else if nodeName.hasPrefix("itemContainer_") {
                        slotIndex = Int(String(nodeName.dropFirst("itemContainer_".count)))
                    } else if nodeName.hasPrefix("itemSprite_") {
                        slotIndex = Int(String(nodeName.dropFirst("itemSprite_".count)))
                    }
                }
                // Check parent chain
                if slotIndex == nil {
                    var currentNode: SKNode? = node
                    while let current = currentNode, slotIndex == nil {
                        if let nodeName = current.name {
                            if nodeName.hasPrefix("inventorySlot_") {
                                slotIndex = Int(String(nodeName.dropFirst("inventorySlot_".count)))
                            } else if nodeName.hasPrefix("itemContainer_") {
                                slotIndex = Int(String(nodeName.dropFirst("itemContainer_".count)))
                            }
                        }
                        currentNode = current.parent
                    }
                }
                
                if let index = slotIndex, let player = gameState?.player, index < player.inventory.count {
                    // Store potential drag start (will start drag if moved in mouseDragged)
                    draggedItemIndex = index
                    touchStartLocation = cameraLocation
                    // Don't show context menu yet - wait to see if it's a drag or click
                    return
                }
            }
        }
        
        // Close context menu if clicking outside
        if camera.childNode(withName: "inventoryContextMenu") != nil {
            closeInventoryContextMenu()
        }
        
        if didClick(nodeNamed: "closeInventory") {
            print("[GameScene] Close inventory button clicked")
            if let panel = camera.childNode(withName: "inventoryPanel") {
                panel.removeFromParent()
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
            }
            return
        }
        
        // Handle BuildUI touches
        if let buildUI = buildUI, buildUI.isVisible {
            let clickLocation = event.location(in: self)
            if buildUI.handleTouch(at: clickLocation) {
                return
            }
        }
        
        if didClick(nodeNamed: "closeSettings") {
            print("[GameScene] Close settings button clicked")
            if let panel = camera.childNode(withName: "settingsPanel") {
                panel.removeFromParent()
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
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
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
            }
            return
        }
        
        if didClick(nodeNamed: "closeLoadSlot") {
            print("[GameScene] Close load slot button clicked")
            if let panel = camera.childNode(withName: "loadSlotPanel") {
                panel.removeFromParent()
                // Only resume game if no other UI is open
                if characterUI?.isVisible != true {
                    isGamePaused = false
                }
            }
            return
        }
        
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
                print("[GameScene] Character button clicked (topmost node)")
                if let player = gameState?.player {
                    characterUI?.toggle(player: player)
                }
                return
            case "inventoryButton":
                print("[GameScene] Inventory button clicked (topmost node)")
                showInventory()
                return
            case "buildButton":
                print("[GameScene] Build button clicked (topmost node)")
                showBuildMenu()
                return
            case "settingsButton":
                print("[GameScene] Settings button clicked (topmost node)")
                showSettings()
                return
            default:
                break
            }
        }
        
        // Handle build placement mode
        if isBuildPlacementMode {
            updatePlacementPreview(at: location)
            return
        }
        
        // Check for question mark interaction (dialogue objects)
        if !isInDialogue {
            handleQuestionMarkInteraction(at: location)
        } else {
            // Check for dialogue button clicks
            handleDialogueInteraction(at: location)
        }
    }*/
    
    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)
        
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
        if let startLocation = touchStartLocation, let draggedIndex = draggedItemIndex,
           let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
            let delta = CGPoint(
                x: cameraLocation.x - startLocation.x,
                y: cameraLocation.y - startLocation.y
            )
            let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
            
            // If moved more than 10 points, start drag
            if distance > 10.0 {
                if let itemContainer = inventoryPanel.childNode(withName: "//itemContainer_\(draggedIndex)") {
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
    
    override func mouseUp(with event: NSEvent) {
        let location = event.location(in: self)
        
        // Handle build placement mode
        if isBuildPlacementMode {
            placeStructureAtPosition(location)
            return
        }
        
        // Handle BuildUI touch end
        if let buildUI = buildUI, buildUI.isVisible {
            if buildUI.handleTouchEnded(at: location) {
                return
            }
        }
        
        guard let camera = cameraNode else { return }
        let cameraLocation = convert(location, to: camera)
        
        // Handle drag and drop end
        if let draggedIndex = draggedItemIndex, let draggedNode = draggedItemNode {
            // Clean up drag first (remove visual before checking drop target)
            draggedNode.removeFromParent()
            let savedDraggedIndex = draggedIndex
            
            // Check if dropped on an inventory slot
            if let inventoryPanel = camera.childNode(withName: "inventoryPanel") {
                let localPoint = inventoryPanel.convert(cameraLocation, from: camera)
                let clickedNodes = inventoryPanel.nodes(at: localPoint)
                
                var targetSlotIndex: Int? = nil
                for node in clickedNodes {
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
            touchStartLocation = nil
            return
        }
        
        // If we had a potential drag but didn't drag, show context menu
        if let draggedIndex = draggedItemIndex, let startLocation = touchStartLocation {
            let delta = CGPoint(
                x: cameraLocation.x - startLocation.x,
                y: cameraLocation.y - startLocation.y
            )
            let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
            
            // If didn't move much, it was a click - show context menu
            if distance <= 10.0 {
                showInventoryContextMenu(at: cameraLocation, itemIndex: draggedIndex)
            }
            
            draggedItemIndex = nil
            touchStartLocation = nil
        }
    }
    
    private func handleQuestionMarkInteraction(at location: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        // Find nodes at this location
        let clickedNodes = nodes(at: location)
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
    
    override func scrollWheel(with event: NSEvent) {
        // Handle BuildUI scrolling
        if let buildUI = buildUI, buildUI.isVisible {
            let deltaY = event.scrollingDeltaY
            print("🖱️ GameScene: scrollWheel event - deltaY=\(deltaY), hasPreciseScrollingDeltas=\(event.hasPreciseScrollingDeltas)")
            buildUI.handleScrollWheel(deltaY: deltaY)  // Let BuildUI handle scaling
            return
        }
    }
}
#endif

