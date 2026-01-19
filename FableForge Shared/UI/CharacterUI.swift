//
//  CharacterUI.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/8/26.
//

import Foundation
import SpriteKit

enum CharacterUITab {
    case equipment
    case skills
    case attributes
    case companions
}

class CharacterUI {
    weak var scene: SKScene?
    weak var camera: SKCameraNode?
    var player: Player?
    
    var isVisible: Bool = false
    var currentTab: CharacterUITab = .equipment
    
    // UI Nodes
    var backgroundPanel: SKNode?
    var tabButtons: [SKNode] = []
    var contentContainer: SKNode?
    
    init(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
    }
    
    func show(player: Player) {
        guard !isVisible else { return }
        self.player = player
        
        // Close all other UIs BEFORE setting isVisible and setting up UI
        // Use GameScene's closeAllUIPanels if available, otherwise use our own
        if let gameScene = scene as? GameScene {
            // Close all panels first
            gameScene.closeAllUIPanels()
            // Small delay to ensure panels are fully removed before we continue
            // This prevents any race conditions where panels might be recreated
        }
        // Also use our own method as backup to ensure everything is closed
        closeAllOtherUIs()
        
        // Set visible flag and setup UI
        isVisible = true
        setupUI()
        
        // Final check - make sure inventory and other panels are still closed after setup
        // (in case something recreated them during setup)
        if let gameScene = scene as? GameScene {
            gameScene.closeAllUIPanels()
        }
        closeAllOtherUIs()
        
        // Notify scene to pause game
        if let gameScene = scene as? GameScene {
            gameScene.isGamePaused = true
        }
    }
    
    private func closeAllOtherUIs() {
        guard let camera = camera else { return }
        
        // Recursively find and remove all UI panels
        func removeAllPanels(in node: SKNode) {
            let panelNames = [
                "inventoryPanel",
                "buildPanel",
                "settingsPanel",
                "saveSlotPanel",
                "loadSlotPanel",
                "inventoryContextMenu",
                "itemInspectPanel"
            ]
            
            for panelName in panelNames {
                if node.name == panelName {
                    node.removeFromParent()
                    return
                }
            }
            
            // Recursively search children
            for child in node.children {
                removeAllPanels(in: child)
            }
        }
        
        // Search recursively through camera's children
        removeAllPanels(in: camera)
        
        // Also use direct search as fallback
        let panelNames = [
            "inventoryPanel",
            "buildPanel",
            "settingsPanel",
            "saveSlotPanel",
            "loadSlotPanel",
            "inventoryContextMenu",
            "itemInspectPanel"
        ]
        
        for panelName in panelNames {
            // Try recursive search with // prefix
            if let panel = camera.childNode(withName: "//\(panelName)") {
                panel.removeFromParent()
            }
            // Try direct child search
            if let panel = camera.childNode(withName: panelName) {
                panel.removeFromParent()
            }
        }
    }
    
    func hide() {
        guard isVisible else { return }
        isVisible = false
        cleanup()
        // Notify scene to resume game
        if let gameScene = scene as? GameScene {
            gameScene.isGamePaused = false
        }
    }
    
    func toggle(player: Player) {
        if isVisible {
            hide()
        } else {
            show(player: player)
        }
    }
    
