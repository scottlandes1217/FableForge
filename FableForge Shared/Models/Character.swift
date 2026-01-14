//
//  Character.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation

struct GameCharacter: Codable, Identifiable {
    let id: UUID
    var name: String
    var characterClass: CharacterClass
    var creationDate: Date
    var spriteDescription: String? // Description used to generate the sprite
    
    // Frame paths organized by animation type and direction
    // Format: ["idle_south", "idle_west", "idle_east", "idle_north", "walk_south_0", "walk_south_1", "walk_south_2", "walk_south_3", ...]
    var framePaths: [String]? // Paths to individual frame images
    
    init(name: String, characterClass: CharacterClass, spriteDescription: String? = nil, framePaths: [String]? = nil) {
        self.id = UUID()
        self.name = name
        self.characterClass = characterClass
        self.creationDate = Date()
        self.spriteDescription = spriteDescription
        self.framePaths = framePaths
    }
    
    var displayName: String {
        return "\(name) - \(characterClass.rawValue)"
    }
}

