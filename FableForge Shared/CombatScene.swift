//
//  CombatScene.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit

class CombatScene: SKScene {
    var combat: Combat
    var gameState: GameState
    var completionHandler: ((Combat.CombatSide?) -> Void)? // nil if fled, .player if won, .enemy if lost
    
    private var combatPanel: SKShapeNode?
    private var actionButtons: [SKNode] = []
    private var combatLog: SKLabelNode?
    private var enemyLabel: SKLabelNode?
    private var playerLabel: SKLabelNode?
    
    init(size: CGSize, combat: Combat, gameState: GameState, completionHandler: @escaping (Combat.CombatSide?) -> Void) {
        self.combat = combat
        self.gameState = gameState
        self.completionHandler = completionHandler
        super.init(size: size)
        self.scaleMode = .aspectFill
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        // Ensure the scene can receive touches
        self.isUserInteractionEnabled = true
        self.isPaused = false
        setupCombatUI()
    }
    
    func setupCombatUI() {
        // Create full-screen combat panel
        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.95, height: size.height * 0.7), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 200
        panel.name = "combatPanel"
        addChild(panel)
        combatPanel = panel
        
        // Player info background
        let playerBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 35), cornerRadius: 6)
        playerBg.fillColor = SKColor(red: 0.1, green: 0.3, blue: 0.1, alpha: 0.95)
        playerBg.strokeColor = .green
        playerBg.lineWidth = 2
        playerBg.position = CGPoint(x: 0, y: 120)
        panel.addChild(playerBg)
        
        playerLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        playerLabel?.text = "\(combat.player.name) HP: \(combat.player.hitPoints)/\(combat.player.maxHitPoints)"
        playerLabel?.fontSize = 18
        playerLabel?.fontColor = .white
        playerLabel?.position = CGPoint(x: 0, y: 0)
        playerLabel?.verticalAlignmentMode = .center
        playerBg.addChild(playerLabel!)
        
        // Enemy info background
        let enemyBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 35), cornerRadius: 6)
        enemyBg.fillColor = SKColor(red: 0.3, green: 0.1, blue: 0.1, alpha: 0.95)
        enemyBg.strokeColor = .red
        enemyBg.lineWidth = 2
        enemyBg.position = CGPoint(x: 0, y: 70)
        panel.addChild(enemyBg)
        
        enemyLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        enemyLabel?.text = "\(combat.enemy.name) HP: \(combat.enemy.hitPoints)/\(combat.enemy.maxHitPoints)"
        enemyLabel?.fontSize = 20
        enemyLabel?.fontColor = .white
        enemyLabel?.position = CGPoint(x: 0, y: 0)
        enemyLabel?.verticalAlignmentMode = .center
        enemyBg.addChild(enemyLabel!)
        
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
            for move in companion.moves.prefix(3) {
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
        log.preferredMaxLayoutWidth = size.width * 0.75
        logBg.addChild(log)
        combatLog = log
    }
    
    func updateCombatUI() {
        enemyLabel?.text = "\(combat.enemy.name) HP: \(combat.enemy.hitPoints)/\(combat.enemy.maxHitPoints)"
        playerLabel?.text = "\(combat.player.name) HP: \(combat.player.hitPoints)/\(combat.player.maxHitPoints)"
    }
    
    func updateCombatLog(_ message: String) {
        combatLog?.text = message
    }
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        print("[CombatScene] touchesBegan at \(location)")
        
        // Hit-test using scene-space nodes
        let touchedNodes = nodes(at: location)
        
        // Helper closure to see if any touched node (or its parent) matches a name
        func didTouch(nodeNamed targetName: String) -> Bool {
            return touchedNodes.contains { node in
                node.name == targetName || node.parent?.name == targetName
            }
        }
        
        // Check for action buttons
        if didTouch(nodeNamed: "Attack") {
            print("[CombatScene] Attack button touched")
            handleCombatAction("Attack")
        } else if didTouch(nodeNamed: "Defend") {
            print("[CombatScene] Defend button touched")
            handleCombatAction("Defend")
        } else if didTouch(nodeNamed: "Item") {
            print("[CombatScene] Item button touched")
            handleCombatAction("Item")
        } else if didTouch(nodeNamed: "Flee") {
            print("[CombatScene] Flee button touched")
            handleCombatAction("Flee")
        } else if let moveNode = touchedNodes.first(where: { $0.name?.hasPrefix("move_") == true }) {
            if let moveName = moveNode.name?.dropFirst(5) {
                print("[CombatScene] Move button touched: \(moveName)")
                handleCombatAction("move_\(moveName)")
            }
        }
    }
    #endif
    
    #if os(OSX)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        print("[CombatScene] mouseDown at \(location)")
        
        let touchedNodes = nodes(at: location)
        
        func didTouch(nodeNamed targetName: String) -> Bool {
            return touchedNodes.contains { node in
                node.name == targetName || node.parent?.name == targetName
            }
        }
        
        if didTouch(nodeNamed: "Attack") {
            handleCombatAction("Attack")
        } else if didTouch(nodeNamed: "Defend") {
            handleCombatAction("Defend")
        } else if didTouch(nodeNamed: "Item") {
            handleCombatAction("Item")
        } else if didTouch(nodeNamed: "Flee") {
            handleCombatAction("Flee")
        } else if let moveNode = touchedNodes.first(where: { $0.name?.hasPrefix("move_") == true }) {
            if let moveName = moveNode.name?.dropFirst(5) {
                handleCombatAction("move_\(moveName)")
            }
        }
    }
    #endif
    
    func handleCombatAction(_ action: String) {
        guard !combat.isComplete else { return }
        
        var combatAction: CombatAction?
        
        if action == "Attack" {
            combatAction = .attack
        } else if action == "Defend" {
            combatAction = .defend
        } else if action == "Flee" {
            combatAction = .flee
        } else if action == "Item" {
            // TODO: Show item selection
            return
        } else if action.hasPrefix("move_") {
            let moveName = String(action.dropFirst(5))
            if let move = AnimalMove.allCases.first(where: { $0.rawValue == moveName }) {
                combatAction = .useMove(move)
            }
        }
        
        guard let action = combatAction else { return }
        
        let results = combat.executeAction(action)
        
        var logMessage = ""
        for result in results {
            logMessage += result.message + "\n"
        }
        updateCombatLog(logMessage)
        updateCombatUI()
        
        if combat.isComplete {
            if combat.winner == .player {
                // Victory
                updateCombatLog("Victory! You gained \(combat.enemy.experienceReward) XP")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.completionHandler?(.player)
                }
            } else if combat.winner == .enemy {
                // Defeat
                updateCombatLog("You were defeated...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.completionHandler?(.enemy)
                }
            } else {
                // Fled
                self.completionHandler?(nil)
            }
        }
    }
}

