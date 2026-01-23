//
//  GameScene_EntityManagement.swift
//  FableForge Shared
//
//  Companion management functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    func createCompanionSprite(companion: Animal) {
        // Remove existing sprite for this companion if it exists
        if let existingSprite = companionSprites[companion.id] {
            existingSprite.removeFromParent()
        }
        
        let sprite = SKSpriteNode(color: .orange, size: CGSize(width: 20, height: 20))
        sprite.position = playerSprite?.position ?? CGPoint.zero
        // Companion uses characterZPosition (slightly below player for layering)
        sprite.zPosition = characterZPosition - 1
        sprite.name = "companion"
        addChild(sprite)
        companionSprites[companion.id] = sprite
    }
    
    func removeCompanionSprite(companionId: UUID) {
        if let sprite = companionSprites[companionId] {
            sprite.removeFromParent()
            companionSprites.removeValue(forKey: companionId)
        }
    }
    
    /// Update companion positions - each companion follows the player's previous positions
    func updateCompanionPositions() {
        guard let player = gameState?.player else { return }
        
        let companionFollowDistance: CGFloat = 25.0  // Distance between companions
        let followSpeed: CGFloat = 2.5  // Speed at which companions move toward their target
        
        for (index, companion) in player.companions.enumerated() {
            guard let sprite = companionSprites[companion.id] else {
                // Sprite doesn't exist yet, create it
                createCompanionSprite(companion: companion)
                continue
            }
            
            // Calculate target position: each companion follows a position from history
            // Companion 0 follows position from 5 steps ago, companion 1 from 10 steps ago, etc.
            let stepsBack = (index + 1) * 5
            let targetPosition: CGPoint
            
            if stepsBack < playerPositionHistory.count {
                // Use historical position
                targetPosition = playerPositionHistory[playerPositionHistory.count - stepsBack - 1]
            } else if !playerPositionHistory.isEmpty {
                // Not enough history, use oldest position
                targetPosition = playerPositionHistory[0]
            } else {
                // No history yet, follow behind player
                let offset = CGFloat(index + 1) * companionFollowDistance
                targetPosition = CGPoint(
                    x: player.position.x,
                    y: player.position.y - offset
                )
            }
            
            // Move sprite toward target position
            let currentPos = sprite.position
            let dx = targetPosition.x - currentPos.x
            let dy = targetPosition.y - currentPos.y
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance > 1.0 {
                // Normalize direction and move
                let moveX = (dx / distance) * followSpeed
                let moveY = (dy / distance) * followSpeed
                sprite.position = CGPoint(
                    x: currentPos.x + moveX,
                    y: currentPos.y + moveY
                )
            } else {
                // Close enough, snap to target
                sprite.position = targetPosition
            }
        }
    }
    
}
