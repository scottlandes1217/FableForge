//
//  DialogueSystem.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation

struct DialogueNode: Codable {
    var id: UUID
    var text: String
    var responses: [DialogueResponse]
    var conditions: [DialogueCondition]?
    var effects: [DialogueEffect]?
    
    init(id: UUID = UUID(), text: String, responses: [DialogueResponse] = [], conditions: [DialogueCondition]? = nil, effects: [DialogueEffect]? = nil) {
        self.id = id
        self.text = text
        self.responses = responses
        self.conditions = conditions
        self.effects = effects
    }
}

struct DialogueResponse: Codable {
    var id: UUID
    var text: String
    var nextNodeId: UUID?
    var conditions: [DialogueCondition]?
    var effects: [DialogueEffect]?
    
    init(id: UUID = UUID(), text: String, nextNodeId: UUID? = nil, conditions: [DialogueCondition]? = nil, effects: [DialogueEffect]? = nil) {
        self.id = id
        self.text = text
        self.nextNodeId = nextNodeId
        self.conditions = conditions
        self.effects = effects
    }
}

enum DialogueCondition: Codable {
    case playerLevel(Int)
    case hasItem(ItemType)
    case hasSkill(BuildingSkill, Int)
    case hasCompanion
    case questCompleted(String)
    case random(Int) // Percentage chance
    
    func evaluate(player: Player) -> Bool {
        switch self {
        case .playerLevel(let minLevel):
            return player.level >= minLevel
        case .hasItem(let itemType):
            return player.inventory.contains { $0.type == itemType }
        case .hasSkill(let skill, let minLevel):
            return (player.buildingSkills[skill] ?? 0) >= minLevel
        case .hasCompanion:
            return !player.companions.isEmpty
        case .questCompleted(let questId):
            // Implement quest system
            return false
        case .random(let percentage):
            return Int.random(in: 1...100) <= percentage
        }
    }
}

enum DialogueEffect: Codable {
    case giveItem(ItemType, Int)
    case giveExperience(Int)
    case giveGold(Int)
    case unlockSkill(BuildingSkill)
    case startQuest(String)
    case changeRelationship(String, Int) // NPC name, relationship change
    
    func apply(player: Player) {
        switch self {
        case .giveItem(let itemType, let quantity):
            let item = Item(name: itemType.rawValue, type: itemType, quantity: quantity)
            player.inventory.append(item)
        case .giveExperience(let amount):
            player.gainExperience(amount)
        case .giveGold(let amount):
            // Implement gold system
            break
        case .unlockSkill(let skill):
            if player.buildingSkills[skill] == nil {
                player.buildingSkills[skill] = 1
            }
        case .startQuest(let questId):
            // Implement quest system
            break
        case .changeRelationship(let npcName, let change):
            // Implement relationship system
            break
        }
    }
}

class NPC: NSObject, Codable {
    var id: UUID
    var name: String
    var positionX: CGFloat
    var positionY: CGFloat
    var dialogueTree: [UUID: DialogueNode]
    var startingNodeId: UUID
    var relationship: Int = 50 // 0-100
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, positionX, positionY, dialogueTree, startingNodeId, relationship
    }
    
    init(id: UUID = UUID(), name: String, position: CGPoint, dialogueTree: [UUID: DialogueNode], startingNodeId: UUID) {
        self.id = id
        self.name = name
        self.positionX = position.x
        self.positionY = position.y
        self.dialogueTree = dialogueTree
        self.startingNodeId = startingNodeId
        super.init()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        positionX = try container.decode(CGFloat.self, forKey: .positionX)
        positionY = try container.decode(CGFloat.self, forKey: .positionY)
        dialogueTree = try container.decode([UUID: DialogueNode].self, forKey: .dialogueTree)
        startingNodeId = try container.decode(UUID.self, forKey: .startingNodeId)
        relationship = try container.decode(Int.self, forKey: .relationship)
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(dialogueTree, forKey: .dialogueTree)
        try container.encode(startingNodeId, forKey: .startingNodeId)
        try container.encode(relationship, forKey: .relationship)
    }
    
    func getCurrentDialogue(player: Player) -> DialogueNode? {
        return dialogueTree[startingNodeId]
    }
    
    func getNextDialogue(responseId: UUID, player: Player) -> DialogueNode? {
        guard let currentDialogue = getCurrentDialogue(player: player) else { return nil }
        
        guard let response = currentDialogue.responses.first(where: { $0.id == responseId }) else { return nil }
        
        // Check conditions
        if let conditions = response.conditions {
            for condition in conditions {
                if !condition.evaluate(player: player) {
                    return nil
                }
            }
        }
        
        // Apply effects
        if let effects = response.effects {
            for effect in effects {
                effect.apply(player: player)
            }
        }
        
        // Get next node
        if let nextNodeId = response.nextNodeId {
            return dialogueTree[nextNodeId]
        }
        
        return nil
    }
}

class DialogueGenerator {
    static func generateDynamicDialogue(npc: NPC, player: Player, context: String) -> DialogueNode {
        // Generate context-aware dialogue based on player state
        var dialogueText = ""
        var responses: [DialogueResponse] = []
        
        // Check player state and generate appropriate dialogue
        if !player.companions.isEmpty {
            dialogueText = "I see you have a companion with you. That's wonderful!"
            responses.append(DialogueResponse(text: "Yes, we're good friends.", nextNodeId: nil))
        } else {
            dialogueText = "You look like you could use a friend. Have you tried befriending any animals?"
            responses.append(DialogueResponse(text: "Not yet, how do I do that?", nextNodeId: nil))
        }
        
        if player.level >= 5 {
            dialogueText += " You seem experienced. Perhaps you could help me with something?"
            responses.append(DialogueResponse(text: "What do you need?", nextNodeId: nil))
        }
        
        // Add generic responses
        responses.append(DialogueResponse(text: "Goodbye", nextNodeId: nil))
        
        return DialogueNode(text: dialogueText, responses: responses)
    }
    
    static func generateQuestDialogue(questType: String, player: Player) -> DialogueNode {
        let questTemplates: [String: String] = [
            "gather": "I need you to gather some materials for me. Can you help?",
            "defeat": "There's a dangerous creature nearby. Will you help defeat it?",
            "deliver": "I need you to deliver something to another NPC. Can you do that?",
            "build": "I need a structure built. Do you have the skills?"
        ]
        
        let dialogueText = questTemplates[questType] ?? "I have a task for you."
        
        let responses = [
            DialogueResponse(text: "I'll help you.", nextNodeId: nil, effects: [.startQuest(questType)]),
            DialogueResponse(text: "Maybe later.", nextNodeId: nil)
        ]
        
        return DialogueNode(text: dialogueText, responses: responses)
    }
}

