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
    // Map information - tracks which map the player is currently on
    var currentMapFileName: String = "Exterior"  // Default map name (TMX file without .tmx extension)
    var useProceduralWorld: Bool = false  // Whether using procedural world or TMX map
    // Note: currentCombat and currentDialogue are not saved as they're runtime-only
    var currentCombat: Combat? {
        didSet { /* Runtime only, not saved */ }
    }
    var currentDialogue: (NPC, DialogueNode)? {
        didSet { /* Runtime only, not saved */ }
    }
    
    enum CodingKeys: String, CodingKey {
        case player, world, structures, npcs, currentMapFileName, useProceduralWorld
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
        // Load map info with defaults for backward compatibility
        currentMapFileName = try container.decodeIfPresent(String.self, forKey: .currentMapFileName) ?? "Exterior"
        useProceduralWorld = try container.decodeIfPresent(Bool.self, forKey: .useProceduralWorld) ?? false
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(player, forKey: .player)
        try container.encode(world, forKey: .world)
        try container.encode(structures, forKey: .structures)
        try container.encode(npcs, forKey: .npcs)
        try container.encode(currentMapFileName, forKey: .currentMapFileName)
        try container.encode(useProceduralWorld, forKey: .useProceduralWorld)
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

