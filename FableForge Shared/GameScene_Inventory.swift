//
//  GameScene_Inventory.swift
//  FableForge Shared
//
//  Inventory and chest management functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    // MARK: - Inventory Display
    
    func showInventory() {
        // Close CharacterUI if open
        characterUI?.hide()
        
        // Close other UIs
        closeAllUIPanels()
        
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
        panel.zPosition = 2000 // Same as CharacterUI and BuildUI to ensure it appears above nameplate (1000)
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
        menu.zPosition = 5000 // Above inventory panel (2000) and BuildUI (2001), but below messages (10000)
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
        panel.zPosition = 5000 // Above inventory panel (2000) and BuildUI (2001), but below messages (10000)
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
    

}
