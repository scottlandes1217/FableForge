//
//  CharacterCreationScene.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class CharacterCreationScene: SKScene {
    
    // MARK: - Properties & State
    
    enum CreationStep {
        case raceSelection
        case genderSelection
        case classSelection
        case spriteDescription
        case attributeAllocation
        case generating
        case spritePreview
    }
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        case other = "Other"
    }
    
    var currentStep: CreationStep = .raceSelection
    var characterName: String = ""
    var selectedRace: Race?
    var selectedGender: Gender?
    var selectedClass: CharacterClass?
    var spriteDescription: String = ""
    var isGeneratingSprites: Bool = false // Track if sprites are generating in background
    var allocatedAttributes: AbilityScores = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0)
    var baseAttributes: AbilityScores = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0) // Base attributes from class (cannot be decreased)
    var remainingAttributePoints: Int = 20 // Start with 20 points to allocate
    var currentCharacter: GameCharacter? // Store current character for preview
    private var loadingSpinner: SKNode? // Reference to loading spinner
    private var previewSprite: SKSpriteNode? // Preview of reference image
    private var previewTexture: SKTexture? // Store preview texture to avoid regenerating
    private var previewImageData: Data? // Store preview image data to reuse for sprite generation
    private var isGeneratingPreview: Bool = false // Track if preview is being generated
    
    // Video playback state
    private var videoNode: SKVideoNode? // Video node for story cut-scene
    private var videoPlayer: AVPlayer? // AVPlayer for video playback
    private var isShowingStory: Bool = false // Track if story video is showing
    
    // Continuous button press handling
    private var heldButtonAbility: Ability? = nil
    private var isHeldButtonIncrease: Bool = false
    private var buttonHoldTimer: Timer? = nil
    
    // Track removed sprites during regeneration so we can update the correct one
    private var removedSprites: [String: (sprite: SKSpriteNode, position: CGPoint, size: CGFloat, parent: SKNode)] = [:] // frameIdentifier -> removed sprite info
    
    // Scrolling state for portrait mode
    var scrollContainer: SKNode?
    var isScrolling: Bool = false
    var lastTouchLocation: CGPoint = .zero
    var scrollMinY: CGFloat = 0
    var scrollMaxY: CGFloat = 0
    
    // Text input fields for direct typing
    #if os(iOS) || os(tvOS)
    private var nameTextField: UITextField?
    private var nameTextFieldContainer: UIView? // Track containerView for name input
    private var descriptionTextField: UITextView?
    #elseif os(macOS)
    private var nameTextField: NSTextView? // Use NSTextView like description field for textContainerInset
    private var nameTextFieldContainer: NSView? // Track containerView for name input
    private var descriptionTextField: NSTextView?
    private var descriptionScrollView: NSView? // Track containerView for description input
    #endif
    
    // MARK: - Helper Functions
    
    func getRaceImageName(race: Race) -> String {
        return "race_\(race.rawValue.lowercased())"
    }
    
    func getClassImageName(characterClass: CharacterClass) -> String {
        return "class_\(characterClass.rawValue.lowercased())"
    }
    
    // MARK: - Scene Lifecycle
    
    override func didMove(to view: SKView) {
        print("🟢 CharacterCreationScene: didMove(to:) called")
        size = view.bounds.size
        backgroundColor = SKColor(red: 0.88, green: 0.82, blue: 0.72, alpha: 1.0)
        
        // Add background image
        addBackgroundImage()
        
        showRaceSelectionScreen()
        print("✅ CharacterCreationScene: UI setup complete")
    }
    
    /// Add background image to the scene
    func addBackgroundImage() {
        // Remove existing background image if present
        childNode(withName: "backgroundImage")?.removeFromParent()
        
        let backgroundImage = SKSpriteNode(imageNamed: "book_page")
        backgroundImage.size = size
        backgroundImage.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundImage.zPosition = -1 // Behind everything
        backgroundImage.name = "backgroundImage"
        addChild(backgroundImage)
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild UI when size changes
        switch currentStep {
        case .raceSelection:
            showRaceSelectionScreen()
        case .genderSelection:
            showGenderSelectionScreen()
        case .classSelection:
            showClassSelectionScreen()
        case .spriteDescription:
            showSpriteDescriptionScreen()
        case .attributeAllocation:
            showAttributeAllocationScreen()
        case .generating:
            break // Don't rebuild during generation
        case .spritePreview:
            break // Don't rebuild sprite preview
        }
    }
    
    // MARK: - Screen Builders
    
    func showRaceSelectionScreen() {
        hideAllTextFields() // Hide any active text fields
        removeAllChildren()
        addBackgroundImage()
        currentStep = .raceSelection
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel removed - no margins needed
        
        // Calculate content dimensions
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        
        // Define panel boundaries (using full screen now)
        let panelTop: CGFloat = size.height
        let panelBottom: CGFloat = 0.0
        
        // Position elements from top to bottom
        let topPadding: CGFloat = 100.0
        let titleY: CGFloat = panelTop - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        
        // Action buttons dimensions
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let bottomPadding: CGFloat = 40.0  // Moved up to avoid border overlap
        let backButtonY: CGFloat = panelBottom + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Book title
        let title = MenuStyling.createBookTitle(text: "Character Race & Gender", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: titleFontSize)
        title.zPosition = 10
        addChild(title)
        
        if isLandscape {
            // LANDSCAPE: Two-column layout - Left for selections, Right for image
            
            // Left column area (for gender + race buttons)
            let leftColumnWidth = dims.panelWidth * 0.5
            let leftColumnX = size.width / 2.0 - dims.panelWidth / 2.0 + leftColumnWidth / 2.0 + 20.0
            
            // Right column area (for race image)
            let rightColumnWidth = dims.panelWidth * 0.45
            let rightColumnX = size.width / 2.0 + dims.panelWidth / 2.0 - rightColumnWidth / 2.0 - 20.0
            
            // Calculate available height for left column content
            let availableHeight = titleBottom - actionButtonsTop - 40.0
            let leftContentStartY = titleBottom - 30.0 // Start below title
            
            // Position image in the center of the available content area (much lower)
            let rightColumnY = (titleBottom + actionButtonsTop) / 2.0
            
            // Race selection at top of left column
            // Race buttons in a 2-column grid
            let races = Race.allCases
            let raceButtonWidth: CGFloat = 220.0
            let raceButtonHeight: CGFloat = 80.0
            let raceSpacing: CGFloat = 12.0
            let raceColumns = 2
            let raceTotalRows = (races.count + raceColumns - 1) / raceColumns
            let raceStartY = leftContentStartY - 75.0
            
            // Align race buttons
            let raceButtonsTotalWidth = CGFloat(raceColumns) * raceButtonWidth + CGFloat(raceColumns - 1) * raceSpacing
            let raceStartX = leftColumnX - raceButtonsTotalWidth / 2.0 + raceButtonWidth / 2.0
            
            var raceIndex = 0
            for raceType in races {
                let row = raceIndex / raceColumns
                let col = raceIndex % raceColumns
                let xPos = raceStartX + CGFloat(col) * (raceButtonWidth + raceSpacing)
                let yPos = raceStartY - CGFloat(row) * (raceButtonHeight + raceSpacing)
                
                let isSelected = selectedRace == raceType
                let button = createRaceButton(
                    raceType: raceType,
                    position: CGPoint(x: xPos, y: yPos),
                    isSelected: isSelected,
                    size: CGSize(width: raceButtonWidth, height: raceButtonHeight)
                )
                button.zPosition = 10
                addChild(button)
                raceIndex += 1
            }
            
            // Gender selection buttons - positioned underneath race buttons in left column
            let lastRaceRow = (races.count - 1) / raceColumns
            let lastRaceY = raceStartY - CGFloat(lastRaceRow) * (raceButtonHeight + raceSpacing)
            let genderStartY = lastRaceY - raceButtonHeight / 2.0 - 50.0 // 50px spacing below race buttons
            
            let genders = Gender.allCases
            let genderButtonWidth: CGFloat = 160.0 // Smaller than race buttons
            let genderButtonHeight: CGFloat = 60.0 // Smaller than race buttons
            let genderSpacing: CGFloat = 12.0
            let genderButtonsTotalWidth = CGFloat(genders.count) * genderButtonWidth + CGFloat(genders.count - 1) * genderSpacing
            let genderStartX = leftColumnX - genderButtonsTotalWidth / 2.0 + genderButtonWidth / 2.0
            
            for (index, gender) in genders.enumerated() {
                let xPos = genderStartX + CGFloat(index) * (genderButtonWidth + genderSpacing)
                let isSelected = selectedGender == gender
                let button = createGenderButton(
                    gender: gender,
                    position: CGPoint(x: xPos, y: genderStartY),
                    isSelected: isSelected,
                    size: CGSize(width: genderButtonWidth, height: genderButtonHeight)
                )
                button.zPosition = 10
                addChild(button)
            }
            
            // Show race image on the right if a race is selected
            if let selectedRace = selectedRace {
                showRaceImage(race: selectedRace, rightX: rightColumnX, imageY: rightColumnY)
            }
        } else {
            // PORTRAIT: Single column layout with scrolling
            // Reset scroll state
            scrollContainer = nil
            isScrolling = false
            lastTouchLocation = .zero
            
            // Calculate available scrollable area
            let containerTop = titleBottom - 20.0
            let containerBottom = actionButtonsTop + 20.0
            let availableHeight = containerTop - containerBottom
            let containerCenterY = (containerTop + containerBottom) / 2.0
            let contentWidth = dims.panelWidth - 40.0
            
            // Create scrollable container with clipping
            let container = SKNode()
            container.position = CGPoint(x: 0, y: 0)
            container.name = "raceSelectionContainer"
            
            // Create clipping mask
            let cropNode = SKCropNode()
            let maskRect = SKShapeNode(rectOf: CGSize(width: contentWidth + 40, height: availableHeight))
            maskRect.fillColor = .white
            maskRect.strokeColor = .clear
            cropNode.maskNode = maskRect
            cropNode.position = CGPoint(x: size.width / 2, y: containerCenterY)
            cropNode.zPosition = 10
            cropNode.name = "raceSelectionCropNode"
            cropNode.addChild(container)
            addChild(cropNode)
            
            // Race buttons at top of scrollable container in a 2-column grid
            let races = Race.allCases
            let raceButtonWidth: CGFloat = 200.0
            let raceButtonHeight: CGFloat = 80.0
            let raceSpacing: CGFloat = 15.0
            let raceColumns = 2
            var currentY = availableHeight / 2.0 - 40.0
            
            var raceIndex = 0
            for raceType in races {
                let row = raceIndex / raceColumns
                let col = raceIndex % raceColumns
                let raceButtonsTotalWidth = CGFloat(raceColumns) * raceButtonWidth + CGFloat(raceColumns - 1) * raceSpacing
                let raceStartX = -raceButtonsTotalWidth / 2.0 + raceButtonWidth / 2.0
                let xPos = raceStartX + CGFloat(col) * (raceButtonWidth + raceSpacing)
                let yPos = currentY - CGFloat(row) * (raceButtonHeight + raceSpacing)
                
                let isSelected = selectedRace == raceType
                let button = createRaceButton(
                    raceType: raceType,
                    position: CGPoint(x: xPos, y: yPos),
                    isSelected: isSelected,
                    size: CGSize(width: raceButtonWidth, height: raceButtonHeight)
                )
                button.zPosition = 10
                container.addChild(button)
                raceIndex += 1
            }
            
            // Calculate last race row position for gender buttons placement and scroll bounds
            let lastRaceRow = (races.count - 1) / raceColumns
            let lastRaceY = currentY - CGFloat(lastRaceRow) * (raceButtonHeight + raceSpacing)
            
            // Gender selection buttons - positioned underneath race buttons in portrait mode too
            let genderStartY = lastRaceY - raceButtonHeight / 2.0 - 50.0 // 50px spacing below race buttons
            
            let genders = Gender.allCases
            let genderButtonWidth: CGFloat = 150.0 // Smaller than race buttons
            let genderButtonHeight: CGFloat = 60.0 // Smaller than race buttons
            let genderSpacing: CGFloat = 12.0
            let genderButtonsTotalWidth = CGFloat(genders.count) * genderButtonWidth + CGFloat(genders.count - 1) * genderSpacing
            let genderStartX = -genderButtonsTotalWidth / 2.0 + genderButtonWidth / 2.0
            
            for (index, gender) in genders.enumerated() {
                let xPos = genderStartX + CGFloat(index) * (genderButtonWidth + genderSpacing)
                let isSelected = selectedGender == gender
                let button = createGenderButton(
                    gender: gender,
                    position: CGPoint(x: xPos, y: genderStartY),
                    isSelected: isSelected,
                    size: CGSize(width: genderButtonWidth, height: genderButtonHeight)
                )
                button.zPosition = 10
                container.addChild(button)
            }
            
            // Recalculate scroll bounds to include gender buttons
            let genderBottom = genderStartY - genderButtonHeight / 2.0
            let updatedContentBottom = genderBottom
            let updatedContentHeight = (availableHeight / 2.0) - updatedContentBottom
            
            if updatedContentHeight > availableHeight {
                scrollMinY = -(updatedContentHeight - availableHeight / 2.0)
                scrollMaxY = availableHeight / 2.0
                scrollContainer = container
                container.position.y = scrollMaxY // Start at top
            } else {
                // Content fits, center it
                container.position.y = (availableHeight - updatedContentHeight) / 2.0
            }
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
            color: (selectedRace == nil || selectedGender == nil) ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: continueButtonY),
            name: "continueButton",
            fontSize: isLandscape ? 20.0 : 24.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
    }
    
    func showRaceImage(race: Race, rightX: CGFloat? = nil, imageY: CGFloat? = nil) {
        // Remove any existing race image
        childNode(withName: "raceImage")?.removeFromParent()
        childNode(withName: "raceImageLabel")?.removeFromParent()
        
        let imageName = getRaceImageName(race: race)
        let imageSprite = SKSpriteNode(imageNamed: imageName)
        
        // Calculate available space in right column
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Calculate title and button positions (matching showRaceSelectionScreen)
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        let topPadding: CGFloat = 100.0
        let titleY: CGFloat = size.height - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let bottomPadding: CGFloat = 40.0
        let backButtonY: CGFloat = 0.0 + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Calculate available space with padding
        let verticalPadding: CGFloat = 20.0 // Padding from title and buttons
        let availableHeight = titleBottom - actionButtonsTop - (verticalPadding * 2)
        let availableWidth = dims.panelWidth * 0.45 - 40.0 // Right column width minus padding
        
        // Position on right side (use provided position or calculate)
        let finalRightX = rightX ?? (size.width / 2.0 + dims.panelWidth / 2.0 - (dims.panelWidth * 0.45) / 2.0 - 20.0)
        let finalImageY = imageY ?? ((titleBottom - verticalPadding + actionButtonsTop + verticalPadding) / 2.0)
        
        // Size the image to fill available space while maintaining aspect ratio
        let imageAspectRatio = imageSprite.size.width / imageSprite.size.height
        var imageWidth = availableWidth
        var imageHeight = imageWidth / imageAspectRatio
        
        // If height exceeds available space, scale down based on height
        if imageHeight > availableHeight {
            imageHeight = availableHeight
            imageWidth = imageHeight * imageAspectRatio
        }
        
        imageSprite.size = CGSize(width: imageWidth, height: imageHeight)
        imageSprite.position = CGPoint(x: finalRightX, y: finalImageY)
        imageSprite.zPosition = 10
        imageSprite.name = "raceImage"
        addChild(imageSprite)
    }
    
    // MARK: - UI Element Creators
    
    /// Generic button creator for selection buttons (race, class, gender)
    private func createSelectionButton(name: String, prefix: String, position: CGPoint, isSelected: Bool, size: CGSize, fontSizeMultiplier: CGFloat = 0.35) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "\(prefix)_\(name)"
        
        // Try to use button images, fall back to colored sprite if images don't exist
        let imageName = isSelected ? "button1_selected" : "button1"
        let buttonSprite: SKSpriteNode
        
        let tempSprite = SKSpriteNode(imageNamed: imageName)
        if tempSprite.texture != nil {
            // Image exists, use it
            buttonSprite = tempSprite
        } else {
            // Fallback: Create colored sprite if image doesn't exist
            buttonSprite = SKSpriteNode(color: isSelected ? MenuStyling.bookAccent : MenuStyling.parchmentBg, size: size)
        }
        
        buttonSprite.size = size
        buttonSprite.zPosition = 1
        buttonSprite.name = "buttonBackground"
        container.addChild(buttonSprite)
        
        // Label on top of button
        let label = SKLabelNode(fontNamed: "Arial")
        label.text = name
        label.fontSize = size.height * fontSizeMultiplier
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 2
        label.isUserInteractionEnabled = false
        buttonSprite.addChild(label)
        
        return container
    }
    
    func createRaceButton(raceType: Race, position: CGPoint, isSelected: Bool, size: CGSize) -> SKNode {
        return createSelectionButton(name: raceType.rawValue, prefix: "raceButton", position: position, isSelected: isSelected, size: size, fontSizeMultiplier: 0.35)
    }
    
    func showClassSelectionScreen() {
        hideAllTextFields() // Hide any active text fields
        removeAllChildren()
        addBackgroundImage()
        currentStep = .classSelection
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel removed - no margins needed
        
        // Calculate content dimensions
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        let nameLabelFontSize: CGFloat = isLandscape ? 18.0 : 22.0
        
        // Define panel boundaries (using full screen now)
        let panelTop: CGFloat = size.height
        let panelBottom: CGFloat = 0.0
        
        // Position elements from top to bottom
        let topPadding: CGFloat = 100.0
        let titleY: CGFloat = panelTop - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        
        // Action buttons dimensions
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let bottomPadding: CGFloat = 40.0  // Moved up to avoid border overlap
        let backButtonY: CGFloat = panelBottom + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Book title (at top center)
        let title = MenuStyling.createBookTitle(text: "Select Class", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: titleFontSize)
        title.zPosition = 10
        addChild(title)
        
        // Character race and gender reminder
        let nameLabel = SKLabelNode(fontNamed: "Arial")
        let raceText = selectedRace != nil ? "\(selectedRace!.rawValue)" : "No Race Selected"
        let genderText = selectedGender != nil ? "\(selectedGender!.rawValue)" : "No Gender Selected"
        nameLabel.text = "\(raceText) - \(genderText)"
        nameLabel.fontSize = nameLabelFontSize
        nameLabel.fontColor = MenuStyling.inkMuted
        nameLabel.position = CGPoint(x: size.width / 2.0, y: titleBottom - 20.0)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        
        let nameLabelBottom: CGFloat = nameLabel.position.y - nameLabelFontSize / 2.0
        
        if isLandscape {
            // LANDSCAPE: Two-column layout - Left for selections, Right for image
            
            // Left column area (for class buttons)
            let leftColumnWidth = dims.panelWidth * 0.5
            let leftColumnX = size.width / 2.0 - dims.panelWidth / 2.0 + leftColumnWidth / 2.0 + 20.0
            
            // Right column area (for class image)
            let rightColumnWidth = dims.panelWidth * 0.45
            let rightColumnX = size.width / 2.0 + dims.panelWidth / 2.0 - rightColumnWidth / 2.0 - 20.0
            
            // Class buttons in a 2-column grid
            let classes = CharacterClass.allCases
            let classButtonWidth: CGFloat = 220.0
            let classButtonHeight: CGFloat = 80.0
            let classSpacing: CGFloat = 12.0
            let classColumns = 2
            let classTotalRows = (classes.count + classColumns - 1) / classColumns
            
            // Center buttons vertically in the available space
            let buttonsCenterY = (nameLabelBottom + actionButtonsTop) / 2.0
            let totalButtonsHeight = CGFloat(classTotalRows) * classButtonHeight + CGFloat(classTotalRows - 1) * classSpacing
            // Position first button's center Y: center - (total height / 2) + (first button height / 2)
            let classStartY = buttonsCenterY + (totalButtonsHeight / 2.0) - (classButtonHeight / 2.0)
            
            // Image position - center it vertically in the available content area (much lower)
            let rightColumnY = (nameLabelBottom + actionButtonsTop) / 2.0
            
            // Align class buttons
            let classButtonsTotalWidth = CGFloat(classColumns) * classButtonWidth + CGFloat(classColumns - 1) * classSpacing
            let classStartX = leftColumnX - classButtonsTotalWidth / 2.0 + classButtonWidth / 2.0
            
            var classIndex = 0
            for classType in classes {
                let row = classIndex / classColumns
                let col = classIndex % classColumns
                let xPos = classStartX + CGFloat(col) * (classButtonWidth + classSpacing)
                let yPos = classStartY - CGFloat(row) * (classButtonHeight + classSpacing)
                
                let isSelected = selectedClass == classType
                let button = createClassButton(
                    classType: classType,
                    position: CGPoint(x: xPos, y: yPos),
                    isSelected: isSelected,
                    size: CGSize(width: classButtonWidth, height: classButtonHeight)
                )
                button.zPosition = 10
                addChild(button)
                classIndex += 1
            }
            
            // Show class image on the right if a class is selected
            if let selectedClass = selectedClass {
                showClassImage(characterClass: selectedClass, rightX: rightColumnX, imageY: rightColumnY)
            }
        } else {
            // PORTRAIT: Single column layout with scrolling
            // Reset scroll state
            scrollContainer = nil
            isScrolling = false
            lastTouchLocation = .zero
            
            // Calculate available scrollable area
            let containerTop = nameLabelBottom - 20.0
            let containerBottom = actionButtonsTop + 20.0
            let availableHeight = containerTop - containerBottom
            let containerCenterY = (containerTop + containerBottom) / 2.0
            let contentWidth = dims.panelWidth - 40.0
            
            // Create scrollable container with clipping
        let container = SKNode()
            container.position = CGPoint(x: 0, y: 0)
            container.name = "classSelectionContainer"
            
            // Create clipping mask
            let cropNode = SKCropNode()
            let maskRect = SKShapeNode(rectOf: CGSize(width: contentWidth + 40, height: availableHeight))
            maskRect.fillColor = .white
            maskRect.strokeColor = .clear
            cropNode.maskNode = maskRect
            cropNode.position = CGPoint(x: size.width / 2, y: containerCenterY)
            cropNode.zPosition = 10
            cropNode.name = "classSelectionCropNode"
            cropNode.addChild(container)
            addChild(cropNode)
            
            // Class buttons in a 2-column grid
            let classes = CharacterClass.allCases
            let classButtonWidth: CGFloat = 200.0
            let classButtonHeight: CGFloat = 80.0
            let classSpacing: CGFloat = 15.0
            let classColumns = 2
            var currentY = availableHeight / 2.0 - 20.0 // Start from top
            
            var classIndex = 0
        for classType in classes {
                let row = classIndex / classColumns
                let col = classIndex % classColumns
                let classButtonsTotalWidth = CGFloat(classColumns) * classButtonWidth + CGFloat(classColumns - 1) * classSpacing
                let classStartX = -classButtonsTotalWidth / 2.0 + classButtonWidth / 2.0
                let xPos = classStartX + CGFloat(col) * (classButtonWidth + classSpacing)
                let yPos = currentY - CGFloat(row) * (classButtonHeight + classSpacing)
            
            let isSelected = selectedClass == classType
            let button = createClassButton(
                classType: classType,
                position: CGPoint(x: xPos, y: yPos),
                isSelected: isSelected,
                    size: CGSize(width: classButtonWidth, height: classButtonHeight)
            )
                button.zPosition = 10
            container.addChild(button)
                classIndex += 1
            }
            
            // Calculate scroll bounds
            let lastClassRow = (classes.count - 1) / classColumns
            let lastClassY = currentY - CGFloat(lastClassRow) * (classButtonHeight + classSpacing)
            let contentBottom = lastClassY - classButtonHeight / 2.0
            let contentHeight = (availableHeight / 2.0) - contentBottom
            
            if contentHeight > availableHeight {
                scrollMinY = -(contentHeight - availableHeight / 2.0)
                scrollMaxY = availableHeight / 2.0
                scrollContainer = container
                container.position.y = scrollMaxY // Start at top
            } else {
                // Content fits, center it
                container.position.y = (availableHeight - contentHeight) / 2.0
            }
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
    
    func showClassImage(characterClass: CharacterClass, rightX: CGFloat? = nil, imageY: CGFloat? = nil) {
        // Remove any existing class image
        childNode(withName: "classImage")?.removeFromParent()
        childNode(withName: "classImageLabel")?.removeFromParent()
        
        let imageName = getClassImageName(characterClass: characterClass)
        let imageSprite = SKSpriteNode(imageNamed: imageName)
        
        // Calculate available space in right column
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Calculate title and button positions (matching showClassSelectionScreen)
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        let nameLabelFontSize: CGFloat = isLandscape ? 18.0 : 22.0
        let topPadding: CGFloat = 100.0
        let titleY: CGFloat = size.height - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        let nameLabelY: CGFloat = titleBottom - 20.0
        let nameLabelBottom: CGFloat = nameLabelY - nameLabelFontSize / 2.0
        
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let bottomPadding: CGFloat = 40.0
        let backButtonY: CGFloat = 0.0 + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Calculate available space with padding
        let verticalPadding: CGFloat = 20.0 // Padding from title/name label and buttons
        let availableHeight = nameLabelBottom - actionButtonsTop - (verticalPadding * 2)
        let availableWidth = dims.panelWidth * 0.45 - 40.0 // Right column width minus padding
        
        // Position on right side (use provided position or calculate)
        let finalRightX = rightX ?? (size.width / 2.0 + dims.panelWidth / 2.0 - (dims.panelWidth * 0.45) / 2.0 - 20.0)
        let finalImageY = imageY ?? ((nameLabelBottom - verticalPadding + actionButtonsTop + verticalPadding) / 2.0)
        
        // Size the image to fill available space while maintaining aspect ratio
        let imageAspectRatio = imageSprite.size.width / imageSprite.size.height
        var imageWidth = availableWidth
        var imageHeight = imageWidth / imageAspectRatio
        
        // If height exceeds available space, scale down based on height
        if imageHeight > availableHeight {
            imageHeight = availableHeight
            imageWidth = imageHeight * imageAspectRatio
        }
        
        imageSprite.size = CGSize(width: imageWidth, height: imageHeight)
        imageSprite.position = CGPoint(x: finalRightX, y: finalImageY)
        imageSprite.zPosition = 10
        imageSprite.name = "classImage"
        addChild(imageSprite)
    }
    
    func showSpriteDescriptionScreen() {
        hideAllTextFields() // Hide any active text fields
        removeAllChildren()
        addBackgroundImage()
        currentStep = .spriteDescription
        
        // Reset scroll state
        scrollContainer = nil
        isScrolling = false
        lastTouchLocation = .zero
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        
        // SINGLE COLUMN LAYOUT for both orientations
        
        // Book page panel removed - no margins needed
        
        // Book title - positioned from top of screen
        let titleY: CGFloat = size.height - 80.0
        let title = MenuStyling.createBookTitle(text: "Character Appearance", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: 30.0)
        title.zPosition = 10
        addChild(title)
        
        // Character race, gender, and class reminder
        let raceClassLabelY: CGFloat = titleY - 40.0
        let raceClassLabel = SKLabelNode(fontNamed: "Arial")
        let raceText = selectedRace?.rawValue ?? "No Race"
        let genderText = selectedGender?.rawValue ?? "No Gender"
        let classText = selectedClass?.rawValue ?? "No Class"
        let raceClassText = "\(raceText) - \(genderText) - \(classText)"
        raceClassLabel.text = raceClassText
        raceClassLabel.fontSize = 18.0
        raceClassLabel.fontColor = MenuStyling.inkMuted
        raceClassLabel.position = CGPoint(x: size.width / 2.0, y: raceClassLabelY)
        raceClassLabel.zPosition = 10
        addChild(raceClassLabel)
        
        // Buttons at bottom (always visible) - moved up for better positioning
        let backButtonY = 100.0  // Position from bottom of screen (no panel margins)
        let continueButtonY = backButtonY + dims.buttonHeight + dims.spacing
        
        // Calculate content area - no scrolling needed, just fit everything
        let titleBottom = titleY - 50.0  // Increased from 30.0 to 50.0 to prevent title cutoff
        let continueButtonTop = continueButtonY + dims.buttonHeight / 2.0
        let bottomSpacing: CGFloat = 25.0
        let containerBottom = continueButtonTop + bottomSpacing
        let containerTop = titleBottom - 20.0
        let availableHeight = containerTop - containerBottom
        let containerCenterY = (containerTop + containerBottom) / 2.0
        
        // Create scrollable container
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 0)
        container.name = "contentContainer"
        
        // Create clipping mask
        let cropNode = SKCropNode()
        let contentWidth = min(dims.buttonWidth, size.width * 0.9)
        let maskWidth = contentWidth + 40
        let mask = SKShapeNode(rectOf: CGSize(width: maskWidth, height: availableHeight))
        mask.fillColor = .white
        mask.strokeColor = .clear
        cropNode.maskNode = mask
        cropNode.position = CGPoint(x: size.width / 2.0, y: containerCenterY)
        cropNode.zPosition = 10
        cropNode.name = "contentCropNode"
        cropNode.addChild(container)
        addChild(cropNode)
        
        // Content starting position - add more top padding to avoid title cutoff
        let topPadding: CGFloat = 30.0
        let startY = availableHeight / 2.0 - topPadding
        var currentY = startY
        
        // Name input label
        let nameInstruction = SKLabelNode(fontNamed: "Arial")
        nameInstruction.text = "Character's Name"
        nameInstruction.fontSize = 20.0
        nameInstruction.fontColor = MenuStyling.inkColor
        nameInstruction.position = CGPoint(x: 0, y: currentY)
        nameInstruction.zPosition = 1
        nameInstruction.horizontalAlignmentMode = .center
        container.addChild(nameInstruction)
        currentY -= 30.0  // Spacing between label and input box
        
        // Name input area
        let nameInputHeight: CGFloat = 50.0
        currentY -= nameInputHeight / 2.0
        let nameInputArea = SKShapeNode(rectOf: CGSize(width: contentWidth, height: nameInputHeight), cornerRadius: 8)
        nameInputArea.fillColor = MenuStyling.parchmentBg
        nameInputArea.strokeColor = MenuStyling.parchmentBorder
        nameInputArea.lineWidth = 2
        nameInputArea.position = CGPoint(x: 0, y: currentY)
        nameInputArea.zPosition = 1
        nameInputArea.name = "nameInputArea"
        
        let nameHighlight = SKShapeNode(rectOf: CGSize(width: contentWidth - 4, height: nameInputHeight * 0.3), cornerRadius: 6)
        nameHighlight.fillColor = SKColor(white: 1.0, alpha: 0.1)
        nameHighlight.strokeColor = SKColor.clear
        nameHighlight.position = CGPoint(x: 0, y: nameInputHeight * 0.15)
        nameInputArea.addChild(nameHighlight)
        
        container.addChild(nameInputArea)
        
        let nameDisplay = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameDisplay.text = characterName.isEmpty ? "" : characterName // Remove placeholder text
        nameDisplay.fontSize = 20.0
        nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        nameDisplay.verticalAlignmentMode = .center
        nameDisplay.horizontalAlignmentMode = .center
        // No padding needed here - center at origin (padding is in native text field)
        nameDisplay.position = CGPoint(x: 0, y: 0)
        nameDisplay.zPosition = 11
        nameDisplay.name = "nameDisplay"
        nameInputArea.addChild(nameDisplay)
        // Move down from name input: half height of name + spacing
        // We need enough space so description input (max 150px height) doesn't overlap
        // Spacing needed: nameInputHeight/2 (to bottom of name) + gap + descriptionHeight/2 (to center of description)
        currentY -= nameInputHeight / 2.0 + 100.0
        
        // Description or Preview area (centered, replaces each other)
        let descriptionPreviewY = currentY
        let descriptionPreviewHeight: CGFloat = 200.0
        
        // Show description box if no preview exists, otherwise show preview
        if previewTexture == nil && !isGeneratingPreview {
            // Description instruction
            currentY = descriptionPreviewY + descriptionPreviewHeight / 2.0 - 30.0
            let instruction = SKLabelNode(fontNamed: "Arial")
            instruction.text = "Describe what your character looks like:"
            instruction.fontSize = 18.0
            instruction.fontColor = MenuStyling.inkColor
            instruction.position = CGPoint(x: 0, y: currentY)
            instruction.zPosition = 1
            instruction.horizontalAlignmentMode = .center
            instruction.name = "instructionLabel"
            container.addChild(instruction)
            currentY -= 35.0  // Increased from 28.0 to 35.0 (removed example text, adjusted spacing)
            
            // Description input area (centered)
            let inputHeight: CGFloat = min(descriptionPreviewHeight - 80.0, 150.0)
            // Position description input area at descriptionPreviewY (center of description area)
            currentY = descriptionPreviewY
            let descriptionInputArea = SKShapeNode(rectOf: CGSize(width: contentWidth, height: inputHeight), cornerRadius: 8)
            descriptionInputArea.fillColor = MenuStyling.parchmentBg
            descriptionInputArea.strokeColor = MenuStyling.parchmentBorder
            descriptionInputArea.lineWidth = 2
            descriptionInputArea.position = CGPoint(x: 0, y: currentY)
            descriptionInputArea.zPosition = 1
            descriptionInputArea.name = "descriptionInputArea"
            
            let highlight = SKShapeNode(rectOf: CGSize(width: contentWidth - 4, height: inputHeight * 0.3), cornerRadius: 6)
            highlight.fillColor = SKColor(white: 1.0, alpha: 0.1)
            highlight.strokeColor = SKColor.clear
            highlight.position = CGPoint(x: 0, y: inputHeight * 0.15)
            descriptionInputArea.addChild(highlight)
            
            container.addChild(descriptionInputArea)
            
            let descriptionDisplay = SKLabelNode(fontNamed: "Arial")
            descriptionDisplay.text = spriteDescription.isEmpty ? "Tap to enter description" : spriteDescription
            descriptionDisplay.fontSize = 18.0
            descriptionDisplay.fontColor = spriteDescription.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
            descriptionDisplay.verticalAlignmentMode = .top
            descriptionDisplay.horizontalAlignmentMode = .left
            // Add more padding: 15px left, 15px top (from top of input area)
            descriptionDisplay.position = CGPoint(x: -contentWidth / 2.0 + 15, y: inputHeight / 2.0 - 15)
            descriptionDisplay.preferredMaxLayoutWidth = contentWidth - 30 // Account for padding on both sides
            descriptionDisplay.numberOfLines = 0
            descriptionDisplay.zPosition = 11
            descriptionDisplay.name = "descriptionDisplay"
            descriptionInputArea.addChild(descriptionDisplay)
        } else if let existingTexture = previewTexture {
            // Show preview in place of description (Continue button already removed)
            displayPreviewImageInSingleColumn(texture: existingTexture, container: container, previewY: descriptionPreviewY, contentWidth: contentWidth)
        }
        
        currentY = descriptionPreviewY - descriptionPreviewHeight / 2.0 - 20.0
        
        // Disable scrolling - content should fit without scrolling
        scrollContainer = nil
        scrollMinY = 0
        scrollMaxY = 0
        
        // Buttons at bottom (only show Continue if no preview exists)
        let buttonWidth: CGFloat = contentWidth
        // Only show Continue button if there's no preview (preview has its own buttons)
        if previewTexture == nil {
            let continueButton = MenuStyling.createBookButton(
                text: "Continue",
                size: CGSize(width: buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentBg,
                position: CGPoint(x: size.width / 2.0, y: continueButtonY),
                name: "continueButton",
                fontSize: 22.0
            )
            continueButton.zPosition = 1000
            addChild(continueButton)
        }
        
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2.0, y: backButtonY),
            name: "backButton",
            fontSize: 22.0
        )
        backButton.zPosition = 1000
        addChild(backButton)
    }
    
    func displayPreviewImageInSingleColumn(texture: SKTexture, container: SKNode, previewY: CGFloat, contentWidth: CGFloat) {
        // Remove description box elements (may already be removed, but safe to try)
        container.childNode(withName: "instructionLabel")?.removeFromParent()
        container.childNode(withName: "exampleLabel")?.removeFromParent()
        container.childNode(withName: "descriptionInputArea")?.removeFromParent()
        
        // Remove loading spinner (will be replaced by preview)
        container.childNode(withName: "loadingSpinner")?.removeFromParent()
        container.childNode(withName: "loadingLabel")?.removeFromParent()
        
        // Remove old preview if exists
        container.childNode(withName: "previewContainer")?.removeFromParent()
        container.childNode(withName: "refreshButton")?.removeFromParent()
        container.childNode(withName: "continueButton")?.removeFromParent()
        
        let textureSize = texture.size()
        let maxWidth: CGFloat = contentWidth - 40
        let maxHeight: CGFloat = 200.0
        let aspectRatio = textureSize.width / textureSize.height
        var finalWidth = min(maxWidth, textureSize.width)
        var finalHeight = finalWidth / aspectRatio
        if finalHeight > maxHeight {
            finalHeight = maxHeight
            finalWidth = finalHeight * aspectRatio
        }
        
        // Create preview sprite
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: finalWidth, height: finalHeight))
        sprite.position = CGPoint(x: 0, y: 0)
        sprite.zPosition = 2
        sprite.name = "previewSprite"
        texture.filteringMode = .linear
        
        // Create container for sprite and border
        let previewContainer = SKNode()
        previewContainer.position = CGPoint(x: 0, y: previewY)
        previewContainer.zPosition = 2
        previewContainer.name = "previewContainer"
        
        // Add fancy border frame
        let borderFrame = MenuStyling.createBookPageBorder(size: CGSize(width: finalWidth, height: finalHeight), padding: 10.0)
        borderFrame.zPosition = 1
        previewContainer.addChild(borderFrame)
        
        // Add sprite to container
        previewContainer.addChild(sprite)
        container.addChild(previewContainer)
        
        previewSprite = sprite
        
        // Add buttons below preview
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let buttonSpacing: CGFloat = 30.0  // Increased from 15.0 for more space between preview and button
        let buttonWidth: CGFloat = contentWidth
        
        // Refresh button
        let refreshButtonY = previewY - finalHeight / 2.0 - buttonSpacing - dims.buttonHeight / 2.0
        let refreshButton = MenuStyling.createBookButton(
            text: "Refresh Character Image",
            size: CGSize(width: buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: 0, y: refreshButtonY),
            name: "refreshButton",
            fontSize: 18.0
        )
        refreshButton.zPosition = 100  // High zPosition to be above other container elements
        container.addChild(refreshButton)
        
        // Continue button (below refresh button) - takes you to attribute screen
        // Add directly to scene (like Back button) to ensure it's on top layer
        // Position it with proper spacing above the Back button
        // Use same backButtonY as showSpriteDescriptionScreen (100.0 from bottom)
        let backButtonY = 100.0  // Position from bottom of screen (matches showSpriteDescriptionScreen)
        let continueButtonSpacing: CGFloat = dims.spacing // Use same spacing as other button pairs
        let sceneContinueButtonY = backButtonY + dims.buttonHeight + continueButtonSpacing
        
        let continueButton = MenuStyling.createBookButton(
            text: "Continue",
            size: CGSize(width: buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.bookSecondary,
            position: CGPoint(x: size.width / 2.0, y: sceneContinueButtonY),
            name: "continueButton",
            fontSize: 18.0
        )
        continueButton.zPosition = 1001  // Higher than Back button (1000) to ensure it's on top
        addChild(continueButton)  // Add directly to scene, not container
        
        // Recalculate scroll bounds to include the buttons
        // Find the crop node to get availableHeight
        if let cropNode = container.parent as? SKCropNode {
            let mask = cropNode.maskNode as? SKShapeNode
            let availableHeight = mask?.frame.height ?? size.height * 0.6
            
            // Find the startY (top of content) - look for name input area
            var startY: CGFloat = availableHeight / 2.0 - 30.0 // Default top padding
            if let nameInputArea = container.childNode(withName: "nameInputArea") {
                let nameInputY = nameInputArea.position.y
                let nameInputHeight: CGFloat = 50.0
                startY = nameInputY + nameInputHeight / 2.0 + 20.0
            }
            
            // Calculate contentBottom based on the lowest button in container (refreshButton)
            // refreshButtonY is the center Y of the button, so bottom is center - height/2
            let buttonBottom = refreshButtonY - dims.buttonHeight / 2.0
            let contentBottom = buttonBottom - 40.0 // Increased padding to ensure refresh button is fully visible
            let contentHeight = startY - contentBottom
            
            // Disable scrolling - just ensure content fits
            // If content doesn't fit, it will be clipped but no scrolling enabled
            scrollContainer = nil
            scrollMinY = 0
            scrollMaxY = 0
        }
    }
    
    func createClassButton(classType: CharacterClass, position: CGPoint, isSelected: Bool, size: CGSize) -> SKNode {
        return createSelectionButton(name: classType.rawValue, prefix: "classButton", position: position, isSelected: isSelected, size: size, fontSizeMultiplier: 0.35)
    }
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let node = atPoint(location)
        
        // First check if tapping on input areas (these should work even in scrollable containers)
        if currentStep == .spriteDescription {
            // Check for name input area first
            var currentNode: SKNode? = node
            while let current = currentNode {
                if let nodeName = current.name {
                    print("🔍 Checking node: \(nodeName)")
                    if nodeName == "nameInputArea" || nodeName == "nameDisplay" {
                        print("✅ Found name input area, showing text field")
                        showNameInputField()
                        return
                    }
                    if nodeName == "descriptionInputArea" || nodeName == "descriptionDisplay" {
                        print("✅ Found description input area, showing text field")
                        showDescriptionInputField()
                        return
                    }
                }
                currentNode = current.parent
            }
            print("❌ No input area found in node hierarchy")
        }
        
        // Check for scrolling in portrait mode on sprite description, race selection, or class selection screen
        if (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height {
            let cropNodeName: String
            if currentStep == .spriteDescription {
                cropNodeName = "contentCropNode"
            } else if currentStep == .raceSelection {
                cropNodeName = "raceSelectionCropNode"
            } else {
                cropNodeName = "classSelectionCropNode"
            }
            if let cropNode = childNode(withName: cropNodeName) {
                let locationInCropNode = convert(location, to: cropNode)
                if cropNode.contains(location) || cropNode.frame.contains(locationInCropNode) {
                    isScrolling = false
                    lastTouchLocation = location
                    return
                }
                // Also check if touch is on any node that's a descendant of the scroll container
                let nodesAtLocation = nodes(at: location)
                for nodeAtLocation in nodesAtLocation {
                    var currentNode: SKNode? = nodeAtLocation
                    while let current = currentNode {
                        if let container = scrollContainer, current == container || current.parent == container {
                            isScrolling = false
                            lastTouchLocation = location
                            return
                        }
                        currentNode = current.parent
                    }
                }
            }
        }
        
        switch currentStep {
        case .raceSelection:
            handleRaceSelectionTouch(node: node)
            
        case .genderSelection:
            handleGenderSelectionTouch(node: node)
            
        case .classSelection:
            handleClassSelectionTouch(node: node)
            
        case .spriteDescription:
            handleSpriteDescriptionTouch(node: node, location: location)
            
        case .attributeAllocation:
            handleAttributeAllocationTouch(node: node)
            
        case .generating:
            break // Ignore touches during generation
            
        case .spritePreview:
            handleSpritePreviewTouch(node: node, location: location)
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        guard (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height else { return }
        guard lastTouchLocation != .zero else { return }
        
        let location = touch.location(in: self)
        let deltaY = location.y - lastTouchLocation.y
        
        if abs(deltaY) > 5 {
            isScrolling = true
            
            let currentY = scrollContainer!.position.y
            let proposedY = currentY - deltaY
            let clampedY = min(scrollMaxY, proposedY)
            let newY = max(scrollMinY, clampedY)
            scrollContainer!.position.y = newY
        }
        
        lastTouchLocation = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopContinuousButtonPress()
        
        guard (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height else { return }
        
        if isScrolling {
            isScrolling = false
            lastTouchLocation = .zero
            return
        }
        
        lastTouchLocation = .zero
        
        if let touch = touches.first {
            let location = touch.location(in: self)
            let node = atPoint(location)
            if currentStep == .spriteDescription {
                handleSpriteDescriptionTouch(node: node, location: location)
            } else if currentStep == .raceSelection {
                handleRaceSelectionTouch(node: node)
            } else if currentStep == .classSelection {
                handleClassSelectionTouch(node: node)
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopContinuousButtonPress()
        isScrolling = false
        lastTouchLocation = .zero
    }
    #endif
    
    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let node = atPoint(location)
        
        // First check if clicking on input areas (these should work even in scrollable containers)
        if currentStep == .spriteDescription {
            // Check for name input area first
            var currentNode: SKNode? = node
            while let current = currentNode {
                if current.name == "nameInputArea" || current.name == "nameDisplay" {
                    showNameInputField()
                    return
                }
                if current.name == "descriptionInputArea" || current.name == "descriptionDisplay" {
                    showDescriptionInputField()
                    return
                }
                currentNode = current.parent
            }
        }
        
        // Check for scrolling in portrait mode on sprite description, race selection, or class selection screen
        if (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height {
            let cropNodeName: String
            if currentStep == .spriteDescription {
                cropNodeName = "contentCropNode"
            } else if currentStep == .raceSelection {
                cropNodeName = "raceSelectionCropNode"
            } else {
                cropNodeName = "classSelectionCropNode"
            }
            if let cropNode = childNode(withName: cropNodeName) {
                let locationInCropNode = convert(location, to: cropNode)
                if cropNode.contains(location) || cropNode.frame.contains(locationInCropNode) {
                    isScrolling = false
                    lastTouchLocation = location
                    return
                }
                // Also check if click is on any node that's a descendant of the scroll container
                let nodesAtLocation = nodes(at: location)
                for nodeAtLocation in nodesAtLocation {
                    var currentNode: SKNode? = nodeAtLocation
                    while let current = currentNode {
                        if let container = scrollContainer, current == container || current.parent == container {
                            isScrolling = false
                            lastTouchLocation = location
                            return
                        }
                        currentNode = current.parent
                    }
                }
            }
        }
        
        switch currentStep {
        case .raceSelection:
            handleRaceSelectionTouch(node: node)
            
        case .genderSelection:
            handleGenderSelectionTouch(node: node)
            
        case .classSelection:
            handleClassSelectionTouch(node: node)
            
        case .spriteDescription:
            handleSpriteDescriptionTouch(node: node, location: location)
            
        case .attributeAllocation:
            handleAttributeAllocationTouch(node: node)
            
        case .generating:
            break // Ignore touches during generation
            
        case .spritePreview:
            handleSpritePreviewTouch(node: node, location: location)
            break
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height else { return }
        guard lastTouchLocation != .zero else { return }
        
        let location = event.location(in: self)
        let deltaY = location.y - lastTouchLocation.y
        
        if abs(deltaY) > 5 {
            isScrolling = true
            
            let currentY = scrollContainer!.position.y
            let proposedY = currentY - deltaY
            let clampedY = min(scrollMaxY, proposedY)
            let newY = max(scrollMinY, clampedY)
            scrollContainer!.position.y = newY
        }
        
        lastTouchLocation = location
    }
    
    override func mouseUp(with event: NSEvent) {
        stopContinuousButtonPress()
        guard (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height else { return }
        
        if isScrolling {
            isScrolling = false
            lastTouchLocation = .zero
            return
        }
        
        lastTouchLocation = .zero
        
        let location = event.location(in: self)
        let node = atPoint(location)
        if currentStep == .spriteDescription {
            handleSpriteDescriptionTouch(node: node, location: location)
        } else if currentStep == .raceSelection {
            handleRaceSelectionTouch(node: node)
        } else if currentStep == .classSelection {
            handleClassSelectionTouch(node: node)
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard (currentStep == .spriteDescription || currentStep == .raceSelection || currentStep == .classSelection) && scrollContainer != nil && size.width <= size.height else { return }
        
        let deltaY: CGFloat
        if event.hasPreciseScrollingDeltas {
            deltaY = event.scrollingDeltaY * 1.0
        } else {
            deltaY = event.scrollingDeltaY * 2.0
        }
        
        let currentY = scrollContainer!.position.y
        let proposedY = currentY - deltaY
        let clampedY = min(scrollMaxY, proposedY)
        let newY = max(scrollMinY, clampedY)
        scrollContainer!.position.y = newY
    }
        #endif
    
    // MARK: - Helpers
    
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
    
    // MARK: - Touch Handlers
    
    func handleRaceSelectionTouch(node: SKNode) {
        // Check for gender button first (since we added gender to race selection screen)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("genderButton_") {
                let genderName = nodeName.replacingOccurrences(of: "genderButton_", with: "")
                if let genderType = Gender.allCases.first(where: { $0.rawValue == genderName }) {
                    selectedGender = genderType
                    showRaceSelectionScreen() // Refresh to show selection
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for race button (traverse up parent chain)
        currentNode = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("raceButton_") {
                let raceName = nodeName.replacingOccurrences(of: "raceButton_", with: "")
                if let raceType = Race.allCases.first(where: { $0.rawValue == raceName }) {
                    selectedRace = raceType
                    showRaceSelectionScreen() // Refresh to show selection
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for continue button (traverse up parent chain)
        if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
            if let raceType = selectedRace, let genderType = selectedGender {
                animateButtonPress(continueButton) {
                    self.showClassSelectionScreen() // Skip gender selection screen since it's integrated
                }
            }
            return
        }
        
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.goBackToStartScreen()
            }
            return
        }
    }
    
    func handleClassSelectionTouch(node: SKNode) {
        // Check for class button (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("classButton_") {
                let className = nodeName.replacingOccurrences(of: "classButton_", with: "")
                if let classType = CharacterClass.allCases.first(where: { $0.rawValue == className }) {
                    selectedClass = classType
                    // Apply class starting attributes
                    applyClassStartingAttributes(for: classType)
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
                self.showRaceSelectionScreen() // Go back to race/gender selection screen
            }
            return
        }
    }
    
    func showGenderSelectionScreen() {
        removeAllChildren()
        currentStep = .genderSelection
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel removed - no margins needed
        
        // Calculate content dimensions
        let titleFontSize: CGFloat = isLandscape ? 30.0 : 34.0
        
        // Gender selection - two buttons side by side
        let buttonWidth: CGFloat = isLandscape ? 200.0 : 180.0
        let buttonHeight: CGFloat = isLandscape ? 70.0 : 75.0
        let spacing: CGFloat = isLandscape ? 30.0 : 25.0
        
        // Define panel boundaries (using full screen now)
        let panelTop: CGFloat = size.height
        let panelBottom: CGFloat = 0.0
        
        // Position elements from top to bottom
        let topPadding: CGFloat = 100.0
        let titleY: CGFloat = panelTop - topPadding
        let titleBottom: CGFloat = titleY - titleFontSize / 2.0
        
        // Race reminder
        let raceLabelY: CGFloat = titleBottom - 20.0
        let raceLabel = SKLabelNode(fontNamed: "Arial")
        let raceText = selectedRace != nil ? "\(selectedRace!.rawValue)" : "No Race Selected"
        raceLabel.text = "Race: \(raceText)"
        raceLabel.fontSize = isLandscape ? 18.0 : 22.0
        raceLabel.fontColor = MenuStyling.inkMuted
        raceLabel.position = CGPoint(x: size.width / 2.0, y: raceLabelY)
        raceLabel.zPosition = 10
        addChild(raceLabel)
        
        // Position action buttons at bottom
        let actionButtonHeight: CGFloat = dims.buttonHeight
        let actionSpacing: CGFloat = dims.spacing
        let bottomPadding: CGFloat = 20.0
        let backButtonY: CGFloat = panelBottom + bottomPadding + actionButtonHeight / 2.0
        let continueButtonY: CGFloat = backButtonY + actionButtonHeight + actionSpacing
        let actionButtonsTop: CGFloat = continueButtonY + actionButtonHeight / 2.0
        
        // Book title
        let title = MenuStyling.createBookTitle(text: "Select Gender", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: titleFontSize)
        title.zPosition = 10
        addChild(title)
        
        // Gender selection container - center it in available space
        let container = SKNode()
        let gridCenterY: CGFloat = (raceLabelY - 25.0 + actionButtonsTop) / 2.0
        container.position = CGPoint(x: size.width / 2.0, y: gridCenterY)
        container.zPosition = 10
        addChild(container)
        
        // Create gender buttons side by side
        let genders = Gender.allCases
        let totalWidth = CGFloat(genders.count) * buttonWidth + CGFloat(genders.count - 1) * spacing
        let startX = -totalWidth / 2.0 + buttonWidth / 2.0
        
        for (index, gender) in genders.enumerated() {
            let xPos = startX + CGFloat(index) * (buttonWidth + spacing)
            let isSelected = selectedGender == gender
            let button = createGenderButton(
                gender: gender,
                position: CGPoint(x: xPos, y: 0),
                isSelected: isSelected,
                size: CGSize(width: buttonWidth, height: buttonHeight)
            )
            container.addChild(button)
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
            color: selectedGender == nil ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: continueButtonY),
            name: "continueButton",
            fontSize: isLandscape ? 20.0 : 24.0
        )
        continueButton.zPosition = 10
        addChild(continueButton)
    }
    
    func createGenderButton(gender: Gender, position: CGPoint, isSelected: Bool, size: CGSize) -> SKNode {
        return createSelectionButton(name: gender.rawValue, prefix: "genderButton", position: position, isSelected: isSelected, size: size, fontSizeMultiplier: 0.4)
    }
    
    func handleGenderSelectionTouch(node: SKNode) {
        // Check for gender button (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("genderButton_") {
                let genderName = nodeName.replacingOccurrences(of: "genderButton_", with: "")
                if let genderType = Gender.allCases.first(where: { $0.rawValue == genderName }) {
                    selectedGender = genderType
                    showGenderSelectionScreen() // Refresh to show selection
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for continue button (traverse up parent chain)
        if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
            if let genderType = selectedGender {
                animateButtonPress(continueButton) {
                    self.showClassSelectionScreen()
                }
            }
            return
        }
        
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showRaceSelectionScreen()
            }
            return
        }
    }
    
    func showAttributeAllocationScreen() {
        hideAllTextFields() // Hide any active text fields
        removeAllChildren()
        addBackgroundImage()
        currentStep = .attributeAllocation
        
        // Ensure starting attributes are applied from the selected class
        // This guarantees the character starts with class-specific attributes
        if let selectedClass = selectedClass {
            applyClassStartingAttributes(for: selectedClass)
        } else {
            // No class selected - reset to 0 for all attributes
            allocatedAttributes = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0)
            baseAttributes = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0)
            remainingAttributePoints = 20
        }
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel removed - no margins needed
        
        // Title - positioned from top of screen
        let titleY: CGFloat = size.height - 80.0
        let title = MenuStyling.createBookTitle(text: "Allocate Attributes", position: CGPoint(x: size.width / 2.0, y: titleY), fontSize: isLandscape ? 30.0 : 34.0)
        title.zPosition = 10
        addChild(title)
        
        // Character race, gender, and class reminder
        let nameLabelY: CGFloat = titleY - 40.0
        let nameLabel = SKLabelNode(fontNamed: "Arial")
        let raceText = selectedRace?.rawValue ?? "No Race"
        let genderText = selectedGender?.rawValue ?? "No Gender"
        let classText = selectedClass?.rawValue ?? "No Class"
        let raceClassText = "\(raceText) - \(genderText) - \(classText)"
        nameLabel.text = raceClassText
        nameLabel.fontSize = isLandscape ? 18.0 : 22.0
        nameLabel.fontColor = MenuStyling.inkMuted
        nameLabel.position = CGPoint(x: size.width / 2.0, y: nameLabelY)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        
        // Points remaining
        let pointsY: CGFloat = nameLabelY - 30.0
        let pointsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        pointsLabel.text = "Points Remaining: \(remainingAttributePoints)"
        pointsLabel.fontSize = isLandscape ? 20.0 : 24.0
        pointsLabel.fontColor = remainingAttributePoints == 0 ? MenuStyling.bookSecondary : MenuStyling.inkColor
        pointsLabel.position = CGPoint(x: size.width / 2.0, y: pointsY)
        pointsLabel.zPosition = 10
        pointsLabel.name = "pointsLabel"
        addChild(pointsLabel)
        
        // Instruction
        let instructionY: CGFloat = pointsY - 35.0
        let instruction = SKLabelNode(fontNamed: "Arial")
        instruction.text = "You have 20 points to allocate"
        instruction.fontSize = isLandscape ? 16.0 : 18.0
        instruction.fontColor = MenuStyling.inkMuted
        instruction.position = CGPoint(x: size.width / 2.0, y: instructionY)
        instruction.zPosition = 10
        addChild(instruction)
        
        // Attributes list
        let attributes: [(Ability, String)] = [
            (.strength, "Strength"),
            (.dexterity, "Dexterity"),
            (.constitution, "Constitution"),
            (.intelligence, "Intelligence"),
            (.wisdom, "Wisdom"),
            (.charisma, "Charisma")
        ]
        
        let attrHeight: CGFloat = isLandscape ? 50.0 : 55.0
        let attrSpacing: CGFloat = 12.0
        let startY: CGFloat = instructionY - 50.0
        
        for (index, (ability, name)) in attributes.enumerated() {
            let yPos = startY - CGFloat(index) * (attrHeight + attrSpacing)
            let score = allocatedAttributes.score(for: ability)
            let baseScore = baseAttributes.score(for: ability)
            
            let attrNode = createAttributeAllocationNode(
                ability: ability,
                name: name,
                score: score,
                modifier: 0, // Not displayed anymore
                position: CGPoint(x: size.width / 2.0, y: yPos),
                size: CGSize(width: isLandscape ? 500.0 : 400.0, height: attrHeight),
                canIncrease: remainingAttributePoints > 0,
                canDecrease: score > baseScore // Can only decrease if above base attribute
            )
            attrNode.zPosition = 10
            addChild(attrNode)
        }
        
        // Calculate bottom of attributes list
        let lastAttributeY = startY - CGFloat(attributes.count - 1) * (attrHeight + attrSpacing)
        let attributesBottom = lastAttributeY - attrHeight / 2.0
        
        // Check if sprites are ready
        let spritesReady = currentCharacter?.framePaths != nil && !currentCharacter!.framePaths!.isEmpty && !isGeneratingSprites
        
        // Define panel boundaries for button positioning (using full screen)
        let panelBottom: CGFloat = 0.0
        let bottomPadding: CGFloat = 40.0
        let minButtonY = panelBottom + bottomPadding + dims.buttonHeight / 2.0
        
        // Position buttons from bottom up to ensure they stay on screen
        var currentButtonY = minButtonY
        
        // Back button (only show when sprites are NOT ready)
        if !spritesReady {
            let backButton = MenuStyling.createBookButton(
                text: "Back",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentDark,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "backButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            backButton.zPosition = 10
            addChild(backButton)
            currentButtonY += dims.buttonHeight + dims.spacing
        }
        
        // Show sprite generation status if sprites are being generated
        if isGeneratingSprites {
            let statusLabel = SKLabelNode(fontNamed: "Arial")
            statusLabel.text = "Generating sprites..."
            statusLabel.fontSize = isLandscape ? 16.0 : 18.0
            statusLabel.fontColor = MenuStyling.inkMuted
            statusLabel.position = CGPoint(x: size.width / 2.0, y: currentButtonY + dims.buttonHeight / 2.0 + 10.0)
            statusLabel.zPosition = 10
            statusLabel.name = "spriteGenerationStatus"
            addChild(statusLabel)
        }
        
        // Add extra spacing between attributes and buttons when sprites are ready
        // Calculate where the topmost button (Start Game) will be if both buttons are shown
        if spritesReady && remainingAttributePoints == 0 {
            // Start Game button is added after View Sprites, so it will be at:
            // currentButtonY + (dims.buttonHeight + dims.spacing)
            let startGameButtonY = currentButtonY + (dims.buttonHeight + dims.spacing)
            let startGameButtonTop = startGameButtonY + dims.buttonHeight / 2.0
            
            // Add extra spacing between last attribute and top button (Start Game)
            let extraSpacing: CGFloat = isLandscape ? 30.0 : 40.0
            let desiredTopButtonTop = attributesBottom - extraSpacing
            
            // Adjust currentButtonY if Start Game button would overlap with attributes
            if startGameButtonTop > desiredTopButtonTop {
                let adjustment = startGameButtonTop - desiredTopButtonTop
                currentButtonY -= adjustment
            }
        }
        
        // View Sprites button (only show when sprites are ready)
        if spritesReady {
            let viewSpritesButton = MenuStyling.createBookButton(
                text: "View Sprites",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentBg,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "viewSpritesButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            viewSpritesButton.zPosition = 10
            addChild(viewSpritesButton)
            currentButtonY += dims.buttonHeight + dims.spacing
        }
        
        // View Story button - always visible
        let viewStoryButton = MenuStyling.createBookButton(
            text: "View Story",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: currentButtonY),
            name: "viewStoryButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        viewStoryButton.zPosition = 10
        addChild(viewStoryButton)
        currentButtonY += dims.buttonHeight + dims.spacing
        
        // Start Game button (only show when all points allocated AND sprites are ready)
        if remainingAttributePoints == 0 && spritesReady {
            let startGameButton = MenuStyling.createBookButton(
                text: "Start Game",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.bookSecondary,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "startGameButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            startGameButton.zPosition = 10
            addChild(startGameButton)
        }
    }
    
    func createAttributeAllocationNode(ability: Ability, name: String, score: Int, modifier: Int, position: CGPoint, size: CGSize, canIncrease: Bool, canDecrease: Bool) -> SKNode {
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
        
        // Score (modifier removed per user request)
        let scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.text = "\(score)"
        scoreLabel.fontSize = size.height * 0.35
        scoreLabel.fontColor = MenuStyling.inkColor
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: 0, y: 0)
        scoreLabel.zPosition = 2
        scoreLabel.name = "scoreLabel"
        bg.addChild(scoreLabel)
        
        // Decrease button - positioned closer to center score label
        if canDecrease {
            let buttonWidth: CGFloat = 40
            let buttonSpacing: CGFloat = 10 // Space between button and score label
            let decreaseButton = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: size.height * 0.7), cornerRadius: 4)
            decreaseButton.fillColor = MenuStyling.bookDanger
            decreaseButton.strokeColor = MenuStyling.parchmentBorder
            decreaseButton.lineWidth = 2
            // Position to the left of score label (score is at x: 0, so position button left of center)
            decreaseButton.position = CGPoint(x: -50 - buttonWidth / 2 - buttonSpacing, y: 0)
            decreaseButton.zPosition = 2
            decreaseButton.name = "decreaseButton_\(ability.rawValue)"
            bg.addChild(decreaseButton)
            
            let minusLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            minusLabel.text = "-"
            minusLabel.fontSize = size.height * 0.5
            minusLabel.fontColor = MenuStyling.inkColor
            minusLabel.verticalAlignmentMode = .center
            minusLabel.zPosition = 3
            decreaseButton.addChild(minusLabel)
        }
        
        // Increase button - positioned closer to center score label
        if canIncrease {
            let buttonWidth: CGFloat = 40
            let buttonSpacing: CGFloat = 10 // Space between button and score label
            let increaseButton = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: size.height * 0.7), cornerRadius: 4)
            increaseButton.fillColor = MenuStyling.bookSecondary
            increaseButton.strokeColor = MenuStyling.parchmentBorder
            increaseButton.lineWidth = 2
            // Position to the right of score label (score is at x: 0, so position button right of center)
            increaseButton.position = CGPoint(x: 50 + buttonWidth / 2 + buttonSpacing, y: 0)
            increaseButton.zPosition = 2
            increaseButton.name = "increaseButton_\(ability.rawValue)"
            bg.addChild(increaseButton)
            
            let plusLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            plusLabel.text = "+"
            plusLabel.fontSize = size.height * 0.5
            plusLabel.fontColor = MenuStyling.inkColor
            plusLabel.verticalAlignmentMode = .center
            plusLabel.zPosition = 3
            increaseButton.addChild(plusLabel)
        }
        
        // Store ability in userData
        container.userData = NSMutableDictionary()
        container.userData?["ability"] = ability.rawValue
        
        return container
    }
    
    func handleAttributeAllocationTouch(node: SKNode) {
        // Check for close story button
        if let closeStoryButton = findNodeWithName("closeStoryButton", startingFrom: node) {
            animateButtonPress(closeStoryButton) {
                self.hideStoryVideo()
            }
            return
        }
        
        // Check for close video not found button
        if let closeVideoNotFoundButton = findNodeWithName("closeVideoNotFoundButton", startingFrom: node) {
            animateButtonPress(closeVideoNotFoundButton) {
                self.hideVideoNotFoundMessage()
            }
            return
        }
        
        // Don't handle other touches if story video is showing
        if isShowingStory {
            return
        }
        
        // Check for back button - go back to sprite description screen
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showSpriteDescriptionScreen()
            }
            return
        }
        
        // Check for view sprites button
        if let viewSpritesButton = findNodeWithName("viewSpritesButton", startingFrom: node) {
            if let character = currentCharacter, let framePaths = character.framePaths, !framePaths.isEmpty {
                animateButtonPress(viewSpritesButton) {
                    self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                }
            }
            return
        }
        
        // Check for view story button
        if let viewStoryButton = findNodeWithName("viewStoryButton", startingFrom: node) {
            animateButtonPress(viewStoryButton) {
                self.showStoryVideo()
            }
            return
        }
        
        // Check for start game button
        if let startGameButton = findNodeWithName("startGameButton", startingFrom: node) {
            if remainingAttributePoints == 0 {
                animateButtonPress(startGameButton) {
                    // Start game directly - sprites are already ready (button only shows when ready)
                    if let character = self.currentCharacter {
                        self.createCharacter(character: character)
                    } else {
                        // Fallback: create character if somehow missing
                        self.createCharacter()
                    }
                }
            }
            return
        }
        
        // Check for increase button
        if let increaseButton = findNodeWithName(prefix: "increaseButton_", startingFrom: node) {
            if let abilityStr = increaseButton.userData?["ability"] as? String ?? increaseButton.name?.replacingOccurrences(of: "increaseButton_", with: ""),
               let ability = Ability(rawValue: abilityStr) {
                // Do initial increment
                if remainingAttributePoints > 0 {
                allocatedAttributes = increaseAttribute(ability, in: allocatedAttributes)
                remainingAttributePoints -= 1
                updateAttributeAllocationScreen()
                }
                // Start continuous pressing
                startContinuousButtonPress(ability: ability, isIncrease: true)
            }
            return
        }
        
        // Check for decrease button
        if let decreaseButton = findNodeWithName(prefix: "decreaseButton_", startingFrom: node) {
            if let abilityStr = decreaseButton.userData?["ability"] as? String ?? decreaseButton.name?.replacingOccurrences(of: "decreaseButton_", with: ""),
               let ability = Ability(rawValue: abilityStr) {
                // Do initial decrement (only if above base attribute)
                let baseScore = baseAttributes.score(for: ability)
                if allocatedAttributes.score(for: ability) > baseScore {
                allocatedAttributes = decreaseAttribute(ability, in: allocatedAttributes)
                remainingAttributePoints += 1
                updateAttributeAllocationScreen()
                }
                // Start continuous pressing
                startContinuousButtonPress(ability: ability, isIncrease: false)
            }
            return
        }
        
        // If touching something else, stop continuous button press
        stopContinuousButtonPress()
    }
    
    /// Start continuous button press (for holding + or - buttons)
    func startContinuousButtonPress(ability: Ability, isIncrease: Bool) {
        stopContinuousButtonPress() // Stop any existing continuous press
        heldButtonAbility = ability
        isHeldButtonIncrease = isIncrease
        
        // Start timer that fires repeatedly
        buttonHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let ability = self.heldButtonAbility else {
                self?.stopContinuousButtonPress()
                return
            }
            
            if self.isHeldButtonIncrease {
                // Increment
                if self.remainingAttributePoints > 0 {
                    self.allocatedAttributes = self.increaseAttribute(ability, in: self.allocatedAttributes)
                    self.remainingAttributePoints -= 1
                    self.updateAttributeAllocationScreen()
                } else {
                    self.stopContinuousButtonPress()
                }
            } else {
                // Decrement (only if above base attribute)
                let baseScore = self.baseAttributes.score(for: ability)
                if self.allocatedAttributes.score(for: ability) > baseScore {
                    self.allocatedAttributes = self.decreaseAttribute(ability, in: self.allocatedAttributes)
                    self.remainingAttributePoints += 1
                    self.updateAttributeAllocationScreen()
                } else {
                    self.stopContinuousButtonPress()
                }
            }
        }
    }
    
    /// Stop continuous button press
    func stopContinuousButtonPress() {
        buttonHoldTimer?.invalidate()
        buttonHoldTimer = nil
        heldButtonAbility = nil
    }
    
    func findNodeWithName(prefix: String, startingFrom node: SKNode) -> SKNode? {
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let name = current.name, name.hasPrefix(prefix) {
                return current
            }
            currentNode = current.parent
        }
        return nil
    }
    
    func increaseAttribute(_ ability: Ability, in scores: AbilityScores) -> AbilityScores {
        var newScores = scores
        switch ability {
        case .strength: newScores.strength += 1
        case .dexterity: newScores.dexterity += 1
        case .constitution: newScores.constitution += 1
        case .intelligence: newScores.intelligence += 1
        case .wisdom: newScores.wisdom += 1
        case .charisma: newScores.charisma += 1
        }
        return newScores
    }
    
    func decreaseAttribute(_ ability: Ability, in scores: AbilityScores) -> AbilityScores {
        var newScores = scores
        switch ability {
        case .strength: newScores.strength -= 1
        case .dexterity: newScores.dexterity -= 1
        case .constitution: newScores.constitution -= 1
        case .intelligence: newScores.intelligence -= 1
        case .wisdom: newScores.wisdom -= 1
        case .charisma: newScores.charisma -= 1
        }
        return newScores
    }
    
    /// Apply starting attributes from class JSON when a class is selected
    func applyClassStartingAttributes(for characterClass: CharacterClass) {
        // Reset attributes to 0 first
        allocatedAttributes = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0)
        baseAttributes = AbilityScores(strength: 0, dexterity: 0, constitution: 0, intelligence: 0, wisdom: 0, charisma: 0) // Reset base attributes
        
        // Load class data from JSON - try multiple paths
        var url: URL?
        
        // Try different bundle paths
        url = Bundle.main.url(forResource: "classes", withExtension: "json", subdirectory: "Prefabs")
        url = url ?? Bundle.main.url(forResource: "classes", withExtension: "json")
        
        // If still not found, try to find it in the bundle's resource path
        if url == nil {
            if let resourcePath = Bundle.main.resourcePath {
                let prefabsPath = (resourcePath as NSString).appendingPathComponent("Prefabs")
                let classesPath = (prefabsPath as NSString).appendingPathComponent("classes.json")
                if FileManager.default.fileExists(atPath: classesPath) {
                    url = URL(fileURLWithPath: classesPath)
                }
            }
        }
        
        // If still not found, try root resource path
        if url == nil {
            if let resourcePath = Bundle.main.resourcePath {
                let classesPath = (resourcePath as NSString).appendingPathComponent("classes.json")
                if FileManager.default.fileExists(atPath: classesPath) {
                    url = URL(fileURLWithPath: classesPath)
                }
            }
        }
        
        guard let fileURL = url else {
            print("⚠️ classes.json not found in bundle, using default attributes")
            print("   Tried: Bundle.main.url(forResource: 'classes', subdirectory: 'Prefabs')")
            print("   Tried: Bundle.main.url(forResource: 'classes')")
            if let resourcePath = Bundle.main.resourcePath {
                print("   Resource path: \(resourcePath)")
                print("   Checking if Prefabs directory exists: \(FileManager.default.fileExists(atPath: (resourcePath as NSString).appendingPathComponent("Prefabs")))")
            }
            remainingAttributePoints = 20
            return
        }
        
        print("✅ Found classes.json at: \(fileURL.path)")
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            
            struct ClassJSON: Codable {
                let id: String
                let startingAttributes: [String: Int]?
            }
            
            struct ClassesContainer: Codable {
                let classes: [ClassJSON]
            }
            
            let container = try decoder.decode(ClassesContainer.self, from: data)
            
            // Find the selected class - try both exact match and lowercase match
            let classIdLower = characterClass.rawValue.lowercased()
            print("🔍 Looking for class with id: '\(classIdLower)' (from rawValue: '\(characterClass.rawValue)')")
            
            guard let classData = container.classes.first(where: { $0.id == classIdLower }) else {
                print("⚠️ Starting attributes not found for class \(characterClass.rawValue) (searched for id: '\(classIdLower)')")
                print("   Available class IDs: \(container.classes.map { $0.id })")
                remainingAttributePoints = 20
                return
            }
            
            guard let startingAttrs = classData.startingAttributes else {
                print("⚠️ Starting attributes dictionary is nil for class \(characterClass.rawValue)")
                remainingAttributePoints = 20
                return
            }
            
            print("✅ Found class data for \(characterClass.rawValue), starting attributes: \(startingAttrs)")
            
            // Apply starting attributes (these are "free" base attributes)
            if let str = startingAttrs["strength"] {
                allocatedAttributes.strength = str
                baseAttributes.strength = str // Store base value
            }
            if let dex = startingAttrs["dexterity"] {
                allocatedAttributes.dexterity = dex
                baseAttributes.dexterity = dex
            }
            if let con = startingAttrs["constitution"] {
                allocatedAttributes.constitution = con
                baseAttributes.constitution = con
            }
            if let int = startingAttrs["intelligence"] {
                allocatedAttributes.intelligence = int
                baseAttributes.intelligence = int
            }
            if let wis = startingAttrs["wisdom"] {
                allocatedAttributes.wisdom = wis
                baseAttributes.wisdom = wis
            }
            if let cha = startingAttrs["charisma"] {
                allocatedAttributes.charisma = cha
                baseAttributes.charisma = cha
            }
            
            // Always start with 20 points to allocate (base attributes are free, don't count against the 20)
            remainingAttributePoints = 20
            
            print("✅ Applied starting attributes for \(characterClass.rawValue): base attributes applied, remaining points = \(remainingAttributePoints)")
            print("   Final attributes: str=\(allocatedAttributes.strength), dex=\(allocatedAttributes.dexterity), con=\(allocatedAttributes.constitution), int=\(allocatedAttributes.intelligence), wis=\(allocatedAttributes.wisdom), cha=\(allocatedAttributes.charisma)")
            print("   Base attributes (cannot be decreased): str=\(baseAttributes.strength), dex=\(baseAttributes.dexterity), con=\(baseAttributes.constitution), int=\(baseAttributes.intelligence), wis=\(baseAttributes.wisdom), cha=\(baseAttributes.charisma)")
        } catch {
            print("❌ Failed to load class starting attributes: \(error)")
            remainingAttributePoints = 20
        }
    }
    
    // MARK: - Screen Updates
    
    func updateAttributeAllocationScreen() {
        // Update points label
        if let pointsLabel = childNode(withName: "pointsLabel") as? SKLabelNode {
            pointsLabel.text = "Points Remaining: \(remainingAttributePoints)"
            pointsLabel.fontColor = remainingAttributePoints == 0 ? MenuStyling.bookSecondary : MenuStyling.inkColor
        }
        
        // Remove existing buttons to rebuild them
        childNode(withName: "startGameButton")?.removeFromParent()
        childNode(withName: "viewSpritesButton")?.removeFromParent()
        childNode(withName: "viewStoryButton")?.removeFromParent()
        childNode(withName: "spriteGenerationStatus")?.removeFromParent()
        // Remove back button if it exists (will be re-added conditionally)
        childNode(withName: "backButton")?.removeFromParent()
        
        // Rebuild buttons with current state
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Check if sprites are ready
        let spritesReady = currentCharacter?.framePaths != nil && !currentCharacter!.framePaths!.isEmpty && !isGeneratingSprites
        
        let panelBottom: CGFloat = 0.0
        let bottomPadding: CGFloat = 40.0
        var currentButtonY = panelBottom + bottomPadding + dims.buttonHeight / 2.0
        
        // Back button (only show when sprites are NOT ready)
        if !spritesReady {
            let backButton = MenuStyling.createBookButton(
                text: "Back",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentDark,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "backButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            backButton.zPosition = 10
            addChild(backButton)
            currentButtonY += dims.buttonHeight + dims.spacing
        }
        
        // Show sprite generation status if sprites are being generated
        if isGeneratingSprites {
            let statusLabel = SKLabelNode(fontNamed: "Arial")
            statusLabel.text = "Generating sprites..."
            statusLabel.fontSize = isLandscape ? 16.0 : 18.0
            statusLabel.fontColor = MenuStyling.inkMuted
            statusLabel.position = CGPoint(x: size.width / 2.0, y: currentButtonY + dims.buttonHeight / 2.0 + 10.0)
            statusLabel.zPosition = 10
            statusLabel.name = "spriteGenerationStatus"
            addChild(statusLabel)
        }
        
        // Calculate bottom of attributes list for spacing
        // Use same calculation as showAttributeAllocationScreen() to maintain consistent positioning
        let titleY: CGFloat = size.height - 80.0
        let nameLabelY: CGFloat = titleY - 40.0
        let pointsY: CGFloat = nameLabelY - 30.0
        let instructionY: CGFloat = pointsY - 35.0
        let attrHeight: CGFloat = isLandscape ? 50.0 : 55.0
        let attrSpacing: CGFloat = 12.0
        let startY: CGFloat = instructionY - 50.0
        let attributes: [(Ability, String)] = [
            (.strength, "Strength"),
            (.dexterity, "Dexterity"),
            (.constitution, "Constitution"),
            (.intelligence, "Intelligence"),
            (.wisdom, "Wisdom"),
            (.charisma, "Charisma")
        ]
        let lastAttributeY = startY - CGFloat(attributes.count - 1) * (attrHeight + attrSpacing)
        let attributesBottom = lastAttributeY - attrHeight / 2.0
        
        // Add extra spacing between attributes and buttons when sprites are ready
        // Calculate where the topmost button (Start Game) will be if buttons are shown
        // View Story is always shown, then View Sprites (if ready), then Start Game (if ready and points allocated)
        if spritesReady && remainingAttributePoints == 0 {
            // Start Game button is added after View Sprites, which is after View Story
            // So it will be at: currentButtonY + (View Story button) + (View Sprites button if shown)
            let buttonsBeforeStartGame = 1 // View Story always shown
            let startGameButtonY = currentButtonY + CGFloat(buttonsBeforeStartGame + (spritesReady ? 1 : 0)) * (dims.buttonHeight + dims.spacing)
            let startGameButtonTop = startGameButtonY + dims.buttonHeight / 2.0
            
            // Add extra spacing between last attribute and top button (Start Game)
            let extraSpacing: CGFloat = isLandscape ? 30.0 : 40.0
            let desiredTopButtonTop = attributesBottom - extraSpacing
            
            // Adjust currentButtonY if Start Game button would overlap with attributes
            if startGameButtonTop > desiredTopButtonTop {
                let adjustment = startGameButtonTop - desiredTopButtonTop
                currentButtonY -= adjustment
            }
        }
        
        // View Sprites button (only show when sprites are ready)
        if spritesReady {
            let viewSpritesButton = MenuStyling.createBookButton(
                text: "View Sprites",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentBg,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "viewSpritesButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            viewSpritesButton.zPosition = 10
            addChild(viewSpritesButton)
            currentButtonY += dims.buttonHeight + dims.spacing
        }
        
        // View Story button - always visible
        let viewStoryButton = MenuStyling.createBookButton(
            text: "View Story",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2.0, y: currentButtonY),
            name: "viewStoryButton",
            fontSize: isLandscape ? 22.0 : 26.0
        )
        viewStoryButton.zPosition = 10
        addChild(viewStoryButton)
        currentButtonY += dims.buttonHeight + dims.spacing
        
        // Start Game button (only show when all points allocated AND sprites are ready)
        if remainingAttributePoints == 0 && spritesReady {
            let startGameButton = MenuStyling.createBookButton(
                text: "Start Game",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.bookSecondary,
                position: CGPoint(x: size.width / 2.0, y: currentButtonY),
                name: "startGameButton",
                fontSize: isLandscape ? 22.0 : 26.0
            )
            startGameButton.zPosition = 10
            addChild(startGameButton)
        }
        
        // Rebuild attribute nodes
        // Note: attributes, attrHeight, attrSpacing, instructionY, and startY are already declared above
        
        for (ability, name) in attributes {
            if let attrNode = childNode(withName: "attribute_\(ability.rawValue)") {
                attrNode.removeFromParent()
            }
        }
        
        for (index, (ability, name)) in attributes.enumerated() {
            let yPos = startY - CGFloat(index) * (attrHeight + attrSpacing)
            let score = allocatedAttributes.score(for: ability)
            let baseScore = baseAttributes.score(for: ability)
            
            let attrNode = createAttributeAllocationNode(
                ability: ability,
                name: name,
                score: score,
                modifier: 0, // Not displayed anymore
                position: CGPoint(x: size.width / 2.0, y: yPos),
                size: CGSize(width: isLandscape ? 500.0 : 400.0, height: attrHeight),
                canIncrease: remainingAttributePoints > 0,
                canDecrease: score > baseScore // Can only decrease if above base attribute
            )
            attrNode.zPosition = 10
            addChild(attrNode)
        }
    }
    
    func handleSpriteDescriptionTouch(node: SKNode, location: CGPoint) {
        // Don't handle button clicks if user was scrolling
        if isScrolling {
            return
        }
        
        // Check for name input area first
        var currentNode: SKNode? = node
        while let current = currentNode {
            if current.name == "nameInputArea" || current.name == "nameDisplay" {
                showNameInputField()
                return
            }
            currentNode = current.parent
        }
        
        // Check for back button
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showClassSelectionScreen()
            }
            return
        }
        
        // Check for refresh button - clears preview and shows description box for editing
        if let refreshButton = findNodeWithName("refreshButton", startingFrom: node) {
            // Prevent multiple simultaneous operations
            guard !isGeneratingPreview else {
                return
            }
            
                animateButtonPress(refreshButton) {
                // Check again inside the animation callback to prevent race conditions
                guard !self.isGeneratingPreview else {
                    return
                }
                
                    // Remove preview and buttons
                    self.removePreviewImage()
                    // Clear preview texture so description shows again
                    self.previewTexture = nil
                    // Clear preview image data so a new one will be generated
                    self.previewImageData = nil
                    // Clear current character and frame paths so sprite generation will restart with new preview
                    self.currentCharacter = nil
                // Rebuild screen to show description and continue button (user can edit description)
                    self.showSpriteDescriptionScreen()
            }
            return
        }
        
        // Check for continue button
        if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
            // Validate that name is not empty
            if characterName.isEmpty {
                return
            }
            
            // If preview exists, go to attribute screen
            if previewTexture != nil {
                animateButtonPress(continueButton) {
                    // Only start sprite generation if it hasn't been started yet for this preview
                    // Check if we already have a character with frame paths, or if sprites are already generating
                    if self.currentCharacter == nil || (self.currentCharacter?.framePaths == nil || self.currentCharacter!.framePaths!.isEmpty) && !self.isGeneratingSprites {
                    self.startBackgroundSpriteGeneration()
                    }
                    self.showAttributeAllocationScreen()
                }
                return
            }
            
            // Otherwise, show loading spinner and generate preview when Continue is clicked
            if !isGeneratingPreview {
                animateButtonPress(continueButton) {
                    // Remove description box elements immediately
                    // Try direct search first
                    var container = self.childNode(withName: "contentContainer")
                    // If not found, try through cropNode
                    if container == nil {
                        if let cropNode = self.childNode(withName: "contentCropNode") {
                            container = cropNode.childNode(withName: "contentContainer")
                        }
                    }
                    
                    if let container = container {
                        container.childNode(withName: "instructionLabel")?.removeFromParent()
                        container.childNode(withName: "exampleLabel")?.removeFromParent()
                        container.childNode(withName: "descriptionInputArea")?.removeFromParent()
                    }
                    // Also remove Continue button
                    self.childNode(withName: "continueButton")?.removeFromParent()
                    
                    // Show loading spinner where the description was
                    self.showLoadingSpinner()
                    // Generate preview image
                    self.generatePreviewImage()
                }
            }
            return
        }
        
        // Check for description input area
        currentNode = node
        while let current = currentNode {
            if current.name == "descriptionInputArea" || current.name == "descriptionDisplay" {
                showDescriptionInputField()
                return
            }
            currentNode = current.parent
        }
    }
    
    // MARK: - Alerts & Input
    
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
        // Only update the description display text - don't recreate buttons
        // Buttons are already correctly positioned in showSpriteDescriptionScreen()
        // Search in container like we do for text input
        var descriptionInputArea: SKShapeNode? = childNode(withName: "descriptionInputArea") as? SKShapeNode
        if descriptionInputArea == nil {
            if let container = childNode(withName: "contentContainer") {
                descriptionInputArea = container.childNode(withName: "descriptionInputArea") as? SKShapeNode
            }
        }
        if descriptionInputArea == nil {
            if let cropNode = childNode(withName: "contentCropNode") {
                if let container = cropNode.childNode(withName: "contentContainer") {
                    descriptionInputArea = container.childNode(withName: "descriptionInputArea") as? SKShapeNode
                }
            }
        }
        
        if let descriptionInputArea = descriptionInputArea,
           let descriptionDisplay = descriptionInputArea.childNode(withName: "descriptionDisplay") as? SKLabelNode {
            descriptionDisplay.text = spriteDescription.isEmpty ? "Tap to enter description" : spriteDescription
            descriptionDisplay.fontColor = spriteDescription.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
        }
    }
    
    func generatePreviewImage() {
        guard !isGeneratingPreview else { return }
        
        isGeneratingPreview = true
        
        // Hide text fields when regenerating preview
        hideAllTextFields()
        
        // Remove old preview
        removePreviewImage()
        
        // Loading spinner is already shown by showLoadingSpinner() when continue is pressed
        
        // Build comprehensive description including race, gender, class, and user description
        var descriptionParts: [String] = []
        
        if let race = selectedRace {
            descriptionParts.append("a \(race.rawValue)")
        }
        
        // Only include gender in prompt if it's male or female (not "Other")
        if let gender = selectedGender, gender != .other {
            descriptionParts.append(gender.rawValue.lowercased())
        }
        
        if let characterClass = selectedClass {
            descriptionParts.append(characterClass.rawValue)
        }
        
        if !spriteDescription.isEmpty {
            descriptionParts.append(spriteDescription)
        }
        
        let fullDescription = descriptionParts.joined(separator: " ")
        
        // Generate reference image (skip background removal for preview to save API calls)
        SpriteGenerationService.shared.generateReferenceImage(description: fullDescription, skipBackgroundRemoval: true) { [weak self] imageData in
            DispatchQueue.main.async {
                guard let self = self, let imageData = imageData else {
                    self?.isGeneratingPreview = false
                    self?.hideLoadingSpinner()
                    return
                }
                
                // Store the image data to reuse for sprite sheet generation
                self.previewImageData = imageData
                
                self.isGeneratingPreview = false
                self.hideLoadingSpinner()
                
                // Create sprite from image data (with background for preview)
                #if os(macOS)
                if let image = NSImage(data: imageData),
                   let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let cgImage = bitmapRep.cgImage {
                    let texture = SKTexture(cgImage: cgImage)
                    // Store texture to avoid regenerating when navigating back
                    self.previewTexture = texture
                    print("✅ Preview texture created successfully")
                    self.displayPreviewImage(texture: texture)
                } else {
                    print("❌ Failed to create preview texture from image data")
                }
                #else
                if let image = UIImage(data: imageData),
                   let cgImage = image.cgImage {
                    let texture = SKTexture(cgImage: cgImage)
                    // Store texture to avoid regenerating when navigating back
                    self.previewTexture = texture
                    print("✅ Preview texture created successfully")
                    self.displayPreviewImage(texture: texture)
                } else {
                    print("❌ Failed to create preview texture from image data")
                }
                #endif
                
                self.updateSpriteDescriptionDisplay()
            }
        }
    }
    
    func displayPreviewImage(texture: SKTexture) {
        // Use single column layout - preview replaces description and continue button
        // Try direct search first
        var container = childNode(withName: "contentContainer")
        // If not found, try through cropNode
        if container == nil {
            if let cropNode = childNode(withName: "contentCropNode") {
                container = cropNode.childNode(withName: "contentContainer")
            }
        }
        
        if let container = container {
            // Get the descriptionPreviewY from the container's current layout
            // Find name input area to calculate position - same calculation as showSpriteDescriptionScreen
            if let nameInputArea = container.childNode(withName: "nameInputArea") {
                let nameInputY = nameInputArea.position.y
                let nameInputHeight: CGFloat = 50.0
                // Calculate position BELOW name field: bottom of name field minus spacing
                // Add more spacing (120 instead of 100) to prevent overlap with name field
                // descriptionPreviewY is the center Y of the preview area
                let descriptionPreviewY = nameInputY - nameInputHeight / 2.0 - 120.0
                let dims = MenuStyling.getResponsiveDimensions(size: size)
                let contentWidth = min(dims.buttonWidth, size.width * 0.9)
                
                displayPreviewImageInSingleColumn(texture: texture, container: container, previewY: descriptionPreviewY, contentWidth: contentWidth)
            }
        }
        
        // Note: Continue button is now added in displayPreviewImageInSingleColumn directly to the scene,
        // so we don't need to remove it here anymore
    }
    
    // MARK: - Loading & Preview
    
    func showLoadingSpinner() {
        // Show loading spinner in the description area
        // Try direct search first
        var container = childNode(withName: "contentContainer")
        // If not found, try through cropNode
        if container == nil {
            if let cropNode = childNode(withName: "contentCropNode") {
                container = cropNode.childNode(withName: "contentContainer")
            }
        }
        
        if let container = container {
            // Calculate position (same as description area) - find name input to get position
            if let nameInputArea = container.childNode(withName: "nameInputArea") {
                let nameInputY = nameInputArea.position.y
                let nameInputHeight: CGFloat = 50.0
                // Same calculation as descriptionPreviewY - position BELOW name field
                // Add more spacing (120 instead of 100) to match preview position
                let spinnerY = nameInputY - nameInputHeight / 2.0 - 120.0
                
                // Create animated loading spinner (rotating arc like generating screen)
                let spinnerRadius: CGFloat = 25.0
                let spinnerPath = CGMutablePath()
                // Create an arc that's 75% of a circle (leaves a gap)
                spinnerPath.addArc(center: .zero, radius: spinnerRadius, startAngle: 0, endAngle: CGFloat.pi * 1.5, clockwise: false)
                
                let spinner = SKShapeNode(path: spinnerPath)
                spinner.strokeColor = MenuStyling.bookAccent
                spinner.fillColor = SKColor.clear
                spinner.lineWidth = 4.0
                spinner.lineCap = .round
                spinner.lineJoin = .round
                spinner.position = CGPoint(x: 0, y: spinnerY)
                spinner.zPosition = 10
                spinner.name = "loadingSpinner"
                
                // Rotate animation
                let rotate = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 1.0)
                let repeatRotate = SKAction.repeatForever(rotate)
                spinner.run(repeatRotate)
                
                container.addChild(spinner)
                
                // Add "Generating Preview..." text below spinner
                let loadingLabel = SKLabelNode(fontNamed: "Arial")
                loadingLabel.text = "Generating Preview..."
                loadingLabel.fontSize = 18.0
                loadingLabel.fontColor = MenuStyling.inkMuted
                loadingLabel.position = CGPoint(x: 0, y: spinnerY - 60.0) // Increased spacing from 40.0 to 60.0
                loadingLabel.zPosition = 10
                loadingLabel.horizontalAlignmentMode = .center
                loadingLabel.name = "loadingLabel"
                container.addChild(loadingLabel)
            }
        }
    }
    
    func hideLoadingSpinner() {
        if let container = childNode(withName: "contentContainer") {
            container.childNode(withName: "loadingSpinner")?.removeFromParent()
            container.childNode(withName: "loadingLabel")?.removeFromParent()
        }
        childNode(withName: "loadingSpinner")?.removeFromParent()
        childNode(withName: "loadingLabel")?.removeFromParent()
    }
    
    // Legacy function - kept for compatibility but not used in single-column layout
    func displayPreviewImageInLandscape(texture: SKTexture, rightX: CGFloat, centerY: CGFloat) {
        // This function is kept for compatibility but not actively used in the new single-column layout
        // The actual implementation is below
        // Remove old preview and refresh button
        removePreviewImage()
        childNode(withName: "refreshButton")?.removeFromParent()
        
        let textureSize = texture.size()
        let textureAspectRatio = textureSize.width / textureSize.height
        
        // Preview size for right column
        let previewWidth: CGFloat = 200.0
        let previewHeight = previewWidth / textureAspectRatio
        let maxHeight: CGFloat = 300.0
        var finalWidth = previewWidth
        var finalHeight = previewHeight
        if previewHeight > maxHeight {
            finalHeight = maxHeight
            finalWidth = finalHeight * textureAspectRatio
        }
        
        // Position preview on right side, vertically centered in content area
        let previewY = centerY
        
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: finalWidth, height: finalHeight)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = CGPoint(x: 0, y: 0) // Position relative to container
        sprite.zPosition = 2
        sprite.name = "previewSprite"
        texture.filteringMode = .linear
        
        // Create container for sprite and border
        let previewContainer = SKNode()
        previewContainer.position = CGPoint(x: rightX, y: previewY)
        previewContainer.zPosition = 10
        previewContainer.name = "previewContainer"
        
        // Add fancy border frame
        let borderFrame = MenuStyling.createBookPageBorder(size: CGSize(width: finalWidth, height: finalHeight), padding: 10.0)
        borderFrame.zPosition = 1
        previewContainer.addChild(borderFrame)
        
        // Add sprite to container
        previewContainer.addChild(sprite)
        addChild(previewContainer)
        
        previewSprite = sprite
        
        // Add label above preview
        let previewLabel = SKLabelNode(fontNamed: "Arial")
        previewLabel.text = "Preview (Front View)"
        previewLabel.fontSize = 16.0
        previewLabel.fontColor = MenuStyling.inkMuted
        previewLabel.position = CGPoint(x: rightX, y: previewY + finalHeight / 2.0 + 20.0)
        previewLabel.zPosition = 10
        previewLabel.name = "previewLabel"
        addChild(previewLabel)
        
        // Add refresh button below preview (only if description exists)
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let buttonSpacing: CGFloat = 20.0
        let refreshButtonY = previewY - finalHeight / 2.0 - buttonSpacing - dims.buttonHeight / 2.0
        let buttonWidth: CGFloat = 200.0
        
        if !spriteDescription.isEmpty {
            let refreshButton = MenuStyling.createBookButton(
                text: isGeneratingPreview ? "Generating..." : "Refresh Preview",
                size: CGSize(width: buttonWidth, height: dims.buttonHeight),
                color: isGeneratingPreview ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
                position: CGPoint(x: rightX, y: refreshButtonY),
                name: "refreshButton",
                fontSize: 18.0
            )
            refreshButton.zPosition = 10
            addChild(refreshButton)
        }
    }
    
    func displayPreviewImageInPortrait(texture: SKTexture, container: SKNode, previewY: CGFloat, contentWidth: CGFloat) {
        // Remove old preview and refresh button
        removePreviewImage()
        container.childNode(withName: "refreshButton")?.removeFromParent()
        
        let textureSize = texture.size()
        let textureAspectRatio = textureSize.width / textureSize.height
        
        // Preview size for portrait column
        let maxWidth: CGFloat = contentWidth * 0.8
        let maxHeight: CGFloat = 180.0
        var previewWidth = maxWidth
        var previewHeight = previewWidth / textureAspectRatio
        if previewHeight > maxHeight {
            previewHeight = maxHeight
            previewWidth = previewHeight * textureAspectRatio
        }
        
        // Create container for sprite and border
        let previewContainer = SKNode()
        previewContainer.position = CGPoint(x: 0, y: previewY)
        previewContainer.zPosition = 1
        previewContainer.name = "previewContainer"
        
        // Add fancy border frame
        let borderFrame = MenuStyling.createBookPageBorder(size: CGSize(width: previewWidth, height: previewHeight), padding: 10.0)
        borderFrame.zPosition = 1
        previewContainer.addChild(borderFrame)
        
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: previewWidth, height: previewHeight)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = CGPoint(x: 0, y: 0) // Position relative to container
        sprite.zPosition = 2
        sprite.name = "previewSprite"
        texture.filteringMode = .linear
        previewContainer.addChild(sprite)
        
        container.addChild(previewContainer)
        
        previewSprite = sprite
        
        // Add label above preview
        let previewLabel = SKLabelNode(fontNamed: "Arial")
        previewLabel.text = "Preview (Front View)"
        previewLabel.fontSize = 18.0
        previewLabel.fontColor = MenuStyling.inkMuted
        previewLabel.position = CGPoint(x: 0, y: previewY + previewHeight / 2.0 + 20.0)
        previewLabel.zPosition = 2
        previewLabel.name = "previewLabel"
        container.addChild(previewLabel)
        
        // Add refresh button below preview (only if description exists)
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let buttonSpacing: CGFloat = 15.0
        let refreshButtonY = previewY - previewHeight / 2.0 - buttonSpacing - dims.buttonHeight / 2.0
        
        if !spriteDescription.isEmpty {
            let refreshButton = MenuStyling.createBookButton(
                text: isGeneratingPreview ? "Generating..." : "Refresh Preview",
                size: CGSize(width: contentWidth, height: dims.buttonHeight),
                color: isGeneratingPreview ? MenuStyling.parchmentDark : MenuStyling.parchmentBg,
                position: CGPoint(x: 0, y: refreshButtonY),
                name: "refreshButton",
                fontSize: 22.0
            )
            refreshButton.zPosition = 1
            container.addChild(refreshButton)
        }
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
                
                // Position continue button below input area
                if let continueButton = childNode(withName: "continueButton") {
                    let newContinueY = inputAreaBottom - buttonSpacing - dims.buttonHeight / 2.0
                    continueButton.position = CGPoint(x: size.width / 2.0, y: newContinueY)
                }
                
                // Position refresh button below continue button
                if let refreshButton = childNode(withName: "refreshButton") {
                    if let continueButton = childNode(withName: "continueButton") {
                        let continueY = continueButton.position.y
                        let refreshSpacing: CGFloat = dims.buttonHeight + dims.spacing
                        refreshButton.position = CGPoint(x: size.width / 2.0, y: continueY - refreshSpacing)
                    }
                }
                
                // Position back button below refresh button (or continue if no refresh)
                if let backButton = childNode(withName: "backButton") {
                    let buttonAbove: SKNode?
                    if let refreshButton = childNode(withName: "refreshButton") {
                        buttonAbove = refreshButton
                    } else if let continueButton = childNode(withName: "continueButton") {
                        buttonAbove = continueButton
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
        // Remove preview container (which includes sprite and border)
        childNode(withName: "previewContainer")?.removeFromParent()
        previewSprite?.removeFromParent()
        previewSprite = nil
        childNode(withName: "previewLabel")?.removeFromParent()
        childNode(withName: "generatingLabel")?.removeFromParent()
        // Don't remove refreshButton here - it should stay visible during regeneration
        // Remove other buttons (check both scene and container)
        childNode(withName: "generateSpritesButton")?.removeFromParent()
        if let container = childNode(withName: "contentContainer") {
            container.childNode(withName: "previewContainer")?.removeFromParent()
            container.childNode(withName: "generateSpritesButton")?.removeFromParent()
            // Refresh button is in container, but keep it visible
        }
    }
    
    func showGeneratingScreen() {
        removeAllChildren()
        addBackgroundImage()
        loadingSpinner?.removeFromParent()
        currentStep = .generating
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel removed - no margins needed
        
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
    
    func startBackgroundSpriteGeneration() {
        guard let raceType = selectedRace, let classType = selectedClass, !characterName.isEmpty else { return }
        
        isGeneratingSprites = true
        
        // Create character first to get ID, then generate sprite with that ID
        let character = GameCharacter(
            name: characterName,
            race: raceType,
            characterClass: classType,
            spriteDescription: spriteDescription.isEmpty ? nil : spriteDescription
        )
        _ = SaveManager.saveCharacter(character) // Save character first
        currentCharacter = character
        
        let descriptionToUse = spriteDescription.isEmpty ? "A \(raceType.rawValue) \(classType.rawValue) character" : spriteDescription
        
        // Generate animation frames using character's ID in background (with background removal)
        // Use preview image data if available (so south idle matches the preview)
        SpriteGenerationService.shared.generateSpriteSheet(description: descriptionToUse, characterId: character.id, skipBackgroundRemoval: false, southIdleReference: previewImageData) { [weak self] (framePaths: [String]?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update character with frame paths
                var updatedCharacter = character
                updatedCharacter.framePaths = framePaths
                _ = SaveManager.saveCharacter(updatedCharacter)
                
                // Store updated character
                self.currentCharacter = updatedCharacter
                self.isGeneratingSprites = false
                
                // Update attribute allocation screen to show View Sprites and Start Game buttons
                if self.currentStep == .attributeAllocation {
                    self.updateAttributeAllocationScreen()
                }
            }
        }
    }
    
    func generateSpriteAndCreateCharacter() {
        guard let raceType = selectedRace, let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Show generating screen with loading spinner
        showGeneratingScreen()
        
        // Create character first to get ID, then generate sprite with that ID
        let character = GameCharacter(
            name: characterName,
            race: raceType,
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
        guard let raceType = selectedRace, let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Create character without sprite (fallback if called directly)
        let character = GameCharacter(name: characterName, race: raceType, characterClass: classType)
        _ = SaveManager.saveCharacter(character)
        createCharacter(character: character)
    }
    
    func createCharacter(character: GameCharacter) {
        guard let raceType = selectedRace, let classType = selectedClass, !characterName.isEmpty else { return }
        
        // Create character (already saved)
        // Create player with allocated ability scores
        let player = Player(name: characterName, characterClass: classType, abilityScores: allocatedAttributes)
        
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
        
        // Always save to slot 1 on first start (if slot 1 is empty for this character)
        // If slot 1 already has a save for this character, use it
        // If slot 1 has a save for a different character, find first available slot
        let slot1Info = SaveManager.getSaveSlotInfo(characterId: character.id, slot: 1)
        if slot1Info?.isEmpty == true {
            // Slot 1 is empty for this character - save there
            _ = SaveManager.saveGame(gameState: gameState, characterId: character.id, toSlot: 1)
        } else {
            // Slot 1 has a save - find first available slot
            var saved = false
            for slot in 1...SaveManager.maxSlots {
                if SaveManager.getSaveSlotInfo(characterId: character.id, slot: slot)?.isEmpty == true {
                    _ = SaveManager.saveGame(gameState: gameState, characterId: character.id, toSlot: slot)
                    saved = true
                    break
                }
            }
            // If no slot was available, overwrite slot 1
            if !saved {
                _ = SaveManager.saveGame(gameState: gameState, characterId: character.id, toSlot: 1)
            }
        }
        
        // Transition to game
        startGame(character: character, gameState: gameState)
    }
    
    // MARK: - Navigation & Transitions
    
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
            textField.placeholder = ""
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
        alert.informativeText = "Character's Name"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = characterName
        inputTextField.placeholderString = ""
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
        // Update the name display label only - don't recreate buttons
        // Search recursively for nameInputArea (it's inside contentContainer/cropNode)
        var nameInputArea: SKShapeNode?
        
        // First try direct child
        if let area = childNode(withName: "nameInputArea") as? SKShapeNode {
            nameInputArea = area
        } else {
            // Search in contentContainer
            if let contentContainer = childNode(withName: "contentContainer") {
                nameInputArea = contentContainer.childNode(withName: "nameInputArea") as? SKShapeNode
            }
            // If not found, search in cropNode > contentContainer (check both cropNode and contentCropNode)
            if nameInputArea == nil {
                if let cropNode = childNode(withName: "contentCropNode") ?? childNode(withName: "cropNode"),
                   let contentContainer = cropNode.childNode(withName: "contentContainer") {
                    nameInputArea = contentContainer.childNode(withName: "nameInputArea") as? SKShapeNode
                }
            }
        }
        
        if let nameInputArea = nameInputArea,
           let nameDisplay = nameInputArea.childNode(withName: "nameDisplay") as? SKLabelNode {
            nameDisplay.text = characterName.isEmpty ? "" : characterName // Remove placeholder text
            nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
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
        if currentStep == .spriteDescription {
            characterName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nameDisplay = childNode(withName: "nameDisplay") as? SKLabelNode {
                nameDisplay.text = characterName.isEmpty ? "" : characterName
                nameDisplay.fontColor = characterName.isEmpty ? MenuStyling.inkMuted : MenuStyling.inkColor
                
                // Update continue button
                if let continueButton = childNode(withName: "continueButton") as? SKShapeNode {
                    continueButton.fillColor = characterName.isEmpty ? SKColor(white: 0.3, alpha: 1.0) : SKColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0)
                }
            }
        }
    }
    
    func handleSpritePreviewTouch(node: SKNode, location: CGPoint) {
        // Check for back button
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showAttributeAllocationScreen()
            }
            return
        }
        
        // Check for regenerate button (individual sprite regeneration)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("regenerate_") {
                // Extract frame path from node name
                let frameIdentifier = nodeName.replacingOccurrences(of: "regenerate_", with: "")
                regenerateSprite(frameIdentifier: frameIdentifier)
                return
            }
            currentNode = current.parent
        }
        
        // Check for start game button
        if let startButton = findNodeWithName("startGameButton", startingFrom: node) {
            animateButtonPress(startButton) {
                if let character = self.currentCharacter {
                    self.removeBackgroundsAndStartGame(character: character)
                }
            }
            return
        }
    }
    
    func regenerateSprite(frameIdentifier: String) {
        guard let character = currentCharacter else { return }
        
        // Parse the path to extract animation type and direction
        // Path format can be:
        // - "CharacterSprites/<UUID>_idle_west.png" (UUID prefix)
        // - "CharacterSprites/idle_south_<characterId>.png" (legacy format)
        let fileName = (frameIdentifier as NSString).lastPathComponent
        var animationType: String? // "idle" or "walk"
        var direction: String? // "south", "west", "east", "north"
        
        // Extract animation type and direction from filename
        // Handle both formats: UUID_idle_dir.png or idle_dir_UUID.png
        if fileName.contains("idle_") {
            animationType = "idle"
            for dir in ["south", "west", "east", "north"] {
                // Check for both patterns: _dir_. or _dir.png (end of string)
                if fileName.contains("_\(dir)_") || fileName.contains("_\(dir).") {
                    direction = dir
                    break
                }
            }
        } else if fileName.contains("walk_") {
            animationType = "walk"
            for dir in ["south", "west", "east", "north"] {
                // Check for both patterns: _dir_. or _dir.png (end of string)
                if fileName.contains("_\(dir)_") || fileName.contains("_\(dir).") {
                    direction = dir
                    break
                }
            }
        }
        
        guard let animType = animationType, let dir = direction else {
            print("⚠️ Could not parse animation type and direction from path: \(frameIdentifier)")
            return
        }
        
        // Build description for fallback text-to-image case (includes pose/direction)
        var fallbackDescriptionParts: [String] = []
        if let race = selectedRace {
            fallbackDescriptionParts.append("a \(race.rawValue)")
        }
        if let gender = selectedGender, gender != .other {
            fallbackDescriptionParts.append(gender.rawValue.lowercased())
        }
        if let characterClass = selectedClass {
            fallbackDescriptionParts.append(characterClass.rawValue)
        }
        if !spriteDescription.isEmpty {
            fallbackDescriptionParts.append(spriteDescription)
        }
        
        // Add pose/direction description for fallback
        let fallbackPoseDescription = animType == "idle" ? "standing still" : "walking"
        let directionDescription = "facing \(dir)"
        fallbackDescriptionParts.append("\(fallbackPoseDescription), \(directionDescription)")
        
        let fullDescription = fallbackDescriptionParts.joined(separator: " ")
        
        // Resolve file path
        let fileURL: URL
        if frameIdentifier.hasPrefix("CharacterSprites/") {
            if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                let fileName = String(frameIdentifier.dropFirst("CharacterSprites/".count))
                fileURL = documentsDir.appendingPathComponent(fileName)
            } else {
                print("⚠️ Failed to get documents directory for regeneration")
                return
            }
        } else {
            fileURL = URL(fileURLWithPath: frameIdentifier)
        }
        
        // Find and remove the specific sprite node from the preview
        // The sprite node name is "frame_<Label>" where Label is capitalized direction
        // But we need to identify which container (idle vs walk) it's in based on the path
        let spriteName = "frame_\(dir.capitalized)"
        var spriteToRemove: SKSpriteNode? = nil
        
        // Search for the sprite, but only in the correct container based on animation type
        // Check if path contains "idle_" or "walk_" to determine which container
        let isIdleSprite = fileName.contains("idle_")
        
        enumerateChildNodes(withName: "//\(spriteName)") { node, _ in
            if let sprite = node as? SKSpriteNode {
                // Check parent hierarchy to determine if this is in idle or walk container
                var currentNode: SKNode? = sprite.parent
                var foundIdleContainer = false
                var foundWalkContainer = false
                
                while let current = currentNode {
                    // Check children for labels to identify container type
                    for child in current.children {
                        if let label = child as? SKLabelNode {
                            if label.text == "Idle Animations" {
                                foundIdleContainer = true
                            } else if label.text == "Walking Animations" {
                                foundWalkContainer = true
                            }
                        }
                    }
                    currentNode = current.parent
                }
                
                // Only select this sprite if it's in the correct container
                if (isIdleSprite && foundIdleContainer && !foundWalkContainer) ||
                   (!isIdleSprite && foundWalkContainer && !foundIdleContainer) {
                    spriteToRemove = sprite
                }
            }
        }
        
        // Remove the sprite if found (it will be re-added after regeneration)
        // Store it in removedSprites so we can update the correct one later
        if let sprite = spriteToRemove, let parent = sprite.parent {
            // Store sprite info: position, size, and parent
            let spriteSize = sprite.size.width // Assuming square sprites
            removedSprites[frameIdentifier] = (sprite: sprite, position: sprite.position, size: spriteSize, parent: parent)
            sprite.removeFromParent()
        }
        
        // If removing a west sprite, also remove the corresponding east sprite
        if dir == "west" {
            let eastSpriteName = "frame_East"
            var eastSpriteToRemove: SKSpriteNode? = nil
            
            enumerateChildNodes(withName: "//\(eastSpriteName)") { node, _ in
                if let sprite = node as? SKSpriteNode {
                    // Check parent hierarchy to determine if this is in the same animation type container
                    var currentNode: SKNode? = sprite.parent
                    var foundIdleContainer = false
                    var foundWalkContainer = false
                    
                    while let current = currentNode {
                        for child in current.children {
                            if let label = child as? SKLabelNode {
                                if label.text == "Idle Animations" {
                                    foundIdleContainer = true
                                } else if label.text == "Walking Animations" {
                                    foundWalkContainer = true
                                }
                            }
                        }
                        currentNode = current.parent
                    }
                    
                    // Only select east sprite if it's in the same container as the west sprite we're removing
                    if (isIdleSprite && foundIdleContainer && !foundWalkContainer) ||
                       (!isIdleSprite && foundWalkContainer && !foundIdleContainer) {
                        eastSpriteToRemove = sprite
                    }
                }
            }
            
            if let eastSprite = eastSpriteToRemove, let parent = eastSprite.parent {
                // Store east sprite mapping too (use the east frame identifier)
                let eastFrameIdentifier = frameIdentifier.replacingOccurrences(of: "_west.", with: "_east.").replacingOccurrences(of: "_west_", with: "_east_")
                let spriteSize = eastSprite.size.width
                removedSprites[eastFrameIdentifier] = (sprite: eastSprite, position: eastSprite.position, size: spriteSize, parent: parent)
                eastSprite.removeFromParent()
            }
        }
        
        // Load the character reference image (south idle - the first image generated)
        // This is the original character reference used for all sprite generation
        // Always use south idle as reference, regardless of whether we're regenerating idle or walk
        let referenceDirection = "south"
        let referenceAnimationType = "idle" // Always use the original character reference (south idle)
        
        // Build reference filename by replacing animation type and direction
        // Handle both formats: UUID_idle_dir.png or idle_dir_UUID.png
        var referenceFileName = fileName
        // Replace the animation type and direction
        referenceFileName = referenceFileName.replacingOccurrences(of: "_\(animType)_\(dir).", with: "_\(referenceAnimationType)_\(referenceDirection).")
        referenceFileName = referenceFileName.replacingOccurrences(of: "_\(animType)_\(dir)_", with: "_\(referenceAnimationType)_\(referenceDirection)_")
        // Also handle format: idle_dir.png -> idle_south.png (if no UUID)
        if !referenceFileName.contains("_\(referenceAnimationType)_\(referenceDirection)") {
            // Fallback: try replacing just the direction in the pattern we found
            if fileName.contains("_\(dir).") {
                referenceFileName = fileName.replacingOccurrences(of: "_\(dir).", with: "_\(referenceDirection).")
            } else if fileName.contains("_\(dir)_") {
                referenceFileName = fileName.replacingOccurrences(of: "_\(dir)_", with: "_\(referenceDirection)_")
            }
            // Ensure it's the idle animation type
            referenceFileName = referenceFileName.replacingOccurrences(of: "_\(animType)_", with: "_\(referenceAnimationType)_")
        }
        let referenceFileURL: URL
        if frameIdentifier.hasPrefix("CharacterSprites/") {
            if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                referenceFileURL = documentsDir.appendingPathComponent(referenceFileName)
            } else {
                print("⚠️ Failed to get documents directory for reference image")
                if let character = self.currentCharacter, let framePaths = character.framePaths {
                    self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                }
                return
            }
        } else {
            // Build reference path by replacing animation type and direction
            var referencePath = frameIdentifier
            referencePath = referencePath.replacingOccurrences(of: "_\(animType)_\(dir).", with: "_\(referenceAnimationType)_\(referenceDirection).")
            referencePath = referencePath.replacingOccurrences(of: "_\(animType)_\(dir)_", with: "_\(referenceAnimationType)_\(referenceDirection)_")
            // Fallback: try replacing just the direction
            if !referencePath.contains("_\(referenceAnimationType)_\(referenceDirection)") {
                if frameIdentifier.contains("_\(dir).") {
                    referencePath = frameIdentifier.replacingOccurrences(of: "_\(dir).", with: "_\(referenceDirection).")
                } else if frameIdentifier.contains("_\(dir)_") {
                    referencePath = frameIdentifier.replacingOccurrences(of: "_\(dir)_", with: "_\(referenceDirection)_")
                }
                referencePath = referencePath.replacingOccurrences(of: "_\(animType)_", with: "_\(referenceAnimationType)_")
            }
            referenceFileURL = URL(fileURLWithPath: referencePath)
        }
        
        // Load reference image data
        // First try the direct path, then try to find it in character's framePaths
        var referenceImageData: Data? = try? Data(contentsOf: referenceFileURL)
        
        // If direct path failed, try to find the reference image in character's framePaths
        if referenceImageData == nil, let framePaths = character.framePaths {
            // Always look for idle_south (the original character reference)
            let referencePathPattern = "idle_south"
            for path in framePaths {
                if path.contains(referencePathPattern) {
                    let pathURL: URL
                    if path.hasPrefix("CharacterSprites/") {
                        if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                            let pathFileName = String(path.dropFirst("CharacterSprites/".count))
                            pathURL = documentsDir.appendingPathComponent(pathFileName)
                        } else {
                            continue
                        }
                    } else {
                        pathURL = URL(fileURLWithPath: path)
                    }
                    referenceImageData = try? Data(contentsOf: pathURL)
                    if referenceImageData != nil {
                        print("✅ Found reference image in framePaths: \(path)")
                        break
                    }
                }
            }
        }
        
        guard let refImageData = referenceImageData else {
            print("⚠️ Could not load reference image: \(referenceFileURL.path). Falling back to text-to-image.")
            // Fallback to text-to-image if reference not found
            SpriteGenerationService.shared.generateReferenceImage(description: fullDescription, skipBackgroundRemoval: false) { [weak self] imageData in
                self?.handleRegeneratedSprite(imageData: imageData, fileURL: fileURL, frameIdentifier: frameIdentifier, fileName: fileName, dir: dir, animType: animType)
            }
            return
        }
        
        // Build view description based on direction (matching initial generation)
        var viewDescription: String
        var directionSpecificNegative: String
        
        if animType == "idle" {
            if dir == "west" {
                viewDescription = "character facing LEFT (west direction), body rotated 90 degrees to the LEFT, showing LEFT side profile ONLY, head facing LEFT, LEFT side of body fully visible, LEFT arm visible, LEFT leg visible, RIGHT side completely hidden, NOT facing camera, NOT front view, NOT facing right, NOT facing east, side profile view ONLY, completely turned to the left"
                directionSpecificNegative = "facing camera, front view, facing right"
            } else if dir == "north" {
                viewDescription = "character facing AWAY from camera (north direction), back view showing back of head, back of shoulders, back of body, back of legs, head facing away from camera, completely turned away, 180 degrees rotated from camera, NOT facing camera, NOT front view, NOT facing south, back view ONLY, no face visible"
                directionSpecificNegative = "facing camera, front view"
            } else {
                // south
                viewDescription = "character facing camera, front view showing front of body"
                directionSpecificNegative = "different character, different clothing"
            }
        } else {
            // walk
            if dir == "west" {
                viewDescription = "character facing LEFT, character facing LEFT, body turned 90 degrees LEFT, showing LEFT side profile, head facing LEFT, LEFT side of body visible, LEFT arm visible, LEFT leg visible, RIGHT side hidden, NOT facing camera, NOT front view, side profile view only, walking stride"
                directionSpecificNegative = "facing camera, front view, facing right"
            } else if dir == "north" {
                viewDescription = "character facing AWAY from camera, back view showing back of head, back of shoulders, back of body, head facing away from camera, walking stride"
                directionSpecificNegative = "facing camera, front view"
            } else {
                // south
                viewDescription = "character facing camera, front view showing front of body"
                directionSpecificNegative = "different character, different clothing"
            }
        }
        
        // Build prompt matching initial generation format EXACTLY
        // The description parameter passed to generateSpriteSheet is:
        // spriteDescription.isEmpty ? "A Race Class character" : spriteDescription
        // So we need to match that format exactly
        let descriptionForPrompt = spriteDescription.isEmpty ? "A \(selectedRace?.rawValue ?? "character") \(selectedClass?.rawValue ?? "character") character" : spriteDescription
        
        // Match the exact format used in initial generation
        let characterDescForPrompt = descriptionForPrompt.isEmpty ? "" : "Character description: \(descriptionForPrompt). "
        let characterDescription = descriptionForPrompt.isEmpty ? "" : "\(descriptionForPrompt). "
        
        // For west/north directions, use FLUX.2 Pro style prompts with directionInstruction
        // For south direction, use img2img style prompts
        let prompt: String
        let negativePrompt: String
        
        if animType == "idle" {
            if dir == "west" || dir == "north" {
                // FLUX.2 Pro style prompt (matches initial generation for west/north idle)
                let directionInstruction = dir == "west" ? "CRITICAL: facing LEFT only, LEFT side profile, body rotated 90 degrees LEFT, LEFT arm and LEFT leg visible, RIGHT side completely hidden, head facing LEFT, NOT facing camera, NOT front view, side profile LEFT ONLY" : "CRITICAL: facing AWAY from camera, back view only, back of head visible, back of body visible, NOT facing camera, NOT front view, back view ONLY"
                prompt = "\(characterDescForPrompt)\(characterDescription)Same character from reference. \(viewDescription). Idle pose, full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). Match clothing from first reference. \(directionInstruction)."
                negativePrompt = "different character, different clothing, facing camera, front view, multiple characters, \(directionSpecificNegative)"
            } else {
                // South direction - img2img style (matches initial generation for south idle)
                prompt = "\(characterDescForPrompt)\(characterDescription)Same character from reference. \(viewDescription). Idle pose, full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). Match reference exactly."
                negativePrompt = "different character, different clothing, \(directionSpecificNegative), weapons, items, background"
            }
        } else {
            // walk animation
            if dir == "west" || dir == "north" {
                // FLUX.2 Pro style prompt (matches initial generation for west/north walk)
                let directionInstruction = dir == "west" ? "CRITICAL: facing LEFT only, LEFT side profile, body rotated 90 degrees LEFT, LEFT arm and LEFT leg visible, RIGHT side completely hidden, head facing LEFT, NOT facing camera, NOT front view, side profile LEFT ONLY" : "CRITICAL: facing AWAY from camera, back view only, back of head visible, back of body visible, NOT facing camera, NOT front view, back view ONLY"
                let armInstruction = dir == "north"
                    ? "arms relaxed straight down at sides, minimal movement, hands close to body, no big swing"
                    : "arms relaxed mostly at sides, very small natural swing, hands stay close to body, no wide or exaggerated arm swing"
                prompt = "\(characterDescForPrompt)\(characterDescription)Same character from reference. \(viewDescription). Walking pose, one leg forward, \(armInstruction), full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). Match clothing from first reference. \(directionInstruction)."
                negativePrompt = "different character, different clothing, facing camera, front view, multiple characters, \(directionSpecificNegative)"
            } else {
                // South direction - FLUX.2 Pro with reference style (matches initial generation for south walk)
                // Note: The prompt format matches exactly what's used in initial generation (line 752 in SpriteGenerationService)
                prompt = "\(characterDescForPrompt)Same character from reference. Walking pose, one leg forward, arms relaxed mostly at sides with very small natural swing, hands close to body, facing camera, full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). Match clothing from first reference."
                negativePrompt = "different character, different clothing, standing still, idle pose, \(directionSpecificNegative), black background, gray background, colored background, transparent background"
            }
        }
        
        // Use FLUX.2 Pro for west/north (matching initial generation), img2img for south
        if dir == "west" || dir == "north" {
            // Load orientation reference image from assets
            let orientationReferenceName = animType == "idle" 
                ? (dir == "west" ? "reference_west_idle" : "reference_north_idle")
                : (dir == "west" ? "reference_west_walk" : "reference_north_walk")
            
            // Helper function to continue with FLUX.2 Pro refinement (matching initial generation)
            func continueWithFlux2ProRefinement(using orientedImageData: Data) {
                // Use FLUX.2 Pro with multiple references: [character reference, orientation reference]
                SpriteGenerationService.shared.generateImageWithFlux2ProMultiReference(
                    referenceImages: [refImageData, orientedImageData],
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    skipBackgroundRemoval: false,
                    strength: 0.5,
                    direction: dir
                ) { [weak self] imageData in
                    self?.handleRegeneratedSprite(imageData: imageData, fileURL: fileURL, frameIdentifier: frameIdentifier, fileName: fileName, dir: dir, animType: animType)
                }
            }
            
            if let orientationReferenceData = SpriteGenerationService.shared.loadReferenceImage(named: orientationReferenceName) {
                print("   ✅ Loaded \(dir) \(animType) orientation reference from assets")
                continueWithFlux2ProRefinement(using: orientationReferenceData)
            } else {
                // Fallback to text-to-image if reference image not found (matching initial generation)
                print("   ⚠️ Reference image '\(orientationReferenceName)' not found, generating with text-to-image...")
                
                // Build orientation prompt matching initial generation exactly
                let directionInstruction = dir == "west" ? "CRITICAL: facing LEFT only, LEFT side profile, body rotated 90 degrees LEFT, LEFT arm and LEFT leg visible, RIGHT side completely hidden, head facing LEFT, NOT facing camera, NOT front view, side profile LEFT ONLY" : "CRITICAL: facing AWAY from camera, back view only, back of head visible, back of body visible, NOT facing camera, NOT front view, back view ONLY"
                
                let orientationPrompt: String
                let orientationNegativePrompt: String
                
                if animType == "idle" {
                    // For idle: use idle pose (matching initial generation for idle)
                    orientationPrompt = "\(characterDescForPrompt)\(characterDescription)\(viewDescription). Idle pose, full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). \(directionInstruction)."
                    orientationNegativePrompt = "multiple characters, facing camera, front view, \(directionSpecificNegative), background"
                } else {
                    // For walk: use walking pose (matching initial generation for walk)
                    let armInstruction = dir == "north"
                        ? "arms relaxed straight down at sides, minimal movement, hands close to body, no big swing"
                        : "arms relaxed mostly at sides, very small natural swing, hands stay close to body, no wide or exaggerated arm swing"
                    orientationPrompt = "\(characterDescForPrompt)\(characterDescription)\(viewDescription). Walking pose, one leg forward, \(armInstruction), full body, fills entire frame, CRITICAL: Character MUST have a thin, clean, solid black outline around the entire silhouette, black border around character edges. \(SpriteSheetConstants.backgroundColorDescription). \(directionInstruction)."
                    orientationNegativePrompt = "multiple characters, facing camera, front view, \(directionSpecificNegative), background"
                }
                
                print("   🎨 Step 1: Generating \(animType)_\(dir) orientation with text-to-image...")
                SpriteGenerationService.shared.generateImageWithReplicateTextToImage(
                    prompt: orientationPrompt,
                    negativePrompt: orientationNegativePrompt,
                    skipBackgroundRemoval: false
                ) { [weak self] generatedImageData in
                    guard let self = self, let generatedImageData = generatedImageData else {
                        print("   ❌ Step 1 failed: Could not generate oriented view for \(animType)_\(dir)")
                        // Reload screen to restore old sprite
                        if let character = self?.currentCharacter, let framePaths = character.framePaths {
                            self?.showSpritePreviewScreen(character: character, framePaths: framePaths)
                        }
                        return
                    }
                    print("   ✅ Step 1 complete: Generated oriented view for \(animType)_\(dir)")
                    continueWithFlux2ProRefinement(using: generatedImageData)
                }
            }
        } else {
            // South direction - use FLUX.2 Pro with walk reference if available (matching initial generation), otherwise img2img
            if animType == "walk" {
                // For walk south, try to use FLUX.2 Pro with walk reference image (matching initial generation)
                let walkReferenceImageName = "reference_south_walk"
                if let walkReferenceData = SpriteGenerationService.shared.loadReferenceImage(named: walkReferenceImageName) {
                    print("   ✅ Loaded south walk reference from assets, using FLUX.2 Pro")
                    // Use FLUX.2 Pro with multiple references: [south idle, walk reference] (matching initial generation)
                    SpriteGenerationService.shared.generateImageWithFlux2ProMultiReference(
                        referenceImages: [refImageData, walkReferenceData],
                        prompt: prompt,
                        negativePrompt: negativePrompt,
                        skipBackgroundRemoval: false,
                        strength: 0.5,
                        direction: dir
                    ) { [weak self] imageData in
                        self?.handleRegeneratedSprite(imageData: imageData, fileURL: fileURL, frameIdentifier: frameIdentifier, fileName: fileName, dir: dir, animType: animType)
                    }
                } else {
                    print("   ⚠️ Walk reference image not found, using img2img fallback")
                    // Fallback to img2img (matching initial generation fallback)
                    SpriteGenerationService.shared.regenerateSpriteFrame(
                        referenceImage: refImageData,
                        prompt: prompt,
                        negativePrompt: negativePrompt,
                        direction: dir,
                        isBackView: false,
                        skipBackgroundRemoval: false,
                        strength: 0.75
                    ) { [weak self] imageData in
                        self?.handleRegeneratedSprite(imageData: imageData, fileURL: fileURL, frameIdentifier: frameIdentifier, fileName: fileName, dir: dir, animType: animType)
                    }
                }
            } else {
                // South idle - use img2img (matching initial generation)
                SpriteGenerationService.shared.regenerateSpriteFrame(
                    referenceImage: refImageData,
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    direction: dir,
                    isBackView: false,
                    skipBackgroundRemoval: false,
                    strength: 0.75
                ) { [weak self] imageData in
                    self?.handleRegeneratedSprite(imageData: imageData, fileURL: fileURL, frameIdentifier: frameIdentifier, fileName: fileName, dir: dir, animType: animType)
                }
            }
        }
    }
    
    private func handleRegeneratedSprite(imageData: Data?, fileURL: URL, frameIdentifier: String, fileName: String, dir: String, animType: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let imageData = imageData else {
                print("❌ Failed to regenerate sprite frame")
                // Reload the screen to restore the old sprite
                if let character = self?.currentCharacter, let framePaths = character.framePaths {
                    self?.showSpritePreviewScreen(character: character, framePaths: framePaths)
                }
                return
            }
            
            // Resize to 1024x1024 for better quality (SpriteKit will scale down for display)
            guard let resizedImageData = SpriteGenerationService.shared.resizeImage(imageData, toWidth: 1024, toHeight: 1024) else {
                print("❌ Failed to resize regenerated sprite frame")
                // Reload the screen to restore the old sprite
                if let character = self.currentCharacter, let framePaths = character.framePaths {
                    self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                }
                return
            }
            
            // Save the resized image to the same path (replacing the old file)
            do {
                try resizedImageData.write(to: fileURL)
                print("✅ Regenerated sprite frame saved (resized to 128x128): \(fileURL.path)")
                
                // If this is a "west" sprite, also create and save the flipped "east" version
                if dir == "west" {
                        // Find the corresponding east sprite path
                        let eastFileName = fileName.replacingOccurrences(of: "_west.", with: "_east.")
                        let eastFileURL: URL
                        if frameIdentifier.hasPrefix("CharacterSprites/") {
                            if let documentsDir = SpriteGenerationService.shared.documentsDirectory {
                                eastFileURL = documentsDir.appendingPathComponent(eastFileName)
                            } else {
                                print("⚠️ Failed to get documents directory for east sprite")
                                // Continue without creating east sprite
                                if let character = self.currentCharacter, let framePaths = character.framePaths {
                                    self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                                }
                                return
                            }
                        } else {
                            let eastPath = frameIdentifier.replacingOccurrences(of: "_west.", with: "_east.")
                            eastFileURL = URL(fileURLWithPath: eastPath)
                        }
                        
                        // Flip the resized west image horizontally to create the east sprite
                        #if os(macOS)
                        guard let westImage = NSImage(data: resizedImageData),
                              let tiffData = westImage.tiffRepresentation,
                              let bitmapRep = NSBitmapImageRep(data: tiffData),
                              let westCGImage = bitmapRep.cgImage else {
                            print("⚠️ Failed to load west image for flipping")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        // Create flipped image using Core Graphics
                        let width = westCGImage.width
                        let height = westCGImage.height
                        let bytesPerPixel = 4
                        let bytesPerRow = width * bytesPerPixel
                        let bitsPerComponent = 8
                        
                        guard let context = CGContext(
                            data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ) else {
                            print("⚠️ Failed to create graphics context for flipping")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        // Flip horizontally by transforming context
                        context.translateBy(x: CGFloat(width), y: 0)
                        context.scaleBy(x: -1.0, y: 1.0)
                        context.draw(westCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                        
                        guard let eastCGImage = context.makeImage() else {
                            print("⚠️ Failed to create flipped image")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        let eastImage = NSImage(cgImage: eastCGImage, size: NSSize(width: width, height: height))
                        guard let eastImageData = eastImage.tiffRepresentation,
                              let eastBitmapRep = NSBitmapImageRep(data: eastImageData),
                              let eastPNGData = eastBitmapRep.representation(using: .png, properties: [:]) else {
                            print("⚠️ Failed to convert flipped image to PNG")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        #else
                        guard let westImage = UIImage(data: resizedImageData),
                              let westCGImage = westImage.cgImage else {
                            print("⚠️ Failed to load west image for flipping")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        // Create flipped image using Core Graphics
                        let width = westCGImage.width
                        let height = westCGImage.height
                        let bytesPerPixel = 4
                        let bytesPerRow = width * bytesPerPixel
                        let bitsPerComponent = 8
                        
                        guard let context = CGContext(
                            data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ) else {
                            print("⚠️ Failed to create graphics context for flipping")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        // Flip horizontally by transforming context
                        context.translateBy(x: CGFloat(width), y: 0)
                        context.scaleBy(x: -1.0, y: 1.0)
                        context.draw(westCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                        
                        guard let eastCGImage = context.makeImage() else {
                            print("⚠️ Failed to create flipped image")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        
                        let eastImage = UIImage(cgImage: eastCGImage)
                        guard let eastPNGData = eastImage.pngData() else {
                            print("⚠️ Failed to convert flipped image to PNG")
                            if let character = self.currentCharacter, let framePaths = character.framePaths {
                                self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                            }
                            return
                        }
                        #endif
                        
                        // Save the flipped east sprite
                        do {
                            try eastPNGData.write(to: eastFileURL)
                            print("✅ Created flipped east sprite: \(eastFileURL.path)")
                        } catch {
                            print("⚠️ Failed to save flipped east sprite: \(error)")
                        }
                }
                
                // Update character's frame paths if needed (should already contain this path)
                // Update only the specific sprite(s) that were regenerated, not the entire screen
                self.updateRegeneratedSprite(frameIdentifier: frameIdentifier, fileURL: fileURL, dir: dir, animType: animType, newImageData: imageData)
                } catch {
                    print("❌ Failed to save regenerated sprite: \(error)")
                    // Reload the screen to restore the old sprite
                    if let character = self.currentCharacter, let framePaths = character.framePaths {
                        self.showSpritePreviewScreen(character: character, framePaths: framePaths)
                    }
                }
            }
    }
    
    /// Update a single regenerated sprite without reloading the entire screen
    private func updateRegeneratedSprite(frameIdentifier: String, fileURL: URL, dir: String, animType: String, newImageData: Data) {
        // Use the removedSprites dictionary to find the exact sprite that was removed for this frameIdentifier
        // This ensures we only update the sprite that corresponds to this specific regeneration
        guard let removedSpriteInfo = removedSprites[frameIdentifier] else {
            print("⚠️ Could not find removed sprite info for \(frameIdentifier), reloading entire screen")
            // Clean up the dictionary entry
            removedSprites.removeValue(forKey: frameIdentifier)
            if let character = currentCharacter, let framePaths = character.framePaths {
                showSpritePreviewScreen(character: character, framePaths: framePaths)
            }
            return
        }
        
        // Create texture from new image data
        #if os(macOS)
        guard let image = NSImage(data: newImageData) else {
            print("⚠️ Failed to create image from data for \(frameIdentifier)")
            removedSprites.removeValue(forKey: frameIdentifier)
            return
        }
        let texture = SKTexture(image: image)
        #else
        guard let image = UIImage(data: newImageData) else {
            print("⚠️ Failed to create image from data for \(frameIdentifier)")
            removedSprites.removeValue(forKey: frameIdentifier)
            return
        }
        let texture = SKTexture(image: image)
        #endif
        texture.filteringMode = .nearest // Match sprite frame filtering
        
        // Create new sprite with the regenerated image
        let newSprite = SKSpriteNode(texture: texture)
        newSprite.size = CGSize(width: removedSpriteInfo.size, height: removedSpriteInfo.size)
        newSprite.position = removedSpriteInfo.position
        newSprite.name = removedSpriteInfo.sprite.name // Preserve the original name
        newSprite.zPosition = removedSpriteInfo.sprite.zPosition
        
        // Copy the label and regenerate button from the original sprite if they exist
        for child in removedSpriteInfo.sprite.children {
            if let label = child as? SKLabelNode {
                let newLabel = label.copy() as! SKLabelNode
                newSprite.addChild(newLabel)
            } else if let button = child.copy() as? SKNode {
                newSprite.addChild(button)
            }
        }
        
        // Add the sprite back to its original parent
        removedSpriteInfo.parent.addChild(newSprite)
        
        // Clean up the dictionary entry
        removedSprites.removeValue(forKey: frameIdentifier)
        
        // If this is west and we also created east, update east too
        if dir == "west" {
            let eastFrameIdentifier = frameIdentifier.replacingOccurrences(of: "_west.", with: "_east.").replacingOccurrences(of: "_west_", with: "_east_")
            if let eastRemovedInfo = removedSprites[eastFrameIdentifier] {
                // Load the east file (which was already saved flipped)
                let eastFileName = fileURL.lastPathComponent.replacingOccurrences(of: "_west.", with: "_east.")
                let eastFileURL = fileURL.deletingLastPathComponent().appendingPathComponent(eastFileName)
                if let eastImageData = try? Data(contentsOf: eastFileURL) {
                    #if os(macOS)
                    if let eastImage = NSImage(data: eastImageData) {
                        let eastTexture = SKTexture(image: eastImage)
                        eastTexture.filteringMode = .nearest
                        let eastSprite = SKSpriteNode(texture: eastTexture)
                        eastSprite.size = CGSize(width: eastRemovedInfo.size, height: eastRemovedInfo.size)
                        eastSprite.position = eastRemovedInfo.position
                        eastSprite.name = eastRemovedInfo.sprite.name
                        eastSprite.zPosition = eastRemovedInfo.sprite.zPosition
                        
                        // Copy children
                        for child in eastRemovedInfo.sprite.children {
                            if let label = child as? SKLabelNode {
                                let newLabel = label.copy() as! SKLabelNode
                                eastSprite.addChild(newLabel)
                            } else if let button = child.copy() as? SKNode {
                                eastSprite.addChild(button)
                            }
                        }
                        
                        eastRemovedInfo.parent.addChild(eastSprite)
                        removedSprites.removeValue(forKey: eastFrameIdentifier)
                    }
                    #else
                    if let eastImage = UIImage(data: eastImageData) {
                        let eastTexture = SKTexture(image: eastImage)
                        eastTexture.filteringMode = .nearest
                        let eastSprite = SKSpriteNode(texture: eastTexture)
                        eastSprite.size = CGSize(width: eastRemovedInfo.size, height: eastRemovedInfo.size)
                        eastSprite.position = eastRemovedInfo.position
                        eastSprite.name = eastRemovedInfo.sprite.name
                        eastSprite.zPosition = eastRemovedInfo.sprite.zPosition
                        
                        // Copy children
                        for child in eastRemovedInfo.sprite.children {
                            if let label = child as? SKLabelNode {
                                let newLabel = label.copy() as! SKLabelNode
                                eastSprite.addChild(newLabel)
                            } else if let button = child.copy() as? SKNode {
                                eastSprite.addChild(button)
                            }
                        }
                        
                        eastRemovedInfo.parent.addChild(eastSprite)
                        removedSprites.removeValue(forKey: eastFrameIdentifier)
                    }
                    #endif
                }
            }
        }
        
        print("✅ Updated sprite for \(frameIdentifier) without reloading screen")
    }
    
    // MARK: - Sprite Preview
    
    /// Show preview screen with all generated sprite frames
    func showSpritePreviewScreen(character: GameCharacter, framePaths: [String]) {
        // Remove all existing children
        removeAllChildren()
        addBackgroundImage()
        currentStep = .spritePreview
        
        backgroundColor = SKColor(red: 0.88, green: 0.82, blue: 0.72, alpha: 1.0)
        
        let isLandscape = size.width > size.height
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        
        // Book page panel removed - no margins needed
        
        // Define panel boundaries (using full screen now)
        let panelTop: CGFloat = size.height
        let panelBottom: CGFloat = 0.0
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
        instructionLabel.text = "Review your character sprites. You can regenerate individual sprites if needed."
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
        let containerSpacing: CGFloat = isLandscape ? 60 : 70  // Increased to prevent refresh button overlap
        
        // Calculate total width for frames (used for both containers)
        let totalFramesWidth: CGFloat = 4 * frameSize + 3 * spacing
        
        // Calculate container dimensions
        let containerWidth: CGFloat = totalFramesWidth + 2 * containerPadding
        // Reduced height: sprite + label + minimal padding (no refresh button space for all since east doesn't have one)
        // Only need space for refresh button on 3 of 4 sprites, but keep consistent height
        let refreshButtonSize: CGFloat = min(30, frameSize * 0.3)
        // Reduced from original: just sprite + label spacing + small padding
        let containerHeight: CGFloat = frameSize + labelHeight + 15 + 2 * containerPadding // Shorter container
        
        // Calculate positions - ensure containers don't get covered by buttons
        let instructionBottom = instructionLabel.position.y - (isLandscape ? 25 : 30) // Bottom of instruction text
        // Account for both buttons (Start Game + Back) with spacing, plus extra padding
        let buttonAreaHeight = (dims.buttonHeight * 2) + dims.spacing + 40 // Both buttons + spacing + extra padding
        let buttonAreaTop = panelBottom + borderMargin + buttonAreaHeight
        let availableHeight = instructionBottom - buttonAreaTop
        let totalContainersHeight = 2 * containerHeight + containerSpacing
        // Position idle container above walk container
        let walkContainerY = buttonAreaTop + containerHeight / 2 + 40 // Position walk container above buttons with padding
        let startY = walkContainerY + containerHeight + containerSpacing // Position idle container above walk
        
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
        // Use walkContainerY calculated above
        walkContainer.position = CGPoint(x: size.width / 2, y: walkContainerY)
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
        
        // Buttons at bottom - positioned above bottom border
        let buttonPadding: CGFloat = isLandscape ? 70 : 80
        let backButtonY: CGFloat = panelBottom + borderMargin + buttonPadding
        let startButtonY: CGFloat = backButtonY + dims.buttonHeight + dims.spacing
        
        // Back button
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2, y: backButtonY),
            name: "backButton",
            fontSize: isLandscape ? 22 : 26
        )
        backButton.zPosition = 10
        addChild(backButton)
        
        // Start Game button
        let startButton = MenuStyling.createBookButton(
            text: "Start Game",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.bookSecondary,
            position: CGPoint(x: size.width / 2, y: startButtonY),
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
        
        // Add regenerate button below label (only for west, north - not east since it's just flipped west, and not south idle since it's the same as preview)
        // Check if this is south idle by checking if path contains "idle_south" and label is "South"
        let isSouthIdle = label.lowercased() == "south" && path.contains("idle_south")
        if label.lowercased() != "east" && !isSouthIdle {
        let regenerateButtonSize: CGFloat = min(30, size * 0.3)
        let regenerateButton = SKShapeNode(rectOf: CGSize(width: regenerateButtonSize, height: regenerateButtonSize), cornerRadius: 4)
        regenerateButton.fillColor = MenuStyling.parchmentBg
        regenerateButton.strokeColor = MenuStyling.parchmentBorder
        regenerateButton.lineWidth = 1
        regenerateButton.position = CGPoint(x: 0, y: -size/2 - 50)
        regenerateButton.zPosition = 3
        regenerateButton.name = "regenerate_\(path)"
        sprite.addChild(regenerateButton)
        
        // Add refresh icon/label
        let refreshLabel = SKLabelNode(fontNamed: "Arial")
        refreshLabel.text = "↻"
        refreshLabel.fontSize = regenerateButtonSize * 0.6
        refreshLabel.fontColor = MenuStyling.inkColor
        refreshLabel.verticalAlignmentMode = .center
        refreshLabel.zPosition = 4
        regenerateButton.addChild(refreshLabel)
        }
    }
    
    /// Remove backgrounds from all frames and start the game
    func removeBackgroundsAndStartGame(character: GameCharacter) {
        guard let framePaths = character.framePaths, !framePaths.isEmpty else {
            print("❌ No frame paths to process")
            return
        }
        
        // Add loading spinner to the Start Game button
        guard let startButton = childNode(withName: "startGameButton") else {
            print("⚠️ Start Game button not found")
            return
        }
        
        // Find the label inside the button to position spinner to its right
        var labelNode: SKLabelNode? = nil
        startButton.enumerateChildNodes(withName: "") { node, _ in
            if let label = node as? SKLabelNode, label.text == "Start Game" {
                labelNode = label
            }
        }
        
        // If not found by text, search all children
        if labelNode == nil {
            for child in startButton.children {
                if let shapeNode = child as? SKShapeNode {
                    for grandchild in shapeNode.children {
                        if let label = grandchild as? SKLabelNode, label.text == "Start Game" {
                            labelNode = label
                            break
                        }
                    }
                }
            }
        }
        
        // Create small loading spinner to the right of "Start Game" text
        let spinnerRadius: CGFloat = 8.0
        let spinnerPath = CGMutablePath()
        spinnerPath.addArc(center: .zero, radius: spinnerRadius, startAngle: 0, endAngle: CGFloat.pi * 1.5, clockwise: false)
        
        let spinner = SKShapeNode(path: spinnerPath)
        spinner.strokeColor = MenuStyling.inkColor
        spinner.fillColor = SKColor.clear
        spinner.lineWidth = 2.5
        spinner.lineCap = .round
        spinner.lineJoin = .round
        
        // Position spinner to the right of the label
        if let label = labelNode {
            // Calculate position: label's right edge + spacing
            // Label position is relative to its parent (button shape), so we need to account for that
            let labelWidth = label.frame.width
            let spacing: CGFloat = 12.0
            spinner.position = CGPoint(x: label.position.x + labelWidth / 2 + spacing + spinnerRadius, y: label.position.y)
        } else {
            // Fallback: position relative to button center (estimate based on button width)
            let isLandscape = size.width > size.height
            let dims = MenuStyling.getResponsiveDimensions(size: size)
            let estimatedTextWidth: CGFloat = isLandscape ? 100 : 120
            spinner.position = CGPoint(x: estimatedTextWidth / 2 + 12 + spinnerRadius, y: 0)
        }
        
        spinner.zPosition = 5  // Above button background, below label
        spinner.name = "loadingSpinner"
        
        // Rotate animation
        let rotate = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 1.0)
        let repeatRotate = SKAction.repeatForever(rotate)
        spinner.run(repeatRotate)
        
        // Add spinner to the button's shape node (not the container)
        // The button structure is: container -> shape node -> label
        if let buttonShape = startButton.children.first(where: { $0 is SKShapeNode && ($0.name == nil || $0.name != "shadow") }) {
            buttonShape.addChild(spinner)
        } else {
            startButton.addChild(spinner)
        }
        
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
                    
                    // Remove loading spinner from button
                    if let startButton = self.childNode(withName: "startGameButton") {
                        startButton.enumerateChildNodes(withName: "loadingSpinner") { node, _ in
                            node.removeFromParent()
                        }
                    }
                    
                    // Actually start the game with the updated character
                    if let gameState = SaveManager.loadGame(characterId: updatedCharacter.id, fromSlot: 1) {
                        self.startGame(character: updatedCharacter, gameState: gameState)
                    } else {
                        // Create new game state if no save exists - always save to slot 1 on first start
                        let abilityScores = AbilityScores(strength: 15, dexterity: 14, constitution: 13, intelligence: 12, wisdom: 10, charisma: 8)
                        let player = Player(name: updatedCharacter.name, characterClass: .ranger, abilityScores: abilityScores)
                        let world = WorldMap(width: 50, height: 50, seed: Int.random(in: 0...Int.max))
                        
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
                        
                        let gameState = GameState(player: player, world: world)
                        
                        // Always autosave to slot 1 on first start
                        _ = SaveManager.saveGame(gameState: gameState, characterId: updatedCharacter.id, toSlot: 1)
                        
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
                // Spinner continues rotating - no need to update text
                
                // Process next frame
                processNextFrame(index: index + 1)
            }
        }
        
        // Start processing
        processNextFrame(index: 0)
    }
    
    // MARK: - Story Video Playback
    
    /// Show and play the story cut-scene video
    func showStoryVideo() {
        // Hide existing video if one is already showing
        hideStoryVideo()
        
        isShowingStory = true
        
        // Try to load video from bundle
        // First, try to find video file in the bundle
        // You can add your video file to the project and reference it here
        // Common video formats: .mp4, .mov, .m4v
        var videoURL: URL?
        
        // Try different possible video file names/locations
        let possibleVideoNames = ["story_cutscene", "intro_story", "character_story", "story"]
        let possibleExtensions = ["mp4", "mov", "m4v"]
        
        for videoName in possibleVideoNames {
            for ext in possibleExtensions {
                if let url = Bundle.main.url(forResource: videoName, withExtension: ext) {
                    videoURL = url
                    break
                }
            }
            if videoURL != nil { break }
        }
        
        guard let url = videoURL else {
            print("⚠️ Story video not found in bundle. Please add a video file named 'story_cutscene.mp4' (or similar) to your project.")
            // Show a message to the user that video is not available
            showVideoNotFoundMessage()
            isShowingStory = false
            return
        }
        
        // Create AVPlayer
        let player = AVPlayer(url: url)
        videoPlayer = player
        
        // Create SKVideoNode with the player
        let videoNode = SKVideoNode(avPlayer: player)
        videoNode.size = size // Full screen
        videoNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        videoNode.zPosition = 1000 // Above everything
        videoNode.name = "storyVideoNode"
        
        // Add dark overlay behind video
        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = SKColor.black
        overlay.strokeColor = SKColor.clear
        overlay.alpha = 0.8
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 999
        overlay.name = "storyVideoOverlay"
        addChild(overlay)
        
        // Add close button
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        let closeButton = MenuStyling.createBookButton(
            text: "Close",
            size: CGSize(width: dims.buttonWidth * 0.5, height: dims.buttonHeight),
            color: MenuStyling.bookSecondary,
            position: CGPoint(x: size.width / 2, y: dims.buttonHeight / 2 + 20),
            name: "closeStoryButton",
            fontSize: isLandscape ? 20 : 24
        )
        closeButton.zPosition = 1001
        addChild(closeButton)
        
        // Add video node
        addChild(videoNode)
        self.videoNode = videoNode
        
        // Play video
        player.play()
        
        // Observe when video finishes playing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(videoDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
    
    /// Hide and stop the story video
    func hideStoryVideo() {
        // Stop video playback
        videoPlayer?.pause()
        videoPlayer?.replaceCurrentItem(with: nil) // Release player item
        videoPlayer = nil
        
        // Remove video node
        if let node = videoNode {
            node.removeFromParent()
            // Pause the video node before removing
            if #available(iOS 13.0, macOS 10.15, tvOS 13.0, *) {
                node.pause()
            }
        }
        videoNode = nil
        
        // Remove overlay
        childNode(withName: "storyVideoOverlay")?.removeFromParent()
        
        // Remove close button
        childNode(withName: "closeStoryButton")?.removeFromParent()
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        isShowingStory = false
    }
    
    /// Show a message when video is not found
    func showVideoNotFoundMessage() {
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Create message overlay
        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = SKColor.black
        overlay.strokeColor = SKColor.clear
        overlay.alpha = 0.8
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 1000
        overlay.name = "videoNotFoundOverlay"
        addChild(overlay)
        
        // Create message label
        let messageLabel = SKLabelNode(fontNamed: "Arial")
        messageLabel.text = "Story video not available"
        messageLabel.fontSize = isLandscape ? 24 : 28
        messageLabel.fontColor = .white
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 30)
        messageLabel.zPosition = 1001
        messageLabel.name = "videoNotFoundMessage"
        addChild(messageLabel)
        
        // Create close button
        let closeButton = MenuStyling.createBookButton(
            text: "Close",
            size: CGSize(width: dims.buttonWidth * 0.5, height: dims.buttonHeight),
            color: MenuStyling.bookSecondary,
            position: CGPoint(x: size.width / 2, y: size.height / 2 - 50),
            name: "closeVideoNotFoundButton",
            fontSize: isLandscape ? 20 : 24
        )
        closeButton.zPosition = 1001
        addChild(closeButton)
    }
    
    /// Hide the video not found message
    func hideVideoNotFoundMessage() {
        childNode(withName: "videoNotFoundOverlay")?.removeFromParent()
        childNode(withName: "videoNotFoundMessage")?.removeFromParent()
        childNode(withName: "closeVideoNotFoundButton")?.removeFromParent()
    }
    
    /// Notification handler for when video finishes playing
    @objc func videoDidFinishPlaying() {
        DispatchQueue.main.async { [weak self] in
            self?.hideStoryVideo()
        }
    }
    
    // MARK: - Text Input Helpers
    
    func showNameInputField() {
        print("📝 showNameInputField() called")
        // Search recursively - nodes are in contentContainer which is in cropNode
        var nameInputArea: SKShapeNode?
        
        // Try direct search first
        nameInputArea = childNode(withName: "nameInputArea") as? SKShapeNode
        
        // Search in contentContainer if not found
        if nameInputArea == nil {
            if let container = childNode(withName: "contentContainer") {
                nameInputArea = container.childNode(withName: "nameInputArea") as? SKShapeNode
            }
        }
        
        // Search in cropNode > container if still not found
        if nameInputArea == nil {
            if let cropNode = childNode(withName: "contentCropNode") {
                if let container = cropNode.childNode(withName: "contentContainer") {
                    nameInputArea = container.childNode(withName: "nameInputArea") as? SKShapeNode
                }
            }
        }
        
        guard let nameInputArea = nameInputArea else {
            print("❌ Could not find nameInputArea node - searching all nodes...")
            enumerateChildNodes(withName: "//nameInputArea") { node, _ in
                print("  Found node: \(node)")
            }
            return
        }
        print("✅ Found nameInputArea node")
        hideAllTextFields() // Hide any existing text fields
        
        // Don't hide the SKShapeNode border - let it show under the container view border
        // The description field doesn't hide its border either
        
        // Get input area frame in scene coordinates
        // Get input area frame in scene coordinates using calculateAccumulatedFrame
        // Get input area frame in scene coordinates using calculateAccumulatedFrame
        let accumulatedFrame = nameInputArea.calculateAccumulatedFrame()
        let inputSize = accumulatedFrame.size
        let inputPosition = nameInputArea.position
        
        #if os(iOS) || os(tvOS)
        guard let skView = view else { return }
        
        // Convert scene coordinates to view coordinates
        // Scene: center (0,0), bottom at -size.height/2, top at size.height/2
        // View: top at 0, bottom at bounds.height
        let frameTopInScene = accumulatedFrame.maxY
        let sceneBottom = -size.height / 2
        let scaleY = skView.bounds.height / size.height
        let viewY = skView.bounds.height - ((frameTopInScene - sceneBottom) * scaleY)
        
        let frameLeftInScene = accumulatedFrame.minX
        let sceneLeft = -size.width / 2
        let scaleX = skView.bounds.width / size.width
        let viewX = ((frameLeftInScene - sceneLeft) * scaleX)
        
        // Create container view for better control over styling and centering
        let containerView = UIView(frame: CGRect(
            x: viewX,
            y: viewY,
            width: inputSize.width,
            height: inputSize.height
        ))
        containerView.backgroundColor = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 0.9)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 2
        containerView.layer.borderColor = UIColor(red: 0.70, green: 0.65, blue: 0.55, alpha: 1.0).cgColor
        
        let textField = UITextField(frame: containerView.bounds)
        textField.text = characterName
        textField.placeholder = "Tap to enter name"
        textField.textAlignment = .center
        textField.contentVerticalAlignment = .center
        textField.font = UIFont(name: "Arial-BoldMT", size: 20)
        textField.textColor = UIColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0)
        textField.backgroundColor = UIColor.clear
        textField.borderStyle = .none
        textField.tintColor = UIColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0) // Match text color to remove blue cursor/tint
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.tag = 1001 // Tag for name field
        textField.delegate = self
        
        containerView.addSubview(textField)
        
        skView.addSubview(containerView)
        textField.becomeFirstResponder()
        nameTextField = textField
        nameTextFieldContainer = containerView
        
        #elseif os(macOS)
        guard let skView = view as? NSView else { return }
        
        // Convert scene coordinates to view coordinates using accumulatedFrame
        // Calculate bottom Y for NSView (bottom-left origin)
        let accumulatedFrameMac = nameInputArea.calculateAccumulatedFrame()
        let inputSizeMac = accumulatedFrameMac.size
        let frameBottomInSceneMac = accumulatedFrameMac.minY
        let sceneBottomMac = -size.height / 2
        let scaleYMac = skView.bounds.height / size.height
        // Convert bottom Y from scene to view: sceneBottom is -height/2, view bottom is 0
        // So: viewBottomY = (frameBottomInScene - sceneBottom) * scaleY
        // Adjust up by 15px to align with visual box (add to move up in view coordinates)
        let viewYMac = (frameBottomInSceneMac - sceneBottomMac) * scaleYMac + 44.0
        
        let frameLeftInSceneMac = accumulatedFrameMac.minX
        let sceneLeftMac = -size.width / 2
        let scaleXMac = skView.bounds.width / size.width
        let viewXMac = ((frameLeftInSceneMac - sceneLeftMac) * scaleXMac)
        
        // Create container view for styling (same as description)
        let containerView = NSView(frame: NSRect(
            x: viewXMac,
            y: viewYMac,
            width: inputSizeMac.width,
            height: inputSizeMac.height
        ))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1.0).cgColor
        containerView.layer?.cornerRadius = 8
        containerView.layer?.borderWidth = 2
        // Use brown border color to match the parchment style (not blue) - ensure it stays brown
        let brownBorderColor = NSColor(red: 0.70, green: 0.65, blue: 0.55, alpha: 1.0).cgColor
        containerView.layer?.borderColor = brownBorderColor
        // Lock the border color so it doesn't change
        containerView.layer?.setNeedsDisplay()
        // Prevent focus ring from showing
        containerView.canDrawConcurrently = false
        
        // Use NSTextView like description field - it has textContainerInset which works!
        // Make it single-line by disabling wrapping
        let textView = NSTextView(frame: NSRect(
            x: 0,
            y: 0,
            width: inputSizeMac.width,
            height: inputSizeMac.height
        ))
        // Set up text view properties first
        textView.font = NSFont(name: "Arial-BoldMT", size: 20)
        textView.textColor = NSColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0)
        textView.backgroundColor = NSColor.clear
        textView.isAutomaticLinkDetectionEnabled = false
        // Add top padding - increase from 8px to 12px for more spacing
        textView.textContainerInset = NSSize(width: 0, height: 12) // 12px top padding, 0px horizontal
        
        // Center align text - apply to the text view's typing attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        textView.defaultParagraphStyle = paragraphStyle
        // Set typing attributes to ensure new text is centered with correct font
        let font = NSFont(name: "Arial-BoldMT", size: 20) ?? NSFont.systemFont(ofSize: 20)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        // Set text with attributed string to ensure font and alignment are preserved
        if !characterName.isEmpty {
            let attributedString = NSMutableAttributedString(string: characterName)
            attributedString.addAttributes([
                .font: font,
                .foregroundColor: NSColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0),
                .paragraphStyle: paragraphStyle
            ], range: NSRange(location: 0, length: attributedString.length))
            textView.textStorage?.setAttributedString(attributedString)
        } else {
            // Set empty string to ensure attributes are applied
            textView.string = ""
        }
        // Make it single-line (disable wrapping)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: inputSizeMac.width, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        
        // Register for text editing notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nameTextDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidEndEditing(_:)),
            name: NSText.didEndEditingNotification,
            object: textView
        )
        
        containerView.addSubview(textView)
        skView.addSubview(containerView)
        skView.window?.makeFirstResponder(textView)
        nameTextField = textView
        nameTextFieldContainer = containerView
        #endif
    }
    
    func showDescriptionInputField() {
        print("📝 showDescriptionInputField() called")
        // Search recursively - nodes are in contentContainer which is in cropNode
        var descriptionInputArea: SKShapeNode?
        
        // Try direct search first
        descriptionInputArea = childNode(withName: "descriptionInputArea") as? SKShapeNode
        
        // Search in contentContainer if not found
        if descriptionInputArea == nil {
            if let container = childNode(withName: "contentContainer") {
                descriptionInputArea = container.childNode(withName: "descriptionInputArea") as? SKShapeNode
            }
        }
        
        // Search in cropNode > container if still not found
        if descriptionInputArea == nil {
            if let cropNode = childNode(withName: "contentCropNode") {
                if let container = cropNode.childNode(withName: "contentContainer") {
                    descriptionInputArea = container.childNode(withName: "descriptionInputArea") as? SKShapeNode
                }
            }
        }
        
        guard let descriptionInputArea = descriptionInputArea else {
            print("❌ Could not find descriptionInputArea node - searching all nodes...")
            enumerateChildNodes(withName: "//descriptionInputArea") { node, _ in
                print("  Found node: \(node)")
            }
            return
        }
        print("✅ Found descriptionInputArea node")
        hideAllTextFields() // Hide any existing text fields
        
        // Get input area frame in scene coordinates using calculateAccumulatedFrame
        let accumulatedFrame = descriptionInputArea.calculateAccumulatedFrame()
        let inputSize = accumulatedFrame.size
        let inputPosition = descriptionInputArea.position
        
        #if os(iOS) || os(tvOS)
        guard let skView = view else { return }
        
        // Convert scene coordinates to view coordinates
        // Scene: center (0,0), bottom at -size.height/2, top at size.height/2
        // View: top at 0, bottom at bounds.height
        let frameTopInScene = accumulatedFrame.maxY
        let sceneBottom = -size.height / 2
        let scaleY = skView.bounds.height / size.height
        let viewY = skView.bounds.height - ((frameTopInScene - sceneBottom) * scaleY)
        
        let frameLeftInScene = accumulatedFrame.minX
        let sceneLeft = -size.width / 2
        let scaleX = skView.bounds.width / size.width
        let viewX = ((frameLeftInScene - sceneLeft) * scaleX)
        
        let textView = UITextView(frame: CGRect(
            x: viewX,
            y: viewY,
            width: inputSize.width,
            height: inputSize.height
        ))
        textView.text = spriteDescription
        textView.font = UIFont(name: "Arial", size: 18)
        textView.textColor = UIColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0)
        textView.backgroundColor = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 0.9)
        textView.layer.cornerRadius = 8
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.returnKeyType = .default
        textView.tag = 1002 // Tag for description field
        textView.delegate = self
        
        skView.addSubview(textView)
        textView.becomeFirstResponder()
        descriptionTextField = textView
        
        #elseif os(macOS)
        guard let skView = view as? NSView else { return }
        
        // Convert scene coordinates to view coordinates using accumulatedFrame
        // Calculate bottom Y for NSView (bottom-left origin) - same as name field
        let accumulatedFrameMac = descriptionInputArea.calculateAccumulatedFrame()
        let inputSizeMac = accumulatedFrameMac.size
        let frameBottomInSceneMac = accumulatedFrameMac.minY
        let sceneBottomMac = -size.height / 2
        let scaleYMac = skView.bounds.height / size.height
        // Convert bottom Y from scene to view: sceneBottom is -height/2, view bottom is 0
        // So: viewBottomY = (frameBottomInScene - sceneBottom) * scaleY
        // Adjust up by 18px to align with visual box (same as name field)
        let viewYMac = (frameBottomInSceneMac - sceneBottomMac) * scaleYMac + 44.0
        
        let frameLeftInSceneMac = accumulatedFrameMac.minX
        let sceneLeftMac = -size.width / 2
        let scaleXMac = skView.bounds.width / size.width
        let viewXMac = ((frameLeftInSceneMac - sceneLeftMac) * scaleXMac)
        
        // Create container view for styling
        let containerView = NSView(frame: NSRect(
            x: viewXMac,
            y: viewYMac,
            width: inputSizeMac.width,
            height: inputSizeMac.height
        ))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1.0).cgColor
        containerView.layer?.cornerRadius = 8
        containerView.layer?.borderWidth = 2
        containerView.layer?.borderColor = NSColor(red: 0.70, green: 0.65, blue: 0.55, alpha: 1.0).cgColor
        
        let scrollView = NSScrollView(frame: NSRect(
            x: 0,
            y: 0,
            width: inputSizeMac.width,
            height: inputSizeMac.height
        ))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.clear
        scrollView.drawsBackground = false
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: inputSizeMac.width, height: inputSizeMac.height))
        textView.string = spriteDescription
        textView.font = NSFont(name: "Arial", size: 18)
        textView.textColor = NSColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0)
        textView.backgroundColor = NSColor.clear
        textView.isAutomaticLinkDetectionEnabled = false
        // Add padding: 15px left, 15px top
        textView.textContainerInset = NSSize(width: 15, height: 15)
        scrollView.documentView = textView
        
        // Register for text editing notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidEndEditing(_:)),
            name: NSText.didEndEditingNotification,
            object: textView
        )
        
        containerView.addSubview(scrollView)
        skView.addSubview(containerView)
        skView.window?.makeFirstResponder(textView)
        descriptionTextField = textView
        descriptionScrollView = containerView // Store containerView reference instead
        #endif
    }
    
    func hideAllTextFields() {
        // Restore SKShapeNode border when hiding native text field
        if let nameInputArea = childNode(withName: "nameInputArea") as? SKShapeNode {
            nameInputArea.strokeColor = MenuStyling.parchmentBorder
            nameInputArea.lineWidth = 2
        } else if let container = childNode(withName: "contentContainer"),
                  let nameInputArea = container.childNode(withName: "nameInputArea") as? SKShapeNode {
            nameInputArea.strokeColor = MenuStyling.parchmentBorder
            nameInputArea.lineWidth = 2
        } else if let cropNode = childNode(withName: "contentCropNode"),
                  let container = cropNode.childNode(withName: "contentContainer"),
                  let nameInputArea = container.childNode(withName: "nameInputArea") as? SKShapeNode {
            nameInputArea.strokeColor = MenuStyling.parchmentBorder
            nameInputArea.lineWidth = 2
        }
        
        #if os(iOS) || os(tvOS)
        nameTextField?.resignFirstResponder()
        nameTextFieldContainer?.removeFromSuperview()
        nameTextFieldContainer = nil
        nameTextField = nil
        
        (descriptionTextField as? UITextView)?.resignFirstResponder()
        descriptionTextField?.removeFromSuperview()
        descriptionTextField = nil
        
        #elseif os(macOS)
        if let textView = nameTextField {
            NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: textView)
            NotificationCenter.default.removeObserver(self, name: NSText.didEndEditingNotification, object: textView)
            // Remove from view hierarchy first - this will automatically resign first responder
            // Don't call resignFirstResponder() directly as it causes issues with NSTextView
            textView.removeFromSuperview()
            // Make window resign first responder if this was the first responder
            if let window = view?.window, window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
        nameTextFieldContainer?.removeFromSuperview()
        nameTextFieldContainer = nil
        nameTextField = nil
        
        if let textView = descriptionTextField {
            NotificationCenter.default.removeObserver(self, name: NSText.didEndEditingNotification, object: textView)
            // Remove from view hierarchy first - this will automatically resign first responder
            // Don't call resignFirstResponder() directly as it causes issues with NSTextView
            textView.removeFromSuperview()
            // Make window resign first responder if this was the first responder
            if let window = view?.window, window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
        // Remove scrollView properly (not contentView)
        descriptionScrollView?.removeFromSuperview()
        descriptionScrollView = nil
        descriptionTextField = nil
        #endif
    }
    
    // MARK: - Text Field Delegates
    
    #if os(iOS) || os(tvOS)
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField.tag == 1001 { // Name field
            if let text = textField.text {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    characterName = trimmedText
                    updateNameDisplay()
                }
            }
            hideAllTextFields()
        }
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField.tag == 1001 { // Name field
            if let text = textField.text {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    characterName = trimmedText
                    updateNameDisplay()
                }
            }
            hideAllTextFields()
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.tag == 1002 { // Description field
            let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Validate description for NSFW content
            let validation = SpriteGenerationService.shared.validateDescriptionForNSFW(trimmedText)
            if !validation.isValid {
                // Show error and keep text field
                let alert = UIAlertController(
                    title: "Invalid Description",
                    message: validation.reason ?? "Description contains inappropriate content.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                if let viewController = self.view?.window?.rootViewController {
                    viewController.present(alert, animated: true)
                }
                return
            }
            
            spriteDescription = trimmedText
            updateSpriteDescriptionDisplay()
            // Don't generate preview automatically - only when Continue is clicked
            hideAllTextFields()
        }
    }
    
    #elseif os(macOS)
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let textField = control as? NSTextField, textField.tag == 1001 {
                if !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    characterName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    updateNameDisplay()
                }
                hideAllTextFields()
                return true
            }
        }
        return false
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField, textField.tag == 1001 {
            let trimmedText = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                characterName = trimmedText
                updateNameDisplay()
            }
            hideAllTextFields()
        }
    }
    #endif
}

