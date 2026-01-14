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
        case spriteDescription
        case generating
        case complete
    }
    
    var currentStep: CreationStep = .name
    var characterName: String = ""
    var selectedClass: CharacterClass?
    var spriteDescription: String = ""
    var currentCharacter: GameCharacter? // Store current character for preview
    private var loadingSpinner: SKNode? // Reference to loading spinner
    private var previewSprite: SKSpriteNode? // Preview of reference image
    private var isGeneratingPreview: Bool = false // Track if preview is being generated
    
    override func didMove(to view: SKView) {
        print("🟢 CharacterCreationScene: didMove(to:) called")
        size = view.bounds.size
        backgroundColor = SKColor(red: 0.88, green: 0.82, blue: 0.72, alpha: 1.0)
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
        case .spriteDescription:
            showSpriteDescriptionScreen()
        case .generating:
            break // Don't rebuild during generation
        case .complete:
            break
        }
    }
    
    func showNameInputScreen() {
        removeAllChildren()
        currentStep = .name
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        panel.zPosition = 1
        addChild(panel)
        
        // Book title - positioned with more padding from top border
        let titleY: CGFloat = isLandscape ? size.height / 2.0 + dims.panelHeight / 2.0 - 80.0 : size.height / 2.0 + dims.panelHeight / 2.0 - 90.0
        let title = MenuStyling.createBookTitle(text: "Character Creation", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: isLandscape ? 30.0 : 34.0)
        title.zPosition = 10
        addChild(title)
        
        // Instruction
        let instructionY: CGFloat = isLandscape ? titleY - 50.0 : titleY - 60.0
        let instruction = SKLabelNode(fontNamed: "Arial")
        instruction.text = "Enter your character's name:"
        instruction.fontSize = isLandscape ? 20.0 : 24.0
        instruction.fontColor = MenuStyling.inkColor
        instruction.position = CGPoint(x: size.width / 2.0, y: instructionY)
        instruction.zPosition = 10
        addChild(instruction)
        
        // Name input area (tappable) - book styled
        let inputWidth = min(dims.buttonWidth, isLandscape ? 450.0 : size.width * 0.85)
        let inputHeight: CGFloat = isLandscape ? 75.0 : 85.0
        let nameInputArea = SKShapeNode(rectOf: CGSize(width: inputWidth, height: inputHeight), cornerRadius: 8)
        nameInputArea.fillColor = MenuStyling.parchmentBg
        nameInputArea.strokeColor = MenuStyling.parchmentBorder
        nameInputArea.lineWidth = 2
        nameInputArea.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        nameInputArea.zPosition = 10
        nameInputArea.name = "nameInputArea"
        
        // Inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: inputWidth - 4, height: inputHeight * 0.3), cornerRadius: 6)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.1)
        highlight.strokeColor = SKColor.clear
        highlight.position = CGPoint(x: 0, y: inputHeight * 0.15)
        nameInputArea.addChild(highlight)
        
        addChild(nameInputArea)
        
        // Name display
        let nameDisplay = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameDisplay.text = characterName.isEmpty ? "Tap to enter name" : characterName
        nameDisplay.fontSize = isLandscape ? 26.0 : 30.0
        nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        nameDisplay.verticalAlignmentMode = .center
        nameDisplay.zPosition = 11
        nameDisplay.name = "nameDisplay"
        nameInputArea.addChild(nameDisplay)
        
        // Continue button
        let continueY: CGFloat = isLandscape ? size.height / 2.0 - 100.0 : size.height / 2.0 - 120.0
        let continueButton = MenuStyling.createBookButton(
            text: "Continue",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: characterName.isEmpty ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: continueY),
            name: "continueButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
        
        // Back button
        let backY: CGFloat = continueY - (dims.buttonHeight + dims.spacing)
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentDark,
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
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
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
        let topPadding: CGFloat = 100.0  // Increased padding to avoid border overlap
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
        
        // Book title
        let title = MenuStyling.createBookTitle(text: "Select Class", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: titleFontSize)
        title.zPosition = 10
        addChild(title)
        
        // Character name reminder
        let nameLabel = SKLabelNode(fontNamed: "Arial")
        nameLabel.text = "Character: \(characterName)"
        nameLabel.fontSize = nameLabelFontSize
        nameLabel.fontColor = MenuStyling.inkMuted
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
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: actionButtonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2.0, y: backButtonY),
            name: "backButton",
            fontSize: isLandscape ? 20 : 24
        )
        backButton.zPosition = 10
        addChild(backButton)
        
        // Continue button
        let continueButton = MenuStyling.createBookButton(
            text: "Continue",
            size: CGSize(width: dims.buttonWidth, height: actionButtonHeight),
            color: selectedClass == nil ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: continueButtonY),
            name: "continueButton",
            fontSize: isLandscape ? 20.0 : 24.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
    }
    
    func showSpriteDescriptionScreen() {
        removeAllChildren()
        currentStep = .spriteDescription
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        panel.zPosition = 1
        addChild(panel)
        
        // Book title - positioned with more padding from top border
        let titleY: CGFloat = isLandscape ? size.height / 2.0 + dims.panelHeight / 2.0 - 80.0 : size.height / 2.0 + dims.panelHeight / 2.0 - 90.0
        let title = MenuStyling.createBookTitle(text: "Character Appearance", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: isLandscape ? 30.0 : 34.0)
        title.zPosition = 10
        addChild(title)
        
        // Character name reminder
        let nameLabelY: CGFloat = titleY - 40.0
        let nameLabel = SKLabelNode(fontNamed: "Arial")
        nameLabel.text = "\(characterName) - \(selectedClass?.rawValue ?? "")"
        nameLabel.fontSize = isLandscape ? 18.0 : 22.0
        nameLabel.fontColor = MenuStyling.inkMuted
        nameLabel.position = CGPoint(x: size.width / 2.0, y: nameLabelY)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        
        // Calculate positions from top to bottom with proper spacing
        // Leave space for preview between name label and instruction
        // Preview can be up to ~200-250px tall, so we need significant space
        let previewSpace: CGFloat = isLandscape ? 250.0 : 280.0 // Space reserved for preview
        let instructionY: CGFloat = nameLabelY - previewSpace - 30.0 // Position instruction well below where preview would be
        let instruction = SKLabelNode(fontNamed: "Arial")
        instruction.text = "Describe what your character looks like:"
        instruction.fontSize = isLandscape ? 18.0 : 22.0
        instruction.fontColor = MenuStyling.inkColor
        instruction.position = CGPoint(x: size.width / 2.0, y: instructionY)
        instruction.zPosition = 10
        instruction.name = "instructionLabel" // Add name for easier finding
        addChild(instruction)
        
        // Example text
        let exampleY: CGFloat = instructionY - 28.0
        let exampleLabel = SKLabelNode(fontNamed: "Arial")
        exampleLabel.text = "e.g., 'A brave warrior with red hair, blue armor, and a sword'"
        exampleLabel.fontSize = isLandscape ? 14.0 : 16.0
        exampleLabel.fontColor = MenuStyling.inkMuted
        exampleLabel.position = CGPoint(x: size.width / 2.0, y: exampleY)
        exampleLabel.zPosition = 10
        exampleLabel.name = "exampleLabel" // Add name for easier finding
        addChild(exampleLabel)
        
        // Description input area - position below example
        let inputWidth = min(dims.buttonWidth, isLandscape ? 500.0 : size.width * 0.9)
        let inputHeight: CGFloat = isLandscape ? 100.0 : 120.0
        // Position input area below example with proper spacing
        let inputAreaY: CGFloat = exampleY - 35.0 - inputHeight / 2.0
        let descriptionInputArea = SKShapeNode(rectOf: CGSize(width: inputWidth, height: inputHeight), cornerRadius: 8)
        descriptionInputArea.fillColor = MenuStyling.parchmentBg
        descriptionInputArea.strokeColor = MenuStyling.parchmentBorder
        descriptionInputArea.lineWidth = 2
        descriptionInputArea.position = CGPoint(x: size.width / 2.0, y: inputAreaY)
        descriptionInputArea.zPosition = 10
        descriptionInputArea.name = "descriptionInputArea"
        
        // Inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: inputWidth - 4, height: inputHeight * 0.3), cornerRadius: 6)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.1)
        highlight.strokeColor = SKColor.clear
        highlight.position = CGPoint(x: 0, y: inputHeight * 0.15)
        descriptionInputArea.addChild(highlight)
        
        addChild(descriptionInputArea)
        
        // Description display (multiline support limited, but show text)
        let descriptionDisplay = SKLabelNode(fontNamed: "Arial")
        descriptionDisplay.text = spriteDescription.isEmpty ? "Tap to enter description" : spriteDescription
        descriptionDisplay.fontSize = isLandscape ? 18.0 : 20.0
        descriptionDisplay.fontColor = spriteDescription.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        descriptionDisplay.verticalAlignmentMode = .center
        descriptionDisplay.preferredMaxLayoutWidth = inputWidth - 20
        descriptionDisplay.numberOfLines = 0
        descriptionDisplay.zPosition = 11
        descriptionDisplay.name = "descriptionDisplay"
        descriptionInputArea.addChild(descriptionDisplay)
        
        // Buttons - position below input area with proper spacing
        let inputAreaBottom = inputAreaY - inputHeight / 2.0
        let buttonSpacing: CGFloat = isLandscape ? 20.0 : 25.0
        let generateY: CGFloat = inputAreaBottom - buttonSpacing - dims.buttonHeight / 2.0
        let generateButton = MenuStyling.createBookButton(
            text: spriteDescription.isEmpty ? "Skip (Use Default)" : "Generate All Sprites",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: generateY),
            name: "generateButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        generateButton.zPosition = 10
        addChild(generateButton)
        
        // Back button - positioned with proper spacing below generate button
        let backSpacing: CGFloat = dims.buttonHeight + dims.spacing
        let backY: CGFloat = generateY - backSpacing
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2.0, y: backY),
            name: "backButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        backButton.zPosition = 10
        addChild(backButton)
        
        // Generate preview if description already exists
        if !spriteDescription.isEmpty {
            generatePreviewImage()
        }
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
        
        // Main button (book styled)
        let button = SKShapeNode(rectOf: size, cornerRadius: 8)
        button.fillColor = isSelected ? MenuStyling.parchmentBg : MenuStyling.parchmentBg
        button.strokeColor = isSelected ? MenuStyling.bookAccent : MenuStyling.parchmentBorder
        button.lineWidth = isSelected ? 3 : 2
        button.zPosition = 1
        container.addChild(button)
        
        // Highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.25), cornerRadius: 6)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.1)
        highlight.strokeColor = SKColor.clear
        highlight.position = CGPoint(x: 0, y: size.height * 0.125)
        highlight.zPosition = 2
        button.addChild(highlight)
        
        // Label
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = classType.rawValue
        label.fontSize = size.height * 0.35
        label.fontColor = MenuStyling.inkColor
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
            
        case .spriteDescription:
            handleSpriteDescriptionTouch(node: node, location: location)
            
        case .generating:
            break // Ignore touches during generation
            
        case .complete:
            if let startButton = findNodeWithName("startGameButton", startingFrom: node) {
                animateButtonPress(startButton) {
                    // Use stored character or try to load from saved data
                    if let character = self.currentCharacter {
                        self.removeBackgroundsAndStartGame(character: character)
                    } else {
                        // Try to find character by name from saved characters
                        let allCharacters = SaveManager.getAllCharacters()
                        if let character = allCharacters.first(where: { $0.name == self.characterName }) {
                            self.removeBackgroundsAndStartGame(character: character)
                        }
                    }
                }
            }
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
            
        case .spriteDescription:
            handleSpriteDescriptionTouch(node: node, location: location)
            
        case .generating:
            break // Ignore touches during generation
            
        case .complete:
            if let startButton = findNodeWithName("startGameButton", startingFrom: node) {
                animateButtonPress(startButton) {
                    // Use stored character or try to load from saved data
                    if let character = self.currentCharacter {
                        self.removeBackgroundsAndStartGame(character: character)
                    } else {
                        // Try to find character by name from saved characters
                        let allCharacters = SaveManager.getAllCharacters()
                        if let character = allCharacters.first(where: { $0.name == self.characterName }) {
                            self.removeBackgroundsAndStartGame(character: character)
                        }
                    }
                }
            }
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
        
        // Check for continue button (traverse up parent chain)
        if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
            if let classType = selectedClass {
                animateButtonPress(continueButton) {
                    self.showSpriteDescriptionScreen()
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
    
    func handleSpriteDescriptionTouch(node: SKNode, location: CGPoint) {
        // Check for back button
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showClassSelectionScreen()
            }
            return
        }
        
        // Check for refresh button
        if let refreshButton = findNodeWithName("refreshButton", startingFrom: node) {
            if !isGeneratingPreview {
                animateButtonPress(refreshButton) {
                    self.generatePreviewImage()
                }
            }
            return
        }
        
        // Check for generate button
        if let generateButton = findNodeWithName("generateButton", startingFrom: node) {
            animateButtonPress(generateButton) {
                self.generateSpriteAndCreateCharacter()
            }
            return
        }
        
        // Check for description input area
        var currentNode: SKNode? = node
        while let current = currentNode {
            if current.name == "descriptionInputArea" || current.name == "descriptionDisplay" {
                showSpriteDescriptionAlert()
                return
            }
            currentNode = current.parent
        }
    }
    
    func showSpriteDescriptionAlert() {
        #if os(iOS) || os(tvOS)
        guard let viewController = self.view?.window?.rootViewController else {
            print("Could not find view controller to present alert")
            return
        }
        
        let alert = UIAlertController(title: "Character Appearance", message: "Describe what your character looks like:", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "e.g., A brave warrior with red hair, blue armor, and a sword"
            textField.text = self.spriteDescription
            textField.autocapitalizationType = .sentences
            textField.autocorrectionType = .yes
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            if let textField = alert?.textFields?.first, let text = textField.text {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Validate description for NSFW content
                let validation = SpriteGenerationService.shared.validateDescriptionForNSFW(trimmedText)
                if !validation.isValid {
                    let errorAlert = UIAlertController(
                        title: "Invalid Description",
                        message: validation.reason ?? "Description contains inappropriate content.",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    if let viewController = self.view?.window?.rootViewController {
                        viewController.present(errorAlert, animated: true)
                    }
                    return
                }
                
                self.spriteDescription = trimmedText
                self.updateSpriteDescriptionDisplay()
                // Generate preview if description is not empty
                if !trimmedText.isEmpty {
                    self.generatePreviewImage()
                } else {
                    // Remove preview if description is cleared
                    self.removePreviewImage()
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(okAction)
        alert.addAction(cancelAction)
        
        viewController.present(alert, animated: true)
        #elseif os(macOS)
        let alert = NSAlert()
        alert.messageText = "Character Appearance"
        alert.informativeText = "Describe what your character looks like:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        inputTextField.stringValue = spriteDescription
        inputTextField.placeholderString = "e.g., A brave warrior with red hair, blue armor, and a sword"
        alert.accessoryView = inputTextField
        alert.window.initialFirstResponder = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let trimmedText = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Validate description for NSFW content
            let validation = SpriteGenerationService.shared.validateDescriptionForNSFW(trimmedText)
            if !validation.isValid {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Invalid Description"
                errorAlert.informativeText = validation.reason ?? "Description contains inappropriate content."
                errorAlert.alertStyle = .warning
                errorAlert.addButton(withTitle: "OK")
                errorAlert.runModal()
                return
            }
            
            spriteDescription = trimmedText
            updateSpriteDescriptionDisplay()
            // Generate preview if description is not empty
            if !trimmedText.isEmpty {
                generatePreviewImage()
            } else {
                // Remove preview if description is cleared
                removePreviewImage()
            }
        }
        #endif
    }
    
    func updateSpriteDescriptionDisplay() {
        if let descriptionInputArea = childNode(withName: "descriptionInputArea") as? SKShapeNode,
           let descriptionDisplay = descriptionInputArea.childNode(withName: "descriptionDisplay") as? SKLabelNode {
            descriptionDisplay.text = spriteDescription.isEmpty ? "Tap to enter description" : spriteDescription
            descriptionDisplay.fontColor = spriteDescription.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        }
        
        // Update generate button text
        if let generateButton = childNode(withName: "generateButton") {
            generateButton.removeFromParent()
        }
        
        // Remove refresh button if it exists
        if let refreshButton = childNode(withName: "refreshButton") {
            refreshButton.removeFromParent()
        }
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Calculate button positions based on input area position (not hardcoded)
        var generateY: CGFloat
        if let inputArea = childNode(withName: "descriptionInputArea") as? SKShapeNode {
            let inputAreaBottom = inputArea.position.y - inputArea.frame.height / 2.0
            let buttonSpacing: CGFloat = isLandscape ? 20.0 : 25.0
            generateY = inputAreaBottom - buttonSpacing - dims.buttonHeight / 2.0
        } else {
            // Fallback to hardcoded position if input area not found
            let hasPreview = previewSprite != nil
            generateY = hasPreview ? (isLandscape ? size.height / 2.0 - 200.0 : size.height / 2.0 - 220.0) : (isLandscape ? size.height / 2.0 - 120.0 : size.height / 2.0 - 140.0)
        }
        
        // Add generate button first
        let newButton = MenuStyling.createBookButton(
            text: spriteDescription.isEmpty ? "Skip (Use Default)" : "Generate All Sprites",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: generateY),
            name: "generateButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        newButton.zPosition = 10
        addChild(newButton)
        
        // Add refresh button if description exists (positioned below generate button)
        if !spriteDescription.isEmpty {
            let refreshSpacing: CGFloat = dims.buttonHeight + dims.spacing
            let refreshY: CGFloat = generateY - refreshSpacing
            let refreshButton = MenuStyling.createBookButton(
                text: isGeneratingPreview ? "Generating..." : "Refresh Preview",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: isGeneratingPreview ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
                position: CGPoint(x: size.width / 2.0, y: refreshY),
                name: "refreshButton",
                fontSize: isLandscape ? 20.0 : 24.0
            )
            refreshButton.zPosition = 10
            addChild(refreshButton)
            
            // Update back button position if it exists
            if let backButton = childNode(withName: "backButton") {
                let backSpacing: CGFloat = dims.buttonHeight + dims.spacing
                backButton.position = CGPoint(x: size.width / 2.0, y: refreshY - backSpacing)
            }
        } else {
            // Update back button position if it exists (below generate button)
            if let backButton = childNode(withName: "backButton") {
                let backSpacing: CGFloat = dims.buttonHeight + dims.spacing
                backButton.position = CGPoint(x: size.width / 2.0, y: generateY - backSpacing)
            }
        }
        
        // If preview exists, update all positions to account for it
        if previewSprite != nil {
            updateElementPositionsForPreview()
        }
    }
    
    func generatePreviewImage() {
        guard !spriteDescription.isEmpty, !isGeneratingPreview else { return }
        
        isGeneratingPreview = true
        updateSpriteDescriptionDisplay() // Update button to show "Generating..."
        
        // Remove old preview
        removePreviewImage()
        
        // Show loading indicator - position where preview will appear
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        let titleY: CGFloat = isLandscape ? size.height / 2.0 + dims.panelHeight / 2.0 - 20.0 : size.height / 2.0 + dims.panelHeight / 2.0 - 25.0
        let nameLabelY: CGFloat = titleY - 40.0
        let previewSpacing: CGFloat = isLandscape ? 20.0 : 25.0
        let previewY: CGFloat = nameLabelY - previewSpacing - 80.0 // Approximate center of preview area
        
        let loadingLabel = SKLabelNode(fontNamed: "Arial")
        loadingLabel.text = "Generating preview..."
        loadingLabel.fontSize = isLandscape ? 16.0 : 18.0
        loadingLabel.fontColor = MenuStyling.inkMuted
        loadingLabel.position = CGPoint(x: size.width / 2.0, y: previewY)
        loadingLabel.zPosition = 10
        loadingLabel.name = "previewLoadingLabel"
        addChild(loadingLabel)
        
        // Use description directly - don't add class type as it might confuse the model
        // The description should be complete on its own
        let fullDescription = spriteDescription
        
        // Generate reference image (skip background removal for preview to save API calls)
        SpriteGenerationService.shared.generateReferenceImage(description: fullDescription, skipBackgroundRemoval: true) { [weak self] imageData in
            DispatchQueue.main.async {
                guard let self = self, let imageData = imageData else {
                    self?.isGeneratingPreview = false
                    self?.childNode(withName: "previewLoadingLabel")?.removeFromParent()
                    self?.updateSpriteDescriptionDisplay()
                    return
                }
                
                self.isGeneratingPreview = false
                self.childNode(withName: "previewLoadingLabel")?.removeFromParent()
                
                // Create sprite from image data (with background for preview)
                #if os(macOS)
                if let image = NSImage(data: imageData),
                   let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let cgImage = bitmapRep.cgImage {
                    let texture = SKTexture(cgImage: cgImage)
                    self.displayPreviewImage(texture: texture)
                }
                #else
                if let image = UIImage(data: imageData),
                   let cgImage = image.cgImage {
                    let texture = SKTexture(cgImage: cgImage)
                    self.displayPreviewImage(texture: texture)
                }
                #endif
                
                self.updateSpriteDescriptionDisplay()
            }
        }
    }
    
    func displayPreviewImage(texture: SKTexture) {
        // Remove old preview
        removePreviewImage()
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Calculate preview size - ensure FULL image is visible without ANY cropping
        // Use the texture's actual aspect ratio and scale to fit available space
        let textureSize = texture.size()
        let textureAspectRatio = textureSize.width / textureSize.height
        
        // Available space for preview (between name label and instruction)
        // Use same calculation as in showSpriteDescriptionScreen
        let titleY: CGFloat = isLandscape ? size.height / 2.0 + dims.panelHeight / 2.0 - 80.0 : size.height / 2.0 + dims.panelHeight / 2.0 - 90.0
        let nameLabelY: CGFloat = titleY - 40.0
        let previewSpace: CGFloat = isLandscape ? 250.0 : 280.0 // Same as in showSpriteDescriptionScreen
        let instructionY: CGFloat = nameLabelY - previewSpace - 30.0 // Same calculation
        let availableHeight = nameLabelY - instructionY - 60.0 // Leave space for label and spacing
        let availableWidth = min(isLandscape ? 300.0 : 260.0, size.width * 0.9)
        
        // Calculate size that fits in available space while maintaining aspect ratio
        // Start with height constraint since we have a tall portrait image (512x1024)
        var previewHeight = availableHeight
        var previewWidth = previewHeight * textureAspectRatio
        
        // If width exceeds available space, scale by width instead
        if previewWidth > availableWidth {
            previewWidth = availableWidth
            previewHeight = previewWidth / textureAspectRatio
        }
        
        // Ensure minimum visible size
        let minWidth: CGFloat = isLandscape ? 100.0 : 80.0
        let minHeight: CGFloat = isLandscape ? 150.0 : 120.0
        if previewWidth < minWidth {
            previewWidth = minWidth
            previewHeight = previewWidth / textureAspectRatio
        }
        if previewHeight < minHeight {
            previewHeight = minHeight
            previewWidth = previewHeight * textureAspectRatio
        }
        
        // Position preview between name label and instruction with proper spacing
        // Make sure preview doesn't overlap with name label or instruction
        let previewSpacing: CGFloat = isLandscape ? 25.0 : 30.0
        // Center preview in the available space between name label and instruction
        let availableSpace = nameLabelY - instructionY - previewSpacing * 2
        // Position preview so it's centered in available space
        let previewY: CGFloat = nameLabelY - previewSpacing - (availableSpace / 2.0)
        
        // Create sprite - ensure it shows the full texture without cropping
        // Use the texture's actual size to maintain aspect ratio
        let sprite = SKSpriteNode(texture: texture)
        // Set size explicitly to ensure full image is visible
        sprite.size = CGSize(width: previewWidth, height: previewHeight)
        // Ensure the sprite uses the full texture
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = CGPoint(x: size.width / 2.0, y: previewY)
        sprite.zPosition = 10
        sprite.name = "previewSprite"
        // Ensure texture filtering doesn't crop
        texture.filteringMode = .linear
        addChild(sprite)
        
        previewSprite = sprite
        
        // Add label above preview
        let previewLabel = SKLabelNode(fontNamed: "Arial")
        previewLabel.text = "Preview (Front View)"
        previewLabel.fontSize = isLandscape ? 16.0 : 18.0
        previewLabel.fontColor = MenuStyling.inkMuted
        previewLabel.position = CGPoint(x: size.width / 2.0, y: previewY + previewHeight / 2.0 + 20.0)
        previewLabel.zPosition = 10
        previewLabel.name = "previewLabel"
        addChild(previewLabel)
        
        // Update positions of elements below preview
        updateElementPositionsForPreview()
    }
    
    func updateElementPositionsForPreview() {
        // When preview is shown, we need to move instruction and elements below it down
        guard let preview = previewSprite else { return }
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        let previewBottom = preview.position.y - preview.size.height / 2.0
        let spacing: CGFloat = isLandscape ? 35.0 : 40.0 // Increased spacing to prevent overlap
        
        // Find and reposition instruction using name
        if let instruction = childNode(withName: "instructionLabel") as? SKLabelNode {
            instruction.position = CGPoint(x: size.width / 2.0, y: previewBottom - spacing)
        } else {
            // Fallback: find by text
            for child in children {
                if let label = child as? SKLabelNode, label.text == "Describe what your character looks like:" {
                    label.position = CGPoint(x: size.width / 2.0, y: previewBottom - spacing)
                    break
                }
            }
        }
        
        // Find and reposition example text using name
        if let exampleLabel = childNode(withName: "exampleLabel") as? SKLabelNode {
            if let instruction = childNode(withName: "instructionLabel") as? SKLabelNode {
                let exampleSpacing: CGFloat = isLandscape ? 30.0 : 35.0
                exampleLabel.position = CGPoint(x: size.width / 2.0, y: instruction.position.y - exampleSpacing)
            }
        } else {
            // Fallback: find by text
            for child in children {
                if let label = child as? SKLabelNode, label.text?.hasPrefix("e.g.,") == true {
                    if let instruction = childNode(withName: "instructionLabel") as? SKLabelNode {
                        let exampleSpacing: CGFloat = isLandscape ? 30.0 : 35.0
                        label.position = CGPoint(x: size.width / 2.0, y: instruction.position.y - exampleSpacing)
                    }
                    break
                }
            }
        }
        
        // Reposition description input area
        if let inputArea = childNode(withName: "descriptionInputArea") as? SKShapeNode {
            let inputHeight = inputArea.frame.height
            if let exampleLabel = childNode(withName: "exampleLabel") as? SKLabelNode {
                let inputSpacing: CGFloat = isLandscape ? 40.0 : 45.0
                let newInputY = exampleLabel.position.y - inputSpacing - inputHeight / 2.0
                inputArea.position = CGPoint(x: size.width / 2.0, y: newInputY)
                
                // Update button positions with proper spacing
                let inputAreaBottom = newInputY - inputHeight / 2.0
                let buttonSpacing: CGFloat = isLandscape ? 20.0 : 25.0
                
                // Position generate button below input area
                if let generateButton = childNode(withName: "generateButton") {
                    let newGenerateY = inputAreaBottom - buttonSpacing - dims.buttonHeight / 2.0
                    generateButton.position = CGPoint(x: size.width / 2.0, y: newGenerateY)
                }
                
                // Position refresh button below generate button
                if let refreshButton = childNode(withName: "refreshButton") {
                    if let generateButton = childNode(withName: "generateButton") {
                        let generateY = generateButton.position.y
                        let refreshSpacing: CGFloat = dims.buttonHeight + dims.spacing
                        refreshButton.position = CGPoint(x: size.width / 2.0, y: generateY - refreshSpacing)
                    }
                }
                
                // Position back button below refresh button (or generate if no refresh)
                if let backButton = childNode(withName: "backButton") {
                    let buttonAbove: SKNode?
                    if let refreshButton = childNode(withName: "refreshButton") {
                        buttonAbove = refreshButton
                    } else if let generateButton = childNode(withName: "generateButton") {
                        buttonAbove = generateButton
                    } else {
                        buttonAbove = nil
                    }
                    
                    if let above = buttonAbove {
                        let backSpacing: CGFloat = dims.buttonHeight + dims.spacing
                        backButton.position = CGPoint(x: size.width / 2.0, y: above.position.y - backSpacing)
                    }
                }
            }
        }
    }
    
    func removePreviewImage() {
        previewSprite?.removeFromParent()
        previewSprite = nil
        childNode(withName: "previewLabel")?.removeFromParent()
        childNode(withName: "previewLoadingLabel")?.removeFromParent()
    }
    
    func showGeneratingScreen() {
        removeAllChildren()
        loadingSpinner?.removeFromParent()
        currentStep = .generating
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        panel.zPosition = 1
        addChild(panel)
        
        // Loading title (using book title style for consistency) - positioned above spinner
        let titleY = isLandscape ? size.height / 2.0 + 60.0 : size.height / 2.0 + 70.0
        let loadingTitle = MenuStyling.createBookTitle(text: "Loading Game...", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: isLandscape ? 28.0 : 32.0)
        loadingTitle.zPosition = 10
        loadingTitle.name = "loadingTitle"
        addChild(loadingTitle)
        
        let statusLabel = SKLabelNode(fontNamed: "Arial")
        statusLabel.text = spriteDescription.isEmpty ? "Creating default sprite..." : "Creating sprite from description..."
        statusLabel.fontSize = isLandscape ? 18.0 : 22.0
        statusLabel.fontColor = MenuStyling.inkMuted
        statusLabel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0 - 60.0)
        statusLabel.zPosition = 10
        statusLabel.name = "statusLabel"
        addChild(statusLabel)
        
        // Create animated loading spinner (rotating circle with gap)
        let spinnerContainer = SKNode()
        spinnerContainer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        spinnerContainer.zPosition = 10
        spinnerContainer.name = "spinnerContainer"
        
        // Create spinning circle arc (like a loading indicator)
        let spinnerRadius: CGFloat = isLandscape ? 30.0 : 35.0
        let spinnerPath = CGMutablePath()
        // Create an arc that's 75% of a circle (leaves a gap)
        spinnerPath.addArc(center: .zero, radius: spinnerRadius, startAngle: 0, endAngle: CGFloat.pi * 1.5, clockwise: false)
        
        let spinner = SKShapeNode(path: spinnerPath)
        spinner.strokeColor = MenuStyling.bookAccent
        spinner.fillColor = SKColor.clear
        spinner.lineWidth = 5.0
        spinner.lineCap = .round
        spinner.lineJoin = .round
        spinner.name = "spinner"
        
        spinnerContainer.addChild(spinner)
        addChild(spinnerContainer)
        loadingSpinner = spinnerContainer
        
        // Animate spinner (rotate continuously)
        let rotateAction = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 1.0)
        let repeatRotation = SKAction.repeatForever(rotateAction)
        spinner.run(repeatRotation, withKey: "spinnerRotation")
    }
    
    func generateSpriteAndCreateCharacter() {
        guard let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Show generating screen with loading spinner
        showGeneratingScreen()
        
        // Create character first to get ID, then generate sprite with that ID
        let character = GameCharacter(
            name: characterName,
            characterClass: classType,
            spriteDescription: spriteDescription.isEmpty ? nil : spriteDescription
        )
        _ = SaveManager.saveCharacter(character) // Save character first
        
        let descriptionToUse = spriteDescription.isEmpty ? "A \(classType.rawValue) character" : spriteDescription
        
        // Generate animation frames using character's ID (skip background removal for preview)
        SpriteGenerationService.shared.generateSpriteSheet(description: descriptionToUse, characterId: character.id, skipBackgroundRemoval: true) { [weak self] (framePaths: [String]?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update character with frame paths
                var updatedCharacter = character
                updatedCharacter.framePaths = framePaths
                _ = SaveManager.saveCharacter(updatedCharacter)
                
                // Store character and show preview screen
                self.currentCharacter = updatedCharacter
                self.showSpritePreviewScreen(character: updatedCharacter, framePaths: framePaths ?? [])
            }
        }
    }
    
    func createCharacter() {
        guard let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Create character without sprite (fallback if called directly)
        let character = GameCharacter(name: characterName, characterClass: classType)
        _ = SaveManager.saveCharacter(character)
        createCharacter(character: character)
    }
    
    func createCharacter(character: GameCharacter) {
        guard let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Create character (already saved)
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
            nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        }
        
        // Update continue button state - need to find the button in the container
        if let continueButton = childNode(withName: "continueButton") {
            // Remove old button
            continueButton.removeFromParent()
            
            // Recreate with new state
            let dims = MenuStyling.getResponsiveDimensions(size: size)
            let isLandscape = size.width > size.height
            let continueY: CGFloat = isLandscape ? size.height / 2.0 - 100.0 : size.height / 2.0 - 120.0
            let newButton = MenuStyling.createBookButton(
                text: "Continue",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: characterName.isEmpty ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
                position: CGPoint(x: size.width / 2.0, y: continueY),
                name: "continueButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            newButton.zPosition = 10
            addChild(newButton)
        }
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
    
    /// Show preview screen with all generated sprite frames
    func showSpritePreviewScreen(character: GameCharacter, framePaths: [String]) {
        // Remove all existing children
        removeAllChildren()
        currentStep = .complete
        
        backgroundColor = SKColor(red: 0.88, green: 0.82, blue: 0.72, alpha: 1.0)
        
        let isLandscape = size.width > size.height
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        panel.zPosition = 1
        addChild(panel)
        
        // Define panel boundaries (border margin is 15px from panel edges)
        let panelTop: CGFloat = size.height / 2.0 + dims.panelHeight / 2.0
        let panelBottom: CGFloat = size.height / 2.0 - dims.panelHeight / 2.0
        let borderMargin: CGFloat = 15.0
        
        // Title - positioned with padding from top border
        let titlePadding: CGFloat = isLandscape ? 110.0 : 120.0
        let titleY: CGFloat = panelTop - borderMargin - titlePadding
        let titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text = "Sprite Preview"
        titleLabel.fontSize = isLandscape ? 40 : 48
        titleLabel.fontColor = MenuStyling.inkColor
        titleLabel.position = CGPoint(x: size.width / 2, y: titleY)
        titleLabel.zPosition = 10
        addChild(titleLabel)
        
        // Instructions
        let instructionLabel = SKLabelNode(fontNamed: "Arial")
        instructionLabel.text = "Review your character sprites. Click 'Start Game' to remove backgrounds and begin."
        instructionLabel.fontSize = isLandscape ? 18 : 22
        instructionLabel.fontColor = MenuStyling.inkMuted
        instructionLabel.position = CGPoint(x: size.width / 2, y: titleY - (isLandscape ? 40 : 55))
        instructionLabel.zPosition = 10
        addChild(instructionLabel)
        
        // Calculate responsive frame size and spacing
        let frameSize: CGFloat = isLandscape ? min(120, (size.width - 100) / 4.5) : min(130, (size.width - 60) / 4.5)
        let spacing: CGFloat = isLandscape ? 15 : 20
        let containerPadding: CGFloat = 20
        let labelHeight: CGFloat = 40
        let containerSpacing: CGFloat = isLandscape ? 25 : 30
        
        // Calculate total width for frames (used for both containers)
        let totalFramesWidth: CGFloat = 4 * frameSize + 3 * spacing
        
        // Calculate container dimensions
        let containerWidth: CGFloat = totalFramesWidth + 2 * containerPadding
        let containerHeight: CGFloat = frameSize + labelHeight + 2 * containerPadding + 30 // Extra space for label below sprites
        
        // Calculate positions - center everything vertically within panel bounds
        let instructionBottom = instructionLabel.position.y - (isLandscape ? 25 : 30) // Bottom of instruction text
        let buttonAreaTop = panelBottom + borderMargin + 80 // Space for button at bottom
        let availableHeight = instructionBottom - buttonAreaTop
        let totalContainersHeight = 2 * containerHeight + containerSpacing
        let startY = instructionBottom - (availableHeight - totalContainersHeight) / 2 - containerHeight / 2
        
        // Create Idle Animations container
        let idleContainer = SKNode()
        idleContainer.position = CGPoint(x: size.width / 2, y: startY)
        idleContainer.zPosition = 5
        addChild(idleContainer)
        
        // White background for idle container
        let idleBackground = SKShapeNode(rectOf: CGSize(width: containerWidth, height: containerHeight), cornerRadius: 12)
        idleBackground.fillColor = SKColor.white
        idleBackground.strokeColor = SKColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
        idleBackground.lineWidth = 2
        idleBackground.position = CGPoint.zero
        idleBackground.zPosition = 0
        idleContainer.addChild(idleBackground)
        
        // Idle label
        let idleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        idleLabel.text = "Idle Animations"
        idleLabel.fontSize = isLandscape ? 24 : 28
        idleLabel.fontColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        idleLabel.position = CGPoint(x: 0, y: containerHeight / 2 - labelHeight / 2 - 10)
        idleLabel.zPosition = 1
        idleContainer.addChild(idleLabel)
        
        // Idle frames - centered horizontally
        let idleStartX: CGFloat = -totalFramesWidth / 2 + frameSize / 2
        let idleY: CGFloat = -labelHeight / 2
        let idleDirections = ["south", "west", "east", "north"]
        for (index, direction) in idleDirections.enumerated() {
            if let path = framePaths.first(where: { $0.contains("idle_\(direction)") }) {
                let xPos: CGFloat = idleStartX + CGFloat(index) * (frameSize + spacing)
                loadAndDisplayFrame(path: path, position: CGPoint(x: xPos, y: idleY), size: frameSize, label: direction.capitalized, parent: idleContainer)
            }
        }
        
        // Create Walking Animations container
        let walkContainer = SKNode()
        walkContainer.position = CGPoint(x: size.width / 2, y: startY - containerHeight - containerSpacing)
        walkContainer.zPosition = 5
        addChild(walkContainer)
        
        // White background for walk container
        let walkBackground = SKShapeNode(rectOf: CGSize(width: containerWidth, height: containerHeight), cornerRadius: 12)
        walkBackground.fillColor = SKColor.white
        walkBackground.strokeColor = SKColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
        walkBackground.lineWidth = 2
        walkBackground.position = CGPoint.zero
        walkBackground.zPosition = 0
        walkContainer.addChild(walkBackground)
        
        // Walk label
        let walkLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        walkLabel.text = "Walking Animations"
        walkLabel.fontSize = isLandscape ? 24 : 28
        walkLabel.fontColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        walkLabel.position = CGPoint(x: 0, y: containerHeight / 2 - labelHeight / 2 - 10)
        walkLabel.zPosition = 1
        walkContainer.addChild(walkLabel)
        
        // Walk frames - centered horizontally
        let walkStartX: CGFloat = -totalFramesWidth / 2 + frameSize / 2
        let walkY: CGFloat = -labelHeight / 2
        let walkDirections = ["south", "west", "east", "north"]
        for (index, direction) in walkDirections.enumerated() {
            if let path = framePaths.first(where: { $0.contains("walk_\(direction)") }) {
                let xPos: CGFloat = walkStartX + CGFloat(index) * (frameSize + spacing)
                loadAndDisplayFrame(path: path, position: CGPoint(x: xPos, y: walkY), size: frameSize, label: direction.capitalized, parent: walkContainer)
            }
        }
        
        // Start Game button - positioned above bottom border
        let buttonPadding: CGFloat = isLandscape ? 70 : 80
        let buttonY: CGFloat = panelBottom + borderMargin + buttonPadding
        let startButton = MenuStyling.createBookButton(
            text: "Start Game",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.bookSecondary,
            position: CGPoint(x: size.width / 2, y: buttonY),
            name: "startGameButton",
            fontSize: isLandscape ? 22 : 26
        )
        startButton.zPosition = 10
        addChild(startButton)
    }
    
    /// Load and display a frame image
    func loadAndDisplayFrame(path: String, position: CGPoint, size: CGFloat, label: String, parent: SKNode) {
        // Resolve relative path (CharacterSprites/...) to full path
        let fileURL: URL
        if path.hasPrefix("CharacterSprites/") {
            // Relative path - resolve to documents directory
            if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                let fileName = (path as NSString).lastPathComponent
                fileURL = documentsDir.appendingPathComponent(fileName)
            } else {
                print("⚠️ Failed to load frame: No documents directory, path: \(path)")
                return
            }
        } else {
            // Assume it's already a full path
            fileURL = URL(fileURLWithPath: path)
        }
        
        guard let imageData = try? Data(contentsOf: fileURL) else {
            print("⚠️ Failed to load frame: \(path) (resolved to: \(fileURL.path))")
            return
        }
        
        #if os(macOS)
        guard let image = NSImage(data: imageData) else { return }
        let texture = SKTexture(image: image)
        #else
        guard let image = UIImage(data: imageData) else { return }
        let texture = SKTexture(image: image)
        #endif
        
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: size, height: size)
        sprite.position = position
        sprite.name = "frame_\(label)"
        sprite.zPosition = 1
        parent.addChild(sprite)
        
        // Add direction label below
        let labelNode = SKLabelNode(fontNamed: "Arial")
        labelNode.text = label
        labelNode.fontSize = size > 100 ? 18 : 16
        labelNode.fontColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        labelNode.position = CGPoint(x: 0, y: -size/2 - 20)
        labelNode.zPosition = 2
        sprite.addChild(labelNode)
    }
    
    /// Remove backgrounds from all frames and start the game
    func removeBackgroundsAndStartGame(character: GameCharacter) {
        guard let framePaths = character.framePaths, !framePaths.isEmpty else {
            print("❌ No frame paths to process")
            return
        }
        
        // Show loading indicator - positioned above the button with high z-position
        let isLandscape = size.width > size.height
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let panelBottom: CGFloat = size.height / 2.0 - dims.panelHeight / 2.0
        let borderMargin: CGFloat = 15.0
        let buttonPadding: CGFloat = isLandscape ? 70 : 80
        let buttonY: CGFloat = panelBottom + borderMargin + buttonPadding
        
        // Position loading label above the button
        let loadingLabel = SKLabelNode(fontNamed: "Arial")
        loadingLabel.text = "Removing backgrounds..."
        loadingLabel.fontSize = isLandscape ? 20 : 24
        loadingLabel.fontColor = MenuStyling.inkColor
        loadingLabel.position = CGPoint(x: size.width / 2, y: buttonY + (isLandscape ? 50 : 60))
        loadingLabel.zPosition = 20  // Higher than button (which is 10)
        loadingLabel.name = "loadingLabel"
        addChild(loadingLabel)
        
        // Process each frame to remove background
        var processedCount = 0
        var processedPaths: [String] = []
        
        func processNextFrame(index: Int) {
            guard index < framePaths.count else {
                // All frames processed, update character and start game
                // Ensure this runs on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    var updatedCharacter = character
                    updatedCharacter.framePaths = processedPaths
                    _ = SaveManager.saveCharacter(updatedCharacter)
                    
                    // Remove loading label
                    if let label = self.childNode(withName: "loadingLabel") {
                        label.removeFromParent()
                    }
                    
                    // Actually start the game with the updated character
                    if let gameState = SaveManager.loadGame(characterId: updatedCharacter.id, fromSlot: 1) {
                        self.startGame(character: updatedCharacter, gameState: gameState)
                    } else {
                        // Create new game state if no save exists
                        let abilityScores = AbilityScores(strength: 15, dexterity: 14, constitution: 13, intelligence: 12, wisdom: 10, charisma: 8)
                        let player = Player(name: updatedCharacter.name, characterClass: .ranger, abilityScores: abilityScores)
                        let world = WorldMap(width: 50, height: 50, seed: Int.random(in: 0...Int.max))
                        let gameState = GameState(player: player, world: world)
                        self.startGame(character: updatedCharacter, gameState: gameState)
                    }
                }
                return
            }
            
            let framePath = framePaths[index]
            // Resolve relative path (CharacterSprites/...) to full path
            let fullPath: String
            if framePath.hasPrefix("CharacterSprites/") {
                if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                    let fileName = String(framePath.dropFirst("CharacterSprites/".count))
                    fullPath = documentsDir.appendingPathComponent(fileName).path
                } else {
                    print("⚠️ Failed to get documents directory for background removal: \(framePath)")
                    processedPaths.append(framePath) // Keep original if path resolution fails
                    processNextFrame(index: index + 1)
                    return
                }
            } else {
                fullPath = framePath
            }
            
            let url = URL(fileURLWithPath: fullPath)
            guard let imageData = try? Data(contentsOf: url) else {
                print("⚠️ Failed to load frame for background removal: \(framePath) (resolved to: \(fullPath))")
                processedPaths.append(framePath) // Keep original if removal fails
                processNextFrame(index: index + 1)
                return
            }
            
            SpriteGenerationService.shared.removeBackground(from: imageData) { [weak self] transparentData in
                guard let self = self else { return }
                
                if let transparentData = transparentData {
                    // Save the transparent version back to the same path
                    do {
                        try transparentData.write(to: url)
                        processedPaths.append(framePath) // Keep relative path for storage
                        print("✅ Removed background from frame \(index + 1)/\(framePaths.count): \(framePath)")
                    } catch {
                        print("⚠️ Failed to save transparent frame: \(error)")
                        processedPaths.append(framePath) // Keep original
                    }
                } else {
                    print("⚠️ Background removal failed for frame \(index + 1), keeping original")
                    processedPaths.append(framePath) // Keep original
                }
                
                processedCount += 1
                if let label = self.childNode(withName: "loadingLabel") as? SKLabelNode {
                    label.text = "Removing backgrounds... \(processedCount)/\(framePaths.count)"
                }
                
                // Process next frame
                processNextFrame(index: index + 1)
            }
        }
        
        // Start processing
        processNextFrame(index: 0)
    }
}

