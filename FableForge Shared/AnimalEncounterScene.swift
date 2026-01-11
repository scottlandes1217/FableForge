//
//  AnimalEncounterScene.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit

class AnimalEncounterScene: SKScene {
    var animal: Animal
    var gameState: GameState
    var completionHandler: ((Bool) -> Void)? // true if befriended, false if left
    
    private var encounterPanel: SKShapeNode?
    
    init(size: CGSize, animal: Animal, gameState: GameState, completionHandler: @escaping (Bool) -> Void) {
        self.animal = animal
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
        setupEncounterUI()
    }
    
    func setupEncounterUI() {
        // Create full-screen encounter UI
        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.9, height: size.height * 0.6), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.15, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.9, alpha: 1.0)
        panel.lineWidth = 3
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition = 200
        panel.name = "encounterPanel"
        addChild(panel)
        encounterPanel = panel
        
        // Title background
        let titleBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 40), cornerRadius: 6)
        titleBg.fillColor = SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.95)
        titleBg.strokeColor = .cyan
        titleBg.lineWidth = 2
        titleBg.position = CGPoint(x: 0, y: 70)
        panel.addChild(titleBg)
        
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = "A wild \(animal.name) appears!"
        label.fontSize = 20
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: 0)
        label.verticalAlignmentMode = .center
        titleBg.addChild(label)
        
        // Animal info
        let animalInfoBg = SKShapeNode(rectOf: CGSize(width: panel.frame.width * 0.9, height: 60), cornerRadius: 6)
        animalInfoBg.fillColor = SKColor(white: 0.1, alpha: 0.95)
        animalInfoBg.strokeColor = .white
        animalInfoBg.lineWidth = 2
        animalInfoBg.position = CGPoint(x: 0, y: 10)
        panel.addChild(animalInfoBg)
        
        let animalInfoLabel = SKLabelNode(fontNamed: "Arial")
        animalInfoLabel.text = "Level \(animal.level) | HP: \(animal.hitPoints)/\(animal.maxHitPoints)"
        animalInfoLabel.fontSize = 16
        animalInfoLabel.fontColor = .white
        animalInfoLabel.position = CGPoint(x: 0, y: 0)
        animalInfoLabel.verticalAlignmentMode = .center
        animalInfoBg.addChild(animalInfoLabel)
        
        // Check if player has befriending item
        let requiredItem = animal.type.requiredBefriendingItem
        if let item = requiredItem, gameState.player.inventory.contains(where: { $0.type == item }) {
            let befriendButton = SKShapeNode(rectOf: CGSize(width: 140, height: 50), cornerRadius: 8)
            befriendButton.fillColor = SKColor(red: 0.1, green: 0.7, blue: 0.1, alpha: 1.0)
            befriendButton.strokeColor = .white
            befriendButton.lineWidth = 2
            befriendButton.position = CGPoint(x: 0, y: -50)
            befriendButton.name = "befriend"
            
            let buttonLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            buttonLabel.text = "Befriend"
            buttonLabel.fontSize = 18
            buttonLabel.fontColor = .white
            buttonLabel.verticalAlignmentMode = .center
            buttonLabel.isUserInteractionEnabled = false
            befriendButton.addChild(buttonLabel)
            panel.addChild(befriendButton)
        } else {
            // Show message if player doesn't have required item
            let noItemLabel = SKLabelNode(fontNamed: "Arial")
            if let item = requiredItem {
                noItemLabel.text = "You need \(item.rawValue) to befriend this animal"
            } else {
                noItemLabel.text = "This animal cannot be befriended"
            }
            noItemLabel.fontSize = 14
            noItemLabel.fontColor = .yellow
            noItemLabel.position = CGPoint(x: 0, y: -50)
            noItemLabel.verticalAlignmentMode = .center
            panel.addChild(noItemLabel)
        }
        
        let leaveButton = SKShapeNode(rectOf: CGSize(width: 140, height: 50), cornerRadius: 8)
        leaveButton.fillColor = SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        leaveButton.strokeColor = .white
        leaveButton.lineWidth = 2
        leaveButton.position = CGPoint(x: 0, y: -110)
        leaveButton.name = "leave"
        
        let leaveLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        leaveLabel.text = "Leave"
        leaveLabel.fontSize = 18
        leaveLabel.fontColor = .white
        leaveLabel.verticalAlignmentMode = .center
        leaveLabel.isUserInteractionEnabled = false
        leaveButton.addChild(leaveLabel)
        panel.addChild(leaveButton)
    }
    
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        print("[AnimalEncounterScene] touchesBegan at \(location), isUserInteractionEnabled: \(isUserInteractionEnabled), isPaused: \(isPaused)")
        
        // Hit-test using scene-space nodes so we don't have to worry about
        // panel or button local coordinate conversions.
        let touchedNodes = nodes(at: location)
        print("[AnimalEncounterScene] Found \(touchedNodes.count) nodes at location")
        for node in touchedNodes {
            print("  - Node: \(type(of: node)), name: \(node.name ?? "nil"), parent: \(node.parent?.name ?? "nil")")
        }
        
        // Helper closure to see if any touched node (or its parent) matches a name
        func didTouch(nodeNamed targetName: String) -> Bool {
            return touchedNodes.contains { node in
                node.name == targetName || node.parent?.name == targetName
            }
        }
        
        if didTouch(nodeNamed: "befriend") {
            print("[AnimalEncounterScene] Befriend button touched")
            handleBefriend()
        } else if didTouch(nodeNamed: "leave") {
            print("[AnimalEncounterScene] Leave button touched")
            handleLeave()
        } else {
            print("[AnimalEncounterScene] No matching button found")
        }
    }
    #endif
    
    #if os(OSX)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        print("[AnimalEncounterScene] mouseDown at \(location)")
        
        guard let panel = encounterPanel else { return }
        // Convert scene-space mouse location into the panel's local coordinate space
        let localPoint = panel.convert(location, from: self)
        
        if let befriendButton = panel.childNode(withName: "befriend") as? SKShapeNode, befriendButton.contains(localPoint) {
            handleBefriend()
        } else if let leaveButton = panel.childNode(withName: "leave") as? SKShapeNode, leaveButton.contains(localPoint) {
            handleLeave()
        }
    }
    #endif
    
    func handleBefriend() {
        // Remove required item from inventory
        let requiredItem = animal.type.requiredBefriendingItem
        if let item = requiredItem {
            if let index = gameState.player.inventory.firstIndex(where: { $0.type == item && $0.quantity > 0 }) {
                gameState.player.inventory[index].quantity -= 1
                if gameState.player.inventory[index].quantity <= 0 {
                    gameState.player.inventory.remove(at: index)
                }
            }
        }
        
        // Befriend the animal
        animal.befriend()
        // Add to companions (up to max 5)
        if gameState.player.canAddCompanion() {
            _ = gameState.player.addCompanion(animal)
        } else {
            // Replace oldest companion if at max
            if !gameState.player.companions.isEmpty {
                gameState.player.companions.removeFirst()
                _ = gameState.player.addCompanion(animal)
            }
        }
        
        // Return to game scene
        completionHandler?(true)
    }
    
    func handleLeave() {
        print("[AnimalEncounterScene] handleLeave called")
        // Return to game scene without befriending
        guard let handler = completionHandler else {
            print("[AnimalEncounterScene] ERROR: completionHandler is nil!")
            return
        }
        
        print("[AnimalEncounterScene] Calling completion handler with false")
        handler(false)
        
        // Also handle the scene transition here as a backup
        // The completion handler should handle it, but if it doesn't work, this will
        DispatchQueue.main.async {
            if let view = self.view {
                // The completion handler should have already handled this, but just in case
                print("[AnimalEncounterScene] View is available: \(view)")
            }
        }
    }
}