// MARK: - Platform-Specific Extensions

// MARK: - Notification Handlers (macOS)
#if os(macOS)
extension CharacterCreationScene {
    @objc func nameTextDidChange(_ notification: Notification) {
        if let textView = notification.object as? NSTextView, textView == nameTextField {
            characterName = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    @objc func textDidEndEditing(_ notification: Notification) {
        // Handle name field editing end
        if let textView = notification.object as? NSTextView, textView == nameTextField {
            let trimmedText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            characterName = trimmedText
            updateNameDisplay()
        }
        
        // Handle description field editing end
        if let textView = notification.object as? NSTextView, textView == descriptionTextField {
            let trimmedText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Validate description for NSFW content
            let validation = SpriteGenerationService.shared.validateDescriptionForNSFW(trimmedText)
            if !validation.isValid {
                // Show error and keep text field
                let alert = NSAlert()
                alert.messageText = "Invalid Description"
                alert.informativeText = validation.reason ?? "Description contains inappropriate content."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            
            spriteDescription = trimmedText
            updateSpriteDescriptionDisplay()
            // Don't generate preview automatically - only when Continue is clicked
            hideAllTextFields()
        }
    }
}
#endif

// MARK: - Custom Text Field Cell (macOS)
#if os(macOS)
class PaddedTextFieldCell: NSTextFieldCell {
    var verticalPadding: CGFloat = 4.0
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        // Calculate text height based on font metrics
        let textHeight: CGFloat = font?.boundingRectForFont.height ?? 20.0
        // Add top padding: move text down from perfect center
        // In bottom-left coordinates, reducing yOffset moves text down (toward bottom)
        // Perfect center: (rect.height - textHeight) / 2.0
        // With top padding, we want text slightly below center
        let centerOffset = (rect.height - textHeight) / 2.0
        let yOffset = centerOffset - verticalPadding // Subtract padding to move down
        // Return rect with top padding
        return NSRect(x: rect.origin.x,
                     y: rect.origin.y + yOffset,
                     width: rect.width,
                     height: textHeight)
    }
    
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        // Same calculation for displayed text with top padding
        let textHeight: CGFloat = font?.boundingRectForFont.height ?? 20.0
        let centerOffset = (rect.height - textHeight) / 2.0
        let yOffset = centerOffset - verticalPadding
        return NSRect(x: rect.origin.x,
                     y: rect.origin.y + yOffset,
                     width: rect.width,
                     height: textHeight)
    }
}
#endif

// MARK: - Protocol Conformance Extensions
#if os(iOS) || os(tvOS)
extension CharacterCreationScene: UITextFieldDelegate, UITextViewDelegate {}
#elseif os(macOS)
extension CharacterCreationScene: NSTextFieldDelegate {}
#endif
