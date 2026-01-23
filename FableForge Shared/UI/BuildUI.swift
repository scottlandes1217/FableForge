//
//  BuildUI.swift
//  FableForge Shared
//
//  Created by Scott Landes on 1/8/26.
//

import Foundation
import SpriteKit

enum BuildUITab: String {
    case buildings = "Buildings"
    case farming = "Farming"
    case interior = "Interior"
}

struct StructureData {
    let id: String
    let name: String
    let description: String
    let structureType: String
    let tab: String
    let image: String?
    let requirements: StructureRequirements
    let size: CGSize
}

struct StructureRequirements {
    let materials: [MaterialRequirement]
    let skills: [SkillRequirement]
}

struct MaterialRequirement {
    let type: String
    let quantity: Int
}

struct SkillRequirement {
    let type: String
    let level: Int
}

class BuildUI {
    weak var scene: SKScene?
    weak var camera: SKCameraNode?
    var player: Player?
    
    var isVisible: Bool = false
    var currentTab: BuildUITab = .buildings
    
    // UI Nodes
    var backgroundPanel: SKNode?
    var tabButtons: [SKNode] = []
    var contentContainer: SKNode?
    var structures: [StructureData] = []
    
    // Scrolling state
    var scrollContainer: SKNode?
    var isScrolling: Bool = false
    var lastTouchLocation: CGPoint = .zero
    var scrollMinY: CGFloat = 0
    var scrollMaxY: CGFloat = 0
    
    init(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
        loadStructures()
    }
    
    private func loadStructures() {
        // Try loading from Prefabs directory first, then root
        guard let url = Bundle.main.url(forResource: "buildable_structures", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "buildable_structures", withExtension: "json"),
              let structuresData = try? Data(contentsOf: url),
              let structuresJson = try? JSONSerialization.jsonObject(with: structuresData) as? [String: Any],
              let structuresArray = structuresJson["structures"] as? [[String: Any]] else {
            print("⚠️ Failed to load buildable structures")
            return
        }
        
        structures = structuresArray.compactMap { structureDict in
            guard let id = structureDict["id"] as? String,
                  let name = structureDict["name"] as? String,
                  let description = structureDict["description"] as? String,
                  let structureType = structureDict["structureType"] as? String,
                  let tab = structureDict["tab"] as? String,
                  let sizeDict = structureDict["size"] as? [String: Any],
                  let width = sizeDict["width"] as? CGFloat,
                  let height = sizeDict["height"] as? CGFloat,
                  let requirementsDict = structureDict["requirements"] as? [String: Any] else {
                return nil
            }
            
            let image = structureDict["image"] as? String
            
            // Parse materials
            var materials: [MaterialRequirement] = []
            if let materialsArray = requirementsDict["materials"] as? [[String: Any]] {
                for materialDict in materialsArray {
                    if let type = materialDict["type"] as? String,
                       let quantity = materialDict["quantity"] as? Int {
                        materials.append(MaterialRequirement(type: type, quantity: quantity))
                    }
                }
            }
            
            // Parse skills
            var skills: [SkillRequirement] = []
            if let skillsArray = requirementsDict["skills"] as? [[String: Any]] {
                for skillDict in skillsArray {
                    if let type = skillDict["type"] as? String,
                       let level = skillDict["level"] as? Int {
                        skills.append(SkillRequirement(type: type, level: level))
                    }
                }
            }
            
            let requirements = StructureRequirements(materials: materials, skills: skills)
            
            return StructureData(
                id: id,
                name: name,
                description: description,
                structureType: structureType,
                tab: tab,
                image: image,
                requirements: requirements,
                size: CGSize(width: width, height: height)
            )
        }
    }
    
    func show(player: Player) {
        guard !isVisible else { return }
        self.player = player
        
        // Close all other UIs
        if let gameScene = scene as? GameScene {
            gameScene.closeAllUIPanels()
        }
        closeAllOtherUIs()
        
        isVisible = true
        setupUI()
        
        // Final check
        if let gameScene = scene as? GameScene {
            gameScene.closeAllUIPanels()
        }
        closeAllOtherUIs()
        
        // Pause game
        if let gameScene = scene as? GameScene {
            gameScene.isGamePaused = true
        }
    }
    
