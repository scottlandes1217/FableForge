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
        label.text = text
        label.fontSize = isEmpty ? 20 : 26
        label.fontColor = isEmpty ? mutedText : lightText
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: subtitle != nil ? 12 : 0)
        label.zPosition = 3
        label.isUserInteractionEnabled = false
        card.addChild(label)
        
        // Subtitle
        if let subtitle = subtitle {
            let subtitleLabel = SKLabelNode(fontNamed: "Arial")
            subtitleLabel.text = subtitle
            subtitleLabel.fontSize = 16
            subtitleLabel.fontColor = isEmpty ? SKColor(white: 0.5, alpha: 1.0) : SKColor(white: 0.85, alpha: 1.0)
            subtitleLabel.verticalAlignmentMode = .center
            subtitleLabel.position = CGPoint(x: 0, y: -18)
            subtitleLabel.zPosition = 3
            subtitleLabel.isUserInteractionEnabled = false
            card.addChild(subtitleLabel)
        }
        
        return container
    }
}

