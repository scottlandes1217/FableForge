//
//  GameScene_Camera.swift
//  FableForge Shared
//
//  Camera management functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    func updateCamera() {
        guard let player = gameState?.player, let camera = cameraNode else { return }
        
        // Use view size if available, otherwise fall back to scene size
        // This ensures we have the correct dimensions for the current orientation
        let screenWidth: CGFloat
        let screenHeight: CGFloat
        if let view = self.view {
            screenWidth = view.bounds.size.width
            screenHeight = view.bounds.size.height
        } else {
            screenWidth = size.width
            screenHeight = size.height
        }
        
        // Calculate player position relative to camera center (in world coordinates)
        let playerWorldPos = player.position
        let cameraWorldPos = camera.position
        
        // Calculate offset from camera center
        let offsetX = playerWorldPos.x - cameraWorldPos.x
        let offsetY = playerWorldPos.y - cameraWorldPos.y
        
        // Get screen bounds (half dimensions)
        let halfWidth = screenWidth / 2
        let halfHeight = screenHeight / 2
        
        // Calculate threshold as percentage of screen size (works for both portrait and landscape)
        let thresholdX = screenWidth * cameraFollowThresholdPercent
        let thresholdY = screenHeight * cameraFollowThresholdPercent
        
        // Calculate desired camera position to keep player within threshold zone
        var newCameraX = cameraWorldPos.x
        var newCameraY = cameraWorldPos.y
        
        // Check horizontal boundaries
        // Left edge: if player is closer than thresholdX to left edge, move camera left
        if offsetX < -halfWidth + thresholdX {
            // Calculate where camera should be to keep player at thresholdX from left edge
            newCameraX = playerWorldPos.x + halfWidth - thresholdX
        }
        // Right edge: if player is closer than thresholdX to right edge, move camera right
        else if offsetX > halfWidth - thresholdX {
            // Calculate where camera should be to keep player at thresholdX from right edge
            newCameraX = playerWorldPos.x - halfWidth + thresholdX
        }
        
        // Check vertical boundaries
        // Bottom edge: if player is closer than thresholdY to bottom edge, move camera down
        if offsetY < -halfHeight + thresholdY {
            newCameraY = playerWorldPos.y + halfHeight - thresholdY
        }
        // Top edge: if player is closer than thresholdY to top edge, move camera up
        else if offsetY > halfHeight - thresholdY {
            newCameraY = playerWorldPos.y - halfHeight + thresholdY
        }
        
        // Update camera position immediately
        if abs(newCameraX - cameraWorldPos.x) > 0.01 || abs(newCameraY - cameraWorldPos.y) > 0.01 {
            camera.position = CGPoint(x: newCameraX, y: newCameraY)
        }
    }
    
}
