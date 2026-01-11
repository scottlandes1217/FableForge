//
//  CombatUI.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

class CombatUI {
    weak var scene: SKScene?
    var combatPanel: SKNode?
    var actionButtons: [SKNode] = []
    var combatLog: SKLabelNode?
    
    init(scene: SKScene) {
        self.scene = scene
    }
    
    func showCombat(combat: Combat) {
        guard let scene = scene, let camera = scene.camera else { return }
        
        // Create full-screen combat panel (relative to camera)
        let panel = SKShapeNode(rectOf: CGSize(width: scene.size.width * 0.95, height: scene.size.height * 0.7), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: 0, y: 0) // Center relative to camera
        panel.zPosition = 200
        camera.addChild(panel)
        combatPanel = panel
        
        // Enemy info background
        let enemyBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 35), cornerRadius: 6)
        enemyBg.fillColor = SKColor(red: 0.3, green: 0.1, blue: 0.1, alpha: 0.95)
        enemyBg.strokeColor = .red
        enemyBg.lineWidth = 2
        enemyBg.position = CGPoint(x: 0, y: 70)
        panel.addChild(enemyBg)
        
        // Enemy info
        let enemyLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        enemyLabel.text = "\(combat.enemy.name) HP: \(combat.enemy.hitPoints)/\(combat.enemy.maxHitPoints)"
        enemyLabel.fontSize = 20
        enemyLabel.fontColor = .white
        enemyLabel.position = CGPoint(x: 0, y: 0)
        enemyLabel.verticalAlignmentMode = .center
        enemyBg.addChild(enemyLabel)
        
        // Action buttons
        let actions = ["Attack", "Defend", "Item", "Flee"]
        let buttonColors: [SKColor] = [
            SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), // Attack - Red
            SKColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1.0), // Defend - Blue
            SKColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0), // Item - Green
            SKColor(red: 0.6, green: 0.6, blue: 0.2, alpha: 1.0)  // Flee - Yellow
        ]
        var xOffset: CGFloat = -165
        
        for (index, action) in actions.enumerated() {
            let button = SKShapeNode(rectOf: CGSize(width: 90, height: 45), cornerRadius: 8)
            button.fillColor = buttonColors[index]
            button.strokeColor = .white
            button.lineWidth = 2
            button.position = CGPoint(x: xOffset, y: -30)
            button.name = action
            
            let label = SKLabelNode(fontNamed: "Arial-BoldMT")
            label.text = action
            label.fontSize = 16
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.isUserInteractionEnabled = false
            button.addChild(label)
            
            panel.addChild(button)
            actionButtons.append(button)
            xOffset += 110
        }
        
        // Companion move buttons
        if let companion = combat.companion {
            let companionLabelBg = SKShapeNode(rectOf: CGSize(width: 200, height: 25), cornerRadius: 5)
            companionLabelBg.fillColor = SKColor(red: 0.3, green: 0.2, blue: 0.0, alpha: 0.95)
            companionLabelBg.strokeColor = .yellow
            companionLabelBg.lineWidth = 2
            companionLabelBg.position = CGPoint(x: 0, y: -90)
            panel.addChild(companionLabelBg)
            
            let companionLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            companionLabel.text = "\(companion.name) Moves:"
            companionLabel.fontSize = 16
            companionLabel.fontColor = .yellow
            companionLabel.position = CGPoint(x: 0, y: 0)
            companionLabel.verticalAlignmentMode = .center
            companionLabelBg.addChild(companionLabel)
            
            var moveXOffset: CGFloat = -110
            for (index, move) in companion.moves.prefix(3).enumerated() {
                let moveButton = SKShapeNode(rectOf: CGSize(width: 100, height: 40), cornerRadius: 8)
                moveButton.fillColor = SKColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0)
                moveButton.strokeColor = .yellow
                moveButton.lineWidth = 2
                moveButton.position = CGPoint(x: moveXOffset, y: -130)
                moveButton.name = "move_\(move.rawValue)"
                
                let moveLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
                moveLabel.text = move.rawValue
                moveLabel.fontSize = 14
                moveLabel.fontColor = .white
                moveLabel.verticalAlignmentMode = .center
                moveLabel.isUserInteractionEnabled = false
                moveButton.addChild(moveLabel)
                
                panel.addChild(moveButton)
                actionButtons.append(moveButton)
                moveXOffset += 110
            }
        }
        
        // Combat log background
        let logBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 50), cornerRadius: 6)
        logBg.fillColor = SKColor(white: 0.1, alpha: 0.95)
        logBg.strokeColor = .white
        logBg.lineWidth = 2
        logBg.position = CGPoint(x: 0, y: 20)
        panel.addChild(logBg)
        
        // Combat log
        let log = SKLabelNode(fontNamed: "Arial")
        log.text = "Combat started!"
        log.fontSize = 14
        log.fontColor = .white
        log.position = CGPoint(x: 0, y: 0)
        log.horizontalAlignmentMode = .center
        log.verticalAlignmentMode = .center
        log.numberOfLines = 0
        log.preferredMaxLayoutWidth = scene.size.width * 0.75
        logBg.addChild(log)
        combatLog = log
    }
    
    func hideCombat() {
        combatPanel?.removeFromParent()
        combatPanel = nil
        actionButtons.removeAll()
    }
    
    func updateCombatLog(_ message: String) {
        combatLog?.text = message
    }
    
    func handleTouch(at location: CGPoint) -> String? {
        guard let panel = combatPanel, let scene = scene, let camera = scene.camera else { return nil }
        
        // Convert touch location to camera's coordinate system
        let cameraLocation = scene.convert(location, to: camera)
        let localPoint = panel.convert(cameraLocation, from: camera)
        
        for button in actionButtons {
            if button.contains(localPoint) {
                return button.name
            }
        }
        
        return nil
    }
}

