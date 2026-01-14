//
//  StartScreenScene.swift
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

class StartScreenScene: SKScene {
    
    enum ScreenState {
        case logo
        case menu
        case characterSelection
        case saveSlotSelection
    }
    
    var currentState: ScreenState = .logo
    var hasSaveFile: Bool = false
    var selectedCharacter: GameCharacter?
    var characterToDelete: GameCharacter?  // Character pending deletion confirmation
    
    // Scrolling state
    var scrollContainer: SKNode?
    var isScrolling: Bool = false
    var lastTouchLocation: CGPoint = .zero
    var scrollMinY: CGFloat = 0
    var scrollMaxY: CGFloat = 0
    
    // Prevent touch events immediately after state transitions
    var isTransitioning: Bool = false
    
    override func didMove(to view: SKView) {
        // Update size to match view
        size = view.bounds.size
        
        // Set background color (parchment/paper texture background)
        backgroundColor = SKColor(red: 0.88, green: 0.82, blue: 0.72, alpha: 1.0)
        
        // Check for save file
        checkForSaveFile()
        
        // Show initial logo screen
        showLogoScreen()
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild UI when size changes
        switch currentState {
        case .logo:
            showLogoScreen()
        case .menu:
            showMenuScreen()
        case .characterSelection:
            showCharacterSelectionScreen()
        case .saveSlotSelection:
            if let character = selectedCharacter {
                showSaveSlotSelectionScreen(character: character)
            }
        }
    }
    
    func checkForSaveFile() {
        // Migrate old save file if it exists
        SaveManager.migrateOldSaveIfNeeded()
        hasSaveFile = SaveManager.hasAnySaves()
    }
    
    func showLogoScreen() {
        // Remove any existing nodes
        removeAllChildren()
        currentState = .logo
        
        let isLandscape = size.width > size.height
        let minDimension = min(size.width, size.height)
        
        // Calculate responsive sizes
        let logoScale: CGFloat = isLandscape ? minDimension / 800 : minDimension / 600
        let wolfSize: CGFloat = isLandscape ? min(200, minDimension * 0.25) : min(250, minDimension * 0.35)
        let titleFontSize: CGFloat = isLandscape ? min(48, size.width * 0.08) : min(64, size.height * 0.1)
        let subtitleFontSize: CGFloat = isLandscape ? min(18, size.width * 0.03) : min(24, size.height * 0.04)
        
        // Create wolf logo container
        let wolfContainer = SKNode()
        let wolfY = isLandscape ? size.height / 2 + 80 : size.height / 2 + 120
        wolfContainer.position = CGPoint(x: size.width / 2, y: wolfY)
        wolfContainer.setScale(logoScale)
        addChild(wolfContainer)
        
        // Create stylized wolf head in shield
        createWolfLogo(container: wolfContainer, size: wolfSize)
        
        // Main logo text container
        let logoContainer = SKNode()
        let logoY = isLandscape ? size.height / 2 - 40 : size.height / 2 - 20
        logoContainer.position = CGPoint(x: size.width / 2, y: logoY)
        addChild(logoContainer)
        
        // Main logo text with shadow
        let logoShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        logoShadow.text = "DOMATERRA"
        logoShadow.fontSize = titleFontSize
        logoShadow.fontColor = SKColor(white: 0.0, alpha: 0.4)
        logoShadow.position = CGPoint(x: 3, y: -3)
        logoShadow.zPosition = 1
        logoContainer.addChild(logoShadow)
        
        let logoMain = SKLabelNode(fontNamed: "Arial-BoldMT")
        logoMain.text = "DOMATERRA"
        logoMain.fontSize = titleFontSize
        logoMain.fontColor = MenuStyling.bookAccent
        logoMain.zPosition = 2
        logoContainer.addChild(logoMain)
        
        // Subtitle
        let subtitle = SKLabelNode(fontNamed: "Arial")
        subtitle.text = "A World of Adventure"
        subtitle.fontSize = subtitleFontSize
        subtitle.fontColor = MenuStyling.inkColor
        let subtitleY = isLandscape ? -titleFontSize * 0.6 : -titleFontSize * 0.7
        subtitle.position = CGPoint(x: 0, y: subtitleY)
        subtitle.zPosition = 2
        logoContainer.addChild(subtitle)
        
        // Subtle pulse animation for logo
        let pulseUp = SKAction.scale(to: 1.02, duration: 2.0)
        let pulseDown = SKAction.scale(to: 1.0, duration: 2.0)
        let pulse = SKAction.sequence([pulseUp, pulseDown])
        logoContainer.run(SKAction.repeatForever(pulse))
        
        // "Tap to continue" prompt
        let promptY = isLandscape ? size.height / 2 - size.height / 2 + 60 : 100
        let prompt = SKLabelNode(fontNamed: "Arial")
        prompt.text = "Tap to Continue"
        prompt.fontSize = isLandscape ? min(18, size.width * 0.03) : min(20, size.height * 0.03)
        prompt.fontColor = MenuStyling.inkMuted
        prompt.position = CGPoint(x: size.width / 2, y: promptY)
        prompt.zPosition = 10
        addChild(prompt)
        
        // Blink animation for prompt
        let fadeOut = SKAction.fadeAlpha(to: 0.3, duration: 1.0)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        let blink = SKAction.sequence([fadeOut, fadeIn])
        prompt.run(SKAction.repeatForever(blink))
    }
    
