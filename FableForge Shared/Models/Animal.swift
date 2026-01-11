//
//  Animal.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

enum AnimalType: String, CaseIterable, Codable {
    case wolf = "Wolf"
    case bear = "Bear"
    case eagle = "Eagle"
    case deer = "Deer"
    case rabbit = "Rabbit"
    case fox = "Fox"
    case owl = "Owl"
    case boar = "Boar"
    case hawk = "Hawk"
    case stag = "Stag"
    
    var baseStats: AnimalStats {
        switch self {
        case .wolf:
            return AnimalStats(hitPoints: 11, armorClass: 13, attackBonus: 4, damageDie: 6, speed: 40)
        case .bear:
            return AnimalStats(hitPoints: 34, armorClass: 11, attackBonus: 6, damageDie: 8, speed: 30)
        case .eagle:
            return AnimalStats(hitPoints: 3, armorClass: 13, attackBonus: 5, damageDie: 4, speed: 60)
        case .deer:
            return AnimalStats(hitPoints: 4, armorClass: 13, attackBonus: 2, damageDie: 4, speed: 50)
        case .rabbit:
            return AnimalStats(hitPoints: 1, armorClass: 12, attackBonus: 0, damageDie: 1, speed: 40)
        case .fox:
            return AnimalStats(hitPoints: 5, armorClass: 13, attackBonus: 1, damageDie: 4, speed: 30)
        case .owl:
            return AnimalStats(hitPoints: 1, armorClass: 11, attackBonus: 3, damageDie: 1, speed: 60)
        case .boar:
            return AnimalStats(hitPoints: 11, armorClass: 11, attackBonus: 3, damageDie: 6, speed: 40)
        case .hawk:
            return AnimalStats(hitPoints: 1, armorClass: 13, attackBonus: 5, damageDie: 1, speed: 60)
        case .stag:
            return AnimalStats(hitPoints: 13, armorClass: 13, attackBonus: 3, damageDie: 6, speed: 50)
        }
    }
    
    var requiredBefriendingItem: ItemType? {
        switch self {
        case .wolf: return .meat
        case .bear: return .honey
        case .eagle: return .fish
        case .deer: return .berries
        case .rabbit: return .carrot
        case .fox: return .chicken
        case .owl: return .mouse
        case .boar: return .apple
        case .hawk: return .fish
        case .stag: return .berries
        }
    }
}

struct AnimalStats: Codable {
    var hitPoints: Int
    var armorClass: Int
    var attackBonus: Int
    var damageDie: Int
    var speed: Int
}

enum AnimalMove: String, CaseIterable, Codable {
    case bite = "Bite"
    case claw = "Claw"
    case charge = "Charge"
    case pounce = "Pounce"
    case howl = "Howl"
    case roar = "Roar"
    case dive = "Dive"
    case tackle = "Tackle"
    
    var damageMultiplier: Double {
        switch self {
        case .bite, .claw: return 1.0
        case .charge, .pounce, .tackle: return 1.5
        case .dive: return 1.2
        case .howl, .roar: return 0.0 // Status moves
        }
    }
    
    var description: String {
        switch self {
        case .bite: return "A quick bite attack"
        case .claw: return "Sharp claws slash the enemy"
        case .charge: return "A powerful charge that deals extra damage"
        case .pounce: return "Leap forward and strike"
        case .howl: return "Intimidating howl that may lower enemy morale"
        case .roar: return "Fearsome roar that may stun enemies"
        case .dive: return "Dive from above for increased damage"
        case .tackle: return "A strong tackle attack"
        }
    }
}

