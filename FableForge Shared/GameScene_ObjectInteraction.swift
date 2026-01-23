//
//  GameScene_ObjectInteraction.swift
//  FableForge Shared
//
//  Object interaction and chest management functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    // MARK: - Object Interaction
    
    /// Clear all auto-walk state to prevent unwanted movement
    private func clearAutoWalkState() {
        isAutoWalking = false
        autoWalkTarget = nil
        autoWalkTargetNode = nil
        autoWalkCompletion = nil
        autoWalkLastPosition = nil
        autoWalkStuckCounter = 0
        autoWalkLastDirection = CGPoint.zero
        autoWalkObstacleAvoidance = nil
        currentMovementDirection = CGPoint.zero
        isMoving = false
    }
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        print("👆 GameScene: touchesBegan at \(location), isGamePaused=\(isGamePaused), isInCombat=\(isInCombat), isInDialogue=\(isInDialogue)")
        
        // Check if touching a chest UI button first
        if chestUI?.isVisible == true {
            print("📦 GameScene: Chest UI is visible, handling UI interaction")
            handleChestUIInteraction(at: location)
            return
        }
        
        // If auto-walk is active and user touched somewhere (not chest UI), cancel auto-walk
        // This allows the user to break auto-walk by touching to move manually
        if isAutoWalking {
            print("🛑 GameScene: Auto-walk cancelled by user touch at \(location)")
            isAutoWalking = false
            autoWalkTarget = nil
            autoWalkTargetNode = nil
            autoWalkCompletion = nil
            autoWalkLastPosition = nil
            autoWalkStuckCounter = 0
            autoWalkLastDirection = CGPoint.zero
            autoWalkObstacleAvoidance = nil
            currentMovementDirection = CGPoint.zero
            isMoving = false
        }
        
        // Check if touching a dialogue button first
        if isInDialogue {
            print("💬 GameScene: In dialogue, handling dialogue interaction")
            handleDialogueInteraction(at: location)
        } else {
            print("🔍 GameScene: Handling chest interaction")
            handleQuestionMarkInteraction(at: location)
        }
    }
    #endif
    
    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        // CRITICAL: This log should appear for EVERY mouse click on the game screen
        print("🖱️🖱️🖱️🖱️🖱️🖱️🖱️ GameScene: mouseDown CALLED - THIS SHOULD APPEAR FOR EVERY CLICK")
        let location = event.location(in: self)
        
        print("🖱️🖱️🖱️ GameScene: mouseDown at \(location)")
        print("   isGamePaused=\(isGamePaused), isInCombat=\(isInCombat), isInDialogue=\(isInDialogue)")
        print("   isUserInteractionEnabled=\(isUserInteractionEnabled), isPaused=\(isPaused), view=\(view != nil ? "exists" : "nil")")
        print("   event.locationInWindow=\(event.locationInWindow)")
        
        // Check if clicking a chest UI button first
        if chestUI?.isVisible == true {
            print("📦 GameScene: Chest UI is visible, handling UI interaction")
            handleChestUIInteraction(at: location)
            return
        }
        
        // Check for chest clicks BEFORE other UI handling (even if paused - we want to detect them)
        // Find nodes at this location to check for chests
        let touchedNodes = nodes(at: location)
        print("🔍 GameScene: Checking for chests - found \(touchedNodes.count) nodes at \(location)")
        
        // Check for chests even if paused (so we can detect them)
        // Search ALL descendants of the touched nodes to find ALL chest containers
        // Then check which ones have the click within their bounding box or collision box
        var foundChests: [(container: SKNode, distance: CGFloat)] = []
        var checkedContainers = Set<SKNode>()
        
        // Recursive function to find all chest containers in a node tree
        func findAllChestContainers(in node: SKNode) {
            // Check if this node is a chest container
            if let name = node.name, name.hasPrefix("chest_entity_"),
               let userData = node.userData, userData["position"] != nil {
                if !checkedContainers.contains(node) {
                    checkedContainers.insert(node)
                    
                    // Check if click is on any of the chest's visual tiles (sprites)
                    var clickOnChest = false
                    
                    // PRIORITY 1: Use nodes(at:) FIRST - this is the most reliable way to detect clicks on sprites
                    // Note: nodes(at:) works even if sprites don't have isUserInteractionEnabled
                    // This directly checks if any sprite at the click location belongs to this chest
                    let nodesAtClick = self.nodes(at: location)
                    print("🔍 Checking \(nodesAtClick.count) nodes at click location for chest '\(name)'")
                    for clickedNode in nodesAtClick {
                        // Walk up the parent chain to see if this node belongs to the chest container
                        var currentNode: SKNode? = clickedNode
                        var depth = 0
                        while let current = currentNode, depth < 10 {
                            if current == node {
                                // Found the chest container in the parent chain - this node belongs to the chest!
                                clickOnChest = true
                                print("✅ Click detected via nodes(at:) for chest '\(name)': clickedNode=\(clickedNode.name ?? "unnamed"), type=\(type(of: clickedNode)), found container at depth \(depth), click=\(location)")
                                break
                            }
                            // Also check if current is a child of the chest container by checking all children
                            if node.children.contains(current) {
                                clickOnChest = true
                                print("✅ Click detected via nodes(at:) for chest '\(name)': clickedNode=\(clickedNode.name ?? "unnamed"), type=\(type(of: clickedNode)), is child of container at depth \(depth), click=\(location)")
                                break
                            }
                            currentNode = current.parent
                            depth += 1
                        }
                        if clickOnChest { break }
                    }
                    
                    // Also print what nodes were found for debugging
                    if !clickOnChest && nodesAtClick.count > 0 {
                        print("🔍 Nodes at click location (not matching chest '\(name)'):")
                        for (index, clickedNode) in nodesAtClick.enumerated() {
                            var currentNode: SKNode? = clickedNode
                            var depth = 0
                            var parentChain = ""
                            while let current = currentNode, depth < 5 {
                                parentChain += "[\(depth)]\(current.name ?? "nil")(\(type(of: current)))"
                                if current == node {
                                    parentChain += "<--CHEST_CONTAINER"
                                }
                                parentChain += " -> "
                                currentNode = current.parent
                                depth += 1
                            }
                            print("   Node \(index): name=\(clickedNode.name ?? "nil"), type=\(type(of: clickedNode)), chain=\(parentChain)")
                        }
                    }
                    
                    // PRIORITY 2: Check visual bounding box (all sprites combined) in SCENE coordinates
                    // Calculate bounding box by converting all sprite positions to scene coordinates
                    // This is more reliable than using calculateAccumulatedFrame() with coordinate conversion
                    if !clickOnChest {
                        // Get all visual sprites (exclude physics nodes)
                        let visualSprites = node.children.compactMap { child -> SKSpriteNode? in
                            guard child.physicsBody == nil, let sprite = child as? SKSpriteNode else { return nil }
                            return sprite
                        }
                        
                        if !visualSprites.isEmpty {
                            // Calculate bounding box from all sprites in SCENE coordinates
                            var minX = CGFloat.greatestFiniteMagnitude
                            var maxX = CGFloat(-CGFloat.greatestFiniteMagnitude)
                            var minY = CGFloat.greatestFiniteMagnitude
                            var maxY = CGFloat(-CGFloat.greatestFiniteMagnitude)
                            
                            for sprite in visualSprites {
                                // Convert sprite's position to scene coordinates
                                // Sprites use anchorPoint (0, 1) = top-left, so we need to account for that
                                let spriteWorldPos = sprite.convert(CGPoint.zero, to: self)
                                let spriteSize = sprite.size
                                
                                // Calculate sprite bounds in scene coordinates
                                // anchorPoint (0, 1) means: position is at top-left of sprite
                                let spriteLeft = spriteWorldPos.x
                                let spriteRight = spriteWorldPos.x + spriteSize.width
                                let spriteTop = spriteWorldPos.y
                                let spriteBottom = spriteWorldPos.y - spriteSize.height
                                
                                minX = min(minX, spriteLeft)
                                maxX = max(maxX, spriteRight)
                                minY = min(minY, spriteBottom)
                                maxY = max(maxY, spriteTop)
                            }
                            
                            // Create bounding box in scene coordinates
                            let visualBoundingBox = CGRect(
                                x: minX,
                                y: minY,
                                width: maxX - minX,
                                height: maxY - minY
                            )
                            
                            // Check if click (already in scene coordinates) is within the box
                            // Use padding (expand by 10pt each side) so clicks just outside still register
                            let paddedVisualBox = visualBoundingBox.insetBy(dx: -10, dy: -10)
                            let contains = paddedVisualBox.contains(location)
                            print("🔍 Visual bounding box check for chest '\(name)': visualBox=\(visualBoundingBox) padded=\(paddedVisualBox), click=\(location), contains=\(contains)")
                            if contains {
                                clickOnChest = true
                                print("✅ Click within visual bounding box for chest '\(name)': visualBox=\(visualBoundingBox), click=\(location)")
                            }
                        }
                    }
                    
                    // PRIORITY 3: Check individual sprites using their world positions
                    // Fallback if bounding box check fails (shouldn't happen, but just in case)
                    if !clickOnChest {
                        print("🔍 Checking \(node.children.count) children of chest '\(name)' for sprite frame matches")
                        for child in node.children {
                            // Skip physics nodes - we only want visual sprites
                            if child.physicsBody != nil { continue }
                            
                            if let sprite = child as? SKSpriteNode {
                                // Convert sprite's position to scene coordinates
                                let spriteWorldPos = sprite.convert(CGPoint.zero, to: self)
                                let spriteSize = sprite.size
                                
                                // Calculate sprite bounds in scene coordinates (anchorPoint 0,1 = top-left)
                                let spriteFrame = CGRect(
                                    x: spriteWorldPos.x,
                                    y: spriteWorldPos.y - spriteSize.height,
                                    width: spriteSize.width,
                                    height: spriteSize.height
                                )
                                
                                // Check if click (in scene coordinates) is within sprite frame (with padding)
                                let paddedFrame = spriteFrame.insetBy(dx: -8, dy: -8)
                                let contains = paddedFrame.contains(location)
                                print("   Sprite '\(sprite.name ?? "unnamed")': spriteFrame=\(spriteFrame) (in scene space), click=\(location), contains=\(contains)")
                                if contains {
                                    clickOnChest = true
                                    print("✅ Click detected on sprite child of chest '\(name)': sprite=\(sprite.name ?? "unnamed"), frame=\(spriteFrame), click=\(location)")
                                    break
                                }
                            }
                        }
                    }
                    
                    // PRIORITY 4: Check collision box (same as used for movement detection)
                    // Use the EXACT same collision box calculation as movement - this is a fallback
                    // The collision box is smaller than the visual area, so this should only trigger if visual detection fails
                    // Use padding (expand by 10pt each side) so clicks just outside still register
                    if !clickOnChest {
                        if let collisionBox = getChestCollisionBox(node: node) {
                            let paddedCollisionBox = collisionBox.insetBy(dx: -10, dy: -10)
                            let contains = paddedCollisionBox.contains(location)
                            print("🔍 Collision box check for chest '\(name)': collisionBox=\(collisionBox), padded=\(paddedCollisionBox), click=\(location), contains=\(contains)")
                            if contains {
                                clickOnChest = true
                                print("✅ Click within collision box for chest '\(name)': collisionBox=\(collisionBox), click=\(location)")
                            }
                        } else {
                            print("⚠️ getChestCollisionBox returned nil for chest '\(name)'")
                        }
                    }
                    
                    if clickOnChest {
                        // Get the chest's world position to calculate distance
                        let chestWorldPos: CGPoint
                        if let positionValue = userData["position"] as? NSValue {
                            chestWorldPos = positionValue.pointValue
                        } else {
                            chestWorldPos = node.convert(CGPoint.zero, to: self)
                        }
                        
                        // Calculate distance from click to chest center
                        let distance = sqrt(pow(chestWorldPos.x - location.x, 2) + pow(chestWorldPos.y - location.y, 2))
                        foundChests.append((container: node, distance: distance))
                    }
                }
                return  // Found container, don't search children (they're sprites, not containers)
            }
            
            // Recursively search children
            for child in node.children {
                findAllChestContainers(in: child)
            }
        }
        
        // Search all touched nodes and their descendants
        for node in touchedNodes {
            findAllChestContainers(in: node)
        }
        
        // If we found chests with the click on their tiles, use the closest one
        if let closestChest = foundChests.min(by: { $0.distance < $1.distance }) {
            print("✅ GameScene: Found \(foundChests.count) chest(s) with click on tiles, using closest: \(closestChest.container.name ?? "unnamed") at distance \(Int(closestChest.distance))")
            handleChestClick(node: closestChest.container, worldPosition: location)
            return  // Don't process other UI if clicking a chest
        }
        
        print("🔍 GameScene: No chest found at click location \(location)")
        
        // Always check for UI (inventory, settings, panels, etc.) even when paused.
        // When paused, UI like inventory is open and must receive touches/clicks.
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
        
        // If auto-walk is active and user clicked somewhere (not a chest, not UI), cancel auto-walk
        // This allows the user to break auto-walk by clicking to move manually
        if isAutoWalking {
            print("🛑 GameScene: Auto-walk cancelled by user click at \(location)")
            isAutoWalking = false
            autoWalkTarget = nil
            autoWalkTargetNode = nil
            autoWalkCompletion = nil
            autoWalkLastPosition = nil
            autoWalkStuckCounter = 0
            autoWalkLastDirection = CGPoint.zero
            autoWalkObstacleAvoidance = nil
            currentMovementDirection = CGPoint.zero
            isMoving = false
        }
        
        // Check for chest/object interaction
        if !isInDialogue {
            handleQuestionMarkInteraction(at: location)
        } else {
            // Check for dialogue button clicks
            handleDialogueInteraction(at: location)
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
    
    /// Handle interaction with chests and objects
    private func handleQuestionMarkInteraction(at location: CGPoint) {
        guard let player = gameState?.player, !isInCombat, !isInDialogue else { return }
        
        // Find nodes at this location
        let touchedNodes = nodes(at: location)
        
        // Debug: Log all touched nodes
        print("🔍 GameScene: Click at \(location), found \(touchedNodes.count) nodes")
        for (index, node) in touchedNodes.enumerated() {
            print("   Node \(index): name=\(node.name ?? "nil"), type=\(type(of: node)), userData.entityType=\(node.userData?["entityType"] as? String ?? "nil")")
        }
        
        // PRIORITY 1: Check if any clicked node is a chest container or child of one
        // Walk up the parent chain from each clicked node to find chest containers
        var foundChests: [(container: SKNode, distance: CGFloat)] = []
        
        for clickedNode in touchedNodes {
            var currentNode: SKNode? = clickedNode
            var depth = 0
            
            // Walk up the parent chain to find chest containers
            while let current = currentNode, depth < 10 {
                // Check if this node is a chest container
                if let name = current.name, name.hasPrefix("chest_entity_"),
                   let userData = current.userData, userData["position"] != nil {
                    // Found a chest container - calculate distance from click to chest center
                    let chestWorldPos: CGPoint
                    if let positionValue = userData["position"] as? NSValue {
                        chestWorldPos = positionValue.pointValue
                    } else {
                        chestWorldPos = current.convert(CGPoint.zero, to: self)
                    }
                    
                    let distance = sqrt(pow(chestWorldPos.x - location.x, 2) + pow(chestWorldPos.y - location.y, 2))
                    foundChests.append((container: current, distance: distance))
                    print("✅ GameScene: Found chest container '\(name)' via parent chain at depth \(depth), distance: \(Int(distance))")
                    break  // Found container, stop walking up this chain
                }
                
                // Also check userData for chest identification
                if let userData = current.userData, userData["entityType"] as? String == "chest" {
                    let chestWorldPos: CGPoint
                    if let positionValue = userData["position"] as? NSValue {
                        chestWorldPos = positionValue.pointValue
                    } else {
                        chestWorldPos = current.convert(CGPoint.zero, to: self)
                    }
                    
                    let distance = sqrt(pow(chestWorldPos.x - location.x, 2) + pow(chestWorldPos.y - location.y, 2))
                    foundChests.append((container: current, distance: distance))
                    print("✅ GameScene: Found chest container (by userData) via parent chain at depth \(depth), distance: \(Int(distance))")
                    break  // Found container, stop walking up this chain
                }
                
                currentNode = current.parent
                depth += 1
            }
        }
        
        // If we found chests, use the closest one
        if let closestChest = foundChests.min(by: { $0.distance < $1.distance }) {
            print("✅ GameScene: Found \(foundChests.count) chest(s), using closest: \(closestChest.container.name ?? "unnamed") at distance \(Int(closestChest.distance))")
            handleChestClick(node: closestChest.container, worldPosition: location)
            return
        }
        
        // PRIORITY 2: Fallback to bounding box search (for cases where nodes(at:) doesn't find the sprites)
        // This can happen if sprites don't have isUserInteractionEnabled or are in a different coordinate space
        var checkedContainers = Set<SKNode>()
        var foundChest: SKNode? = nil
        
        func findAllChestContainers(in node: SKNode) {
            // Check if this node is a chest container
            if let name = node.name, name.hasPrefix("chest_entity_"),
               let userData = node.userData, userData["position"] != nil {
                if !checkedContainers.contains(node) {
                    checkedContainers.insert(node)
                    
                    // Check if click is on any of the chest's visual tiles (sprites)
                    var clickOnChest = false
                    
                    // Check if click is within the bounding box of all chest tiles
                    let chestBoundingBox = calculateBoundingBox(for: node)
                    // Add small padding for easier clicking
                    let paddedBox = chestBoundingBox.insetBy(dx: -10, dy: -10)
                    if paddedBox.contains(location) {
                        clickOnChest = true
                        print("✅ Click within bounding box for chest: bbox=\(chestBoundingBox), padded=\(paddedBox), click=\(location)")
                    }
                    
                    // Also check collision box as fallback
                    if !clickOnChest {
                        if let collisionBox = getChestCollisionBox(node: node) {
                            let paddedBox = collisionBox.insetBy(dx: -20, dy: -20)
                            if paddedBox.contains(location) {
                                clickOnChest = true
                                print("✅ Click within collision box for chest: collisionBox=\(collisionBox), padded=\(paddedBox), click=\(location)")
                            }
                        }
                    }
                    
                    if clickOnChest {
                        foundChest = node
                        return  // Stop searching
                    }
                }
                return  // Found container, don't search children
            }
            
            // Also check userData for chest identification
            if let userData = node.userData, userData["entityType"] as? String == "chest" {
                if !checkedContainers.contains(node) {
                    checkedContainers.insert(node)
                    
                    // Check if click is on any of the chest's visual tiles (sprites)
                    var clickOnChest = false
                    
                    // PRIORITY 1: Check bounding box first (most reliable, accounts for all visual elements)
                    let chestBoundingBox = calculateBoundingBox(for: node)
                    if chestBoundingBox.width > 0 && chestBoundingBox.height > 0 {
                        // Add padding for easier clicking
                        let paddedBox = chestBoundingBox.insetBy(dx: -10, dy: -10)
                        if paddedBox.contains(location) {
                            clickOnChest = true
                            print("✅ Click within bounding box for chest (by userData): bbox=\(chestBoundingBox), padded=\(paddedBox), click=\(location)")
                        }
                    }
                    
                    // PRIORITY 2: Check collision box as fallback
                    if !clickOnChest {
                        if let collisionBox = getChestCollisionBox(node: node) {
                            let paddedBox = collisionBox.insetBy(dx: -20, dy: -20)
                            if paddedBox.contains(location) {
                                clickOnChest = true
                                print("✅ Click within collision box for chest (by userData): collisionBox=\(collisionBox), padded=\(paddedBox), click=\(location)")
                            }
                        }
                    }
                    
                    if clickOnChest {
                        foundChest = node
                        return  // Stop searching
                    }
                }
                return
            }
            
            // Recursively search children (only if we haven't found a chest yet)
            if foundChest == nil {
                for child in node.children {
                    findAllChestContainers(in: child)
                    if foundChest != nil {
                        return  // Stop searching
                    }
                }
            }
        }
        
        // Search all touched nodes and their descendants (fallback)
        for node in touchedNodes {
            findAllChestContainers(in: node)
            if let chest = foundChest {
                print("✅ GameScene: Found chest node via bounding box search: \(chest.name ?? "unnamed")")
                handleChestClick(node: chest, worldPosition: location)
                return
            }
        }
        
        print("🔍 GameScene: No chest found in clicked nodes")
        
    }
    
    /// Calculate bounding box for a node and all its children (optimized)
    /// Returns frame in scene coordinates
    func calculateBoundingBox(for node: SKNode) -> CGRect {
        // First try to get the accumulated frame directly (fastest)
        let accumulatedFrame = node.calculateAccumulatedFrame()
        
        // If the node has a reasonable frame, use it
        if accumulatedFrame.width > 0 && accumulatedFrame.height > 0 {
            return accumulatedFrame
        }
        
        // Fallback: check direct children only (not all descendants)
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        for child in node.children {
            if let sprite = child as? SKSpriteNode {
                let spriteFrame = sprite.calculateAccumulatedFrame()
                minX = min(minX, spriteFrame.minX)
                minY = min(minY, spriteFrame.minY)
                maxX = max(maxX, spriteFrame.maxX)
                maxY = max(maxY, spriteFrame.maxY)
            }
        }
        
        // If no sprites found, use node's own frame
        if minX == CGFloat.infinity {
            return accumulatedFrame
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Handle chest click - walk to chest and open it
    /// Find the chest container node from a clicked node
    private func findChestContainerNode(from node: SKNode) -> SKNode? {
        // Check this node first
        if let name = node.name, name.hasPrefix("chest_entity_"),
           let userData = node.userData, userData["position"] != nil {
            return node  // This is the container with position data
        }
        
        // Check children
        for child in node.children {
            if let childName = child.name, childName.hasPrefix("chest_entity_"),
               let childUserData = child.userData, childUserData["position"] != nil {
                return child  // Child is the container
            }
        }
        
        // Check parent chain (up to 5 levels to find container)
        var currentNode: SKNode? = node.parent
        var depth = 0
        while let current = currentNode, depth < 5 {
            if let name = current.name, name.hasPrefix("chest_entity_"),
               let userData = current.userData, userData["position"] != nil {
                return current  // Parent is the container
            }
            currentNode = current.parent
            depth += 1
        }
        
        // Fallback: if we found a chest node but no position, return it anyway
        if let name = node.name, name.hasPrefix("chest_entity_") {
            return node
        }
        if let userData = node.userData, userData["entityType"] as? String == "chest" {
            return node
        }
        
        // Check children fallback
        for child in node.children {
            if let childName = child.name, childName.hasPrefix("chest_entity_") {
                return child
            }
            if let childUserData = child.userData, childUserData["entityType"] as? String == "chest" {
                return child
            }
        }
        
        // Check parent chain fallback
        currentNode = node.parent
        depth = 0
        while let current = currentNode, depth < 5 {
            if let name = current.name, name.hasPrefix("chest_entity_") {
                return current
            }
            if let userData = current.userData, userData["entityType"] as? String == "chest" {
                return current
            }
            currentNode = current.parent
            depth += 1
        }
        
        return nil
    }
    
    /// Find chest entity data (entity key, position, items) - used when chest is actually opened
    private func findChestEntityData(containerNode: SKNode, prefabId: String) -> (entityKey: EntityKey, position: CGPoint, items: [Item])? {
        guard let chunkManager = chunkManager else { return nil }
        
        // Get the actual chest position from userData
        var actualChestPosition: CGPoint
        if let userData = containerNode.userData,
           let positionValue = userData["position"] as? NSValue {
            actualChestPosition = positionValue.pointValue
        } else {
            // Fallback: calculate from node hierarchy
            actualChestPosition = containerNode.convert(CGPoint.zero, to: self)
        }
        
        // First, check if we already have this chest in chestSprites (fastest path)
        // Search by position since the node key might not match
        var entityKey: EntityKey?
        var matchedChestPosition: CGPoint?
        var cachedNode: SKNode?
        
        // Search chestSprites by position (more reliable than node identity)
        // Find the CLOSEST match, not just the first one within threshold
        var closestCacheDistance: CGFloat = CGFloat.greatestFiniteMagnitude
        let cacheMatchThreshold: CGFloat = 10.0  // Within 10 pixels (same chest)
        
        for (cachedChestNode, cachedData) in chestSprites {
            let positionDistance = sqrt(pow(cachedData.position.x - actualChestPosition.x, 2) + pow(cachedData.position.y - actualChestPosition.y, 2))
            if positionDistance < cacheMatchThreshold && positionDistance < closestCacheDistance {
                // Found closer matching chest by position
                closestCacheDistance = positionDistance
                entityKey = cachedData.entityKey
                matchedChestPosition = cachedData.position
                cachedNode = cachedChestNode
            }
        }
        
        // If we found a cached entry but the node doesn't match, update the cache key
        if let cached = cachedNode, cached !== containerNode {
            chestSprites[containerNode] = chestSprites[cached]!
            chestSprites.removeValue(forKey: cached)
        }
        
        if entityKey == nil {
            // Need to find the chest entity key by searching chunks
            let chestPosition = actualChestPosition
        
        // Find which chunk this chest is in and get its entity key
        let chunkKey = ChunkKey.fromWorldPosition(chestPosition, chunkSize: ChunkManager.defaultChunkSize, tileSize: 32.0)
        guard let chunkData = chunkManager.getChunk(chunkKey) else {
                return nil
        }
        
            // Find the chest entity in the chunk (match by position and prefab ID)
            // CRITICAL: Find the CLOSEST chest, not just the first one within threshold
        var chestEntityKey: EntityKey? = nil
            var foundPosition = chestPosition
            var closestDistance: CGFloat = CGFloat.greatestFiniteMagnitude
            let maxDistance: CGFloat = 16.0  // Half a tile - chests should be at exact positions
            
        for (index, entity) in chunkData.entitiesBelow.enumerated() {
            if entity.type == .chest && entity.prefabId == prefabId {
                let distance = sqrt(pow(entity.position.x - chestPosition.x, 2) + pow(entity.position.y - chestPosition.y, 2))
                    if distance < maxDistance && distance < closestDistance {
                        closestDistance = distance
                    chestEntityKey = EntityKey(chunkKey: chunkKey, entityIndex: index)
                        foundPosition = entity.position
                    }
                }
            }
            
            guard let foundEntityKey = chestEntityKey else {
                return nil
            }
            
            entityKey = foundEntityKey
            matchedChestPosition = foundPosition
        }
        
        guard let finalEntityKey = entityKey, let finalPosition = matchedChestPosition else {
            return nil
        }
        
        // Get chest contents (generate if not already stored)
        let chunkKey = finalEntityKey.chunkKey
        guard let chunkData = chunkManager.getChunk(chunkKey) else {
            return nil
        }
        
        var chestItems = chunkData.chestContents[finalEntityKey] ?? []
        if chestItems.isEmpty {
            // Generate contents if not already generated
            if let chestPrefab = PrefabFactory.shared.getChestPrefab(prefabId) {
            chestItems = PrefabFactory.shared.generateChestLoot(for: chestPrefab)
                chunkData.chestContents[finalEntityKey] = chestItems
            }
        }
        
        // Store chest data for later use (if not already stored)
        if chestSprites[containerNode] == nil {
            chestSprites[containerNode] = (entityKey: finalEntityKey, prefabId: prefabId, position: finalPosition)
        }
        chestContents[finalEntityKey] = chestItems
        
        return (entityKey: finalEntityKey, position: finalPosition, items: chestItems)
    }
    
    func handleChestClick(node: SKNode, worldPosition: CGPoint) {
        guard let player = gameState?.player else { return }
        
        // Normalize to container node
        guard let containerNode = findChestContainerNode(from: node) else {
            print("⚠️ GameScene: Could not find chest container node from clicked node")
            return
        }
        
        // Get chest prefab ID from userData
        guard let userData = containerNode.userData,
              let prefabId = userData["prefabId"] as? String,
              let chestPrefab = PrefabFactory.shared.getChestPrefab(prefabId) else {
            print("⚠️ GameScene: Could not find chest prefab for clicked chest")
            return
        }
        
        // Get the chest's target position for auto-walk
        // Use the center of the bounding box (visual area) as the target, not the collision box
        // This ensures the player walks to where they can see and interact with the chest
        let chestTargetPosition: CGPoint
        let chestBoundingBox = calculateBoundingBox(for: containerNode)
        if chestBoundingBox.width > 0 && chestBoundingBox.height > 0 {
            // Use the center of the visual bounding box
            chestTargetPosition = CGPoint(x: chestBoundingBox.midX, y: chestBoundingBox.midY)
        } else if let collisionBox = getChestCollisionBox(node: containerNode) {
            // Fallback: use the center of the collision box
            chestTargetPosition = CGPoint(x: collisionBox.midX, y: collisionBox.midY)
        } else {
            // Final fallback: use entity position from userData
            if let positionValue = userData["position"] as? NSValue {
                chestTargetPosition = positionValue.pointValue
            } else {
                // Last resort: convert container node's position to scene coordinates
                chestTargetPosition = containerNode.convert(CGPoint.zero, to: self)
            }
        }
        
        // Calculate interaction radius based on chest visual size (not collision box)
        // Use the larger dimension of the visual bounding box for more accurate sizing
        // Smaller chests get proportionally smaller interaction distances
        let maxVisualDimension = max(chestBoundingBox.width, chestBoundingBox.height)
        // Use 0.8x the max visual dimension, with a minimum of 12 and maximum of 80
        // This gives smaller chests much closer interaction distances
        let interactionRadius = max(12.0, min(80.0, maxVisualDimension * 0.8))
        print("📦 Chest interaction radius: visualSize=(\(chestBoundingBox.width), \(chestBoundingBox.height)), maxDim=\(maxVisualDimension), radius=\(interactionRadius)")
        
        // Use generic auto-walk - the chest-specific logic (finding entity, getting items) 
        // will be done when we actually reach the chest (in the completion handler)
        // The targetNode ensures we stop when colliding with the chest, not when reaching the position
        autoWalkTo(target: chestTargetPosition, targetNode: containerNode, interactionRadius: interactionRadius) { [weak self] in
            guard let self = self, let chunkManager = self.chunkManager else { return }
            
            // Now that we've reached the chest, find the entity data and open it
            if let chestData = self.findChestEntityData(containerNode: containerNode, prefabId: prefabId) {
                self.openChest(prefab: chestPrefab, items: chestData.items, entityKey: chestData.entityKey)
            } else {
                print("⚠️ GameScene: Could not find chest entity data when opening chest")
            }
        }
    }
    
    /// Generic auto-walk method - walks player to a target position with obstacle avoidance
    /// - Parameters:
    ///   - target: Target position to walk to
    ///   - targetNode: Optional target node for collision-based completion (e.g., chest). If provided, completion is based on collision box intersection.
    ///   - interactionRadius: Distance from target to trigger completion (default: 64.0 = 2 tiles). Only used if targetNode is nil.
    ///   - completion: Optional callback when player reaches target
    func autoWalkTo(target: CGPoint, targetNode: SKNode? = nil, interactionRadius: CGFloat = 64.0, completion: (() -> Void)? = nil) {
        guard let player = gameState?.player else { return }
        
        // If we have a target node, check collision immediately
        if let targetNode = targetNode {
            let playerFrame = getPlayerCollisionFrame(at: player.position)
            
            // Use prefab collision box if this is a chest, otherwise use calculated bounding box
            let targetBoundingBox: CGRect
            if let chestCollisionBox = getChestCollisionBox(node: targetNode) {
                targetBoundingBox = chestCollisionBox
                print("🚶‍♂️ Auto-walk start: Using chest collision box: \(targetBoundingBox)")
        } else {
                targetBoundingBox = calculateBoundingBox(for: targetNode)
                print("🚶‍♂️ Auto-walk start: Using calculated bounding box: \(targetBoundingBox)")
            }
            
            print("🚶‍♂️ Auto-walk start: Player frame: \(playerFrame) at \(player.position)")
            
            if playerFrame.intersects(targetBoundingBox) {
                // Already colliding, call completion immediately
                print("✅ Auto-walk start: Already colliding with target, calling completion immediately")
                if let completion = completion {
                    completion()
                }
                return
            }
        } else {
            // Fallback to distance check
            let distance = sqrt(pow(target.x - player.position.x, 2) + pow(target.y - player.position.y, 2))
            if distance <= interactionRadius {
                // Already close enough, call completion immediately
                print("✅ Auto-walk start: Already within interaction radius, calling completion immediately")
                if let completion = completion {
                    completion()
                }
                return
            }
        }
        
        // Reset auto-walk state
        autoWalkLastPosition = nil
        autoWalkStuckCounter = 0
        autoWalkLastDirection = CGPoint.zero
        autoWalkObstacleAvoidance = nil
        
        // Initialize animation state for auto-walk
        // Note: animationTimer will be initialized in update() loop with currentTime
        currentAnimationFrame = 0
        animationTimer = -1  // Use -1 as sentinel value to indicate it needs initialization
        isMoving = true  // Ensure moving flag is set
        
        // Start auto-walking
        autoWalkTarget = target
        autoWalkTargetNode = targetNode
        autoWalkInteractionRadius = interactionRadius
        isAutoWalking = true
        autoWalkCompletion = completion
        
        print("🚶‍♂️ GameScene: Starting auto-walk to target: \(target), radius: \(interactionRadius)")
    }
    
    /// Open chest UI
    private func openChest(prefab: ChestPrefab, items: [Item], entityKey: EntityKey) {
        guard let chestUI = chestUI else { return }
        chestUI.show(chest: prefab, items: items, entityKey: entityKey)
        // Note: lastOpenedChestNode is set in handleChestClick, and will be reset when chest UI closes
    }
    
    /// Collect an object and add it to player inventory (called from collision detection)
    func collectObject(_ object: TiledObject, sprite: SKSpriteNode) {
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
    
    /// Handle chest UI button interactions
    func handleChestUIInteraction(at location: CGPoint) {
        guard let camera = cameraNode, let chestUI = chestUI else { return }
        let touchedNodes = nodes(at: location)
        
        for node in touchedNodes {
            if let name = node.name {
                if name == "chestClose" {
                    // Clear any auto-walk state before closing UI to prevent unwanted movement
                    clearAutoWalkState()
                    
                    chestUI.hide()
                    lastOpenedChestNode = nil  // Reset so player can open chests again
                    return
                } else if name == "chestTakeAll" {
                    takeAllItemsFromChest()
                    return
                } else if name == "chestTakeSelected" {
                    takeSelectedItemsFromChest()
                    return
                } else if name.hasPrefix("chestSlot_") {
                    // Toggle item selection
                    let slotIndexString = String(name.dropFirst("chestSlot_".count))
                    if let slotIndex = Int(slotIndexString) {
                        chestUI.toggleItemSelection(at: slotIndex)
                    }
                    return
                }
            }
        }
    }
    
    /// Take all items from chest
    private func takeAllItemsFromChest() {
        guard let chestUI = chestUI, let player = gameState?.player, let entityKey = chestUI.chestEntityKey else { return }
        
        let items = chestUI.items
        
        if items.isEmpty {
            showMessage("Chest is empty")
            clearAutoWalkState()
            chestUI.hide()
            lastOpenedChestNode = nil  // Reset so player can open chests again
            return
        }
        
        // Add all items to player inventory
        for item in items {
            player.inventory.append(item)
        }
        
        // Clear chest contents
        chestUI.items.removeAll()
        chestContents[entityKey] = []
        
        // Update chunk data
        if let chunkManager = chunkManager {
            let chunkKey = entityKey.chunkKey
            if let chunkData = chunkManager.getChunk(chunkKey) {
                chunkData.chestContents[entityKey] = []
            }
        }
        
        // Close chest UI
        clearAutoWalkState()
        chestUI.hide()
        lastOpenedChestNode = nil  // Reset so player can open chests again
        
        showMessage("Took all \(items.count) item(s) from chest")
    }
    
    /// Take selected items from chest
    private func takeSelectedItemsFromChest() {
        guard let chestUI = chestUI, let player = gameState?.player, let entityKey = chestUI.chestEntityKey else { return }
        
        let selectedIndices = Array(chestUI.selectedItems).sorted(by: >)  // Sort descending to remove from end first
        guard !selectedIndices.isEmpty else {
            showMessage("No items selected")
            return
        }
        
        // Add selected items to player inventory and remove from chest
        var itemsTaken: [Item] = []
        for index in selectedIndices {
            guard index < chestUI.items.count else { continue }
            let item = chestUI.items[index]
            player.inventory.append(item)
            itemsTaken.append(item)
            chestUI.items.remove(at: index)
        }
        
        // Clear selection
        chestUI.selectedItems.removeAll()
        
        // Update chest contents
        chestContents[entityKey] = chestUI.items
        
        // Update chunk data
        if let chunkManager = chunkManager {
            let chunkKey = entityKey.chunkKey
            if let chunkData = chunkManager.getChunk(chunkKey) {
                chunkData.chestContents[entityKey] = chestUI.items
            }
        }
        
        // Refresh chest UI if there are still items, otherwise close
        if chestUI.items.isEmpty {
            clearAutoWalkState()
            chestUI.hide()
            lastOpenedChestNode = nil  // Reset so player can open chests again
            showMessage("Took \(itemsTaken.count) item(s) from chest. Chest is now empty.")
        } else {
            // Refresh UI to update item positions after removal
            if let prefabId = chestSprites.first(where: { $0.value.entityKey == entityKey })?.value.prefabId,
               let chestPrefab = PrefabFactory.shared.getChestPrefab(prefabId) {
                chestUI.hide()
                chestUI.show(chest: chestPrefab, items: chestUI.items, entityKey: entityKey)
                // Don't reset lastOpenedChestNode here since we're just refreshing the UI
            }
            showMessage("Took \(itemsTaken.count) item(s) from chest")
        }
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
    func showMessage(_ message: String, color: SKColor = .white) {
        guard let camera = cameraNode else { 
            print("⚠️ GameScene: showMessage - no camera node")
            return 
        }
        
        print("📢 GameScene: showMessage called - '\(message)', color: \(color)")
        
        // Remove any existing message
        camera.childNode(withName: "messageLabel")?.removeFromParent()
        
        let messageLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        messageLabel.text = message
        messageLabel.fontSize = 24
        messageLabel.fontColor = color
        messageLabel.position = CGPoint(x: 0, y: size.height * 0.3)
        messageLabel.zPosition = 10000  // Very high zPosition to appear above all UI
        messageLabel.name = "messageLabel"
        messageLabel.horizontalAlignmentMode = .center
        
        // Add background
        let background = SKShapeNode(rectOf: CGSize(width: messageLabel.frame.width + 40, height: messageLabel.frame.height + 20), cornerRadius: 8)
        background.fillColor = SKColor(white: 0, alpha: 0.7)
        background.strokeColor = color
        background.lineWidth = 2
        background.position = CGPoint(x: 0, y: 0)
        background.zPosition = -1
        messageLabel.insertChild(background, at: 0)
        
        camera.addChild(messageLabel)
        print("✅ GameScene: Message label added to camera at position \(messageLabel.position), zPosition: \(messageLabel.zPosition)")
        
        // Animate message appearance and fade out
        messageLabel.alpha = 0
        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 3.0)  // Increased to 3 seconds
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        messageLabel.run(SKAction.sequence([fadeIn, wait, fadeOut, remove]))
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
    
}