    func createWolfLogo(container: SKNode, size: CGFloat) {
        // Shield outline (heraldic shield shape)
        let shieldPath = CGMutablePath()
        let shieldWidth = size
        let shieldHeight = size * 1.2
        let shieldTopWidth = shieldWidth * 0.9
        let shieldTopY = shieldHeight * 0.5
        
        shieldPath.move(to: CGPoint(x: -shieldTopWidth / 2, y: shieldTopY))
        shieldPath.addLine(to: CGPoint(x: shieldTopWidth / 2, y: shieldTopY))
        shieldPath.addLine(to: CGPoint(x: shieldWidth / 2, y: shieldTopY * 0.3))
        shieldPath.addLine(to: CGPoint(x: shieldWidth / 2, y: -shieldHeight * 0.5))
        shieldPath.addLine(to: CGPoint(x: 0, y: -shieldHeight * 0.5 - shieldHeight * 0.1))
        shieldPath.addLine(to: CGPoint(x: -shieldWidth / 2, y: -shieldHeight * 0.5))
        shieldPath.addLine(to: CGPoint(x: -shieldWidth / 2, y: shieldTopY * 0.3))
        shieldPath.closeSubpath()
        
        let shield = SKShapeNode(path: shieldPath)
        shield.strokeColor = SKColor(white: 0.3, alpha: 0.8)
        shield.fillColor = SKColor.clear
        shield.lineWidth = size * 0.08
        shield.zPosition = 1
        container.addChild(shield)
        
        // Wolf head (simplified stylized version)
        let wolfContainer = SKNode()
        wolfContainer.zPosition = 2
        container.addChild(wolfContainer)
        
        // Wolf head base (main shape)
        let headPath = CGMutablePath()
        let headWidth = size * 0.7
        let headHeight = size * 0.6
        let headTopY = size * 0.2
        let headBottomY = -size * 0.15
        
        // Create angular wolf head shape
        headPath.move(to: CGPoint(x: -headWidth * 0.3, y: headTopY))
        headPath.addLine(to: CGPoint(x: headWidth * 0.3, y: headTopY))
        headPath.addLine(to: CGPoint(x: headWidth * 0.4, y: headTopY * 0.5))
        headPath.addLine(to: CGPoint(x: headWidth * 0.35, y: 0))
        headPath.addLine(to: CGPoint(x: headWidth * 0.4, y: headBottomY))
        headPath.addLine(to: CGPoint(x: 0, y: headBottomY * 1.2))
        headPath.addLine(to: CGPoint(x: -headWidth * 0.4, y: headBottomY))
        headPath.addLine(to: CGPoint(x: -headWidth * 0.35, y: 0))
        headPath.addLine(to: CGPoint(x: -headWidth * 0.4, y: headTopY * 0.5))
        headPath.closeSubpath()
        
        let wolfHead = SKShapeNode(path: headPath)
        wolfHead.fillColor = SKColor.black
        wolfHead.strokeColor = SKColor.clear
        wolfHead.zPosition = 1
        wolfContainer.addChild(wolfHead)
        
        // Left ear
        let leftEarPath = CGMutablePath()
        leftEarPath.move(to: CGPoint(x: -headWidth * 0.25, y: headTopY))
        leftEarPath.addLine(to: CGPoint(x: -headWidth * 0.15, y: headTopY * 1.3))
        leftEarPath.addLine(to: CGPoint(x: -headWidth * 0.35, y: headTopY * 1.1))
        leftEarPath.closeSubpath()
        
        let leftEar = SKShapeNode(path: leftEarPath)
        leftEar.fillColor = SKColor.black
        leftEar.strokeColor = SKColor.clear
        leftEar.zPosition = 2
        wolfContainer.addChild(leftEar)
        
        // Right ear (partially behind shield)
        let rightEarPath = CGMutablePath()
        rightEarPath.move(to: CGPoint(x: headWidth * 0.15, y: headTopY))
        rightEarPath.addLine(to: CGPoint(x: headWidth * 0.25, y: headTopY * 1.2))
        rightEarPath.addLine(to: CGPoint(x: headWidth * 0.35, y: headTopY * 1.0))
        rightEarPath.closeSubpath()
        
        let rightEar = SKShapeNode(path: rightEarPath)
        rightEar.fillColor = SKColor.black
        rightEar.strokeColor = SKColor.clear
        rightEar.zPosition = 2
        wolfContainer.addChild(rightEar)
        
        // Snout
        let snoutPath = CGMutablePath()
        snoutPath.move(to: CGPoint(x: -headWidth * 0.15, y: headBottomY * 0.5))
        snoutPath.addLine(to: CGPoint(x: headWidth * 0.15, y: headBottomY * 0.5))
        snoutPath.addLine(to: CGPoint(x: headWidth * 0.1, y: headBottomY * 1.3))
        snoutPath.addLine(to: CGPoint(x: 0, y: headBottomY * 1.4))
        snoutPath.addLine(to: CGPoint(x: -headWidth * 0.1, y: headBottomY * 1.3))
        snoutPath.closeSubpath()
        
        let snout = SKShapeNode(path: snoutPath)
        snout.fillColor = SKColor.black
        snout.strokeColor = SKColor.clear
        snout.zPosition = 2
        wolfContainer.addChild(snout)
        
        // Nose
        let nose = SKShapeNode(rectOf: CGSize(width: size * 0.08, height: size * 0.06))
        nose.fillColor = SKColor(white: 0.2, alpha: 1.0)
        nose.strokeColor = SKColor.clear
        nose.position = CGPoint(x: 0, y: headBottomY * 1.3)
        nose.zPosition = 3
        wolfContainer.addChild(nose)
        
        // Glowing blue eyes
        let eyeSize = size * 0.12
        let eyeY = size * 0.05
        let eyeSpacing = size * 0.15
        
        // Left eye glow
        let leftEyeGlow = SKShapeNode(circleOfRadius: eyeSize * 1.3)
        leftEyeGlow.fillColor = SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.6)
        leftEyeGlow.strokeColor = SKColor.clear
        leftEyeGlow.position = CGPoint(x: -eyeSpacing, y: eyeY)
        leftEyeGlow.zPosition = 3
        wolfContainer.addChild(leftEyeGlow)
        
        // Left eye
        let leftEye = SKShapeNode(circleOfRadius: eyeSize)
        leftEye.fillColor = SKColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        leftEye.strokeColor = SKColor.clear
        leftEye.position = CGPoint(x: -eyeSpacing, y: eyeY)
        leftEye.zPosition = 4
        wolfContainer.addChild(leftEye)
        
