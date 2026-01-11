//
//  CharacterCreationScene.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class CharacterCreationScene: SKScene {
    
    enum CreationStep {
        case name
        case classSelection
        case complete
    }
    
    var currentStep: CreationStep = .name
    var characterName: String = ""
    var selectedClass: CharacterClass?
    
    override func didMove(to view: SKView) {
        print("🟢 CharacterCreationScene: didMove(to:) called")
        size = view.bounds.size
        backgroundColor = SKColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        showNameInputScreen()
        print("✅ CharacterCreationScene: UI setup complete")
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild UI when size changes
        switch currentStep {
        case .name:
            showNameInputScreen()
        case .classSelection:
            showClassSelectionScreen()
        case .complete:
            break
        }
    }
    
    func showNameInputScreen() {
        removeAllChildren()
        currentStep = .name
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Modern panel
        let panel = MenuStyling.createModernPanel(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        panel.zPosition = 1
        addChild(panel)
        
        // Modern title - positioned closer to top of panel
        let titleY: CGFloat = isLandscape ? size.height / 2.0 + dims.panelHeight / 2.0 - 20.0 : size.height / 2.0 + dims.panelHeight / 2.0 - 25.0
        let title = MenuStyling.createModernTitle(text: "Character Creation", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: isLandscape ? 30.0 : 34.0)
        title.zPosition = 10
        addChild(title)
        
        // Instruction
        let instructionY: CGFloat = isLandscape ? titleY - 50.0 : titleY - 60.0
        let instruction = SKLabelNode(fontNamed: "Arial")
        instruction.text = "Enter your character's name:"
        instruction.fontSize = isLandscape ? 20.0 : 24.0
        instruction.fontColor = MenuStyling.lightText
        instruction.position = CGPoint(x: size.width / 2.0, y: instructionY)
        instruction.zPosition = 10
        addChild(instruction)
        
        // Name input area (tappable) - modern styled
        let inputWidth = min(dims.buttonWidth, isLandscape ? 450.0 : size.width * 0.85)
        let inputHeight: CGFloat = isLandscape ? 75.0 : 85.0
        let nameInputArea = SKShapeNode(rectOf: CGSize(width: inputWidth, height: inputHeight), cornerRadius: 16)
        nameInputArea.fillColor = SKColor(white: 0.2, alpha: 0.9)
        nameInputArea.strokeColor = SKColor(white: 0.5, alpha: 0.8)
        nameInputArea.lineWidth = 2
        nameInputArea.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        nameInputArea.zPosition = 10
        nameInputArea.name = "nameInputArea"
        
        // Inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: inputWidth - 4, height: inputHeight * 0.3), cornerRadius: 16)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.15)
        highlight.strokeColor = SKColor.clear
        highlight.position = CGPoint(x: 0, y: inputHeight * 0.15)
        nameInputArea.addChild(highlight)
        
        addChild(nameInputArea)
        
        // Name display
        let nameDisplay = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameDisplay.text = characterName.isEmpty ? "Tap to enter name" : characterName
        nameDisplay.fontSize = isLandscape ? 26.0 : 30.0
        nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.mutedText : MenuStyling.lightText
        nameDisplay.verticalAlignmentMode = .center
        nameDisplay.zPosition = 11
        nameDisplay.name = "nameDisplay"
        nameInputArea.addChild(nameDisplay)
        
        // Continue button
        let continueY: CGFloat = isLandscape ? size.height / 2.0 - 100.0 : size.height / 2.0 - 120.0
        let continueButton = MenuStyling.createModernButton(
            text: "Continue",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: characterName.isEmpty ? SKColor(white: 0.3, alpha: 1.0) : MenuStyling.secondaryColor,
            position: CGPoint(x: size.width / 2.0, y: continueY),
            name: "continueButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
        
        // Back button
        let backY: CGFloat = continueY - (dims.buttonHeight + dims.spacing)
        let backButton = MenuStyling.createModernButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: size.width / 2.0, y: backY),
            name: "backButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        backButton.zPosition = 10
        addChild(backButton)
    }
    
    func showClassSelectionScreen() {
        removeAllChildren()
        currentStep = .classSelection
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Modern panel
        let panel = MenuStyling.createModernPanel(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 1
        addChild(panel)
        
        // Calculate content dimensions
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        let nameLabelFontSize: CGFloat = isLandscape ? 18.0 : 22.0
        
        // Class selection grid dimensions
        let classes = CharacterClass.allCases
        let columns: Int = isLandscape ? 3 : 2
        let maxButtonWidth: CGFloat = isLandscape ? 180.0 : 160.0
        let buttonWidthMultiplier: CGFloat = isLandscape ? 0.5 : 0.45
        let buttonWidth: CGFloat = min(maxButtonWidth, dims.buttonWidth * buttonWidthMultiplier)
        let buttonHeight: CGFloat = isLandscape ? 55.0 : 60.0
        let spacing: CGFloat = isLandscape ? 12.0 : 15.0
        
        let totalRows: Int = (classes.count + columns - 1) / columns
        let gridHeight: CGFloat = CGFloat(totalRows) * buttonHeight + CGFloat(max(0, totalRows - 1)) * spacing
        
        // Action buttons dimensions
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let actionButtonsHeight: CGFloat = actionButtonHeight * 2 + actionSpacing // Create + Back buttons
        
        // Define panel boundaries
        let panelTop: CGFloat = size.height / 2.0 + dims.panelHeight / 2.0
        let panelBottom: CGFloat = size.height / 2.0 - dims.panelHeight / 2.0
        
        // Position elements from top to bottom
        let topPadding: CGFloat = 40.0
        let titleY: CGFloat = panelTop - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        
        let nameLabelSpacing: CGFloat = 15.0
        let nameY: CGFloat = titleBottom - nameLabelSpacing - nameLabelFontSize / 2.0
        let nameLabelBottom: CGFloat = nameY - nameLabelFontSize / 2.0
        
        // Position action buttons at bottom
        let bottomPadding: CGFloat = 20.0
        let backButtonY: CGFloat = panelBottom + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Calculate available space for grid
        let availableGridHeight = nameLabelBottom - actionButtonsTop - 20.0 // 20px spacing buffer
        
        // Adjust grid if it doesn't fit
        var adjustedSpacing = spacing
        var adjustedButtonHeight = buttonHeight
        if gridHeight > availableGridHeight {
            // Scale down to fit
            let scaleFactor = availableGridHeight / gridHeight
            adjustedSpacing = spacing * scaleFactor
            adjustedButtonHeight = buttonHeight * scaleFactor
        }
        
        // Recalculate grid height with adjusted dimensions
        let adjustedGridHeight: CGFloat = CGFloat(totalRows) * adjustedButtonHeight + CGFloat(max(0, totalRows - 1)) * adjustedSpacing
        
        // Modern title
        let title = MenuStyling.createModernTitle(text: "Select Class", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: titleFontSize)
        title.zPosition = 10
        addChild(title)
        
        // Character name reminder
        let nameLabel = SKLabelNode(fontNamed: "Arial")
        nameLabel.text = "Character: \(characterName)"
        nameLabel.fontSize = nameLabelFontSize
        nameLabel.fontColor = MenuStyling.mutedText
        nameLabel.position = CGPoint(x: size.width / 2.0, y: nameY)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        
        // Class selection container - center it in available space
        let container = SKNode()
        let gridCenterY: CGFloat = (nameLabelBottom + actionButtonsTop) / 2.0
        container.position = CGPoint(x: size.width / 2.0, y: gridCenterY)
        container.zPosition = 10
        addChild(container)
        
        // Create class buttons in a responsive grid
        var index = 0
        let centerRow: CGFloat = CGFloat(totalRows - 1) / 2.0 // Center row position
        
        for classType in classes {
            let row: Int = index / columns
            let col: Int = index % columns
            let centerCol: CGFloat = CGFloat(columns - 1) / 2.0
            let xPos: CGFloat = (CGFloat(col) - centerCol) * (buttonWidth + adjustedSpacing)
            let yPos: CGFloat = (centerRow - CGFloat(row)) * (adjustedButtonHeight + adjustedSpacing)
            
            let isSelected = selectedClass == classType
            let button = createClassButton(
                classType: classType,
                position: CGPoint(x: xPos, y: yPos),
                isSelected: isSelected,
                size: CGSize(width: buttonWidth, height: adjustedButtonHeight)
            )
            container.addChild(button)
            index += 1
        }
        
        // Back button
        let backButton = MenuStyling.createModernButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: actionButtonHeight),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: size.width / 2.0, y: backButtonY),
            name: "backButton",
            fontSize: isLandscape ? 20 : 24
        )
        backButton.zPosition = 10
        addChild(backButton)
        
        // Continue button
        let continueButton = MenuStyling.createModernButton(
            text: "Create Character",
            size: CGSize(width: dims.buttonWidth, height: actionButtonHeight),
            color: selectedClass == nil ? SKColor(white: 0.3, alpha: 1.0) : MenuStyling.secondaryColor,
            position: CGPoint(x: size.width / 2.0, y: continueButtonY),
            name: "createButton",
            fontSize: isLandscape ? 20.0 : 24.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
    }
    
    func createClassButton(classType: CharacterClass, position: CGPoint, isSelected: Bool, size: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "classButton_\(classType.rawValue)"
        
        // Shadow
        let shadow = SKShapeNode(rectOf: size, cornerRadius: 14)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.3)
        shadow.strokeColor = SKColor.clear
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main button
        let button = SKShapeNode(rectOf: size, cornerRadius: 14)
        button.fillColor = isSelected ? MenuStyling.secondaryColor : MenuStyling.accentColor
        button.strokeColor = isSelected ? SKColor(white: 1.0, alpha: 0.8) : SKColor(white: 1.0, alpha: 0.4)
        button.lineWidth = isSelected ? 3 : 2
        button.zPosition = 1
        container.addChild(button)
        
        // Highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.3), cornerRadius: 14)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.2)
        highlight.strokeColor = SKColor.clear
        highlight.position = CGPoint(x: 0, y: size.height * 0.15)
        highlight.zPosition = 2
        button.addChild(highlight)
        
        // Label
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = classType.rawValue
        label.fontSize = size.height * 0.35
        label.fontColor = MenuStyling.lightText
        label.verticalAlignmentMode = .center
        label.zPosition = 3
        label.isUserInteractionEnabled = false
        button.addChild(label)
        
        return container
    }
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let node = atPoint(location)
        
        switch currentStep {
        case .name:
            handleNameInputTouch(node: node, location: location)
            
        case .classSelection:
            handleClassSelectionTouch(node: node)
            
        case .complete:
            break
        }
    }
    #endif
    
    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let node = atPoint(location)
        
        switch currentStep {
        case .name:
            handleNameInputTouch(node: node, location: location)
            
        case .classSelection:
            handleClassSelectionTouch(node: node)
            
        case .complete:
            break
        }
    }
    #endif
    
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
    
    func handleNameInputTouch(node: SKNode, location: CGPoint) {
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.goBackToStartScreen()
            }
            return
        }
        
        // Check for continue button (traverse up parent chain)
        if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
            if !characterName.isEmpty {
                animateButtonPress(continueButton) {
                    self.showClassSelectionScreen()
                }
            }
            return
        }
        
        // Check for name input area (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if current.name == "nameInputArea" || current.name == "nameDisplay" {
                showNameInputAlert()
                return
            }
            currentNode = current.parent
        }
        
        // Don't show input if tapping elsewhere - only show when tapping the name input area
    }
    
    func handleClassSelectionTouch(node: SKNode) {
        // Check for class button (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("classButton_") {
                let className = nodeName.replacingOccurrences(of: "classButton_", with: "")
                if let classType = CharacterClass.allCases.first(where: { $0.rawValue == className }) {
                    selectedClass = classType
                    showClassSelectionScreen() // Refresh to show selection
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for create button (traverse up parent chain)
        if let createButton = findNodeWithName("createButton", startingFrom: node) {
            if let classType = selectedClass {
                animateButtonPress(createButton) {
                    self.createCharacter()
                }
            }
            return
        }
        
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showNameInputScreen()
            }
            return
        }
    }
    
    func showNameInputAlert() {
        #if os(iOS) || os(tvOS)
        // Get the view controller to present the alert
        guard let viewController = self.view?.window?.rootViewController else {
            print("Could not find view controller to present alert")
            return
        }
        
        // Create alert with text field
        let alert = UIAlertController(title: "Character Name", message: "Enter your character's name:", preferredStyle: .alert)
        
        // Add text field
        alert.addTextField { textField in
            textField.placeholder = "Enter name"
            textField.text = self.characterName
            textField.autocapitalizationType = .words
            textField.autocorrectionType = .no
        }
        
        // Add OK action
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            if let textField = alert?.textFields?.first, let text = textField.text {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    self.characterName = trimmedText
                    self.updateNameDisplay()
                }
            }
        }
        
        // Add Cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(okAction)
        alert.addAction(cancelAction)
        
        // Present the alert
        viewController.present(alert, animated: true)
        #elseif os(macOS)
        // macOS implementation using NSAlert
        let alert = NSAlert()
        alert.messageText = "Character Name"
        alert.informativeText = "Enter your character's name:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = characterName
        inputTextField.placeholderString = "Enter name"
        alert.accessoryView = inputTextField
        alert.window.initialFirstResponder = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let trimmedText = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                characterName = trimmedText
                updateNameDisplay()
            }
        }
        #endif
    }
    
    func updateNameDisplay() {
        // Update the name display label
        if let nameInputArea = childNode(withName: "nameInputArea") as? SKShapeNode,
           let nameDisplay = nameInputArea.childNode(withName: "nameDisplay") as? SKLabelNode {
            nameDisplay.text = characterName.isEmpty ? "Tap to enter name" : characterName
            nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.mutedText : MenuStyling.lightText
        }
        
        // Update continue button state - need to find the button in the container
        if let continueButton = childNode(withName: "continueButton") {
            // Remove old button
            continueButton.removeFromParent()
            
            // Recreate with new state
            let dims = MenuStyling.getResponsiveDimensions(size: size)
            let isLandscape = size.width > size.height
            let continueY: CGFloat = isLandscape ? size.height / 2.0 - 100.0 : size.height / 2.0 - 120.0
            let newButton = MenuStyling.createModernButton(
                text: "Continue",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: characterName.isEmpty ? SKColor(white: 0.3, alpha: 1.0) : MenuStyling.secondaryColor,
                position: CGPoint(x: size.width / 2.0, y: continueY),
                name: "continueButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            newButton.zPosition = 10
            addChild(newButton)
        }
    }
    
    func createCharacter() {
        guard let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Create character
        let character = GameCharacter(name: characterName, characterClass: classType)
        _ = SaveManager.saveCharacter(character)
        
        // Create player with default ability scores
        let abilityScores = AbilityScores(strength: 15, dexterity: 14, constitution: 13, intelligence: 12, wisdom: 10, charisma: 8)
        let player = Player(name: characterName, characterClass: classType, abilityScores: abilityScores)
        
        // Initialize world
        let worldSeed = Int.random(in: 1...100000)
        let world = WorldMap(width: 50, height: 50, seed: worldSeed)
        
        // Set player position
        let worldCenterX = CGFloat(world.width) * world.tileSize / 2
        let worldCenterY = CGFloat(world.height) * world.tileSize / 2
        player.position = CGPoint(x: worldCenterX, y: worldCenterY)
        
        // Give player initial items
        player.inventory.append(Material(materialType: .wood, quantity: 20))
        player.inventory.append(Material(materialType: .stone, quantity: 15))
        player.inventory.append(Material(materialType: .iron, quantity: 10))
        player.inventory.append(Item(name: "Meat", type: .meat, quantity: 3))
        player.inventory.append(Item(name: "Berries", type: .berries, quantity: 5))
        
        // Initialize building skills
        player.buildingSkills[.carpentry] = 2
        player.buildingSkills[.farming] = 1
        player.buildingSkills[.animalHusbandry] = 1
        
        // Create game state
        let gameState = GameState(player: player, world: world)
        
        // Save to first available slot
        for slot in 1...SaveManager.maxSlots {
            if SaveManager.getSaveSlotInfo(characterId: character.id, slot: slot)?.isEmpty == true {
                _ = SaveManager.saveGame(gameState: gameState, characterId: character.id, toSlot: slot)
                break
            }
        }
        
        // Transition to game
        startGame(character: character, gameState: gameState)
    }
    
    func startGame(character: GameCharacter, gameState: GameState) {
        guard let skView = self.view else { return }
        
        print("🟢 CharacterCreationScene: startGame() - Transitioning to GameScene")
        print("  → Current scene size: \(size)")
        print("  → View bounds: \(skView.bounds)")
        
        // Create game scene
        let gameScene = GameScene.newGameScene()
        
        // Set the scene size to match the view bounds
        gameScene.size = skView.bounds.size
        print("  → Set GameScene size to: \(gameScene.size)")
        
        // Set up camera
        gameScene.cameraNode = SKCameraNode()
        gameScene.camera = gameScene.cameraNode
        gameScene.addChild(gameScene.cameraNode!)
        
        // Create combat UI
        gameScene.combatUI = CombatUI(scene: gameScene)
        
        // Set the game state
        gameScene.gameState = gameState
        
        // Set the character ID
        gameScene.currentCharacterId = character.id
        
        // Restore the game from state
        gameScene.restoreGameFromState()
        
        // Store reference in view controller if needed
        #if os(iOS) || os(tvOS)
        if let window = skView.window as? UIWindow,
           let viewController = window.rootViewController {
            // Note: GameViewController is platform-specific, so we can't cast to it here
            // This code can be extended if needed per platform
        }
        #elseif os(macOS)
        if let window = skView.window as? NSWindow,
           let viewController = window.contentViewController {
            // Note: GameViewController is platform-specific, so we can't cast to it here
            // This code can be extended if needed per platform
        }
        #endif
        
        // Present game scene with transition
        skView.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.5))
        print("✅ CharacterCreationScene: GameScene presented")
    }
    
    func goBackToStartScreen() {
        guard let skView = self.view else { return }
        let startScene = StartScreenScene(size: size)
        startScene.scaleMode = .aspectFill
        skView.presentScene(startScene, transition: SKTransition.fade(withDuration: 0.5))
    }
    
    func animateButtonPress(_ button: SKNode, completion: @escaping () -> Void) {
        let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        
        button.run(sequence) {
            completion()
        }
    }
    
    // Handle text input from view controller
    func handleTextInput(_ text: String) {
        if currentStep == .name {
            characterName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nameDisplay = childNode(withName: "nameDisplay") as? SKLabelNode {
                nameDisplay.text = characterName.isEmpty ? "Enter name..." : characterName
                nameDisplay.fontColor = characterName.isEmpty ? SKColor(white: 0.5, alpha: 1.0) : SKColor(white: 1.0, alpha: 1.0)
                
                // Update continue button
                if let continueButton = childNode(withName: "continueButton") as? SKShapeNode {
                    continueButton.fillColor = characterName.isEmpty ? SKColor(white: 0.3, alpha: 1.0) : SKColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0)
                }
            }
        }
    }
}

