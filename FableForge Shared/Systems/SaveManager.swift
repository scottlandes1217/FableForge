//
//  SaveManager.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation


struct SaveSlot: Codable {
    let slotNumber: Int
    let playerName: String
    let playerLevel: Int
    let saveDate: Date
    let isEmpty: Bool
    
    var displayName: String {
        if isEmpty {
            return "Empty Slot \(slotNumber)"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(playerName) - Lv.\(playerLevel) (\(formatter.string(from: saveDate)))"
    }
}

class SaveManager {
    static let maxSlots = 5
    static let saveFileNamePrefix = "saveSlot"
    static let charactersFileName = "characters.json"
    
    // MARK: - Character Management
    
    static func getCharactersFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent(charactersFileName)
    }
    
    static func getAllCharacters() -> [GameCharacter] {
        guard let url = getCharactersFileURL() else { return [] }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([GameCharacter].self, from: data)
        } catch {
            print("Error loading characters: \(error.localizedDescription)")
            return []
        }
    }
    
    static func saveCharacter(_ character: GameCharacter) -> Bool {
        var characters = getAllCharacters()
        
        // Check if character already exists (update) or add new
        if let index = characters.firstIndex(where: { $0.id == character.id }) {
            characters[index] = character
        } else {
            characters.append(character)
        }
        
        guard let url = getCharactersFileURL() else { return false }
        
        do {
            let data = try JSONEncoder().encode(characters)
            try data.write(to: url)
            print("Character saved: \(character.name)")
            return true
        } catch {
            print("Failed to save character: \(error.localizedDescription)")
            return false
        }
    }
    
    static func deleteCharacter(_ characterId: UUID) -> Bool {
        var characters = getAllCharacters()
        characters.removeAll { $0.id == characterId }
        
        guard let url = getCharactersFileURL() else { return false }
        
        do {
            let data = try JSONEncoder().encode(characters)
            try data.write(to: url)
            
            // Also delete all save slots for this character
            for slot in 1...maxSlots {
                _ = deleteSave(characterId: characterId, slot: slot)
            }
            
            print("Character deleted: \(characterId)")
            return true
        } catch {
            print("Failed to delete character: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Save File Management
    
    static func getSaveFileURL(characterId: UUID, slot: Int) -> URL? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("character_\(characterId.uuidString)_slot\(slot).json")
    }
    
    // Legacy method for backward compatibility
    static func getSaveFileURL(forSlot slot: Int) -> URL? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("\(saveFileNamePrefix)\(slot).json")
    }
    
    static func getSaveSlotInfo(characterId: UUID, slot: Int) -> SaveSlot? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        guard let url = getSaveFileURL(characterId: characterId, slot: slot) else { return nil }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let gameState = GameState.load(from: data) else {
                return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let saveDate = attributes[.modificationDate] as? Date ?? Date()
            
            return SaveSlot(
                slotNumber: slot,
                playerName: gameState.player.name,
                playerLevel: gameState.player.level,
                saveDate: saveDate,
                isEmpty: false
            )
        } catch {
            print("Error reading save slot \(slot): \(error.localizedDescription)")
            return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
        }
    }
    
    static func getAllSaveSlots(characterId: UUID) -> [SaveSlot] {
        return (1...maxSlots).compactMap { getSaveSlotInfo(characterId: characterId, slot: $0) }
    }
    
    // Legacy method for backward compatibility
    static func getSaveSlotInfo(slot: Int) -> SaveSlot? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        guard let url = getSaveFileURL(forSlot: slot) else { return nil }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let gameState = GameState.load(from: data) else {
                return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let saveDate = attributes[.modificationDate] as? Date ?? Date()
            
            return SaveSlot(
                slotNumber: slot,
                playerName: gameState.player.name,
                playerLevel: gameState.player.level,
                saveDate: saveDate,
                isEmpty: false
            )
        } catch {
            print("Error reading save slot \(slot): \(error.localizedDescription)")
            return SaveSlot(slotNumber: slot, playerName: "", playerLevel: 0, saveDate: Date(), isEmpty: true)
        }
    }
    
    static func getAllSaveSlots() -> [SaveSlot] {
        return (1...maxSlots).compactMap { getSaveSlotInfo(slot: $0) }
    }
    
    static func hasAnySaves() -> Bool {
        // Check for character-based saves
        let characters = getAllCharacters()
        for character in characters {
            if getAllSaveSlots(characterId: character.id).contains(where: { !$0.isEmpty }) {
                return true
            }
        }
        
        // Check for legacy format saves
        if getAllSaveSlots().contains(where: { !$0.isEmpty }) {
            return true
        }
        
        // Check for old format save file (migration support)
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let oldSaveFileURL = documentsDirectory.appendingPathComponent("savedGame.json")
        return fileManager.fileExists(atPath: oldSaveFileURL.path)
    }
    
    static func migrateOldSaveIfNeeded() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let oldSaveFileURL = documentsDirectory.appendingPathComponent("savedGame.json")
        
        // Check if old save exists and we have an empty slot
        guard fileManager.fileExists(atPath: oldSaveFileURL.path) else { return }
        
        // Find first empty slot
        for slotNum in 1...maxSlots {
            if getSaveSlotInfo(slot: slotNum)?.isEmpty == true {
                // Migrate old save to first empty slot
                do {
                    let newSaveURL = getSaveFileURL(forSlot: slotNum)!
                    try fileManager.copyItem(at: oldSaveFileURL, to: newSaveURL)
                    try fileManager.removeItem(at: oldSaveFileURL)
                    print("Migrated old save file to slot \(slotNum)")
                } catch {
                    print("Failed to migrate old save file: \(error.localizedDescription)")
                }
                return
            }
        }
    }
    
    static func saveGame(gameState: GameState, characterId: UUID, toSlot slot: Int) -> Bool {
        guard slot >= 1 && slot <= maxSlots else { return false }
        guard let data = gameState.save() else { return false }
        guard let url = getSaveFileURL(characterId: characterId, slot: slot) else { return false }
        
        do {
            try data.write(to: url)
            print("Game saved successfully to character \(characterId) slot \(slot): \(url.path)")
            return true
        } catch {
            print("Failed to save game to slot \(slot): \(error.localizedDescription)")
            return false
        }
    }
    
    static func loadGame(characterId: UUID, fromSlot slot: Int) -> GameState? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        guard let url = getSaveFileURL(characterId: characterId, slot: slot) else { return nil }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            return GameState.load(from: data)
        } catch {
            print("Failed to load game from slot \(slot): \(error.localizedDescription)")
            return nil
        }
    }
    
    static func deleteSave(characterId: UUID, slot: Int) -> Bool {
        guard slot >= 1 && slot <= maxSlots else { return false }
        guard let url = getSaveFileURL(characterId: characterId, slot: slot) else { return false }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }
        
        do {
            try fileManager.removeItem(at: url)
            print("Deleted save slot \(slot) for character \(characterId)")
            return true
        } catch {
            print("Failed to delete save slot \(slot): \(error.localizedDescription)")
            return false
        }
    }
    
    // Legacy methods for backward compatibility
    static func saveGame(gameState: GameState, toSlot slot: Int) -> Bool {
        guard slot >= 1 && slot <= maxSlots else { return false }
        guard let data = gameState.save() else { return false }
        guard let url = getSaveFileURL(forSlot: slot) else { return false }
        
        do {
            try data.write(to: url)
            print("Game saved successfully to slot \(slot): \(url.path)")
            return true
        } catch {
            print("Failed to save game to slot \(slot): \(error.localizedDescription)")
            return false
        }
    }
    
    static func loadGame(fromSlot slot: Int) -> GameState? {
        guard slot >= 1 && slot <= maxSlots else { return nil }
        guard let url = getSaveFileURL(forSlot: slot) else { return nil }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            return GameState.load(from: data)
        } catch {
            print("Failed to load game from slot \(slot): \(error.localizedDescription)")
            return nil
        }
    }
    
    static func deleteSave(slot: Int) -> Bool {
        guard slot >= 1 && slot <= maxSlots else { return false }
        guard let url = getSaveFileURL(forSlot: slot) else { return false }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }
        
        do {
            try fileManager.removeItem(at: url)
            print("Deleted save slot \(slot)")
            return true
        } catch {
            print("Failed to delete save slot \(slot): \(error.localizedDescription)")
            return false
        }
    }
}

