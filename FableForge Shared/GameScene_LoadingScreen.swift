//
//  GameScene_LoadingScreen.swift
//  FableForge Shared
//
//  Loading screen functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    // MARK: - Loading Screen
    
    /// Show loading screen overlay (camera-relative, centered on view)
    func showLoadingScreen(message: String = "Loading...") {
        // Remove existing loading screen if any
        hideLoadingScreen()
        
        guard let camera = cameraNode else {
            print("⚠️ Cannot show loading screen: no camera node")
            return
        }
        
        // Get view size (what's actually visible on screen)
        let viewSize: CGSize
        if let view = self.view {
            viewSize = view.bounds.size
        } else {
            viewSize = size  // Fallback to scene size
        }
        
        // Create loading screen overlay (add to camera so it stays centered)
        let overlay = SKNode()
        overlay.name = "loadingScreen"
        // Position relative to camera (camera is at (0,0) in its own coordinate space)
        overlay.position = CGPoint(x: 0, y: 0)
        overlay.zPosition = 10000  // Above everything
        
        // Semi-transparent dark background covering entire view
        let background = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.9), size: viewSize)
        background.position = CGPoint(x: 0, y: 0)
        background.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        overlay.addChild(background)
        
        // Create a nicer container for text and spinner
        let contentContainer = SKNode()
        contentContainer.position = CGPoint(x: 0, y: 0)
        overlay.addChild(contentContainer)
        
        // Loading text with shadow
        let loadingLabelShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        loadingLabelShadow.text = message
        loadingLabelShadow.fontSize = 36
        loadingLabelShadow.fontColor = SKColor(white: 0, alpha: 0.5)
        loadingLabelShadow.position = CGPoint(x: 2, y: -2)
        contentContainer.addChild(loadingLabelShadow)
        
        let loadingLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        loadingLabel.text = message
        loadingLabel.fontSize = 36
        loadingLabel.fontColor = .white
        loadingLabel.position = CGPoint(x: 0, y: 50)
        contentContainer.addChild(loadingLabel)
        
        // Better spinning indicator (circle with segments)
        let spinnerRadius: CGFloat = 25
        let spinner = SKNode()
        spinner.position = CGPoint(x: 0, y: -20)
        
        // Create 8 segments for a nice spinner
        for i in 0..<8 {
            let segment = SKShapeNode(circleOfRadius: spinnerRadius / 3)
            let angle = CGFloat(i) * .pi * 2 / 8
            let x = cos(angle) * spinnerRadius
            let y = sin(angle) * spinnerRadius
            segment.position = CGPoint(x: x, y: y)
            segment.fillColor = SKColor(white: 1.0, alpha: 0.3 + CGFloat(i) * 0.7 / 8)
            segment.strokeColor = .clear
            spinner.addChild(segment)
        }
        
        contentContainer.addChild(spinner)
        
        // Smooth rotation animation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 1.5)
        spinner.run(SKAction.repeatForever(rotate))
        
        // Add overlay to camera so it follows camera position
        camera.addChild(overlay)
        loadingScreen = overlay
    }
    
    /// Hide loading screen overlay
    func hideLoadingScreen() {
        loadingScreen?.removeFromParent()
        loadingScreen = nil
    }
}