    private func setupUI() {
        guard let scene = scene, let camera = camera else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Create background panel - full screen
        let panelWidth = viewSize.width * 0.98
        let panelHeight = viewSize.height * 0.98
        let panel = MenuStyling.createBookPage(size: CGSize(width: panelWidth, height: panelHeight))
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = 2000
        panel.name = "characterUIPanel"
        camera.addChild(panel)
        backgroundPanel = panel
        
        // Title
        let titleY = panelHeight / 2 - 50
        let title = MenuStyling.createBookTitle(
            text: "Character",
            position: CGPoint(x: 0, y: titleY),
            fontSize: isLandscape ? 32 : 36
        )
        title.zPosition = 2001
        panel.addChild(title)
        
        // Tab buttons
        let tabY = titleY - 50
        let tabWidth: CGFloat = isLandscape ? 150 : 120
        let tabHeight: CGFloat = isLandscape ? 45 : 50
        let tabSpacing: CGFloat = 10
        
        let tabs: [(CharacterUITab, String)] = [
            (.equipment, "Equipment"),
            (.skills, "Skills"),
            (.attributes, "Attributes"),
            (.companions, "Companions")
        ]
        
        let totalTabsWidth = CGFloat(tabs.count) * tabWidth + CGFloat(tabs.count - 1) * tabSpacing
        let startX = -totalTabsWidth / 2 + tabWidth / 2
        
        for (index, (tab, label)) in tabs.enumerated() {
            let xPos = startX + CGFloat(index) * (tabWidth + tabSpacing)
            let isSelected = tab == currentTab
            let button = createTabButton(
                text: label,
                position: CGPoint(x: xPos, y: tabY),
                size: CGSize(width: tabWidth, height: tabHeight),
                isSelected: isSelected,
                tab: tab
            )
            button.zPosition = 2001
            panel.addChild(button)
            tabButtons.append(button)
        }
        
        // Content container
        let contentY = tabY - tabHeight / 2 - 20
        let contentHeight = panelHeight - (titleY - contentY) - 40
        let contentContainer = SKNode()
        contentContainer.position = CGPoint(x: 0, y: contentY - contentHeight / 2)
        contentContainer.zPosition = 2001
        panel.addChild(contentContainer)
        self.contentContainer = contentContainer
        
        // Close button (top right)
        let closeButtonSize: CGFloat = isLandscape ? 40 : 45
        let closeButton = SKShapeNode(rectOf: CGSize(width: closeButtonSize, height: closeButtonSize), cornerRadius: 6)
        closeButton.fillColor = MenuStyling.bookDanger
        closeButton.strokeColor = MenuStyling.parchmentBorder
        closeButton.lineWidth = 2
        closeButton.position = CGPoint(x: panelWidth / 2 - closeButtonSize / 2 - 20, y: panelHeight / 2 - closeButtonSize / 2 - 20)
        closeButton.zPosition = 2002
        closeButton.name = "closeCharacterUI"
        panel.addChild(closeButton)
        
        let closeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        closeLabel.text = "×"
        closeLabel.fontSize = closeButtonSize * 0.6
        closeLabel.fontColor = MenuStyling.inkColor
        closeLabel.verticalAlignmentMode = .center
        closeLabel.zPosition = 2003
        closeButton.addChild(closeLabel)
        
        // Show initial tab content
        updateTabContent()
    }
    
    private func createTabButton(text: String, position: CGPoint, size: CGSize, isSelected: Bool, tab: CharacterUITab) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "tabButton_\(text)"
        
        let button = SKShapeNode(rectOf: size, cornerRadius: 6)
        button.fillColor = isSelected ? MenuStyling.parchmentBg : MenuStyling.parchmentDark
        button.strokeColor = isSelected ? MenuStyling.bookAccent : MenuStyling.parchmentBorder
        button.lineWidth = isSelected ? 3 : 2
        button.zPosition = 1
        container.addChild(button)
        
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = size.height * 0.4
        label.fontColor = MenuStyling.inkColor
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        button.addChild(label)
        
        // Store tab reference in userData
        container.userData = NSMutableDictionary()
        container.userData?["tab"] = tab
        
