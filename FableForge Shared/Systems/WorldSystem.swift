//
//  WorldSystem.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

// Seeded random number generator for deterministic world generation
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

enum TileType: String, Codable, CaseIterable {
    case grass = "grass"
    case dirt = "dirt"
    case water = "water"
    case stone = "stone"
    case forest = "forest"
    case path = "path"
}

struct Tile: Codable {
    var type: TileType
    var position: CGPoint
    var isWalkable: Bool
    var structureId: UUID?
    var animalId: UUID?
    var itemId: UUID?
    
    init(type: TileType, position: CGPoint) {
        self.type = type
        self.position = position
        self.isWalkable = type != .water
        self.structureId = nil
        self.animalId = nil
        self.itemId = nil
    }
}

class WorldMap: NSObject, Codable {
    var tiles: [[Tile]]
    var width: Int
    var height: Int
    var tileSize: CGFloat = 32.0
    var seed: Int // Store seed for deterministic generation
    
    enum CodingKeys: String, CodingKey {
        case tiles, width, height, tileSize, seed
    }
    
    init(width: Int, height: Int, seed: Int? = nil) {
        self.width = width
        self.height = height
        // Use provided seed or generate a random one (but store it for consistency)
        self.seed = seed ?? Int.random(in: 0...Int.max)
        
        // Initialize tiles with grass
        tiles = []
        for y in 0..<height {
            var row: [Tile] = []
            for x in 0..<width {
                let position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                row.append(Tile(type: .grass, position: position))
            }
            tiles.append(row)
        }
        
        super.init()
        
        generateWorld()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tiles = try container.decode([[Tile]].self, forKey: .tiles)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        tileSize = try container.decode(CGFloat.self, forKey: .tileSize)
        // Use saved seed or generate a new one, but don't regenerate world if tiles already exist
        seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? Int.random(in: 0...Int.max)
        super.init()
        // Don't call generateWorld() here - tiles are already loaded from saved data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tiles, forKey: .tiles)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(tileSize, forKey: .tileSize)
        try container.encode(seed, forKey: .seed)
    }
    
