//
//  ChestUI.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/8/26.
//

import Foundation
import SpriteKit

class ChestUI {
    weak var scene: SKScene?
    weak var camera: SKCameraNode?
    var items: [Item] = []
    var chestEntityKey: EntityKey?
    
    var isVisible: Bool = false
    
    // UI Nodes
    var backgroundPanel: SKNode?
    var itemSlots: [SKNode] = []
    var selectedItems: Set<Int> = []  // Track which items are selected
    
    init(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
    }
    
    func show(chest: ChestPrefab, items: [Item], entityKey: EntityKey) {
        guard !isVisible else { return }
        
        self.items = items
        self.chestEntityKey = entityKey
        
        // Close all other UIs
        if let gameScene = scene as? GameScene {
            gameScene.closeAllUIPanels()
            gameScene.characterUI?.hide()
            gameScene.isGamePaused = true
        }
        
        isVisible = true
        setupUI(chestName: chest.name)
    }
    
    func hide() {
        guard isVisible else { return }
        isVisible = false
        cleanup()
        
        if let gameScene = scene as? GameScene {
            gameScene.isGamePaused = false
        }
    }
    
    private func setupUI(chestName: String) {
        guard let scene = scene, let camera = camera else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Panel dimensions
        let panelWidth = min(viewSize.width * 0.9, isLandscape ? 800 : 600)
        let panelHeight = min(viewSize.height * 0.8, isLandscape ? 600 : 700)
        
        // Create background panel
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 16)
        panel.fillColor = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(red: 0.7, green: 0.6, blue: 0.4, alpha: 1.0)
        panel.lineWidth = 4
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = 2000
        panel.name = "chestPanel"
        camera.addChild(panel)
        backgroundPanel = panel
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panelWidth * 0.95, height: 55), cornerRadius: 10)
        titleBg.fillColor = SKColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 0.95)
        titleBg.strokeColor = SKColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 1.0)
        titleBg.lineWidth = 3
        titleBg.position = CGPoint(x: 0, y: panelHeight / 2 - 35)
        panel.addChild(titleBg)
        
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "\(chestName) - Contents"
        title.fontSize = 32
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 0)
        title.verticalAlignmentMode = .center
        title.zPosition = 1
        titleBg.addChild(title)
        
        // Item slots configuration
        let slotsPerRow = isLandscape ? 8 : 6
        let numRows = isLandscape ? 6 : 8
        
        let slotSize: CGFloat = isLandscape ? 60 : 50
        let slotSpacing: CGFloat = 10
        let slotsAreaWidth = CGFloat(slotsPerRow) * slotSize + CGFloat(slotsPerRow - 1) * slotSpacing
        let slotsAreaHeight = CGFloat(numRows) * slotSize + CGFloat(numRows - 1) * slotSpacing
        
        // Slots container background
        let slotsBg = SKShapeNode(rectOf: CGSize(width: slotsAreaWidth + 30, height: slotsAreaHeight + 30), cornerRadius: 10)
        slotsBg.fillColor = SKColor(white: 0.08, alpha: 0.95)
        slotsBg.strokeColor = SKColor(white: 0.4, alpha: 0.8)
        slotsBg.lineWidth = 2
        slotsBg.position = CGPoint(x: 0, y: 20)
        panel.addChild(slotsBg)
        
        // Create item slots
        let startX = -slotsAreaWidth / 2 + slotSize / 2
        let startY = slotsAreaHeight / 2 - slotSize / 2
        
        for row in 0..<numRows {
            for col in 0..<slotsPerRow {
                let slotIndex = row * slotsPerRow + col
                
                let x = startX + CGFloat(col) * (slotSize + slotSpacing)
                let y = startY - CGFloat(row) * (slotSize + slotSpacing)
                
                // Create slot background
                let slotBg = SKShapeNode(rectOf: CGSize(width: slotSize, height: slotSize), cornerRadius: 6)
                slotBg.fillColor = SKColor(white: 0.25, alpha: 0.9)
                slotBg.strokeColor = SKColor(white: 0.6, alpha: 0.8)
                slotBg.lineWidth = 2
                slotBg.position = CGPoint(x: x, y: y)
                slotBg.name = "chestSlot_\(slotIndex)"
                slotBg.zPosition = 1
                slotsBg.addChild(slotBg)
                itemSlots.append(slotBg)
                
                // Display item if available
                if slotIndex < items.count {
                    let item = items[slotIndex]
                    displayItem(item: item, in: slotBg, slotIndex: slotIndex, slotSize: slotSize)
                }
            }
        }
        
        // Button area at bottom
        let buttonY = -panelHeight / 2 + 80
        
        // Take All button
        let takeAllButton = SKShapeNode(rectOf: CGSize(width: 180, height: 55), cornerRadius: 10)
        takeAllButton.fillColor = SKColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)
        takeAllButton.strokeColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0)
        takeAllButton.lineWidth = 3
        takeAllButton.position = CGPoint(x: isLandscape ? -100 : 0, y: buttonY)
        takeAllButton.name = "chestTakeAll"
        takeAllButton.zPosition = 10
        
        let takeAllLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        takeAllLabel.text = "Take All"
        takeAllLabel.fontSize = 22
        takeAllLabel.fontColor = .white
        takeAllLabel.verticalAlignmentMode = .center
        takeAllLabel.zPosition = 1
        takeAllButton.addChild(takeAllLabel)
        panel.addChild(takeAllButton)
        
        // Take Selected button
        let takeSelectedButton = SKShapeNode(rectOf: CGSize(width: 180, height: 55), cornerRadius: 10)
        takeSelectedButton.fillColor = SKColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0)
        takeSelectedButton.strokeColor = SKColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0)
        takeSelectedButton.lineWidth = 3
        takeSelectedButton.position = CGPoint(x: isLandscape ? 100 : 0, y: buttonY - (isLandscape ? 0 : 70))
        takeSelectedButton.name = "chestTakeSelected"
        takeSelectedButton.zPosition = 10
        
        let takeSelectedLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        takeSelectedLabel.text = "Take Selected"
        takeSelectedLabel.fontSize = 22
        takeSelectedLabel.fontColor = .white
        takeSelectedLabel.verticalAlignmentMode = .center
        takeSelectedLabel.zPosition = 1
        takeSelectedButton.addChild(takeSelectedLabel)
        panel.addChild(takeSelectedButton)
        
        // Close button
        let closeButton = SKShapeNode(rectOf: CGSize(width: 140, height: 55), cornerRadius: 10)
        closeButton.fillColor = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1.0)
        closeButton.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        closeButton.lineWidth = 3
        closeButton.position = CGPoint(x: 0, y: buttonY - (isLandscape ? 70 : 140))
        closeButton.name = "chestClose"
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
    
    private func displayItem(item: Item, in slot: SKShapeNode, slotIndex: Int, slotSize: CGFloat) {
        let itemContainer = SKNode()
        itemContainer.name = "chestItem_\(slotIndex)"
        itemContainer.position = CGPoint(x: 0, y: 0)
        itemContainer.zPosition = 2
        slot.addChild(itemContainer)
        
        // Create item sprite from GID if available
        if let gid = item.gid {
            let itemSize = CGSize(width: slotSize * 0.8, height: slotSize * 0.8)
            if let itemSprite = TileManager.shared.createSprite(for: gid, size: itemSize) {
                itemSprite.position = CGPoint(x: 0, y: 0)
                itemSprite.zPosition = 1
                itemSprite.name = "chestItemSprite_\(slotIndex)"
                itemContainer.addChild(itemSprite)
            }
        } else {
            // Fallback: colored square with item name
            let fallbackSprite = SKSpriteNode(color: SKColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 0.8), size: CGSize(width: slotSize * 0.7, height: slotSize * 0.7))
            fallbackSprite.position = CGPoint(x: 0, y: 0)
            fallbackSprite.zPosition = 1
            itemContainer.addChild(fallbackSprite)
            
            let nameLabel = SKLabelNode(fontNamed: "Arial")
            nameLabel.text = String(item.name.prefix(4))
            nameLabel.fontSize = 8
            nameLabel.fontColor = .white
            nameLabel.position = CGPoint(x: 0, y: 0)
            nameLabel.verticalAlignmentMode = .center
            nameLabel.zPosition = 2
            itemContainer.addChild(nameLabel)
        }
        
        // Show quantity if > 1
        if item.quantity > 1 {
            let quantityBg = SKShapeNode(rectOf: CGSize(width: 24, height: 18), cornerRadius: 4)
            quantityBg.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.85)
            quantityBg.strokeColor = SKColor(white: 0.9, alpha: 1.0)
            quantityBg.lineWidth = 1.5
            quantityBg.position = CGPoint(x: slotSize / 2 - 14, y: -slotSize / 2 + 12)
            quantityBg.zPosition = 4
            itemContainer.addChild(quantityBg)
            
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
        
        // Selection indicator (initially hidden)
        let selectionIndicator = SKShapeNode(rectOf: CGSize(width: slotSize - 4, height: slotSize - 4), cornerRadius: 4)
        selectionIndicator.fillColor = .clear
        selectionIndicator.strokeColor = SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        selectionIndicator.lineWidth = 3
        selectionIndicator.position = CGPoint(x: 0, y: 0)
        selectionIndicator.name = "chestSelection_\(slotIndex)"
        selectionIndicator.zPosition = 10
        selectionIndicator.isHidden = true
        slot.addChild(selectionIndicator)
    }
    
    func toggleItemSelection(at slotIndex: Int) {
        if selectedItems.contains(slotIndex) {
            selectedItems.remove(slotIndex)
        } else {
            selectedItems.insert(slotIndex)
        }
        
        // Update visual indicator
        if let slot = itemSlots.first(where: { $0.name == "chestSlot_\(slotIndex)" }),
           let indicator = slot.childNode(withName: "chestSelection_\(slotIndex)") as? SKShapeNode {
            indicator.isHidden = !selectedItems.contains(slotIndex)
        }
    }
    
    func getSelectedItems() -> [Item] {
        return selectedItems.compactMap { index in
            guard index < items.count else { return nil }
            return items[index]
        }
    }
    
    private func cleanup() {
        backgroundPanel?.removeFromParent()
        backgroundPanel = nil
        itemSlots.removeAll()
        selectedItems.removeAll()
    }
    
    private func getViewSize() -> CGSize {
        guard let scene = scene else { return CGSize(width: 1024, height: 768) }
        if let view = scene.view {
            return view.bounds.size
        }
        return scene.size
    }
}
