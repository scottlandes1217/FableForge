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
    
    init(name: String, characterClass: CharacterClass) {
        self.id = UUID()
        self.name = name
        self.characterClass = characterClass
        self.creationDate = Date()
    }
    
    var displayName: String {
        return "\(name) - \(characterClass.rawValue)"
    }
}