    private func closeAllOtherUIs() {
        guard let camera = camera else { return }
        
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
            
            for child in node.children {
                removeAllPanels(in: child)
            }
        }
        
        removeAllPanels(in: camera)
        
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
            if let panel = camera.childNode(withName: "//\(panelName)") {
                panel.removeFromParent()
            }
            if let panel = camera.childNode(withName: panelName) {
                panel.removeFromParent()
            }
        }
    }
    
    func hide() {
        guard isVisible else { return }
        isVisible = false
        cleanup()
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
        let panelWidth = viewSize.width
        let panelHeight = viewSize.height
        let panel = MenuStyling.createBookPage(size: CGSize(width: panelWidth, height: panelHeight))
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = 2000
        panel.name = "buildUIPanel"
        camera.addChild(panel)
        backgroundPanel = panel
        
        // Title
        let titleY = panelHeight / 2 - 50
        let title = MenuStyling.createBookTitle(
            text: "Build",
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
        
        let tabs: [(BuildUITab, String)] = [
            (.buildings, "Buildings"),
            (.farming, "Farming"),
            (.interior, "Interior")
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
        // Ensure proper bottom padding so cards don't overlap the bottom
        let bottomPadding: CGFloat = 100 // Extra padding at bottom to prevent overlap (increased further)
        let contentY = tabY - tabHeight / 2 - 20
        let contentHeight = panelHeight - (titleY - contentY) - bottomPadding
        let contentContainer = SKNode()
        contentContainer.position = CGPoint(x: 0, y: contentY - contentHeight / 2)
        contentContainer.zPosition = 2001
        panel.addChild(contentContainer)
        self.contentContainer = contentContainer
        
        // Close button - positioned in top-right corner, always visible
        let closeButtonSize: CGFloat = isLandscape ? 40 : 45
        let closeButton = SKShapeNode(rectOf: CGSize(width: closeButtonSize, height: closeButtonSize), cornerRadius: 6)
        closeButton.fillColor = MenuStyling.bookDanger
        closeButton.strokeColor = MenuStyling.parchmentBorder
        closeButton.lineWidth = 2
        // Position relative to view bounds, ensuring it's always visible
        // Use viewSize for positioning to ensure it's always within visible area
        let closeButtonMargin: CGFloat = 15 // Margin from edge
        closeButton.position = CGPoint(x: viewSize.width / 2 - closeButtonSize / 2 - closeButtonMargin, y: viewSize.height / 2 - closeButtonSize / 2 - closeButtonMargin)
        closeButton.zPosition = 2002
        closeButton.name = "closeBuildUI"
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
    
    private func createTabButton(text: String, position: CGPoint, size: CGSize, isSelected: Bool, tab: BuildUITab) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "buildTabButton_\(text)"
        
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
        
        container.userData = NSMutableDictionary()
        container.userData?["tab"] = tab
        
        return container
    }
    
    private func updateTabContent() {
        contentContainer?.removeAllChildren()
        
        // Reset scroll state
        scrollContainer = nil
        isScrolling = false
        
        guard let player = player, let backgroundPanel = backgroundPanel else { return }
        
        let filteredStructures = structures.filter { structure in
            structure.tab == currentTab.rawValue
        }
        
        let viewSize = getViewSize()
        let isLandscape = viewSize.width > viewSize.height
        
        // Calculate available space for content
        // Get panel dimensions (same as in setupUI) - use full screen height
        let panelHeight = viewSize.height
        let titleY = panelHeight / 2 - 50
        let tabY = titleY - 50
        let tabHeight: CGFloat = isLandscape ? 45 : 50
        
        // Calculate content area bounds (same calculation as setupUI)
        // Ensure proper bottom padding so cards don't overlap the bottom
        let bottomPadding: CGFloat = 80 // Extra padding at bottom to prevent overlap (increased further)
        let contentY = tabY - tabHeight / 2 - 20
        let contentHeight = panelHeight - (titleY - contentY) - bottomPadding
        let availableHeight = contentHeight
        
        // contentContainer is positioned at: CGPoint(x: 0, y: contentY - contentHeight / 2)
        // So in contentContainer's coordinate system:
        // - Top of content area is at: contentY - (contentY - contentHeight / 2) = contentHeight / 2
        // - Bottom of content area is at: contentY - contentHeight - (contentY - contentHeight / 2) = -contentHeight / 2
        // - Center is at: 0 (relative to contentContainer)
        let containerCenterY: CGFloat = 0  // Center of contentContainer
        
        // Calculate card layout
        let cardWidth: CGFloat = isLandscape ? 200 : 180
        let cardHeight: CGFloat = isLandscape ? 250 : 280
        let cardSpacing: CGFloat = 15
        let cardsPerRow: Int = isLandscape ? 3 : 2
        
        let containerWidth = viewSize.width * 0.9
        let totalCardsWidth = CGFloat(min(cardsPerRow, filteredStructures.count)) * cardWidth + CGFloat(min(cardsPerRow, filteredStructures.count) - 1) * cardSpacing
        let startX = -totalCardsWidth / 2 + cardWidth / 2
        
        // Create scrollable container with clipping (same approach as StartScreenScene)
        let scrollableContainer = SKNode()
        scrollableContainer.position = CGPoint(x: 0, y: 0) // Position relative to crop node
        scrollableContainer.name = "buildScrollContainer"
        
        // Create clipping mask
        let cropNode = SKCropNode()
        let mask = SKShapeNode(rectOf: CGSize(width: containerWidth, height: availableHeight))
        mask.fillColor = .white
        mask.strokeColor = .clear
        cropNode.maskNode = mask
        cropNode.position = CGPoint(x: 0, y: containerCenterY)
        cropNode.zPosition = 2001
        cropNode.name = "buildCropNode"
        cropNode.addChild(scrollableContainer)
        contentContainer?.addChild(cropNode)
        
        // Position cards starting from top of available space (same as StartScreenScene)
        // In scrollableContainer's coordinate system (centered at 0,0):
        // - Top of visible area is at +availableHeight/2
        // - Bottom of visible area is at -availableHeight/2
        let topPadding = cardHeight / 2 + 10
        let startY = availableHeight / 2 - topPadding  // First card center (positive, near top)
        
        print("🔧 BuildUI: Positioning cards - availableHeight=\(availableHeight), containerCenterY=\(containerCenterY), startY=\(startY), cardHeight=\(cardHeight)")
        
        for (index, structure) in filteredStructures.enumerated() {
            let row = index / cardsPerRow
            let col = index % cardsPerRow
            
            let xPos = startX + CGFloat(col) * (cardWidth + cardSpacing)
            let yPos = startY - CGFloat(row) * (cardHeight + cardSpacing)  // Cards go down (decreasing Y)
            
            print("🔧 BuildUI: Card \(index) (\(structure.name)) at row=\(row), col=\(col), pos=(\(xPos), \(yPos))")
            
            let card = createStructureCard(
                structure: structure,
                position: CGPoint(x: xPos, y: yPos),
                size: CGSize(width: cardWidth, height: cardHeight),
                player: player
            )
            scrollableContainer.addChild(card)
        }
        
        // Calculate scroll bounds (same logic as StartScreenScene)
        let totalRows = (filteredStructures.count + cardsPerRow - 1) / cardsPerRow
        let lastRowIndex = max(0, totalRows - 1)
        // After positioning loop, calculate last item center
        var lastItemCenterY: CGFloat
        if !filteredStructures.isEmpty {
            lastItemCenterY = startY - CGFloat(lastRowIndex) * (cardHeight + cardSpacing)
        } else {
            lastItemCenterY = startY
        }
        let firstItemTop = startY + cardHeight / 2
        let lastItemBottom = lastItemCenterY - cardHeight / 2
        let totalContentHeight = firstItemTop - lastItemBottom
        
        print("📊 BuildUI Scroll: totalContentHeight=\(totalContentHeight), availableHeight=\(availableHeight), startY=\(startY), lastItemBottom=\(lastItemBottom)")
        
        if totalContentHeight > availableHeight {
            // Content exceeds available space, enable scrolling (same logic as StartScreenScene)
            // The container starts at position 0 relative to the crop node
            // The visible area extends from -availableHeight/2 to +availableHeight/2 relative to crop node center
            // When container is at 0:
            //   - First item top is at firstItemTop relative to container center
            //   - Last item bottom is at lastItemBottom relative to container center (negative, below center)
            // In SpriteKit, moving container UP (positive Y) makes content appear to move DOWN on screen
            // To show the bottom content, we need to move container UP so lastItemBottom aligns with -availableHeight/2
            // When container is at position Y: lastItemBottom + Y = -availableHeight/2
            // So: Y = -availableHeight/2 - lastItemBottom
            // This gives us a positive Y (container moves up to show bottom content)
            let scrollDownAmount = -availableHeight / 2 - lastItemBottom
            self.scrollMinY = 0 // Start position, showing top content
            self.scrollMaxY = scrollDownAmount // Maximum scroll down (positive Y to show bottom content)
            scrollContainer = scrollableContainer
            scrollableContainer.position.y = 0  // Start at top
            print("✅ BuildUI Scrolling enabled: scrollMinY=\(self.scrollMinY), scrollMaxY=\(self.scrollMaxY)")
        } else {
            // Content fits, no scrolling needed
            scrollContainer = scrollableContainer  // Still set it so touch detection works
            self.scrollMinY = 0
            self.scrollMaxY = 0
            print("⚠️ BuildUI Scrolling disabled: content fits")
        }
    }
    
    private func createStructureCard(structure: StructureData, position: CGPoint, size: CGSize, player: Player) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "structureCard_\(structure.id)"
        
        // Check if player can build
        let canBuild = canBuildStructure(structure: structure, player: player)
        
        // Card background
        let cardBg = SKShapeNode(rectOf: size, cornerRadius: 8)
        cardBg.fillColor = canBuild ? MenuStyling.parchmentBg : MenuStyling.parchmentDark
        cardBg.strokeColor = canBuild ? MenuStyling.bookAccent : MenuStyling.parchmentBorder
        cardBg.lineWidth = canBuild ? 2 : 1
        cardBg.zPosition = 1
        container.addChild(cardBg)
        
        // Card coordinate system: (0,0) is at center
        // Top of card: y = size.height / 2
        // Bottom of card: y = -size.height / 2
        
        // Layout from top to bottom:
        // 1. Title at top
        // 2. Image below title
        // 3. Requirements at bottom
        
        let topMargin: CGFloat = 15
        let bottomMargin: CGFloat = 15
        let spacing: CGFloat = 10
        
        // Name/Title at the top
        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text = structure.name
        nameLabel.fontSize = size.height * 0.08
        nameLabel.fontColor = MenuStyling.inkColor
        nameLabel.verticalAlignmentMode = .top
        nameLabel.horizontalAlignmentMode = .center
        let nameY = size.height / 2 - topMargin
        nameLabel.position = CGPoint(x: 0, y: nameY)
        nameLabel.zPosition = 10
        cardBg.addChild(nameLabel)
        
        // Image below title
        let imageHeight: CGFloat = size.height * 0.35
        let imageY = nameY - nameLabel.fontSize - spacing - imageHeight / 2
        
        // Create a clipping container for the image
        let imageContainer = SKNode()
        imageContainer.position = CGPoint(x: 0, y: imageY)
        imageContainer.zPosition = 1
        
        if let imageName = structure.image {
            // Create sprite and check if image loaded successfully
            let imageSprite = SKSpriteNode(imageNamed: imageName)
            // Check if the sprite has a valid size (image was found)
            if imageSprite.size.width > 0 && imageSprite.size.height > 0 {
                // Scale to fit within bounds
                let maxWidth = size.width - 20
                let maxHeight = imageHeight
                let imageScale = min(maxWidth / imageSprite.size.width, maxHeight / imageSprite.size.height)
                imageSprite.setScale(imageScale)
                imageSprite.position = CGPoint(x: 0, y: 0)
                imageSprite.zPosition = 1
                imageSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                imageContainer.addChild(imageSprite)
            } else {
                // Image not found, show placeholder
                let placeholder = SKShapeNode(rectOf: CGSize(width: size.width - 20, height: imageHeight), cornerRadius: 4)
                placeholder.fillColor = MenuStyling.parchmentDark
                placeholder.strokeColor = MenuStyling.parchmentBorder
                placeholder.lineWidth = 1
                placeholder.position = CGPoint(x: 0, y: 0)
                placeholder.zPosition = 1
                imageContainer.addChild(placeholder)
                
                let placeholderLabel = SKLabelNode(fontNamed: "Arial")
                placeholderLabel.text = "No Image"
                placeholderLabel.fontSize = 14
                placeholderLabel.fontColor = MenuStyling.inkMuted
                placeholderLabel.verticalAlignmentMode = .center
                placeholderLabel.zPosition = 2
                placeholder.addChild(placeholderLabel)
            }
        } else {
            // Placeholder
            let placeholder = SKShapeNode(rectOf: CGSize(width: size.width - 20, height: imageHeight), cornerRadius: 4)
            placeholder.fillColor = MenuStyling.parchmentDark
            placeholder.strokeColor = MenuStyling.parchmentBorder
            placeholder.lineWidth = 1
            placeholder.position = CGPoint(x: 0, y: 0)
            placeholder.zPosition = 1
            imageContainer.addChild(placeholder)
            
            let placeholderLabel = SKLabelNode(fontNamed: "Arial")
            placeholderLabel.text = "No Image"
            placeholderLabel.fontSize = 14
            placeholderLabel.fontColor = MenuStyling.inkMuted
            placeholderLabel.verticalAlignmentMode = .center
            placeholderLabel.zPosition = 2
            placeholder.addChild(placeholderLabel)
        }
        cardBg.addChild(imageContainer)
        
        // Requirements at the bottom
        var requirementsText = "Requires:\n"
        
        // Materials
        if !structure.requirements.materials.isEmpty {
            for material in structure.requirements.materials {
                let hasEnough = hasMaterial(material: material, player: player)
                let prefix = hasEnough ? "✓" : "✗"
                requirementsText += "\(prefix) \(material.quantity)x \(material.type)\n"
            }
        }
        
        // Skills
        if !structure.requirements.skills.isEmpty {
            for skill in structure.requirements.skills {
                let hasSkill = hasSkill(skill: skill, player: player)
                let prefix = hasSkill ? "✓" : "✗"
                requirementsText += "\(prefix) \(skill.type) Lv.\(skill.level)\n"
            }
        }
        
        let requirementsLabel = SKLabelNode(fontNamed: "Arial")
        requirementsLabel.text = requirementsText
        requirementsLabel.fontSize = size.height * 0.06
        requirementsLabel.fontColor = MenuStyling.inkMuted
        requirementsLabel.verticalAlignmentMode = .top
        requirementsLabel.horizontalAlignmentMode = .left
        requirementsLabel.numberOfLines = 0
        requirementsLabel.preferredMaxLayoutWidth = size.width - 20
        // Position requirements directly below the image instead of at the bottom
        let requirementsY = imageY - imageHeight / 2 - spacing
        requirementsLabel.position = CGPoint(x: -size.width / 2 + 10, y: requirementsY)
        requirementsLabel.zPosition = 10 // Higher zPosition to ensure it's above image
        cardBg.addChild(requirementsLabel)
        
        // Store structure data
        container.userData = NSMutableDictionary()
        container.userData?["structureId"] = structure.id
        container.userData?["structureType"] = structure.structureType
        
        return container
    }
    
    private func canBuildStructure(structure: StructureData, player: Player) -> Bool {
        // Check materials
        for material in structure.requirements.materials {
            if !hasMaterial(material: material, player: player) {
                return false
            }
        }
        
        // Check skills
        for skill in structure.requirements.skills {
            if !hasSkill(skill: skill, player: player) {
                return false
            }
        }
        
        return true
    }
    
    private func hasMaterial(material: MaterialRequirement, player: Player) -> Bool {
        print("🔍 BuildUI: Checking material requirement - type: '\(material.type)', quantity needed: \(material.quantity)")
        
        // Try to match MaterialType first
        let materialType: MaterialType?
        if let mt = MaterialType(rawValue: material.type) {
            materialType = mt
        } else if let mt = MaterialType.allCases.first(where: { $0.rawValue.lowercased() == material.type.lowercased() }) {
            materialType = mt
        } else {
            print("⚠️ BuildUI: Unknown material type '\(material.type)' in build requirements")
            print("⚠️ BuildUI: Available MaterialType cases: \(MaterialType.allCases.map { $0.rawValue })")
            return false
        }
        
        guard let materialType = materialType else { return false }
        
        // Check both Material instances AND Item instances with matching ItemType
        var totalQuantity: Int = 0
        
        // First, check for Material instances
        let materialInstances = player.inventory.compactMap { $0 as? Material }
        print("🔍 BuildUI: Found \(materialInstances.count) Material instances in inventory")
        let matchingMaterials = materialInstances.filter { $0.materialType == materialType }
        totalQuantity += matchingMaterials.reduce(0) { $0 + $1.quantity }
        print("🔍 BuildUI: From Material instances: \(totalQuantity) \(material.type)")
        
        // Also check for Item instances with matching ItemType (for backwards compatibility)
        // Map MaterialType to ItemType
        let itemType: ItemType?
        switch materialType {
        case .wood: itemType = .wood
        case .stone: itemType = .stone
        case .iron: itemType = .iron
        case .cloth: itemType = .cloth
        case .rope: itemType = .rope
        case .nails: itemType = .nails
        }
        
        if let itemType = itemType {
            let matchingItems = player.inventory.filter { 
                $0.type == itemType && !($0 is Material) // Don't double-count Material instances
            }
            let itemQuantity = matchingItems.reduce(0) { $0 + $1.quantity }
            totalQuantity += itemQuantity
            print("🔍 BuildUI: From Item instances (type=\(itemType.rawValue)): \(itemQuantity) \(material.type)")
        }
        
        print("🔍 BuildUI: Total quantity of \(material.type): \(totalQuantity), needed: \(material.quantity)")
        let hasEnough = totalQuantity >= material.quantity
        print("🔍 BuildUI: Has enough \(material.type): \(hasEnough)")
        return hasEnough
    }
    
    private func hasSkill(skill: SkillRequirement, player: Player) -> Bool {
        // Convert skill type to BuildingSkill enum (handle both "carpentry" and "Carpentry")
        let skillName = skill.type.capitalized
        guard let skillType = BuildingSkill(rawValue: skillName) else {
            // Try matching by case-insensitive comparison
            if let matchingSkill = BuildingSkill.allCases.first(where: { $0.rawValue.lowercased() == skill.type.lowercased() }) {
                let playerSkillLevel = player.buildingSkills[matchingSkill] ?? 0
                return playerSkillLevel >= skill.level
            }
            return false
        }
        let playerSkillLevel = player.buildingSkills[skillType] ?? 0
        return playerSkillLevel >= skill.level
    }
    
    func handleTouch(at location: CGPoint) -> Bool {
        guard isVisible, let backgroundPanel = backgroundPanel, let camera = camera else {
            return false
        }
        
        let panelLocation = backgroundPanel.convert(location, from: camera)
        
        // Check ALL nodes at this location for buttons and cards
        let allNodesAtLocation = backgroundPanel.nodes(at: panelLocation)
        print("🔍 BuildUI: Touch at \(panelLocation), found \(allNodesAtLocation.count) nodes")
        
        // First, check all nodes for close button
        for node in allNodesAtLocation {
        if let closeButton = findNodeWithName("closeBuildUI", startingFrom: node) {
                print("✅ BuildUI: Close button clicked")
            hide()
            return true
            }
        }
        
        // Then check all nodes for tab buttons
        for node in allNodesAtLocation {
        if let tabButton = findNodeWithName(prefix: "buildTabButton_", startingFrom: node) {
            if let tab = tabButton.userData?["tab"] as? BuildUITab {
                    print("✅ BuildUI: Tab button clicked: \(tab)")
                currentTab = tab
                updateTabButtons()
                updateTabContent()
                return true
                }
            }
        }
        
        // Check for structure cards - search all nodes at this location
        
        for nodeAtLocation in allNodesAtLocation {
            var currentNode: SKNode? = nodeAtLocation
            while let current = currentNode {
                // Check if this is a structure card
                if let nodeName = current.name, nodeName.hasPrefix("structureCard_") {
                    print("✅ BuildUI: Found structure card: \(nodeName)")
                    
                    // Initialize scroll state (for potential scrolling)
                    if scrollContainer != nil {
                        isScrolling = false
                        lastTouchLocation = location
                    }
                    
                    // Process the card click immediately
                    if let structureId = current.userData?["structureId"] as? String,
                       let structureTypeString = current.userData?["structureType"] as? String,
               let structureType = StructureType(rawValue: structureTypeString),
               let player = player,
               let gameScene = scene as? GameScene {
                        
                        print("✅ BuildUI: Processing card click for \(structureTypeString)")
                
                // Find the structure data
                guard let structure = structures.first(where: { $0.id == structureId }) else {
                            print("❌ BuildUI: Structure not found for id: \(structureId)")
                    return false
                }
                
                // Check if player can build this structure
                if canBuildStructure(structure: structure, player: player) {
                            print("✅ BuildUI: Can build, entering placement mode")
                            // Close UI and enter build placement mode with JSON data
                    hide()
                            gameScene.enterBuildPlacementMode(structureData: structure)
                    return true
                } else {
                            print("❌ BuildUI: Cannot build, showing error")
                    // Show error message with missing requirements
                    let missingItems = getMissingRequirements(structure: structure)
                    gameScene.showMessage("Cannot build: \(missingItems)", color: .red)
                    return true
                }
                    }
                    return true // We found a card
                }
                currentNode = current.parent
            }
        }
        
        // Check if we're in the scrollable area (but not on a card) - initialize scroll state
        if let scrollContainer = scrollContainer {
            // Convert to scroll container's coordinate space to check if we're in the content area
            let locationInScrollContainer = backgroundPanel.convert(panelLocation, to: scrollContainer)
            let viewSize = getViewSize()
            let containerWidth = viewSize.width * 0.9
            let panelHeight = viewSize.height * 0.98
            let titleY = panelHeight / 2 - 50
            let tabY = titleY - 50
            let tabHeight: CGFloat = viewSize.width > viewSize.height ? 45 : 50
            let contentY = tabY - tabHeight / 2 - 20
            let contentHeight = panelHeight - (titleY - contentY) - 40
            let availableHeight = contentHeight
            
            // Check if touch is in the content area (wide bounds to catch all touches)
            if abs(locationInScrollContainer.x) < containerWidth && 
               abs(locationInScrollContainer.y) < availableHeight * 2 {
                print("📜 BuildUI: Touch in scrollable area, initializing scroll state")
                isScrolling = false
                lastTouchLocation = location
                // Don't return true here - let it fall through so other handlers can work
                // We'll handle scrolling in handleTouchMoved
            }
        }
        
        return false
    }
    
    func handleTouchMoved(at location: CGPoint) {
        guard isVisible, let scrollContainer = scrollContainer else { 
            print("⚠️ BuildUI: handleTouchMoved - not visible or no scrollContainer")
            return 
        }
        guard lastTouchLocation != .zero else { 
            print("⚠️ BuildUI: handleTouchMoved - lastTouchLocation is zero")
            return 
        }
        
        let deltaY = location.y - lastTouchLocation.y
        
        print("📜 BuildUI: Touch moved - deltaY=\(deltaY), isScrolling=\(isScrolling)")
        
        // If vertical movement is significant, start scrolling (same as StartScreenScene)
        if abs(deltaY) > 5 {
            if !isScrolling {
                print("📜 BuildUI: Starting scroll")
            }
            isScrolling = true
            
            // Update container position (reversed from StartScreenScene - user wants opposite behavior)
            // Dragging up (negative deltaY) should scroll up (show content above) = container moves down (toward scrollMinY, decrease Y)
            // Dragging down (positive deltaY) should scroll down (show content below) = container moves up (toward scrollMaxY, increase Y)
            let currentY = scrollContainer.position.y
            let proposedY = currentY + deltaY  // Reversed: add deltaY instead of subtract
            let clampedY = min(scrollMaxY, proposedY)
            let newY = max(scrollMinY, clampedY)
            scrollContainer.position.y = newY
            print("📜 BuildUI: Scrolled - currentY=\(currentY), deltaY=\(deltaY), proposedY=\(proposedY), clampedY=\(clampedY), newY=\(newY), bounds=[\(scrollMinY), \(scrollMaxY)]")
        }
        
        lastTouchLocation = location
    }
    
    func handleTouchEnded(at location: CGPoint? = nil) -> Bool {
        guard isVisible else { return false }
        
        // Reset scroll state
        isScrolling = false
        lastTouchLocation = .zero
        return false
    }
    
    func handleScrollWheel(deltaY: CGFloat) {
        guard isVisible, let scrollContainer = scrollContainer else { 
            print("🖱️ BuildUI: Mouse wheel - not visible or no scrollContainer, isVisible=\(isVisible), scrollContainer=\(scrollContainer != nil)")
            return 
        }
        
        // Handle trackpad/mouse wheel scrolling (reversed to match drag direction)
        // deltaY is positive when scrolling up, negative when scrolling down
        // Scrolling up (positive deltaY) should show content above = container moves down (decrease Y)
        // Scrolling down (negative deltaY) should show content below = container moves up (increase Y)
        // Scale based on delta magnitude (trackpad has smaller values, mouse wheel has larger)
        let scaledDeltaY: CGFloat
        if abs(deltaY) < 1.0 {  // Very small values suggest trackpad - use as-is
            scaledDeltaY = deltaY * 1.0
        } else if abs(deltaY) < 10 {  // Medium values - trackpad with momentum
            scaledDeltaY = deltaY * 1.5
        } else {  // Large values - mouse wheel
            scaledDeltaY = deltaY * 3.0
        }
        
        let currentY = scrollContainer.position.y
        let proposedY = currentY - scaledDeltaY  // Scroll up (positive deltaY) = content moves up = container moves down (subtract)
        let clampedY = min(scrollMaxY, proposedY)
        let newY = max(scrollMinY, clampedY)
        scrollContainer.position.y = newY
        print("🖱️ BuildUI: Mouse wheel - deltaY=\(deltaY), scaledDeltaY=\(scaledDeltaY), currentY=\(currentY), proposedY=\(proposedY), newY=\(newY), bounds=[\(scrollMinY), \(scrollMaxY)]")
    }
    
    private func getMissingRequirements(structure: StructureData) -> String {
        guard let player = player else { return "Unknown error" }
        
        var missing: [String] = []
        
        for material in structure.requirements.materials {
            if !hasMaterial(material: material, player: player) {
                let hasQuantity = getMaterialQuantity(material: material, player: player)
                missing.append("\(material.quantity - hasQuantity) more \(material.type)")
            }
        }
        
        for skill in structure.requirements.skills {
            if !hasSkill(skill: skill, player: player) {
                let skillName = skill.type.capitalized
                let skillType = BuildingSkill(rawValue: skillName) ?? BuildingSkill.allCases.first(where: { $0.rawValue.lowercased() == skill.type.lowercased() }) ?? .carpentry
                let playerLevel = player.buildingSkills[skillType] ?? 0
                missing.append("\(skill.type) level \(skill.level) (you have \(playerLevel))")
            }
        }
        
        return missing.joined(separator: ", ")
    }
    
    private func getMaterialQuantity(material: MaterialRequirement, player: Player) -> Int {
        // Try to match MaterialType first
        let materialType: MaterialType?
        if let mt = MaterialType(rawValue: material.type) {
            materialType = mt
        } else if let mt = MaterialType.allCases.first(where: { $0.rawValue.lowercased() == material.type.lowercased() }) {
            materialType = mt
        } else {
            return 0
        }
        
        guard let materialType = materialType else { return 0 }
        
        var totalQuantity: Int = 0
        
        // Check Material instances
        let materialInstances = player.inventory.compactMap { $0 as? Material }
        let matchingMaterials = materialInstances.filter { $0.materialType == materialType }
        totalQuantity += matchingMaterials.reduce(0) { $0 + $1.quantity }
        
        // Also check Item instances with matching ItemType (for backwards compatibility)
        let itemType: ItemType?
        switch materialType {
        case .wood: itemType = .wood
        case .stone: itemType = .stone
        case .iron: itemType = .iron
        case .cloth: itemType = .cloth
        case .rope: itemType = .rope
        case .nails: itemType = .nails
        }
        
        if let itemType = itemType {
            let matchingItems = player.inventory.filter { 
                $0.type == itemType && !($0 is Material) // Don't double-count Material instances
            }
            totalQuantity += matchingItems.reduce(0) { $0 + $1.quantity }
        }
        
        return totalQuantity
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
        let tabs: [BuildUITab] = [.buildings, .farming, .interior]
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