    private func generateWorld() {
        // Use seeded random number generator for deterministic world generation
        var generator = SeededRandomNumberGenerator(seed: UInt64(seed))
        
        // Generate terrain with more interesting patterns
        // Create some water bodies (lakes/rivers)
        let numWaterBodies = 3 + Int.random(in: 0...2, using: &generator)
        for _ in 0..<numWaterBodies {
            let centerX = Int.random(in: 5..<(width - 5), using: &generator)
            let centerY = Int.random(in: 5..<(height - 5), using: &generator)
            let radius = 3 + Int.random(in: 0...3, using: &generator)
            
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = centerX + dx
                    let y = centerY + dy
                    if x >= 0 && x < width && y >= 0 && y < height {
                        let distance = sqrt(Double(dx * dx + dy * dy))
                        if distance <= Double(radius) {
                            let position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                            tiles[y][x] = Tile(type: .water, position: position)
                        }
                    }
                }
            }
        }
        
        // Generate forest patches
        let numForestPatches = 8 + Int.random(in: 0...4, using: &generator)
        for _ in 0..<numForestPatches {
            let centerX = Int.random(in: 0..<width, using: &generator)
            let centerY = Int.random(in: 0..<height, using: &generator)
            let size = 2 + Int.random(in: 0...4, using: &generator)
            
            for dy in -size...size {
                for dx in -size...size {
                    let x = centerX + dx
                    let y = centerY + dy
                    if x >= 0 && x < width && y >= 0 && y < height {
                        // Don't overwrite water
                        if tiles[y][x].type != .water {
                            let random = Int.random(in: 0...100, using: &generator)
                            if random < 70 { // 70% chance to be forest in this patch
                                let position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                                tiles[y][x] = Tile(type: .forest, position: position)
                            }
                        }
                    }
                }
            }
        }
        
        // Add some dirt patches
        let numDirtPatches = 5 + Int.random(in: 0...3, using: &generator)
        for _ in 0..<numDirtPatches {
            let centerX = Int.random(in: 0..<width, using: &generator)
            let centerY = Int.random(in: 0..<height, using: &generator)
            let size = 1 + Int.random(in: 0...2, using: &generator)
            
            for dy in -size...size {
                for dx in -size...size {
                    let x = centerX + dx
                    let y = centerY + dy
                    if x >= 0 && x < width && y >= 0 && y < height {
                        // Don't overwrite water or forest
                        if tiles[y][x].type != .water && tiles[y][x].type != .forest {
                            let position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                            tiles[y][x] = Tile(type: .dirt, position: position)
                        }
                    }
                }
            }
        }
        
        // Add some paths connecting areas
        let numPaths = 2 + Int.random(in: 0...2, using: &generator)
        for _ in 0..<numPaths {
            let startX = Int.random(in: 0..<width, using: &generator)
            let startY = Int.random(in: 0..<height, using: &generator)
            let endX = Int.random(in: 0..<width, using: &generator)
            let endY = Int.random(in: 0..<height, using: &generator)
            
            // Simple path drawing
            var x = startX
            var y = startY
            while x != endX || y != endY {
                if x < endX { x += 1 }
                else if x > endX { x -= 1 }
                if y < endY { y += 1 }
                else if y > endY { y -= 1 }
                
                if x >= 0 && x < width && y >= 0 && y < height {
                    // Don't overwrite water
                    if tiles[y][x].type != .water {
                        let position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                        tiles[y][x] = Tile(type: .path, position: position)
                    }
                }
            }
        }
    }
    
    func tileAt(position: CGPoint) -> Tile? {
        let x = Int(position.x / tileSize)
        let y = Int(position.y / tileSize)
        
        if x >= 0 && x < width && y >= 0 && y < height {
            return tiles[y][x]
        }
        return nil
    }
    
    func canMoveTo(position: CGPoint) -> Bool {
        guard let tile = tileAt(position: position) else { return false }
        return tile.isWalkable && tile.structureId == nil
    }
    
    func placeStructure(_ structure: Structure, at position: CGPoint) -> Bool {
        guard let tile = tileAt(position: position) else { return false }
        if tile.structureId != nil { return false }
        
        let x = Int(position.x / tileSize)
        let y = Int(position.y / tileSize)
        
        // Check if area is clear
        let sizeX = Int(structure.size.width)
        let sizeY = Int(structure.size.height)
        
        for dy in 0..<sizeY {
            for dx in 0..<sizeX {
                let checkX = x + dx
                let checkY = y + dy
                
                if checkX >= width || checkY >= height {
                    return false
                }
                
                if tiles[checkY][checkX].structureId != nil {
                    return false
                }
            }
        }
        
        // Place structure
        for dy in 0..<sizeY {
            for dx in 0..<sizeX {
                tiles[y + dy][x + dx].structureId = structure.id
            }
        }
        
        return true
    }
    
    func spawnAnimal(_ animal: Animal, at position: CGPoint) -> Bool {
        guard let tile = tileAt(position: position) else { return false }
        if tile.animalId != nil { return false }
        
        let x = Int(position.x / tileSize)
        let y = Int(position.y / tileSize)
        tiles[y][x].animalId = animal.id
        return true
    }
    
    func removeAnimal(at position: CGPoint) {
        guard let tile = tileAt(position: position) else { return }
        let x = Int(position.x / tileSize)
        let y = Int(position.y / tileSize)
        tiles[y][x].animalId = nil
    }
}

class EncounterSystem {
    static func generateRandomEnemy(level: Int) -> Enemy {
        // Try to use prefabs first
        let allEnemyPrefabs = PrefabFactory.shared.getAllEnemyPrefabs()
        if !allEnemyPrefabs.isEmpty {
            let prefabArray = Array(allEnemyPrefabs.values)
            if let randomPrefab = prefabArray.randomElement() {
                // Scale stats by level if prefab level is different
                let prefabLevel = randomPrefab.level ?? 1
                let levelMultiplier = level > prefabLevel ? Double(level) / Double(prefabLevel) : 1.0
                
                return Enemy(
                    name: randomPrefab.name,
                    hitPoints: Int(Double(randomPrefab.hitPoints) * levelMultiplier),
                    armorClass: Int(Double(randomPrefab.defensePoints) * levelMultiplier),
                    attackBonus: Int(Double(randomPrefab.attackPoints) * levelMultiplier),
                    damageDie: 6, // Default damage die (could be added to prefab later)
                    experienceReward: randomPrefab.experienceReward ?? (10 * level),
                    goldReward: randomPrefab.goldReward ?? (5 * level)
                )
            }
        }
        
        // Fallback to old hardcoded system if no prefabs available
        let enemyNames = ["Goblin", "Orc", "Bandit", "Wild Beast", "Skeleton", "Zombie"]
        let name = enemyNames.randomElement()!
        
        let baseHP = 10 + (level * 5)
        let baseAC = 12 + level
        let baseAttack = 3 + level
        let baseDamage = 6
        let expReward = 50 * level
        let goldReward = Int.random(in: 5...20) * level
        
        return Enemy(
            name: name,
            hitPoints: baseHP,
            armorClass: baseAC,
            attackBonus: baseAttack,
            damageDie: baseDamage,
            experienceReward: expReward,
            goldReward: goldReward
        )
    }
}