        return container
    }
    
    private func updateTabContent() {
        contentContainer?.removeAllChildren()
        
        switch currentTab {
        case .equipment:
            showEquipmentTab()
        case .skills:
            showSkillsTab()
        case .attributes:
            showAttributesTab()
        case .companions:
            showCompanionsTab()
        }
    }
    
    private func showEquipmentTab() {
        guard let contentContainer = contentContainer, let player = player else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Calculate available space for equipment layout
        let availableHeight = viewSize.height * 0.7 // Leave space for title and tabs
        let availableWidth = viewSize.width * 0.9
        
        // Calculate slot size to fit all equipment on screen
        // We have: Head, Neck, Chest, Hands, Legs, Feet, 2 Rings, 2 Weapons = 10 slots
        // Layout: 3 columns max, ~4 rows
        let maxSlotsPerRow: CGFloat = 3
        let estimatedRows: CGFloat = 4
        let slotSpacing: CGFloat = 10
        
        // Calculate optimal slot size
        let maxSlotWidth = (availableWidth - (maxSlotsPerRow - 1) * slotSpacing) / maxSlotsPerRow
        let maxSlotHeight = (availableHeight - (estimatedRows - 1) * slotSpacing) / estimatedRows
        let slotSize = min(maxSlotWidth, maxSlotHeight, isLandscape ? 90 : 75)
        
        // Equipment slots layout - more compact, centered
        let startY: CGFloat = availableHeight / 2 - 50
        let centerX: CGFloat = 0
        
        // Row 1: Head (center)
        createEquipmentSlot(
            name: "Head",
            position: CGPoint(x: centerX, y: startY),
            size: slotSize,
            item: player.equippedHead
        )
        
        // Row 2: Neck (center)
        let row2Y = startY - slotSize - slotSpacing
        createEquipmentSlot(
            name: "Neck",
            position: CGPoint(x: centerX, y: row2Y),
            size: slotSize,
            item: player.equippedNeck
        )
        
        // Row 3: Hands (left), Chest (center), Ring1 (right)
        let row3Y = row2Y - slotSize - slotSpacing
        createEquipmentSlot(
            name: "Hands",
            position: CGPoint(x: -(slotSize + slotSpacing), y: row3Y),
            size: slotSize,
            item: player.equippedHands
        )
        createEquipmentSlot(
            name: "Chest",
            position: CGPoint(x: centerX, y: row3Y),
            size: slotSize,
            item: player.equippedChest
        )
        createEquipmentSlot(
            name: "Ring1",
            position: CGPoint(x: slotSize + slotSpacing, y: row3Y),
            size: slotSize,
            item: player.equippedRing1
        )
        
        // Row 4: Legs (center)
        let row4Y = row3Y - slotSize - slotSpacing
        createEquipmentSlot(
            name: "Legs",
            position: CGPoint(x: centerX, y: row4Y),
            size: slotSize,
            item: player.equippedLegs
        )
        
        // Row 5: Feet (center)
        let row5Y = row4Y - slotSize - slotSpacing
        createEquipmentSlot(
            name: "Feet",
            position: CGPoint(x: centerX, y: row5Y),
            size: slotSize,
            item: player.equippedFeet
        )
        
        // Row 6: Ring1 (left), Ring2 (right)
        let row6Y = row5Y - slotSize - slotSpacing
        createEquipmentSlot(
            name: "Ring1",
            position: CGPoint(x: -(slotSize / 2 + slotSpacing / 2), y: row6Y),
            size: slotSize,
            item: player.equippedRing1
        )
        createEquipmentSlot(
            name: "Ring2",
            position: CGPoint(x: slotSize / 2 + slotSpacing / 2, y: row6Y),
            size: slotSize,
            item: player.equippedRing2
        )
        
        // Row 7: WeaponLeft (left), WeaponRight (right)
        let row7Y = row6Y - slotSize - slotSpacing
        createEquipmentSlot(
            name: "WeaponLeft",
            position: CGPoint(x: -(slotSize / 2 + slotSpacing / 2), y: row7Y),
            size: slotSize,
            item: player.equippedWeaponLeft
        )
        createEquipmentSlot(
            name: "WeaponRight",
            position: CGPoint(x: slotSize / 2 + slotSpacing / 2, y: row7Y),
            size: slotSize,
            item: player.equippedWeaponRight
        )
    }
    
    private func createEquipmentSlot(name: String, position: CGPoint, size: CGFloat, item: Item?) -> SKNode {
        guard let contentContainer = contentContainer else { return SKNode() }
        
        let container = SKNode()
        container.position = position
        container.name = "equipmentSlot_\(name)"
        
        // Slot background
        let slotBg = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: 6)
        slotBg.fillColor = MenuStyling.parchmentDark
        slotBg.strokeColor = MenuStyling.parchmentBorder
        slotBg.lineWidth = 2
        slotBg.zPosition = 1
        container.addChild(slotBg)
        
        // Item icon or placeholder
        if let item = item {
            let itemLabel = SKLabelNode(fontNamed: "Arial")
            itemLabel.text = item.name
            itemLabel.fontSize = min(size * 0.18, 14)
            itemLabel.fontColor = MenuStyling.inkColor
            itemLabel.verticalAlignmentMode = .center
            itemLabel.horizontalAlignmentMode = .center
            itemLabel.numberOfLines = 2
            itemLabel.preferredMaxLayoutWidth = size * 0.85
            itemLabel.zPosition = 2
            slotBg.addChild(itemLabel)
        } else {
            let placeholderLabel = SKLabelNode(fontNamed: "Arial")
            placeholderLabel.text = name
            placeholderLabel.fontSize = min(size * 0.22, 16)
            placeholderLabel.fontColor = MenuStyling.inkMuted
            placeholderLabel.verticalAlignmentMode = .center
            placeholderLabel.horizontalAlignmentMode = .center
            placeholderLabel.zPosition = 2
            slotBg.addChild(placeholderLabel)
        }
        
        contentContainer.addChild(container)
        return container
    }
    
    private func showSkillsTab() {
        guard let contentContainer = contentContainer, let player = player else { return }
        
        // Load skills from prefab
        guard let skillsPath = Bundle.main.path(forResource: "skills", ofType: "json", inDirectory: "Prefabs"),
              let skillsData = try? Data(contentsOf: URL(fileURLWithPath: skillsPath)),
              let skillsJson = try? JSONSerialization.jsonObject(with: skillsData) as? [String: Any],
              let skillsArray = skillsJson["skills"] as? [[String: Any]] else {
            // Show error message
            let errorLabel = SKLabelNode(fontNamed: "Arial")
            errorLabel.text = "Failed to load skills"
            errorLabel.fontColor = MenuStyling.inkColor
            errorLabel.position = CGPoint(x: 0, y: 0)
            contentContainer.addChild(errorLabel)
            return
        }
        
        // Filter skills available to player
        let availableSkills = skillsArray.filter { skillDict in
            guard let allowedOwners = skillDict["allowedOwners"] as? [String] else { return false }
            guard allowedOwners.contains("player") else { return false }
            
            // Check class requirement
            if let classes = skillDict["classes"] as? [String], !classes.isEmpty {
                return classes.contains(player.characterClass.rawValue.lowercased())
            }
            
            return true
        }
        
        // Display skills in a scrollable list
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        let skillHeight: CGFloat = isLandscape ? 60 : 70
        let skillSpacing: CGFloat = 10
        let startY: CGFloat = 150
        
        for (index, skillDict) in availableSkills.enumerated() {
            guard let skillId = skillDict["id"] as? String,
                  let skillName = skillDict["name"] as? String,
                  let skillDescription = skillDict["description"] as? String else { continue }
            
            let isLearned = player.learnedSkills.contains(skillId)
            let yPos = startY - CGFloat(index) * (skillHeight + skillSpacing)
            
            let skillNode = createSkillNode(
                id: skillId,
                name: skillName,
                description: skillDescription,
                position: CGPoint(x: 0, y: yPos),
                size: CGSize(width: isLandscape ? 500 : 400, height: skillHeight),
                isLearned: isLearned,
                canLearn: player.skillPoints > 0 && !isLearned
            )
            contentContainer.addChild(skillNode)
        }
        
        // Show skill points remaining
        let pointsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        pointsLabel.text = "Skill Points: \(player.skillPoints)"
        pointsLabel.fontSize = isLandscape ? 20 : 24
        pointsLabel.fontColor = MenuStyling.inkColor
        pointsLabel.position = CGPoint(x: 0, y: -250)
        pointsLabel.zPosition = 10
        contentContainer.addChild(pointsLabel)
    }
    
    private func createSkillNode(id: String, name: String, description: String, position: CGPoint, size: CGSize, isLearned: Bool, canLearn: Bool) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "skill_\(id)"
        
        // Background
        let bg = SKShapeNode(rectOf: size, cornerRadius: 6)
        bg.fillColor = isLearned ? MenuStyling.parchmentBg : MenuStyling.parchmentDark
        bg.strokeColor = MenuStyling.parchmentBorder
        bg.lineWidth = 2
        bg.zPosition = 1
        container.addChild(bg)
        
        // Skill name
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = name
        nameLabel.fontSize = size.height * 0.3
        nameLabel.fontColor = MenuStyling.inkColor
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .top
        nameLabel.position = CGPoint(x: -size.width / 2 + 10, y: size.height / 2 - 10)
        nameLabel.zPosition = 2
        bg.addChild(nameLabel)
        
        // Skill description
        let descLabel = SKLabelNode(fontNamed: "Arial")
        descLabel.text = description
        descLabel.fontSize = size.height * 0.2
        descLabel.fontColor = MenuStyling.inkMuted
        descLabel.horizontalAlignmentMode = .left
        descLabel.verticalAlignmentMode = .top
        descLabel.position = CGPoint(x: -size.width / 2 + 10, y: size.height / 2 - 35)
        descLabel.preferredMaxLayoutWidth = size.width - 100
        descLabel.numberOfLines = 0
        descLabel.zPosition = 2
        bg.addChild(descLabel)
        
        // Learn button or learned indicator
        if isLearned {
            let learnedLabel = SKLabelNode(fontNamed: "Arial")
            learnedLabel.text = "✓ Learned"
            learnedLabel.fontSize = size.height * 0.25
            learnedLabel.fontColor = MenuStyling.bookSecondary
            learnedLabel.horizontalAlignmentMode = .right
            learnedLabel.verticalAlignmentMode = .center
            learnedLabel.position = CGPoint(x: size.width / 2 - 10, y: 0)
            learnedLabel.zPosition = 2
            bg.addChild(learnedLabel)
        } else if canLearn {
            let learnButton = SKShapeNode(rectOf: CGSize(width: 80, height: size.height * 0.6), cornerRadius: 4)
            learnButton.fillColor = MenuStyling.bookSecondary
            learnButton.strokeColor = MenuStyling.parchmentBorder
            learnButton.lineWidth = 2
            learnButton.position = CGPoint(x: size.width / 2 - 50, y: 0)
            learnButton.zPosition = 2
            learnButton.name = "learnButton_\(id)"
            bg.addChild(learnButton)
            
            let buttonLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            buttonLabel.text = "Learn"
            buttonLabel.fontSize = size.height * 0.25
            buttonLabel.fontColor = MenuStyling.inkColor
            buttonLabel.verticalAlignmentMode = .center
            buttonLabel.zPosition = 3
            learnButton.addChild(buttonLabel)
        }
        
        // Store skill ID in userData
        container.userData = NSMutableDictionary()
        container.userData?["skillId"] = id
        
        return container
    }
    
    private func showAttributesTab() {
        guard let contentContainer = contentContainer, let player = player else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        let attrHeight: CGFloat = isLandscape ? 50 : 60
        let attrSpacing: CGFloat = 15
        let startY: CGFloat = 150
        
        let attributes: [(Ability, String)] = [
            (.strength, "Strength"),
            (.dexterity, "Dexterity"),
            (.intelligence, "Intelligence"),
            (.wisdom, "Wisdom"),
            (.charisma, "Charisma"),
            (.constitution, "Constitution")
        ]
        
        for (index, (ability, name)) in attributes.enumerated() {
            let yPos = startY - CGFloat(index) * (attrHeight + attrSpacing)
            let score = player.abilityScores.score(for: ability)
            let modifier = player.abilityScores.modifier(for: ability)
            
            let attrNode = createAttributeNode(
                ability: ability,
                name: name,
                score: score,
                modifier: modifier,
                position: CGPoint(x: 0, y: yPos),
                size: CGSize(width: isLandscape ? 500 : 400, height: attrHeight),
                canIncrease: player.attributePoints > 0 && score < 20
            )
            contentContainer.addChild(attrNode)
        }
        
        // Show attribute points remaining
        let pointsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        pointsLabel.text = "Attribute Points: \(player.attributePoints)"
        pointsLabel.fontSize = isLandscape ? 20 : 24
        pointsLabel.fontColor = MenuStyling.inkColor
        pointsLabel.position = CGPoint(x: 0, y: -250)
        pointsLabel.zPosition = 10
        contentContainer.addChild(pointsLabel)
    }
    
    private func createAttributeNode(ability: Ability, name: String, score: Int, modifier: Int, position: CGPoint, size: CGSize, canIncrease: Bool) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "attribute_\(ability.rawValue)"
        
        // Background
        let bg = SKShapeNode(rectOf: size, cornerRadius: 6)
        bg.fillColor = MenuStyling.parchmentBg
        bg.strokeColor = MenuStyling.parchmentBorder
        bg.lineWidth = 2
        bg.zPosition = 1
        container.addChild(bg)
        
        // Attribute name
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = name
        nameLabel.fontSize = size.height * 0.4
        nameLabel.fontColor = MenuStyling.inkColor
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: -size.width / 2 + 10, y: 0)
        nameLabel.zPosition = 2
        bg.addChild(nameLabel)
        
        // Score and modifier - position to the left to make room for buttons
        let scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.text = "\(score) (\(modifier >= 0 ? "+" : "")\(modifier))"
        scoreLabel.fontSize = size.height * 0.35
        scoreLabel.fontColor = MenuStyling.inkColor
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        // Position score label to the left of center to avoid button overlap
        scoreLabel.position = CGPoint(x: -size.width * 0.15, y: 0)
        scoreLabel.zPosition = 2
        bg.addChild(scoreLabel)
        
        // Increase button - positioned on the right, closer to edge with proper spacing
        if canIncrease {
            let buttonWidth: CGFloat = 45
            let buttonHeight: CGFloat = size.height * 0.7
            let rightMargin: CGFloat = 15
            
            let increaseButton = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 4)
            increaseButton.fillColor = MenuStyling.bookSecondary
            increaseButton.strokeColor = MenuStyling.parchmentBorder
            increaseButton.lineWidth = 2
            // Position button on the right with margin, ensuring it doesn't overlap with score text
            increaseButton.position = CGPoint(x: size.width / 2 - rightMargin - buttonWidth / 2, y: 0)
            increaseButton.zPosition = 2
            increaseButton.name = "increaseButton_\(ability.rawValue)"
            bg.addChild(increaseButton)
            
            let buttonLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            buttonLabel.text = "+"
            buttonLabel.fontSize = size.height * 0.5
            buttonLabel.fontColor = MenuStyling.inkColor
            buttonLabel.verticalAlignmentMode = .center
            buttonLabel.horizontalAlignmentMode = .center
            buttonLabel.zPosition = 3
            increaseButton.addChild(buttonLabel)
        }
        
        // Store ability in userData
        container.userData = NSMutableDictionary()
        container.userData?["ability"] = ability.rawValue
        
        return container
    }
    
    private func showCompanionsTab() {
        guard let contentContainer = contentContainer, let player = player else { return }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Get all companions
        let companions = player.companions
        
        if companions.isEmpty {
            // Show message if no companions
            let noCompanionsLabel = SKLabelNode(fontNamed: "Arial")
            noCompanionsLabel.text = "You have no companions yet."
            noCompanionsLabel.fontSize = isLandscape ? 24 : 28
            noCompanionsLabel.fontColor = MenuStyling.inkMuted
            noCompanionsLabel.position = CGPoint(x: 0, y: 0)
            noCompanionsLabel.zPosition = 10
            contentContainer.addChild(noCompanionsLabel)
            return
        }
        
        // Display companions in a scrollable list
        let companionHeight: CGFloat = isLandscape ? 80 : 90
        let companionSpacing: CGFloat = 15
        let startY: CGFloat = 150
        
        for (index, companion) in companions.enumerated() {
            let yPos = startY - CGFloat(index) * (companionHeight + companionSpacing)
            
            let companionNode = createCompanionNode(
                companion: companion,
                position: CGPoint(x: 0, y: yPos),
                size: CGSize(width: isLandscape ? 500 : 400, height: companionHeight)
            )
            contentContainer.addChild(companionNode)
        }
    }
    
    private func createCompanionNode(companion: Animal, position: CGPoint, size: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "companion_\(companion.id.uuidString)"
        
        // Background
        let bg = SKShapeNode(rectOf: size, cornerRadius: 6)
        bg.fillColor = MenuStyling.parchmentBg
        bg.strokeColor = MenuStyling.parchmentBorder
        bg.lineWidth = 2
        bg.zPosition = 1
        container.addChild(bg)
        
        // Companion name
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = companion.name
        nameLabel.fontSize = size.height * 0.3
        nameLabel.fontColor = MenuStyling.inkColor
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .top
        nameLabel.position = CGPoint(x: -size.width / 2 + 10, y: size.height / 2 - 10)
        nameLabel.zPosition = 2
        bg.addChild(nameLabel)
        
        // Level label
        let levelLabel = SKLabelNode(fontNamed: "Arial")
        levelLabel.text = "Level \(companion.level)"
        levelLabel.fontSize = size.height * 0.22
        levelLabel.fontColor = MenuStyling.inkMuted
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.verticalAlignmentMode = .top
        levelLabel.position = CGPoint(x: -size.width / 2 + 10, y: size.height / 2 - 35)
        levelLabel.zPosition = 2
        bg.addChild(levelLabel)
        
        // Health bar background
        let healthBarWidth = size.width - 40
        let healthBarHeight: CGFloat = 20
        let healthBarY = -size.height / 2 + 30
        
        let healthBarBg = SKShapeNode(rectOf: CGSize(width: healthBarWidth, height: healthBarHeight), cornerRadius: 4)
        healthBarBg.fillColor = SKColor(white: 0.3, alpha: 0.8)
        healthBarBg.strokeColor = MenuStyling.parchmentBorder
        healthBarBg.lineWidth = 1.5
        healthBarBg.position = CGPoint(x: 0, y: healthBarY)
        healthBarBg.zPosition = 2
        bg.addChild(healthBarBg)
        
        // Health bar fill (green)
        let healthPercent = companion.maxHitPoints > 0 ? CGFloat(companion.hitPoints) / CGFloat(companion.maxHitPoints) : 0.0
        let healthFillWidth = healthBarWidth * max(0, min(1, healthPercent))
        
        let healthBarFill = SKShapeNode()
        healthBarFill.path = CGPath(roundedRect: CGRect(x: -healthBarWidth / 2, y: -healthBarHeight / 2, width: healthFillWidth, height: healthBarHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
        healthBarFill.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
        healthBarFill.strokeColor = .clear
        healthBarFill.position = CGPoint(x: 0, y: healthBarY)
        healthBarFill.zPosition = 3
        bg.addChild(healthBarFill)
        
        // Health label
        let healthLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        healthLabel.text = "HP: \(companion.hitPoints)/\(companion.maxHitPoints)"
        healthLabel.fontSize = size.height * 0.2
        healthLabel.fontColor = .white
        healthLabel.horizontalAlignmentMode = .center
        healthLabel.verticalAlignmentMode = .center
        healthLabel.position = CGPoint(x: 0, y: healthBarY)
        healthLabel.zPosition = 4
        bg.addChild(healthLabel)
        
        // Store companion ID in userData
        container.userData = NSMutableDictionary()
        container.userData?["companionId"] = companion.id.uuidString
        
        return container
    }
    
    func handleTouch(at location: CGPoint) -> Bool {
        guard isVisible, let backgroundPanel = backgroundPanel, let camera = camera else { 
            return false 
        }
        
        // Convert touch location to panel coordinates
        let panelLocation = backgroundPanel.convert(location, from: camera)
        
        // Use atPoint to find the node at this location (more reliable than bounds check)
        let node = backgroundPanel.atPoint(panelLocation)
        
        // Check for close button FIRST (before bounds check, in case it's at the edge)
        if let closeButton = findNodeWithName("closeCharacterUI", startingFrom: node) {
            print("[CharacterUI] Close button clicked - hiding UI")
            // Call hide() which will set isVisible = false and remove the panel
            hide()
            return true
        }
        
        // Check for tab button clicks BEFORE bounds check (tab buttons might be at edges)
        if let tabButton = findNodeWithName(prefix: "tabButton_", startingFrom: node) {
            print("[CharacterUI] Tab button found: \(tabButton.name ?? "unknown")")
            if let tab = tabButton.userData?["tab"] as? CharacterUITab {
                print("[CharacterUI] Switching to tab: \(tab)")
                currentTab = tab
                updateTabButtons()
                updateTabContent()
                return true
            } else {
                print("[CharacterUI] Tab button found but no tab data in userData")
            }
        }
        
        // First check if touch is even within the panel bounds (for other UI elements)
        let panelFrame = CGRect(
            x: -backgroundPanel.frame.width / 2,
            y: -backgroundPanel.frame.height / 2,
            width: backgroundPanel.frame.width,
            height: backgroundPanel.frame.height
        )
        guard panelFrame.contains(panelLocation) else { 
            return false 
        }
        
        // Check content container interactions
        guard let contentContainer = contentContainer else { return false }
        let localLocation = contentContainer.convert(location, from: camera)
        let contentNode = contentContainer.atPoint(localLocation)
        
        // Check for skill learn button
        if let learnButton = findNodeWithName(prefix: "learnButton_", startingFrom: contentNode) {
            if let skillId = learnButton.parent?.parent?.userData?["skillId"] as? String,
               let player = player,
               player.learnedSkills.contains(skillId) == false,
               player.skillPoints > 0 {
                player.learnSkill(skillId: skillId)
                updateTabContent()
                return true
            }
        }
        
        // Check for attribute increase button
        if let increaseButton = findNodeWithName(prefix: "increaseButton_", startingFrom: contentNode) {
            if let abilityStr = increaseButton.parent?.userData?["ability"] as? String,
               let ability = Ability(rawValue: abilityStr),
               let player = player,
               player.attributePoints > 0 {
                player.spendAttributePoint(on: ability)
                updateTabContent()
                return true
            }
        }
        
        return false
    }
    
    private func findNodeWithName(_ name: String, startingFrom node: SKNode) -> SKNode? {
        var currentNode: SKNode? = node
        while let current = currentNode {
            if current.name == name {
                return current
            }
            currentNode = current.parent
        }
        return nil
    }
    
    private func findNodeWithName(prefix: String, startingFrom node: SKNode) -> SKNode? {
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let name = current.name, name.hasPrefix(prefix) {
                return current
            }
            currentNode = current.parent
        }
        return nil
    }
    
    private func updateTabButtons() {
        let tabs: [CharacterUITab] = [.equipment, .skills, .attributes, .companions]
        for (index, button) in tabButtons.enumerated() {
            if index < tabs.count {
                let tab = tabs[index]
                let isSelected = tab == currentTab
                if let shapeNode = button.children.first as? SKShapeNode {
                    shapeNode.fillColor = isSelected ? MenuStyling.parchmentBg : MenuStyling.parchmentDark
                    shapeNode.strokeColor = isSelected ? MenuStyling.bookAccent : MenuStyling.parchmentBorder
                    shapeNode.lineWidth = isSelected ? 3 : 2
                }
            }
        }
    }
    
    private func getViewSize() -> CGSize {
        guard let scene = scene else { return CGSize(width: 375, height: 667) }
        if let view = scene.view {
            return view.bounds.size
        }
        return scene.size
    }
    
    private func cleanup() {
        backgroundPanel?.removeFromParent()
        backgroundPanel = nil
        tabButtons.removeAll()
        contentContainer = nil
    }
}