        // Right eye glow
        let rightEyeGlow = SKShapeNode(circleOfRadius: eyeSize * 1.3)
        rightEyeGlow.fillColor = SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.6)
        rightEyeGlow.strokeColor = SKColor.clear
        rightEyeGlow.position = CGPoint(x: eyeSpacing, y: eyeY)
        rightEyeGlow.zPosition = 3
        wolfContainer.addChild(rightEyeGlow)
        
        // Right eye
        let rightEye = SKShapeNode(circleOfRadius: eyeSize)
        rightEye.fillColor = SKColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        rightEye.strokeColor = SKColor.clear
        rightEye.position = CGPoint(x: eyeSpacing, y: eyeY)
        rightEye.zPosition = 4
        wolfContainer.addChild(rightEye)
        
        // White highlight lines on face (angular style)
        let highlight1 = SKShapeNode(rectOf: CGSize(width: size * 0.15, height: size * 0.02))
        highlight1.fillColor = SKColor(white: 0.9, alpha: 0.8)
        highlight1.strokeColor = SKColor.clear
        highlight1.position = CGPoint(x: -size * 0.1, y: size * 0.05)
        highlight1.zRotation = -0.3
        highlight1.zPosition = 3
        wolfContainer.addChild(highlight1)
        
        let highlight2 = SKShapeNode(rectOf: CGSize(width: size * 0.15, height: size * 0.02))
        highlight2.fillColor = SKColor(white: 0.9, alpha: 0.8)
        highlight2.strokeColor = SKColor.clear
        highlight2.position = CGPoint(x: size * 0.1, y: size * 0.05)
        highlight2.zRotation = 0.3
        highlight2.zPosition = 3
        wolfContainer.addChild(highlight2)
        
        // Stylized fur/mane on left side (breaking shield frame)
        let furPath = CGMutablePath()
        furPath.move(to: CGPoint(x: -headWidth * 0.4, y: headTopY * 0.3))
        furPath.addLine(to: CGPoint(x: -headWidth * 0.6, y: headTopY * 0.6))
        furPath.addLine(to: CGPoint(x: -headWidth * 0.5, y: headTopY * 0.8))
        furPath.addLine(to: CGPoint(x: -headWidth * 0.45, y: headTopY * 0.5))
        furPath.closeSubpath()
        
        let fur = SKShapeNode(path: furPath)
        fur.fillColor = SKColor.black
        fur.strokeColor = SKColor.clear
        fur.zPosition = 0
        wolfContainer.addChild(fur)
        
        // Subtle glow animation for eyes
        let glowUp = SKAction.fadeAlpha(to: 0.8, duration: 1.5)
        let glowDown = SKAction.fadeAlpha(to: 0.5, duration: 1.5)
        let glow = SKAction.sequence([glowUp, glowDown])
        leftEyeGlow.run(SKAction.repeatForever(glow))
        rightEyeGlow.run(SKAction.repeatForever(glow))
    }
    
    func showMenuScreen() {
        // Remove any existing nodes
        removeAllChildren()
        currentState = .menu
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 1
        addChild(panel)
        
        // Book title
        let titleY = isLandscape ? size.height / 2 + dims.panelHeight / 2 - 40 : size.height / 2 + dims.panelHeight / 2 - 50
        let title = MenuStyling.createBookTitle(text: "Main Menu", position: CGPoint(x: size.width / 2, y: titleY))
        title.zPosition = 10
        addChild(title)
        
        // Button container
        let buttonContainer = SKNode()
        buttonContainer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        buttonContainer.zPosition = 10
        addChild(buttonContainer)
        
        var buttonY: CGFloat = isLandscape ? 30 : 40
        
        // Continue button (only show if save exists)
        if hasSaveFile {
            let continueButton = MenuStyling.createBookButton(
                text: "Continue",
                size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
                color: MenuStyling.parchmentBg,
                position: CGPoint(x: 0.0, y: buttonY),
                name: "continueButton",
                fontSize: isLandscape ? 22 : 26
            )
            buttonContainer.addChild(continueButton)
            buttonY -= (dims.buttonHeight + dims.spacing)
        }
        
        // Start New Game button
        let newGameButton = MenuStyling.createBookButton(
            text: "Start New Game",
            size: CGSize(width: dims.buttonWidth, height: dims.buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: 0.0, y: buttonY),
            name: "newGameButton",
            fontSize: isLandscape ? 22 : 26
        )
        buttonContainer.addChild(newGameButton)
    }
    
    func showCharacterSelectionScreen() {
        // Remove any existing nodes
        removeAllChildren()
        currentState = .characterSelection
        
        // Reset scroll state
        scrollContainer = nil
        isScrolling = false
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 1
        panel.name = "characterSelectionPanel"
        addChild(panel)
        
        // Book title - moved down to avoid border overlap
        let titleY = isLandscape ? size.height / 2 + dims.panelHeight / 2 - 70 : size.height / 2 + dims.panelHeight / 2 - 80
        let title = MenuStyling.createBookTitle(text: "Select Character", position: CGPoint(x: size.width / 2, y: titleY), fontSize: isLandscape ? 30 : 34)
        title.zPosition = 10
        addChild(title)
        
        // Get all characters
        let characters = SaveManager.getAllCharacters()
        
        // Back button (calculate position first to determine available space)
        // Moved down to ensure it's below the border (border margin is 15px, button needs space)
        let backY = isLandscape ? size.height / 2 - dims.panelHeight / 2 + 75 : size.height / 2 - dims.panelHeight / 2 + 85
        
        // Calculate available space for characters
        // Top boundary: below title (with some spacing)
        let titleHeight: CGFloat = isLandscape ? 30 : 34
        let titleBottom = titleY - titleHeight / 2
        let topSpacing: CGFloat = isLandscape ? 20 : 25
        let containerTop = titleBottom - topSpacing
        
        // Bottom boundary: above back button (with spacing)
        let backButtonHeight = dims.buttonHeight
        let backButtonTop = backY + backButtonHeight / 2
        let bottomSpacing: CGFloat = isLandscape ? 20 : 25
        let containerBottom = backButtonTop + bottomSpacing
        
        // Available height for the container
        let availableHeight = containerTop - containerBottom
        let containerCenterY = (containerTop + containerBottom) / 2
        
        // Calculate card dimensions - ensure they fit properly in both orientations
        let deleteButtonWidth: CGFloat = isLandscape ? 50 : 55
        let deleteButtonSpacing: CGFloat = 8  // Space between card and delete button
        let maxAvailableWidth = isLandscape ? min(380, size.width * 0.75) : size.width * 0.88
        let totalCardWidth = min(dims.buttonWidth, maxAvailableWidth)
        let cardWidth = totalCardWidth - deleteButtonWidth - deleteButtonSpacing
        let cardHeight: CGFloat = isLandscape ? 70 : 80
        let cardSpacing: CGFloat = isLandscape ? 12 : 14
        
        // Create scrollable container with clipping
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 0) // Position will be set on the crop node
        container.name = "characterContainer"
        
        // Create clipping mask
        let cropNode = SKCropNode()
        let mask = SKShapeNode(rectOf: CGSize(width: totalCardWidth + 40, height: availableHeight))
        mask.fillColor = .white
        mask.strokeColor = .clear
        cropNode.maskNode = mask
        cropNode.position = CGPoint(x: size.width / 2, y: containerCenterY)
        cropNode.zPosition = 10
        cropNode.name = "characterCropNode"
        cropNode.addChild(container)
        addChild(cropNode)
        
        // Position characters starting from top of available space
        // Account for card height to ensure top card isn't cut off
        let topPadding = cardHeight / 2 + (isLandscape ? 10 : 15) // Half card height + small padding
        let startY = availableHeight / 2 - topPadding
        var charY = startY
        for character in characters {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            let subtitle = "Created: \(formatter.string(from: character.creationDate))"
            
            // Create character card container (centered)
            let charCard = SKNode()
            charCard.position = CGPoint(x: 0.0, y: charY)
            charCard.name = "characterCard_\(character.id.uuidString)"
            container.addChild(charCard)
            
            // Calculate positions relative to card center
            let charButtonX = -(deleteButtonWidth + deleteButtonSpacing) / 2
            let deleteButtonX = (cardWidth + deleteButtonSpacing) / 2
            
            // Main character button (left side, clickable)
            let charButton = MenuStyling.createBookCardButton(
                text: character.displayName,
                subtitle: subtitle,
                size: CGSize(width: cardWidth, height: cardHeight),
                position: CGPoint(x: charButtonX, y: 0.0),
                name: "character_\(character.id.uuidString)"
            )
            charCard.addChild(charButton)
            
            // Delete button (right side)
            let deleteButtonSize = CGSize(width: deleteButtonWidth, height: cardHeight - 6)
            let deleteButton = MenuStyling.createBookButton(
                text: "✕",
                size: deleteButtonSize,
                color: MenuStyling.parchmentDark,
                position: CGPoint(x: deleteButtonX, y: 0.0),
                name: "deleteCharacter_\(character.id.uuidString)",
                fontSize: isLandscape ? 22 : 24
            )
            charCard.addChild(deleteButton)
            
            charY -= (cardHeight + cardSpacing)
        }
        
        // Calculate scroll bounds
        // After loop, charY is the position where the NEXT item would be centered
        // So we need to go back one step to get the last item's center
        let lastItemCenterY: CGFloat
        if !characters.isEmpty {
            lastItemCenterY = charY + (cardHeight + cardSpacing)
        } else {
            lastItemCenterY = startY
        }
        let firstItemTop = startY + cardHeight / 2
        let lastItemBottom = lastItemCenterY - cardHeight / 2
        let contentHeight = firstItemTop - lastItemBottom
        print("📊 Scroll calculation: contentHeight=\(contentHeight), availableHeight=\(availableHeight), firstItemTop=\(firstItemTop), lastItemBottom=\(lastItemBottom)")
        if contentHeight > availableHeight {
            // Content exceeds available space, enable scrolling
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
            scrollMinY = 0 // Start position, showing top content
            scrollMaxY = scrollDownAmount // Maximum scroll down (positive Y to show bottom content)
            scrollContainer = container
            // Ensure container starts at the correct position
            container.position.y = 0
            print("✅ Scrolling enabled: scrollMinY=\(scrollMinY), scrollMaxY=\(scrollMaxY), container start Y=\(container.position.y)")
        } else {
            // Content fits, no scrolling needed
            scrollContainer = nil
            scrollMinY = 0
            scrollMaxY = 0
            print("⚠️ Scrolling disabled: content fits")
        }
        
        // Back button - ensure it's on top of everything
        let backButton = MenuStyling.createModernButton(
            text: "Back",
            size: CGSize(width: min(200, dims.buttonWidth * 0.7), height: dims.buttonHeight),
            color: MenuStyling.dangerColor,
            position: CGPoint(x: size.width / 2, y: backY),
            name: "backButton",
            fontSize: isLandscape ? 20 : 24
        )
        backButton.zPosition = 1000 // High zPosition to ensure it's on top
        addChild(backButton)
    }
    
    func showSaveSlotSelectionScreen(character: GameCharacter) {
        // Remove any existing nodes
        removeAllChildren()
        currentState = .saveSlotSelection
        selectedCharacter = character
        
        // Reset scroll state
        scrollContainer = nil
        isScrolling = false
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        
        // Book page panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: dims.panelWidth, height: dims.panelHeight))
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 1
        panel.name = "saveSlotPanel"
        addChild(panel)
        
        // Book title - moved down to avoid border overlap
        let titleY = isLandscape ? size.height / 2 + dims.panelHeight / 2 - 70 : size.height / 2 + dims.panelHeight / 2 - 80
        let title = MenuStyling.createBookTitle(text: "Select Save Slot", position: CGPoint(x: size.width / 2, y: titleY), fontSize: isLandscape ? 30 : 34)
        title.zPosition = 10
        addChild(title)
        
        // Character name
        let charNameY = isLandscape ? titleY - 45 : titleY - 50
        let charName = SKLabelNode(fontNamed: "Arial")
        charName.text = character.displayName
        charName.fontSize = isLandscape ? 20 : 24
        charName.fontColor = MenuStyling.inkMuted
        charName.position = CGPoint(x: size.width / 2, y: charNameY)
        charName.zPosition = 10
        addChild(charName)
        
        // Get all save slots for this character
        let saveSlots = SaveManager.getAllSaveSlots(characterId: character.id)
        
        // Back button (calculate position first to determine available space)
        // Moved down to ensure it's below the border (border margin is 15px, button needs space)
        let backY = isLandscape ? size.height / 2 - dims.panelHeight / 2 + 75 : size.height / 2 - dims.panelHeight / 2 + 85
        
        // Calculate available space for save slots
        // Top boundary: below character name (with some spacing)
        let charNameHeight: CGFloat = isLandscape ? 20 : 24
        let charNameBottom = charNameY - charNameHeight / 2
        let topSpacing: CGFloat = isLandscape ? 20 : 25
        let containerTop = charNameBottom - topSpacing
        
        // Bottom boundary: above back button (with spacing)
        let backButtonHeight = dims.buttonHeight
        let backButtonTop = backY + backButtonHeight / 2
        let bottomSpacing: CGFloat = isLandscape ? 20 : 25
        let containerBottom = backButtonTop + bottomSpacing
        
        // Available height for the container
        let availableHeight = containerTop - containerBottom
        let containerCenterY = (containerTop + containerBottom) / 2
        
        // Card dimensions
        let cardWidth = min(dims.buttonWidth, isLandscape ? 400 : size.width * 0.8)
        let cardHeight: CGFloat = isLandscape ? 70 : 85
        let cardSpacing: CGFloat = isLandscape ? 12 : 15
        
        // Create scrollable container with clipping
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 0) // Position will be set on the crop node
        container.name = "saveSlotContainer"
        
        // Create clipping mask
        let cropNode = SKCropNode()
        let mask = SKShapeNode(rectOf: CGSize(width: cardWidth + 40, height: availableHeight))
        mask.fillColor = .white
        mask.strokeColor = .clear
        cropNode.maskNode = mask
        cropNode.position = CGPoint(x: size.width / 2, y: containerCenterY)
        cropNode.zPosition = 10
        cropNode.name = "saveSlotCropNode"
        cropNode.addChild(container)
        addChild(cropNode)
        
        // Position slots starting from top of available space
        // Account for card height to ensure top card isn't cut off
        let topPadding = cardHeight / 2 + (isLandscape ? 10 : 15) // Half card height + small padding
        let startY = availableHeight / 2 - topPadding
        var slotY = startY
        for slot in saveSlots {
            let slotButton = MenuStyling.createBookCardButton(
                text: slot.displayName,
                subtitle: nil,
                size: CGSize(width: cardWidth, height: cardHeight),
                position: CGPoint(x: 0.0, y: slotY),
                name: "saveSlot_\(slot.slotNumber)",
                isEmpty: slot.isEmpty
            )
            container.addChild(slotButton)
            slotY -= (cardHeight + cardSpacing)
        }
        
        // Calculate scroll bounds
        // After loop, slotY is the center position for the next item
        // Last item center is at slotY + (cardHeight + cardSpacing)
        // Content height: from first item top to last item bottom
        let lastItemCenterY = slotY + (cardHeight + cardSpacing)
        let firstItemTop = startY + cardHeight / 2
        let lastItemBottom = lastItemCenterY - cardHeight / 2
        let contentHeight = firstItemTop - lastItemBottom
        if contentHeight > availableHeight {
            // Content exceeds available space, enable scrolling
            // The container starts at position 0 relative to the crop node
            // The visible area extends from -availableHeight/2 to +availableHeight/2 relative to crop node center
            // When container is at 0, lastItemBottom is relative to container center (negative, below center)
            // In SpriteKit, moving container UP (positive Y) makes content appear to move DOWN on screen
            // To show the bottom content, we need to move container UP so lastItemBottom aligns with -availableHeight/2
            // When container is at position Y: lastItemBottom + Y = -availableHeight/2
            // So: Y = -availableHeight/2 - lastItemBottom
            // This gives us a positive Y (container moves up to show bottom content)
            let scrollDownAmount = -availableHeight / 2 - lastItemBottom
            scrollMinY = 0 // Start position, showing top content
            scrollMaxY = scrollDownAmount // Maximum scroll down (positive Y to show bottom content)
            scrollContainer = container
            // Ensure container starts at the correct position
            container.position.y = 0
        } else {
            // Content fits, no scrolling needed
            scrollContainer = nil
            scrollMinY = 0
            scrollMaxY = 0
        }
        
        // Back button - ensure it's on top of everything
        let backButton = MenuStyling.createBookButton(
            text: "Back",
            size: CGSize(width: min(200, dims.buttonWidth * 0.7), height: dims.buttonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2, y: backY),
            name: "backButton",
            fontSize: isLandscape ? 20 : 24
        )
        backButton.zPosition = 1000 // High zPosition to ensure it's on top
        addChild(backButton)
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
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Ignore touches during transitions
        if isTransitioning {
            return
        }
        
        // Check if we're in a scrollable area
        if scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) {
            // Check if touch is in the crop node area or on any scrollable content
            if let cropNode = childNode(withName: currentState == .characterSelection ? "characterCropNode" : "saveSlotCropNode") {
                // Convert location to crop node's coordinate space for accurate bounds checking
                let locationInCropNode = convert(location, to: cropNode)
                
                // Check if touch is within crop node bounds
                if cropNode.contains(location) || cropNode.frame.contains(locationInCropNode) {
                    // Initialize scroll state
                    isScrolling = false
                    lastTouchLocation = location
                    return // Don't handle as button click yet
                }
                // Also check if touch is on any node that's a descendant of the scroll container
                // Check all nodes at this location to find if any are descendants of scrollContainer
                let nodesAtLocation = nodes(at: location)
                for node in nodesAtLocation {
                    var currentNode: SKNode? = node
                    while let current = currentNode {
                        if current == scrollContainer || current.parent == scrollContainer {
                            // Touch is on scrollable content
                            isScrolling = false
                            lastTouchLocation = location
                            return // Don't handle as button click yet
                        }
                        currentNode = current.parent
                    }
                }
            }
        }
        
        handleTouch(location: location)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        guard scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) else { return }
        
        // Only process if we have a valid lastTouchLocation (from touchesBegan in scrollable area)
        guard lastTouchLocation != .zero else { return }
        
        let location = touch.location(in: self)
        let deltaY = location.y - lastTouchLocation.y
        
        // If movement is significant, start scrolling
        if abs(deltaY) > 5 {
            isScrolling = true
            
            // Update container position
            // Dragging down (positive deltaY) should scroll down (show content below) = container moves down (toward scrollMinY, negative Y)
            // Dragging up (negative deltaY) should scroll up (show content above) = container moves up (toward 0, positive Y)
            let currentY = scrollContainer!.position.y
            let proposedY = currentY - deltaY
            let clampedY = min(scrollMaxY, proposedY)
            let newY = max(scrollMinY, clampedY)
            print("📜 touchesMoved: currentY=\(currentY), deltaY=\(deltaY), proposedY=\(proposedY), clampedY=\(clampedY), newY=\(newY), bounds=[\(scrollMinY), \(scrollMaxY)]")
            scrollContainer!.position.y = newY
        }
        
        lastTouchLocation = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) else {
            // Not in scrollable area, handle normally
            return
        }
        
        // Ignore touches during transitions
        if isTransitioning {
            return
        }
        
        // If we were scrolling, don't trigger button clicks
        if isScrolling {
            isScrolling = false
            return
        }
        
        // Otherwise, handle as a tap
        if let touch = touches.first {
            let location = touch.location(in: self)
            handleTouch(location: location)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isScrolling = false
        lastTouchLocation = .zero
    }
    #endif
    
    #if os(macOS)
    var mouseDownLocation: CGPoint = .zero
    
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        mouseDownLocation = location
        print("🟢 StartScreenScene: mouseDown at (\(Int(location.x)), \(Int(location.y))), currentState: \(currentState)")
        
        // Ignore clicks during transitions
        if isTransitioning {
            mouseDownLocation = .zero
            return
        }
        
        // Always initialize scroll state if we're in a scrollable area
        if scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) {
            // Check if click is in the crop node area or on any scrollable content
            if let cropNode = childNode(withName: currentState == .characterSelection ? "characterCropNode" : "saveSlotCropNode") {
                // Convert location to crop node's coordinate space for accurate bounds checking
                let locationInCropNode = convert(location, to: cropNode)
                
                // Check if click is within crop node bounds
                if cropNode.contains(location) || cropNode.frame.contains(locationInCropNode) {
                    // Initialize scroll state - track this as a potential scroll
                    isScrolling = false
                    lastTouchLocation = location
                    print("✅ mouseDown: Set lastTouchLocation=\(location) (cropNode)")
                    return // Don't handle as button click yet - wait for mouseUp/mouseDragged
                }
                // Also check if click is on any node that's a descendant of the scroll container
                // Check all nodes at this location to find if any are descendants of scrollContainer
                let nodesAtLocation = nodes(at: location)
                for node in nodesAtLocation {
                    var currentNode: SKNode? = node
                    while let current = currentNode {
                        if current == scrollContainer || current.parent == scrollContainer {
                            // Click is on scrollable content
                            isScrolling = false
                            lastTouchLocation = location
                            print("✅ mouseDown: Set lastTouchLocation=\(location) (scrollContainer descendant)")
                            return // Don't handle as button click yet - wait for mouseUp/mouseDragged
                        }
                        currentNode = current.parent
                    }
                }
                print("❌ mouseDown: Click not in scrollable area (checked \(nodesAtLocation.count) nodes at \(location))")
            }
        }
        
        // Not in scrollable area, handle as click immediately
        handleTouch(location: location)
    }
    
    override func mouseDragged(with event: NSEvent) {
        print("🖱️ mouseDragged called")
        guard scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) else {
            print("❌ mouseDragged: scrollContainer=nil or wrong state")
            return
        }
        
        let location = event.location(in: self)
        
        // Only process if we have a valid lastTouchLocation (from mouseDown in scrollable area)
        guard lastTouchLocation != .zero else {
            print("❌ mouseDragged: lastTouchLocation is zero")
            return
        }
        
        let deltaY = location.y - lastTouchLocation.y
        print("🖱️ mouseDragged: deltaY=\(deltaY), location=\(location), lastTouchLocation=\(lastTouchLocation)")
        
        // If movement is significant, start scrolling
        if abs(deltaY) > 5 {
            isScrolling = true
            
            // Update container position
            // Dragging down (positive deltaY) should scroll down (show content below) = container moves down (toward scrollMinY, negative Y)
            // Dragging up (negative deltaY) should scroll up (show content above) = container moves up (toward 0, positive Y)
            let currentY = scrollContainer!.position.y
            let proposedY = currentY - deltaY
            let clampedY = min(scrollMaxY, proposedY)
            let newY = max(scrollMinY, clampedY)
            print("📜 mouseDragged: currentY=\(currentY), deltaY=\(deltaY), proposedY=\(proposedY), clampedY=\(clampedY), newY=\(newY), bounds=[\(scrollMinY), \(scrollMaxY)]")
            scrollContainer!.position.y = newY
            
            lastTouchLocation = location
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = event.location(in: self)
        
        // Ignore clicks during transitions
        if isTransitioning {
            mouseDownLocation = .zero
            return
        }
        
        // If we were scrolling, don't trigger button clicks
        if isScrolling {
            isScrolling = false
            lastTouchLocation = .zero
            return
        }
        
        // Reset scroll tracking
        lastTouchLocation = .zero
        
        // If we initialized scroll tracking (clicked in scrollable area), handle as click
        if mouseDownLocation != .zero {
            handleTouch(location: location)
            mouseDownLocation = .zero
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        print("🖱️ scrollWheel called: scrollingDeltaY=\(event.scrollingDeltaY), hasPreciseScrollingDeltas=\(event.hasPreciseScrollingDeltas)")
        guard scrollContainer != nil && (currentState == .characterSelection || currentState == .saveSlotSelection) else {
            print("❌ scrollWheel: scrollContainer=nil or wrong state")
            return
        }
        
        // Handle trackpad/mouse wheel scrolling
        // event.scrollingDeltaY is positive when scrolling up, negative when scrolling down
        // Scrolling up should show content above (container moves up/positive Y)
        // Scrolling down should show content below (container moves down/negative Y)
        // Use precise scrolling deltas if available (trackpad), otherwise use regular deltas (mouse wheel)
        let deltaY: CGFloat
        if event.hasPreciseScrollingDeltas {
            // Trackpad: deltas are already smooth, use a moderate scale
            deltaY = event.scrollingDeltaY * 1.0
        } else {
            // Mouse wheel: deltas are larger, use a smaller scale
            deltaY = event.scrollingDeltaY * 2.0
        }
        
        // Update container position
        // Scrolling up (positive scrollingDeltaY) should show content above (container moves up toward 0, positive Y)
        // Scrolling down (negative scrollingDeltaY) should show content below (container moves down toward scrollMinY, negative Y)
        // Invert deltaY: positive scrollingDeltaY (scroll up) moves container up (positive Y), negative scrollingDeltaY (scroll down) moves container down (negative Y)
        let currentY = scrollContainer!.position.y
        let proposedY = currentY - deltaY
        let clampedY = min(scrollMaxY, proposedY)
        let newY = max(scrollMinY, clampedY)
        print("📜 scrollWheel: currentY=\(currentY), deltaY=\(deltaY), proposedY=\(proposedY), clampedY=\(clampedY), newY=\(newY), bounds=[\(scrollMinY), \(scrollMaxY)]")
        scrollContainer!.position.y = newY
    }
    #endif
    
    func handleTouch(location: CGPoint) {
        print("🟢 StartScreenScene: handleTouch called, currentState: \(currentState)")
        
        // Ignore touches during transitions
        if isTransitioning {
            return
        }
        
        switch currentState {
        case .logo:
            // Transition to menu
            print("  → Transitioning from logo to menu")
            isTransitioning = true
            showMenuScreen()
            // Clear the transitioning flag after a brief delay to prevent click-through
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.2),
                SKAction.run { [weak self] in
                    self?.isTransitioning = false
                }
            ]))
            
        case .menu:
            // Check which button was tapped
            let node = atPoint(location)
            print("  → Menu state: clicked node: \(node.name ?? "nil")")
            var buttonNode: SKNode? = nil
            
            // Check for back button (traverse up parent chain)
            if let backButton = findNodeWithName("backButton", startingFrom: node) {
                buttonNode = backButton
                print("  → Found backButton")
                animateButtonPress(buttonNode!) {
                    self.showMenuScreen()
                }
                return
            }
            
            // Check for main menu buttons (traverse up parent chain)
            if let continueButton = findNodeWithName("continueButton", startingFrom: node) {
                buttonNode = continueButton
                print("  → Found continueButton")
                // Animate button press
                animateButtonPress(buttonNode!) {
                    self.showCharacterSelectionScreen()
                }
            } else if let newGameButton = findNodeWithName("newGameButton", startingFrom: node) {
                buttonNode = newGameButton
                print("  → Found newGameButton - calling startNewGame()")
                // Animate button press
                animateButtonPress(buttonNode!) {
                    self.startNewGame()
                }
            } else {
                print("  → No button found at click location")
            }
            
        case .characterSelection:
            // Check if confirmation dialog is showing first
            handleCharacterSelectionTouch(location: location)
            
        case .saveSlotSelection:
            handleSaveSlotSelectionTouch(location: location)
        }
    }
    
    func handleCharacterSelectionTouch(location: CGPoint) {
        let node = atPoint(location)
        
        // Check for delete button first (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("deleteCharacter_") {
                let characterIdString = nodeName.replacingOccurrences(of: "deleteCharacter_", with: "")
                if let characterId = UUID(uuidString: characterIdString),
                   let character = SaveManager.getAllCharacters().first(where: { $0.id == characterId }) {
                    animateButtonPress(current) {
                        self.showDeleteConfirmation(character: character)
                    }
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for character button (traverse up parent chain)
        currentNode = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("character_") {
                let characterIdString = nodeName.replacingOccurrences(of: "character_", with: "")
                if let characterId = UUID(uuidString: characterIdString),
                   let character = SaveManager.getAllCharacters().first(where: { $0.id == characterId }) {
                    animateButtonPress(current) {
                        self.showSaveSlotSelectionScreen(character: character)
                    }
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showMenuScreen()
            }
        }
        
        // Check for confirmation dialog buttons
        if let confirmButton = findNodeWithName("confirmDeleteButton", startingFrom: node) {
            animateButtonPress(confirmButton) {
                self.confirmDeleteCharacter()
            }
        } else if let cancelButton = findNodeWithName("cancelDeleteButton", startingFrom: node) {
            animateButtonPress(cancelButton) {
                self.cancelDeleteCharacter()
            }
        }
    }
    
    func handleSaveSlotSelectionTouch(location: CGPoint) {
        guard let character = selectedCharacter else { return }
        let node = atPoint(location)
        
        // Check for save slot buttons (traverse up parent chain)
        var currentNode: SKNode? = node
        while let current = currentNode {
            if let nodeName = current.name, nodeName.hasPrefix("saveSlot_") {
                let slotNumber = Int(nodeName.replacingOccurrences(of: "saveSlot_", with: "")) ?? 0
                if slotNumber > 0 {
                    let slot = SaveManager.getSaveSlotInfo(characterId: character.id, slot: slotNumber)
                    if let slot = slot, !slot.isEmpty {
                        animateButtonPress(current) {
                            self.loadGame(characterId: character.id, fromSlot: slotNumber)
                        }
                    }
                }
                return
            }
            currentNode = current.parent
        }
        
        // Check for back button (traverse up parent chain)
        if let backButton = findNodeWithName("backButton", startingFrom: node) {
            animateButtonPress(backButton) {
                self.showCharacterSelectionScreen()
            }
        }
    }
    
    func loadGame(characterId: UUID, fromSlot slot: Int) {
        guard let skView = self.view else { return }
        guard let loadedState = SaveManager.loadGame(characterId: characterId, fromSlot: slot) else {
            print("Failed to load game from character \(characterId) slot \(slot)")
            return
        }
        
        print("Game loaded successfully from character \(characterId) slot \(slot)")
        
        // Create game scene
        let gameScene = GameScene.newGameScene()
        
        // Set the scene size to match the view bounds
        gameScene.size = skView.bounds.size
        
        // Set up camera first (needed before restoring state)
        gameScene.cameraNode = SKCameraNode()
        gameScene.camera = gameScene.cameraNode
        gameScene.addChild(gameScene.cameraNode!)
        
        // Create combat UI
        gameScene.combatUI = CombatUI(scene: gameScene)
        
        // Set the loaded game state
        gameScene.gameState = loadedState
        
        // Set the character ID
        gameScene.currentCharacterId = characterId
        
        // Restore the game from loaded state
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
    }
    
    // Legacy method for backward compatibility
    func loadGame(fromSlot slot: Int) {
        guard let skView = self.view else { return }
        guard let loadedState = SaveManager.loadGame(fromSlot: slot) else {
            print("Failed to load game from slot \(slot)")
            return
        }
        
        print("Game loaded successfully from slot \(slot)")
        
        // Create game scene
        let gameScene = GameScene.newGameScene()
        
        // Set the scene size to match the view bounds
        gameScene.size = skView.bounds.size
        
        // Set up camera first (needed before restoring state)
        gameScene.cameraNode = SKCameraNode()
        gameScene.camera = gameScene.cameraNode
        gameScene.addChild(gameScene.cameraNode!)
        
        // Create combat UI
        gameScene.combatUI = CombatUI(scene: gameScene)
        
        // Set the loaded game state
        gameScene.gameState = loadedState
        
        // Restore the game from loaded state
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
    }
    
    func startNewGame() {
        guard let skView = self.view else { 
            print("❌ StartScreenScene: startNewGame() - No view available")
            return 
        }
        
        print("🟢 StartScreenScene: startNewGame() - Transitioning to CharacterCreationScene")
        print("  → Current scene size: \(size)")
        print("  → View bounds: \(skView.bounds)")
        
        // Transition to character creation scene
        let creationScene = CharacterCreationScene(size: size)
        creationScene.scaleMode = .aspectFill
        print("  → Created CharacterCreationScene with size: \(creationScene.size)")
        skView.presentScene(creationScene, transition: SKTransition.fade(withDuration: 0.5))
        
        print("✅ StartScreenScene: CharacterCreationScene presented")
    }
    
    func animateButtonPress(_ button: SKNode, completion: @escaping () -> Void) {
        let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        
        button.run(sequence) {
            completion()
        }
    }
    
    func showDeleteConfirmation(character: GameCharacter) {
        characterToDelete = character
        
        // Create overlay panel
        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = SKColor(white: 0.0, alpha: 0.7)
        overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 100
        overlay.name = "deleteConfirmationOverlay"
        addChild(overlay)
        
        let dims = MenuStyling.getResponsiveDimensions(size: size)
        let isLandscape = size.width > size.height
        let panelWidth: CGFloat = isLandscape ? 400 : size.width * 0.8
        // Increased height to provide proper spacing between text and buttons
        let panelHeight: CGFloat = isLandscape ? 280 : 320
        
        // Confirmation panel
        let panel = MenuStyling.createBookPage(size: CGSize(width: panelWidth, height: panelHeight))
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 101
        panel.name = "deleteConfirmationPanel"
        addChild(panel)
        
        // Warning text
        let warningText = SKLabelNode(fontNamed: "Arial-BoldMT")
        warningText.text = "Delete Character?"
        warningText.fontSize = isLandscape ? 28 : 32
        warningText.fontColor = MenuStyling.bookDanger
        warningText.position = CGPoint(x: size.width / 2, y: size.height / 2 + (isLandscape ? 50 : 70))
        warningText.zPosition = 102
        warningText.horizontalAlignmentMode = .center
        addChild(warningText)
        
        // Character name
        let charName = SKLabelNode(fontNamed: "Arial")
        charName.text = character.displayName
        charName.fontSize = isLandscape ? 22 : 26
        charName.fontColor = MenuStyling.inkColor
        charName.position = CGPoint(x: size.width / 2, y: size.height / 2 + (isLandscape ? 10 : 20))
        charName.zPosition = 102
        charName.horizontalAlignmentMode = .center
        addChild(charName)
        
        // Warning message
        let message = SKLabelNode(fontNamed: "Arial")
        message.text = "This will permanently delete the character"
        message.fontSize = isLandscape ? 18 : 20
        message.fontColor = MenuStyling.inkMuted
        // Adjusted to keep messages grouped together
        message.position = CGPoint(x: size.width / 2, y: size.height / 2 - (isLandscape ? 10 : 15))
        message.zPosition = 102
        message.horizontalAlignmentMode = .center
        addChild(message)
        
        let message2 = SKLabelNode(fontNamed: "Arial")
        message2.text = "and all associated save files."
        message2.fontSize = isLandscape ? 18 : 20
        message2.fontColor = MenuStyling.inkMuted
        // Positioned higher to ensure spacing above buttons
        message2.position = CGPoint(x: size.width / 2, y: size.height / 2 - (isLandscape ? 30 : 40))
        message2.zPosition = 102
        message2.horizontalAlignmentMode = .center
        addChild(message2)
        
        // Buttons - positioned to fit within panel with proper spacing from border
        // Panel has 15px border margin, so buttons need to be at least that far from edges
        let buttonWidth: CGFloat = isLandscape ? 140 : 150
        let buttonHeight: CGFloat = isLandscape ? 50 : 55
        let buttonSpacing: CGFloat = isLandscape ? 20 : 25
        
        // Calculate button Y position: panel bottom + border margin + button half height + padding
        // Panel bottom is at: size.height / 2 - panelHeight / 2
        // Border is at: panel bottom + 15px
        // Button center should be: border + button half height + padding (at least 10px)
        let panelBottom = size.height / 2 - panelHeight / 2
        let borderY = panelBottom + 15
        let buttonY = borderY + buttonHeight / 2 + 15 // 15px padding above border
        
        // Cancel button
        let cancelButton = MenuStyling.createBookButton(
            text: "Cancel",
            size: CGSize(width: buttonWidth, height: buttonHeight),
            color: MenuStyling.parchmentBg,
            position: CGPoint(x: size.width / 2 - buttonWidth / 2 - buttonSpacing / 2, y: buttonY),
            name: "cancelDeleteButton",
            fontSize: isLandscape ? 20 : 24
        )
        cancelButton.zPosition = 102
        addChild(cancelButton)
        
        // Confirm button
        let confirmButton = MenuStyling.createBookButton(
            text: "Delete",
            size: CGSize(width: buttonWidth, height: buttonHeight),
            color: MenuStyling.parchmentDark,
            position: CGPoint(x: size.width / 2 + buttonWidth / 2 + buttonSpacing / 2, y: buttonY),
            name: "confirmDeleteButton",
            fontSize: isLandscape ? 20 : 24
        )
        confirmButton.zPosition = 102
        addChild(confirmButton)
    }
    
    func confirmDeleteCharacter() {
        guard let character = characterToDelete else { return }
        
        // Delete the character and all save files
        let success = SaveManager.deleteCharacter(character.id)
        
        if success {
            // Remove confirmation dialog
            removeConfirmationDialog()
            
            // Refresh character selection screen
            showCharacterSelectionScreen()
            
            // If no characters left, go back to menu
            if SaveManager.getAllCharacters().isEmpty {
                showMenuScreen()
            }
        } else {
            // Show error message (could enhance this later)
            print("Failed to delete character")
            removeConfirmationDialog()
        }
        
        characterToDelete = nil
    }
    
    func cancelDeleteCharacter() {
        removeConfirmationDialog()
        characterToDelete = nil
    }
    
    func removeConfirmationDialog() {
        // Remove overlay and panel
        childNode(withName: "deleteConfirmationOverlay")?.removeFromParent()
        childNode(withName: "deleteConfirmationPanel")?.removeFromParent()
        // Remove all text labels (they don't have names, so remove by type and position)
        children.forEach { child in
            if let label = child as? SKLabelNode,
               label.position.y > size.height / 2 - 100 && label.position.y < size.height / 2 + 150,
               child.name == nil || child.name?.hasPrefix("deleteConfirmation") == true {
                child.removeFromParent()
            }
        }
        // Remove buttons
        childNode(withName: "confirmDeleteButton")?.removeFromParent()
        childNode(withName: "cancelDeleteButton")?.removeFromParent()
    }
}

