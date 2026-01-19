//
//  Structure.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

enum StructureType: String, CaseIterable, Codable {
    case farm = "Farm"
    case shelter = "Shelter"
    case barn = "Barn"
    case house = "House"
    case workshop = "Workshop"
    case storage = "Storage"
    case fence = "Fence"
    case gate = "Gate"
    
    var requiredMaterials: [MaterialType: Int] {
        // DEPRECATED: Requirements are now loaded from JSON (buildable_structures.json)
        // This is kept for backwards compatibility only
        switch self {
        case .farm:
            return [.wood: 10] // JSON: 10 Wood only
        case .shelter:
            return [.wood: 15, .cloth: 5]
        case .barn:
            return [.wood: 30, .nails: 10, .iron: 5]
        case .house:
            return [.wood: 50, .stone: 20, .nails: 15, .iron: 10]
        case .workshop:
            return [.wood: 25, .iron: 10, .stone: 10]
        case .storage:
            return [.wood: 20, .nails: 5]
        case .fence:
            return [.wood: 5]
        case .gate:
            return [.wood: 3, .iron: 2]
        }
    }
    
    var requiredSkills: [BuildingSkill: Int] {
        switch self {
        case .farm:
            return [.farming: 1]
        case .shelter:
            return [.carpentry: 1]
        case .barn:
            return [.carpentry: 2, .animalHusbandry: 1]
        case .house:
            return [.carpentry: 3, .masonry: 2]
        case .workshop:
            return [.carpentry: 2, .engineering: 1]
        case .storage:
            return [.carpentry: 1]
        case .fence:
            return [.carpentry: 1]
        case .gate:
            return [.carpentry: 1, .smithing: 1]
        }
    }
    
    var size: CGSize {
        switch self {
        case .farm:
            return CGSize(width: 3, height: 3)
        case .shelter:
            return CGSize(width: 2, height: 2)
        case .barn:
            return CGSize(width: 4, height: 3)
        case .house:
            return CGSize(width: 3, height: 3)
        case .workshop:
            return CGSize(width: 3, height: 2)
        case .storage:
            return CGSize(width: 2, height: 2)
        case .fence:
            return CGSize(width: 1, height: 1)
        case .gate:
            return CGSize(width: 1, height: 1)
        }
    }
    
    var capacity: Int {
        switch self {
        case .farm:
            return 5
        case .shelter:
            return 3
        case .barn:
            return 10
        case .house:
            return 0 // Player residence
        case .workshop:
            return 0 // Crafting
        case .storage:
            return 0 // Items
        case .fence:
            return 0
        case .gate:
            return 0
        }
    }
}

class Structure: NSObject, Codable {
    var id: UUID
    var type: StructureType
    var positionX: CGFloat
    var positionY: CGFloat
    var sizeWidth: CGFloat
    var sizeHeight: CGFloat
    var level: Int = 1
    var animals: [Animal] = []
    var isComplete: Bool = false
    var buildProgress: Int = 0
    var buildTime: Int // in seconds
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }
    
    var size: CGSize {
        get { CGSize(width: sizeWidth, height: sizeHeight) }
        set {
            sizeWidth = newValue.width
            sizeHeight = newValue.height
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, positionX, positionY, sizeWidth, sizeHeight
        case level, animals, isComplete, buildProgress, buildTime
    }
    
    init(type: StructureType, position: CGPoint) {
        self.id = UUID()
        self.type = type
        self.positionX = position.x
        self.positionY = position.y
        let typeSize = type.size
        self.sizeWidth = typeSize.width
        self.sizeHeight = typeSize.height
        
        // Calculate build time based on structure complexity
        let materialCount = type.requiredMaterials.values.reduce(0, +)
        self.buildTime = materialCount * 2 // 2 seconds per material unit
        
        super.init()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(StructureType.self, forKey: .type)
        positionX = try container.decode(CGFloat.self, forKey: .positionX)
        positionY = try container.decode(CGFloat.self, forKey: .positionY)
        sizeWidth = try container.decode(CGFloat.self, forKey: .sizeWidth)
        sizeHeight = try container.decode(CGFloat.self, forKey: .sizeHeight)
        level = try container.decode(Int.self, forKey: .level)
        animals = try container.decode([Animal].self, forKey: .animals)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        buildProgress = try container.decode(Int.self, forKey: .buildProgress)
        buildTime = try container.decode(Int.self, forKey: .buildTime)
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(sizeWidth, forKey: .sizeWidth)
        try container.encode(sizeHeight, forKey: .sizeHeight)
        try container.encode(level, forKey: .level)
        try container.encode(animals, forKey: .animals)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(buildProgress, forKey: .buildProgress)
        try container.encode(buildTime, forKey: .buildTime)
    }
    
    var maxCapacity: Int {
        return type.capacity * level
    }
    
    func canAddAnimal() -> Bool {
        return animals.count < maxCapacity
    }
    
    func addAnimal(_ animal: Animal) -> Bool {
        if canAddAnimal() {
            animals.append(animal)
            return true
        }
        return false
    }
    
    func removeAnimal(_ animal: Animal) {
        animals.removeAll { $0.id == animal.id }
    }
    
    func upgrade() {
        level += 1
    }
}

