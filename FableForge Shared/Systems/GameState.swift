//
//  GameState.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation

class GameState: NSObject, Codable {
    var player: Player
    var world: WorldMap
    var structures: [Structure] = []
    var npcs: [NPC] = []
    // Note: currentCombat and currentDialogue are not saved as they're runtime-only
    var currentCombat: Combat? {
        didSet { /* Runtime only, not saved */ }
    }
    var currentDialogue: (NPC, DialogueNode)? {
        didSet { /* Runtime only, not saved */ }
    }
    
    enum CodingKeys: String, CodingKey {
        case player, world, structures, npcs
        // Exclude currentCombat and currentDialogue from encoding
    }
    
    init(player: Player, world: WorldMap) {
        self.player = player
        self.world = world
        super.init()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        player = try container.decode(Player.self, forKey: .player)
        world = try container.decode(WorldMap.self, forKey: .world)
        structures = try container.decode([Structure].self, forKey: .structures)
        npcs = try container.decode([NPC].self, forKey: .npcs)
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(player, forKey: .player)
        try container.encode(world, forKey: .world)
        try container.encode(structures, forKey: .structures)
        try container.encode(npcs, forKey: .npcs)
    }
    
    func save() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
    
    static func load(from data: Data) -> GameState? {
        let decoder = JSONDecoder()
        return try? decoder.decode(GameState.self, from: data)
    }
}

