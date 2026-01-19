//
//  MenuStyling.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/8/26.
//

import SpriteKit

class MenuStyling {
    
    // Modern color palette
    static let primaryColor = SKColor(red: 0.15, green: 0.25, blue: 0.35, alpha: 1.0) // Deep blue-gray
    static let secondaryColor = SKColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1.0) // Emerald green
    static let accentColor = SKColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0) // Bright blue
    static let dangerColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0) // Red
    static let darkBg = SKColor(red: 0.08, green: 0.1, blue: 0.12, alpha: 0.98) // Very dark blue-gray
    static let panelBg = SKColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 0.98) // Dark panel
    static let lightText = SKColor(white: 0.95, alpha: 1.0)
    static let mutedText = SKColor(white: 0.7, alpha: 1.0)
    
    // Book/Scroll color palette
    static let parchmentBg = SKColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1.0) // Parchment background
    static let parchmentDark = SKColor(red: 0.85, green: 0.80, blue: 0.70, alpha: 1.0) // Darker parchment
    static let parchmentBorder = SKColor(red: 0.65, green: 0.55, blue: 0.40, alpha: 1.0) // Brown border
    static let inkColor = SKColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0) // Dark ink
    static let inkMuted = SKColor(red: 0.35, green: 0.28, blue: 0.22, alpha: 1.0) // Muted ink
    static let bookAccent = SKColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0) // Brown accent
    static let bookDanger = SKColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1.0) // Red for danger
    static let bookSecondary = SKColor(red: 0.3, green: 0.5, blue: 0.3, alpha: 1.0) // Green for actions
    
    // Create a modern panel with shadow and gradient effect
    static func createModernPanel(size: CGSize, cornerRadius: CGFloat = 20) -> SKNode {
        let container = SKNode()
        
        // Shadow layer
        let shadow = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.5)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -4)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main panel
        let panel = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        panel.fillColor = panelBg
        panel.strokeColor = SKColor(white: 0.3, alpha: 0.6)
        panel.lineWidth = 2
        panel.zPosition = 1
        container.addChild(panel)
        
        return container
    }
    
    // Create a modern button with hover effect
    static func createModernButton(
        text: String,
        size: CGSize,
        color: SKColor,
        position: CGPoint,
        name: String,
        fontSize: CGFloat = 24
    ) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = name
        
        // Shadow
        let shadow = SKShapeNode(rectOf: size, cornerRadius: 12)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.4)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main button
        let button = SKShapeNode(rectOf: size, cornerRadius: 12)
        button.fillColor = color
        button.strokeColor = SKColor(white: 1.0, alpha: 0.3)
        button.lineWidth = 2
        button.zPosition = 1
        container.addChild(button)
        
        // Top highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.3), cornerRadius: 12)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.25)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: 0, y: size.height * 0.15)
        highlight.zPosition = 2
        button.addChild(highlight)
        
        // Label with shadow
        let labelShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        labelShadow.text = text
        labelShadow.fontSize = fontSize
        labelShadow.fontColor = SKColor(white: 0.0, alpha: 0.5)
        labelShadow.position = CGPoint(x: 1, y: -1)
        labelShadow.verticalAlignmentMode = .center
        labelShadow.zPosition = 1
        labelShadow.isUserInteractionEnabled = false
        button.addChild(labelShadow)
        
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = lightText
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        label.isUserInteractionEnabled = false
        button.addChild(label)
        
        return container
    }
    
    // Create a modern title
    static func createModernTitle(text: String, position: CGPoint, fontSize: CGFloat = 36) -> SKNode {
        let container = SKNode()
        container.position = position
        
        // Text shadow
        let shadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = SKColor(white: 0.0, alpha: 0.5)
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main text
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = text
        title.fontSize = fontSize
        title.fontColor = secondaryColor
        title.zPosition = 1
        container.addChild(title)
        
        return container
    }
    
    // Get responsive dimensions based on orientation
    static func getResponsiveDimensions(size: CGSize) -> (panelWidth: CGFloat, panelHeight: CGFloat, buttonWidth: CGFloat, buttonHeight: CGFloat, spacing: CGFloat) {
        let isLandscape = size.width > size.height
        let minDimension = min(size.width, size.height)
        
        if isLandscape {
            return (
                panelWidth: size.width * 0.85,
                panelHeight: size.height * 0.9,
                buttonWidth: min(350.0, size.width * 0.4),
                buttonHeight: 65.0,
                spacing: 15.0
            )
        } else {
            return (
                panelWidth: size.width * 0.9,
                panelHeight: size.height * 0.85,
                buttonWidth: min(320.0, size.width * 0.85),
                buttonHeight: 70.0,
                spacing: 20.0
            )
        }
    }
    
    // Helper function to truncate text if it's too wide
    static func truncateText(text: String, fontName: String, fontSize: CGFloat, maxWidth: CGFloat) -> String {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        
        // Check if text fits
        if label.frame.width <= maxWidth {
            return text
        }
        
        // Binary search for the maximum text that fits
        var low = 0
        var high = text.count
        var bestFit = ""
        
        while low <= high {
            let mid = (low + high) / 2
            let truncated = String(text.prefix(mid)) + "..."
            label.text = truncated
            
            if label.frame.width <= maxWidth {
                bestFit = truncated
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        return bestFit.isEmpty ? "..." : bestFit
    }
    
    // Create a card-style button (for character/save slot selection)
    static func createCardButton(
        text: String,
        subtitle: String? = nil,
        size: CGSize,
        position: CGPoint,
        name: String,
        isSelected: Bool = false,
        isEmpty: Bool = false
    ) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = name
        
        // Shadow
        let shadow = SKShapeNode(rectOf: size, cornerRadius: 16)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -3)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main card
        let card = SKShapeNode(rectOf: size, cornerRadius: 16)
        if isEmpty {
            card.fillColor = SKColor(white: 0.15, alpha: 0.8)
        } else if isSelected {
            card.fillColor = secondaryColor
        } else {
            card.fillColor = accentColor
        }
        card.strokeColor = isSelected ? SKColor(white: 1.0, alpha: 0.8) : SKColor(white: 1.0, alpha: 0.4)
        card.lineWidth = isSelected ? 3 : 2
        card.zPosition = 1
        container.addChild(card)
        
        // Gradient overlay
        let gradient = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.4), cornerRadius: 16)
        gradient.fillColor = SKColor(white: 1.0, alpha: isEmpty ? 0.05 : 0.15)
        gradient.strokeColor = .clear
        gradient.position = CGPoint(x: 0, y: size.height * 0.2)
        gradient.zPosition = 2
        card.addChild(gradient)
        
        // Main label
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        let fontSize: CGFloat = isEmpty ? 20 : 26
        label.fontSize = fontSize
        label.fontColor = isEmpty ? mutedText : lightText
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: subtitle != nil ? 12 : 0)
        label.zPosition = 3
        label.isUserInteractionEnabled = false
        
        // Truncate text if it's too wide for the container
        // Leave 20 points padding on each side (40 total)
        let maxWidth = size.width - 40
        label.text = truncateText(text: text, fontName: "Arial-BoldMT", fontSize: fontSize, maxWidth: maxWidth)
        
        card.addChild(label)
        
        // Subtitle
        if let subtitle = subtitle {
            let subtitleLabel = SKLabelNode(fontNamed: "Arial")
            let subtitleFontSize: CGFloat = 16
            subtitleLabel.fontSize = subtitleFontSize
            subtitleLabel.fontColor = isEmpty ? SKColor(white: 0.5, alpha: 1.0) : SKColor(white: 0.85, alpha: 1.0)
            subtitleLabel.verticalAlignmentMode = .center
            subtitleLabel.horizontalAlignmentMode = .center
            subtitleLabel.position = CGPoint(x: 0, y: -18)
            subtitleLabel.zPosition = 3
            subtitleLabel.isUserInteractionEnabled = false
            
            // Truncate subtitle if it's too wide
            let maxSubtitleWidth = size.width - 40
            subtitleLabel.text = truncateText(text: subtitle, fontName: "Arial", fontSize: subtitleFontSize, maxWidth: maxSubtitleWidth)
            
            card.addChild(subtitleLabel)
        }
        
        return container
    }
    
    // Create a book page panel with decorative border
    static func createBookPage(size: CGSize, cornerRadius: CGFloat = 8) -> SKNode {
        let container = SKNode()
        
        // Shadow for depth
        let shadow = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 6, y: -6)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main parchment background
        let page = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        page.fillColor = parchmentBg
        page.strokeColor = .clear
        page.lineWidth = 0
        page.zPosition = 1
        container.addChild(page)
        
        // Add some texture variation (subtle noise effect using overlapping shapes)
        let texture1 = SKShapeNode(rectOf: CGSize(width: size.width * 0.3, height: size.height))
        texture1.fillColor = SKColor(white: 1.0, alpha: 0.03)
        texture1.strokeColor = .clear
        texture1.position = CGPoint(x: -size.width * 0.2, y: 0)
        texture1.zPosition = 2
        page.addChild(texture1)
        
        // Create a gradient effect on the right side instead of a solid bar
        // Use multiple overlapping rectangles with decreasing opacity to create a smooth gradient
        let gradientWidth: CGFloat = size.width * 0.25
        let gradientCenterX: CGFloat = size.width * 0.15
        let gradientSteps: Int = 12 // Number of gradient segments for smooth transition
        let stepWidth = gradientWidth / CGFloat(gradientSteps)
        let maxAlpha: CGFloat = 0.02 // Maximum opacity at the center
        
        for i in 0..<gradientSteps {
            // Create a smooth fade from center to edges using a bell curve-like distribution
            let normalizedPosition = (CGFloat(i) - CGFloat(gradientSteps) / 2.0) / (CGFloat(gradientSteps) / 2.0)
            // Use a smooth curve (cosine-based) for natural gradient falloff
            let stepAlpha = maxAlpha * (1.0 - abs(normalizedPosition))
            
            if stepAlpha > 0.001 { // Only create visible segments
                let gradientSegment = SKShapeNode(rectOf: CGSize(width: stepWidth, height: size.height))
                gradientSegment.fillColor = SKColor(white: 0.0, alpha: stepAlpha)
                gradientSegment.strokeColor = .clear
                // Position each segment to create a gradient centered at gradientCenterX
                let segmentX = gradientCenterX + (CGFloat(i) - CGFloat(gradientSteps) / 2.0) * stepWidth
                gradientSegment.position = CGPoint(x: segmentX, y: 0)
                gradientSegment.zPosition = 2
                page.addChild(gradientSegment)
            }
        }
        
        // Decorative border (double line)
        let borderWidth: CGFloat = 3
        let borderMargin: CGFloat = 15
        
        // Outer border
        let outerBorder = SKShapeNode(rectOf: CGSize(width: size.width - borderMargin * 2, height: size.height - borderMargin * 2), cornerRadius: cornerRadius)
        outerBorder.fillColor = .clear
        outerBorder.strokeColor = parchmentBorder
        outerBorder.lineWidth = borderWidth
        outerBorder.zPosition = 3
        page.addChild(outerBorder)
        
        // Inner border (decorative)
        let innerBorder = SKShapeNode(rectOf: CGSize(width: size.width - borderMargin * 2 - 20, height: size.height - borderMargin * 2 - 20), cornerRadius: cornerRadius)
        innerBorder.fillColor = .clear
        innerBorder.strokeColor = SKColor(red: 0.75, green: 0.65, blue: 0.50, alpha: 0.6)
        innerBorder.lineWidth = 1
        innerBorder.zPosition = 3
        page.addChild(innerBorder)
        
        // Add corner decorations (simple corner brackets)
        let cornerSize: CGFloat = 12
        let cornerOffset: CGFloat = borderMargin + 5
        
        // Top-left corner
        addCornerBracket(to: page, position: CGPoint(x: -size.width/2 + cornerOffset, y: size.height/2 - cornerOffset), size: cornerSize, corner: .topLeft)
        
        // Top-right corner
        addCornerBracket(to: page, position: CGPoint(x: size.width/2 - cornerOffset, y: size.height/2 - cornerOffset), size: cornerSize, corner: .topRight)
        
        // Bottom-left corner
        addCornerBracket(to: page, position: CGPoint(x: -size.width/2 + cornerOffset, y: -size.height/2 + cornerOffset), size: cornerSize, corner: .bottomLeft)
        
        // Bottom-right corner
        addCornerBracket(to: page, position: CGPoint(x: size.width/2 - cornerOffset, y: -size.height/2 + cornerOffset), size: cornerSize, corner: .bottomRight)
        
        return container
    }
    
    private enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private static func addCornerBracket(to node: SKNode, position: CGPoint, size: CGFloat, corner: Corner) {
        let path = CGMutablePath()
        let lineWidth: CGFloat = 2
        
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: position.x, y: position.y - size))
            path.addLine(to: CGPoint(x: position.x, y: position.y))
            path.addLine(to: CGPoint(x: position.x + size, y: position.y))
        case .topRight:
            path.move(to: CGPoint(x: position.x, y: position.y - size))
            path.addLine(to: CGPoint(x: position.x, y: position.y))
            path.addLine(to: CGPoint(x: position.x - size, y: position.y))
        case .bottomLeft:
            path.move(to: CGPoint(x: position.x, y: position.y + size))
            path.addLine(to: CGPoint(x: position.x, y: position.y))
            path.addLine(to: CGPoint(x: position.x + size, y: position.y))
        case .bottomRight:
            path.move(to: CGPoint(x: position.x, y: position.y + size))
            path.addLine(to: CGPoint(x: position.x, y: position.y))
            path.addLine(to: CGPoint(x: position.x - size, y: position.y))
        }
        
        let bracket = SKShapeNode(path: path)
        bracket.strokeColor = parchmentBorder
        bracket.fillColor = .clear
        bracket.lineWidth = lineWidth
        bracket.lineCap = .round
        bracket.lineJoin = .round
        bracket.zPosition = 4
        node.addChild(bracket)
    }
    
    // Create a book-themed button
    static func createBookButton(
        text: String,
        size: CGSize,
        color: SKColor,
        position: CGPoint,
        name: String,
        fontSize: CGFloat = 24
    ) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = name
        
        // Shadow
        let shadow = SKShapeNode(rectOf: size, cornerRadius: 6)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.2)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -3)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main button (parchment style)
        let button = SKShapeNode(rectOf: size, cornerRadius: 6)
        button.fillColor = color
        button.strokeColor = parchmentBorder
        button.lineWidth = 2
        button.zPosition = 1
        container.addChild(button)
        
        // Subtle inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.25), cornerRadius: 4)
        highlight.fillColor = SKColor(white: 1.0, alpha: 0.15)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: 0, y: size.height * 0.125)
        highlight.zPosition = 2
        button.addChild(highlight)
        
        // Label with subtle shadow
        let labelShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        labelShadow.text = text
        labelShadow.fontSize = fontSize
        labelShadow.fontColor = SKColor(white: 0.0, alpha: 0.3)
        labelShadow.position = CGPoint(x: 1, y: -1)
        labelShadow.verticalAlignmentMode = .center
        labelShadow.zPosition = 1
        labelShadow.isUserInteractionEnabled = false
        button.addChild(labelShadow)
        
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = inkColor
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        label.isUserInteractionEnabled = false
        button.addChild(label)
        
        return container
    }
    
    // Create a book-themed title
    static func createBookTitle(text: String, position: CGPoint, fontSize: CGFloat = 36) -> SKNode {
        let container = SKNode()
        container.position = position
        
        // Text shadow (subtle)
        let shadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = SKColor(white: 0.0, alpha: 0.2)
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main text
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = text
        title.fontSize = fontSize
        title.fontColor = inkColor
        title.zPosition = 1
        container.addChild(title)
        
        // Underline decoration
        let underlineWidth = title.frame.width + 20
        let underline = SKShapeNode(rectOf: CGSize(width: underlineWidth, height: 3))
        underline.fillColor = parchmentBorder
        underline.strokeColor = .clear
        underline.position = CGPoint(x: 0, y: -fontSize * 0.4)
        underline.zPosition = 1
        container.addChild(underline)
        
        return container
    }
    
    // Create a book-themed card button (for character/save slot selection)
    static func createBookCardButton(
        text: String,
        subtitle: String? = nil,
        size: CGSize,
        position: CGPoint,
        name: String,
        isSelected: Bool = false,
        isEmpty: Bool = false
    ) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = name
        
        // Shadow
        let shadow = SKShapeNode(rectOf: size, cornerRadius: 8)
        shadow.fillColor = SKColor(white: 0.0, alpha: 0.2)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -3)
        shadow.zPosition = 0
        container.addChild(shadow)
        
        // Main card (parchment style)
        let card = SKShapeNode(rectOf: size, cornerRadius: 8)
        if isEmpty {
            card.fillColor = SKColor(red: 0.90, green: 0.85, blue: 0.75, alpha: 0.8)
        } else if isSelected {
            card.fillColor = SKColor(red: 0.95, green: 0.90, blue: 0.80, alpha: 1.0)
        } else {
            card.fillColor = parchmentBg
        }
        card.strokeColor = isSelected ? bookAccent : parchmentBorder
        card.lineWidth = isSelected ? 3 : 2
        card.zPosition = 1
        container.addChild(card)
        
        // Subtle texture
        let texture = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height * 0.3), cornerRadius: 6)
        texture.fillColor = SKColor(white: 1.0, alpha: isEmpty ? 0.05 : 0.1)
        texture.strokeColor = .clear
        texture.position = CGPoint(x: 0, y: size.height * 0.15)
        texture.zPosition = 2
        card.addChild(texture)
        
        // Main label
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        let fontSize: CGFloat = isEmpty ? 20 : 26
        label.fontSize = fontSize
        label.fontColor = isEmpty ? inkMuted : inkColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: subtitle != nil ? 12 : 0)
        label.zPosition = 3
        label.isUserInteractionEnabled = false
        
        // Truncate text if it's too wide for the container
        let maxWidth = size.width - 40
        label.text = truncateText(text: text, fontName: "Arial-BoldMT", fontSize: fontSize, maxWidth: maxWidth)
        
        card.addChild(label)
        
        // Subtitle
        if let subtitle = subtitle {
            let subtitleLabel = SKLabelNode(fontNamed: "Arial")
            let subtitleFontSize: CGFloat = 16
            subtitleLabel.fontSize = subtitleFontSize
            subtitleLabel.fontColor = isEmpty ? inkMuted : SKColor(red: 0.40, green: 0.32, blue: 0.26, alpha: 1.0)
            subtitleLabel.verticalAlignmentMode = .center
            subtitleLabel.horizontalAlignmentMode = .center
            subtitleLabel.position = CGPoint(x: 0, y: -18)
            subtitleLabel.zPosition = 3
            subtitleLabel.isUserInteractionEnabled = false
            
            // Truncate subtitle if it's too wide
            let maxSubtitleWidth = size.width - 40
            subtitleLabel.text = truncateText(text: subtitle, fontName: "Arial", fontSize: subtitleFontSize, maxWidth: maxSubtitleWidth)
            
            card.addChild(subtitleLabel)
        }
        
        return container
    }
    
    // Create a fancy book page border frame
    static func createBookPageBorder(size: CGSize, padding: CGFloat = 10.0) -> SKNode {
        let container = SKNode()
        
        // Outer border (thick brown)
        let outerBorder = SKShapeNode(rectOf: CGSize(width: size.width + padding * 2, height: size.height + padding * 2), cornerRadius: 4)
        outerBorder.fillColor = .clear
        outerBorder.strokeColor = parchmentBorder
        outerBorder.lineWidth = 4.0
        outerBorder.zPosition = 1
        container.addChild(outerBorder)
        
        // Middle decorative border (lighter brown)
        let middleBorder = SKShapeNode(rectOf: CGSize(width: size.width + padding * 2 - 4, height: size.height + padding * 2 - 4), cornerRadius: 3)
        middleBorder.fillColor = .clear
        middleBorder.strokeColor = parchmentDark
        middleBorder.lineWidth = 1.5
        middleBorder.zPosition = 2
        container.addChild(middleBorder)
        
        // Inner border (darker brown accent)
        let innerBorder = SKShapeNode(rectOf: CGSize(width: size.width + padding * 2 - 8, height: size.height + padding * 2 - 8), cornerRadius: 2)
        innerBorder.fillColor = .clear
        innerBorder.strokeColor = bookAccent
        innerBorder.lineWidth = 1.0
        innerBorder.zPosition = 3
        container.addChild(innerBorder)
        
        // Corner decorations (small squares at corners)
        let cornerSize: CGFloat = 8.0
        let halfWidth = (size.width + padding * 2) / 2.0
        let halfHeight = (size.height + padding * 2) / 2.0
        
        for xSign in [-1, 1] {
            for ySign in [-1, 1] {
                let corner = SKShapeNode(rectOf: CGSize(width: cornerSize, height: cornerSize))
                corner.fillColor = bookAccent
                corner.strokeColor = parchmentBorder
                corner.lineWidth = 1.0
                corner.position = CGPoint(x: CGFloat(xSign) * (halfWidth - cornerSize / 2 - 2), y: CGFloat(ySign) * (halfHeight - cornerSize / 2 - 2))
                corner.zPosition = 4
                container.addChild(corner)
            }
        }
        
        return container
    }
}

