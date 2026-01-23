//
//  Item.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

enum ItemType: String, Codable {
    // Befriending items
    case meat = "Meat"
    case honey = "Honey"
    case fish = "Fish"
    case berries = "Berries"
    case carrot = "Carrot"
    case chicken = "Chicken"
    case mouse = "Mouse"
    case apple = "Apple"
    
    // Building materials
    case wood = "Wood"
    case stone = "Stone"
    case iron = "Iron"
    case cloth = "Cloth"
    case rope = "Rope"
    case nails = "Nails"
    
    // Consumables
    case healthPotion = "Health Potion"
    case food = "Food"
    
    // Equipment
    case weapon = "Weapon"
    case armor = "Armor"
}

enum WeaponType: String, CaseIterable, Codable {
    case sword = "Sword"
    case axe = "Axe"
    case bow = "Bow"
    case staff = "Staff"
    case dagger = "Dagger"
    case mace = "Mace"
    case spear = "Spear"
    
    var damageDie: Int {
        switch self {
        case .dagger: return 4
        case .staff, .mace: return 6
        case .sword, .axe, .spear: return 8
        case .bow: return 6
        }
    }
    
    var range: Int {
        switch self {
        case .bow, .spear: return 5
        default: return 1
        }
    }
}

enum ArmorType: String, CaseIterable, Codable {
    case light = "Light Armor"
    case medium = "Medium Armor"
    case heavy = "Heavy Armor"
    case shield = "Shield"
    
    var armorClass: Int {
        switch self {
        case .light: return 11
        case .medium: return 14
        case .heavy: return 17
        case .shield: return 2 // Bonus
        }
    }
    
    var requiredStrength: Int {
        switch self {
        case .light: return 0
        case .medium: return 13
        case .heavy: return 15
        case .shield: return 0
        }
    }
}

class Item: NSObject, Codable {
    var id: UUID
    var name: String
    var type: ItemType
    var quantity: Int = 1
    var itemDescription: String = ""
    var value: Int = 0 // Gold value
    var gid: Int? = nil // Global Tile ID from Tiled map (for displaying tile image)
    var stackable: Bool = false // Whether this item can stack with others of the same type
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, quantity, itemDescription, value, gid, stackable
    }
    
    init(id: UUID = UUID(), name: String, type: ItemType, quantity: Int = 1, description: String = "", value: Int = 0, gid: Int? = nil, stackable: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.quantity = quantity
        self.itemDescription = description
        self.value = value
        self.gid = gid
        self.stackable = stackable
        super.init()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ItemType.self, forKey: .type)
        quantity = try container.decode(Int.self, forKey: .quantity)
        itemDescription = try container.decode(String.self, forKey: .itemDescription)
        value = try container.decode(Int.self, forKey: .value)
        gid = try container.decodeIfPresent(Int.self, forKey: .gid)
        stackable = try container.decodeIfPresent(Bool.self, forKey: .stackable) ?? false
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(itemDescription, forKey: .itemDescription)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(gid, forKey: .gid)
        try container.encode(stackable, forKey: .stackable)
    }
    
    func use(on target: Any?) -> Bool {
        // Override in subclasses
        return false
    }
}

class Weapon: Item {
    var weaponType: WeaponType
    var damageDie: Int
    var range: Int
    var isMagical: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case weaponType, damageDie, range, isMagical
    }
    
    init(name: String, weaponType: WeaponType, isMagical: Bool = false, value: Int = 0) {
        self.weaponType = weaponType
        self.damageDie = weaponType.damageDie
        self.range = weaponType.range
        self.isMagical = isMagical
        
        let description = isMagical ? "A magical \(weaponType.rawValue.lowercased())" : "A \(weaponType.rawValue.lowercased())"
        
        super.init(name: name, type: .weapon, description: description, value: value)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weaponType = try container.decode(WeaponType.self, forKey: .weaponType)
        damageDie = try container.decode(Int.self, forKey: .damageDie)
        range = try container.decode(Int.self, forKey: .range)
        isMagical = try container.decode(Bool.self, forKey: .isMagical)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weaponType, forKey: .weaponType)
        try container.encode(damageDie, forKey: .damageDie)
        try container.encode(range, forKey: .range)
        try container.encode(isMagical, forKey: .isMagical)
    }
}

class Armor: Item {
    var armorType: ArmorType
    var armorClass: Int
    var requiredStrength: Int
    
    enum CodingKeys: String, CodingKey {
        case armorType, armorClass, requiredStrength
    }
    
    init(name: String, armorType: ArmorType, value: Int = 0) {
        self.armorType = armorType
        self.armorClass = armorType.armorClass
        self.requiredStrength = armorType.requiredStrength
        
        let description = "\(armorType.rawValue) that provides protection"
        
        super.init(name: name, type: .armor, description: description, value: value)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        armorType = try container.decode(ArmorType.self, forKey: .armorType)
        armorClass = try container.decode(Int.self, forKey: .armorClass)
        requiredStrength = try container.decode(Int.self, forKey: .requiredStrength)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(armorType, forKey: .armorType)
        try container.encode(armorClass, forKey: .armorClass)
        try container.encode(requiredStrength, forKey: .requiredStrength)
    }
}

class Consumable: Item {
    var effect: ConsumableEffect
    
    enum CodingKeys: String, CodingKey {
        case effect
    }
    
    init(name: String, type: ItemType, effect: ConsumableEffect, quantity: Int = 1, value: Int = 0) {
        self.effect = effect
        super.init(name: name, type: type, quantity: quantity, value: value)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        effect = try container.decode(ConsumableEffect.self, forKey: .effect)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(effect, forKey: .effect)
    }
    
    override func use(on target: Any?) -> Bool {
        guard quantity > 0 else { return false }
        
        if let player = target as? Player {
            switch effect {
            case .heal(let amount):
                player.hitPoints = min(player.maxHitPoints, player.hitPoints + amount)
                quantity -= 1
                return true
            case .restoreMana(_):
                // Implement if you add mana system
                quantity -= 1
                return true
            }
        }
        
        return false
    }
}

enum ConsumableEffect: Codable {
    case heal(Int)
    case restoreMana(Int)
}

class Material: Item {
    var materialType: MaterialType
    
    enum CodingKeys: String, CodingKey {
        case materialType
    }
    
    init(materialType: MaterialType, quantity: Int = 1) {
        self.materialType = materialType
        super.init(
            name: materialType.rawValue,
            type: .wood, // Will be set based on material type
            quantity: quantity,
            description: "Building material: \(materialType.rawValue)",
            value: materialType.baseValue
        )
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        materialType = try container.decode(MaterialType.self, forKey: .materialType)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(materialType, forKey: .materialType)
    }
}

enum MaterialType: String, CaseIterable, Codable {
    case wood = "Wood"
    case stone = "Stone"
    case iron = "Iron"
    case cloth = "Cloth"
    case rope = "Rope"
    case nails = "Nails"
    
    var baseValue: Int {
        switch self {
        case .wood: return 1
        case .stone: return 2
        case .iron: return 5
        case .cloth: return 2
        case .rope: return 3
        case .nails: return 1
        }
    }
}