class Animal: NSObject, Codable {
    var id: UUID
    var name: String
    var type: AnimalType
    var level: Int = 1
    var experiencePoints: Int = 0
    var hitPoints: Int
    var maxHitPoints: Int
    var armorClass: Int
    var attackBonus: Int
    var damageDie: Int
    var speed: Int
    var moves: [AnimalMove] = []
    var friendshipLevel: Int = 0 // 0-100, affects combat effectiveness
    var isBefriended: Bool = false
    var positionX: CGFloat = 0
    var positionY: CGFloat = 0
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, level, experiencePoints, hitPoints, maxHitPoints
        case armorClass, attackBonus, damageDie, speed, moves
        case friendshipLevel, isBefriended, positionX, positionY
    }
    
    init(type: AnimalType, name: String? = nil) {
        self.id = UUID()
        self.type = type
        self.name = name ?? type.rawValue
        let stats = type.baseStats
        self.hitPoints = stats.hitPoints
        self.maxHitPoints = stats.hitPoints
        self.armorClass = stats.armorClass
        self.attackBonus = stats.attackBonus
        self.damageDie = stats.damageDie
        self.speed = stats.speed
        
        super.init()
        
        // Assign moves based on type
        assignMoves()
    }
    
    private func assignMoves() {
        switch type {
        case .wolf:
            moves = [.bite, .howl, .pounce]
        case .bear:
            moves = [.claw, .roar, .charge]
        case .eagle, .hawk:
            moves = [.dive, .claw, .pounce]
        case .deer, .stag:
            moves = [.charge, .tackle]
        case .rabbit:
            moves = [.bite, .pounce]
        case .fox:
            moves = [.bite, .pounce, .tackle]
        case .owl:
            moves = [.dive, .claw]
        case .boar:
            moves = [.charge, .tackle, .bite]
        }
    }
    
    func befriend() {
        isBefriended = true
        friendshipLevel = 10 // Starting friendship
    }
    
    func increaseFriendship(_ amount: Int) {
        friendshipLevel = min(100, friendshipLevel + amount)
    }
    
    func attackRoll() -> Int {
        let friendshipBonus = friendshipLevel / 20 // Up to +5 bonus
        return Int.random(in: 1...20) + attackBonus + friendshipBonus
    }
    
    func damageRoll(move: AnimalMove) -> Int {
        let baseDamage = Int.random(in: 1...damageDie)
        let friendshipBonus = friendshipLevel / 25 // Up to +4 bonus
        let moveDamage = Int(Double(baseDamage) * move.damageMultiplier)
        return max(1, moveDamage + friendshipBonus)
    }
    
    func rollInitiative() -> Int {
        return Int.random(in: 1...20) + (speed / 10)
    }
    
    func gainExperience(_ amount: Int) {
        experiencePoints += amount
        let expNeeded = level * 100
        if experiencePoints >= expNeeded {
            levelUp()
        }
    }
    
    private func levelUp() {
        level += 1
        maxHitPoints += Int.random(in: 1...4)
        hitPoints = maxHitPoints
        attackBonus += 1
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AnimalType.self, forKey: .type)
        level = try container.decode(Int.self, forKey: .level)
        experiencePoints = try container.decode(Int.self, forKey: .experiencePoints)
        hitPoints = try container.decode(Int.self, forKey: .hitPoints)
        maxHitPoints = try container.decode(Int.self, forKey: .maxHitPoints)
        armorClass = try container.decode(Int.self, forKey: .armorClass)
        attackBonus = try container.decode(Int.self, forKey: .attackBonus)
        damageDie = try container.decode(Int.self, forKey: .damageDie)
        speed = try container.decode(Int.self, forKey: .speed)
        moves = try container.decode([AnimalMove].self, forKey: .moves)
        friendshipLevel = try container.decode(Int.self, forKey: .friendshipLevel)
        isBefriended = try container.decode(Bool.self, forKey: .isBefriended)
        positionX = try container.decode(CGFloat.self, forKey: .positionX)
        positionY = try container.decode(CGFloat.self, forKey: .positionY)
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(level, forKey: .level)
        try container.encode(experiencePoints, forKey: .experiencePoints)
        try container.encode(hitPoints, forKey: .hitPoints)
        try container.encode(maxHitPoints, forKey: .maxHitPoints)
        try container.encode(armorClass, forKey: .armorClass)
        try container.encode(attackBonus, forKey: .attackBonus)
        try container.encode(damageDie, forKey: .damageDie)
        try container.encode(speed, forKey: .speed)
        try container.encode(moves, forKey: .moves)
        try container.encode(friendshipLevel, forKey: .friendshipLevel)
        try container.encode(isBefriended, forKey: .isBefriended)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
    }
}

