//
//  Player.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

// D&D Ability Scores
struct AbilityScores: Codable {
    var strength: Int = 10
    var dexterity: Int = 10
    var constitution: Int = 10
    var intelligence: Int = 10
    var wisdom: Int = 10
    var charisma: Int = 10
    
    func modifier(for ability: Ability) -> Int {
        let score = self.score(for: ability)
        return (score - 10) / 2
    }
    
    func score(for ability: Ability) -> Int {
        switch ability {
        case .strength: return strength
        case .dexterity: return dexterity
        case .constitution: return constitution
        case .intelligence: return intelligence
        case .wisdom: return wisdom
        case .charisma: return charisma
        }
    }
}

enum Ability: String, Codable {
    case strength, dexterity, constitution, intelligence, wisdom, charisma
}

// D&D Races
enum Race: String, CaseIterable, Codable {
    case human = "Human"
    case elf = "Elf"
    case dwarf = "Dwarf"
    case halfling = "Halfling"
    case orc = "Orc"
    case tiefling = "Tiefling"
}

// D&D Classes
enum CharacterClass: String, CaseIterable, Codable {
    case fighter = "Fighter"
    case rogue = "Rogue"
    case wizard = "Wizard"
    case cleric = "Cleric"
    case ranger = "Ranger"
    case paladin = "Paladin"
    case barbarian = "Barbarian"
    case bard = "Bard"
    
    var hitDie: Int {
        switch self {
        case .wizard, .rogue: return 6
        case .cleric, .ranger, .bard: return 8
        case .fighter, .paladin: return 10
        case .barbarian: return 12
        }
    }
    
    var primaryAbility: Ability {
        switch self {
        case .fighter, .paladin, .barbarian: return .strength
        case .rogue, .ranger: return .dexterity
        case .wizard: return .intelligence
        case .cleric: return .wisdom
        case .bard: return .charisma
        }
    }
    
    enum ResourceType {
        case mana
        case rage
        case energy
    }
    
    var resourceType: ResourceType {
        switch self {
        case .wizard, .cleric, .ranger, .paladin, .bard: return .mana
        case .barbarian: return .rage
        case .fighter, .rogue: return .energy
        }
    }
}

// D&D Skills
enum Skill: String, CaseIterable, Codable {
    case athletics = "Athletics"
    case acrobatics = "Acrobatics"
    case sleightOfHand = "Sleight of Hand"
    case stealth = "Stealth"
    case arcana = "Arcana"
    case history = "History"
    case investigation = "Investigation"
    case nature = "Nature"
    case religion = "Religion"
    case animalHandling = "Animal Handling"
    case insight = "Insight"
    case medicine = "Medicine"
    case perception = "Perception"
    case survival = "Survival"
    case deception = "Deception"
    case intimidation = "Intimidation"
    case performance = "Performance"
    case persuasion = "Persuasion"
    
    var associatedAbility: Ability {
        switch self {
        case .athletics: return .strength
        case .acrobatics, .sleightOfHand, .stealth: return .dexterity
        case .arcana, .history, .investigation, .nature, .religion: return .intelligence
        case .animalHandling, .insight, .medicine, .perception, .survival: return .wisdom
        case .deception, .intimidation, .performance, .persuasion: return .charisma
        }
    }
}

struct SkillProficiency: Codable {
    var skill: Skill
    var proficiencyBonus: Int
    var isProficient: Bool
    
    func roll(abilityScores: AbilityScores) -> Int {
        let abilityModifier = abilityScores.modifier(for: skill.associatedAbility)
        let proficiency = isProficient ? proficiencyBonus : 0
        return Int.random(in: 1...20) + abilityModifier + proficiency
    }
}

class Player: NSObject, Codable {
    var name: String
    var characterClass: CharacterClass
    var level: Int = 1
    var experiencePoints: Int = 0
    var abilityScores: AbilityScores
    var hitPoints: Int
    var maxHitPoints: Int
    var armorClass: Int = 10
    
    // Resource pools (mana, rage, energy)
    var mana: Int = 0
    var maxMana: Int = 0
    var rage: Int = 0
    var maxRage: Int = 0
    var energy: Int = 0
    var maxEnergy: Int = 0
    var skills: [SkillProficiency] = []
    var inventory: [Item] = []
    var equippedWeapon: Weapon?
    var equippedArmor: Armor?
    var companions: [Animal] = []  // Up to 5 companions
    var positionX: CGFloat = 0
    var positionY: CGFloat = 0
    
    // Equipment slots
    var equippedHead: Armor?
    var equippedChest: Armor?
    var equippedLegs: Armor?
    var equippedHands: Armor?
    var equippedFeet: Armor?
    var equippedNeck: Item?
    var equippedRing1: Item?
    var equippedRing2: Item?
    var equippedWeaponLeft: Weapon?
    var equippedWeaponRight: Weapon?
    
    // Skill and attribute points
    var skillPoints: Int = 0
    var attributePoints: Int = 0
    
    // Learned skills (from skills.json)
    var learnedSkills: [String] = [] // Array of skill IDs
    
    // Maximum number of companions
    static let maxCompanions = 5
    
    // Check if can add another companion
    func canAddCompanion() -> Bool {
        return companions.count < Player.maxCompanions
    }
    
    // Add a companion (returns true if successful)
    func addCompanion(_ animal: Animal) -> Bool {
        guard canAddCompanion() else { return false }
        companions.append(animal)
        return true
    }
    
    // Remove a companion
    func removeCompanion(_ animal: Animal) {
        companions.removeAll { $0.id == animal.id }
    }
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }
    
    // Building-related skills
    var buildingSkills: [BuildingSkill: Int] = [:]
    
    enum CodingKeys: String, CodingKey {
        case name, characterClass, level, experiencePoints, abilityScores
        case hitPoints, maxHitPoints, armorClass, skills, inventory
        case equippedWeapon, equippedArmor, companions
        case positionX, positionY, buildingSkills
        case equippedHead, equippedChest, equippedLegs, equippedHands, equippedFeet
        case equippedNeck, equippedRing1, equippedRing2
        case equippedWeaponLeft, equippedWeaponRight
        case skillPoints, attributePoints, learnedSkills
        case mana, maxMana, rage, maxRage, energy, maxEnergy
    }
    
    var proficiencyBonus: Int {
        return (level - 1) / 4 + 2
    }
    
    init(name: String, characterClass: CharacterClass, abilityScores: AbilityScores) {
        self.name = name
        self.characterClass = characterClass
        self.abilityScores = abilityScores
        
        // Calculate initial HP
        let conModifier = abilityScores.modifier(for: .constitution)
        self.maxHitPoints = characterClass.hitDie + conModifier
        self.hitPoints = maxHitPoints
        
        // Initialize resources based on class
        let resourceType = characterClass.resourceType
        switch resourceType {
        case .mana:
            let intModifier = abilityScores.modifier(for: .intelligence)
            self.maxMana = max(0, characterClass.hitDie + intModifier)
            self.mana = maxMana
        case .rage:
            self.maxRage = 100 // Rage is typically 0-100
            self.rage = 0
        case .energy:
            let dexModifier = abilityScores.modifier(for: .dexterity)
            self.maxEnergy = max(0, characterClass.hitDie * 2 + dexModifier)
            self.energy = maxEnergy
        }
        
        // Initialize skill and attribute points (start with 0, allocated during character creation)
        self.skillPoints = 0
        self.attributePoints = 0
        
        super.init()
        
        // Initialize skills based on class
        initializeSkills()
    }
    
    private func initializeSkills() {
        // Each class gets certain skill proficiencies
        let classSkills: [CharacterClass: [Skill]] = [
            .fighter: [.athletics, .intimidation],
            .rogue: [.acrobatics, .stealth, .sleightOfHand, .investigation],
            .wizard: [.arcana, .history, .investigation],
            .cleric: [.insight, .medicine, .religion],
            .ranger: [.animalHandling, .nature, .perception, .survival],
            .paladin: [.athletics, .insight, .intimidation, .persuasion],
            .barbarian: [.athletics, .intimidation, .nature, .perception],
            .bard: [.deception, .performance, .persuasion]
        ]
        
        if let classSkillList = classSkills[characterClass] {
            for skill in classSkillList {
                skills.append(SkillProficiency(
                    skill: skill,
                    proficiencyBonus: proficiencyBonus,
                    isProficient: true
                ))
            }
        }
        
        // Add all other skills as non-proficient
        for skill in Skill.allCases {
            if !skills.contains(where: { $0.skill == skill }) {
                skills.append(SkillProficiency(
                    skill: skill,
                    proficiencyBonus: proficiencyBonus,
                    isProficient: false
                ))
            }
        }
    }
    
    func gainExperience(_ amount: Int) {
        experiencePoints += amount
        let expNeeded = experienceForLevel(level + 1)
        if experiencePoints >= expNeeded {
            levelUp()
        }
    }
    
    private func experienceForLevel(_ level: Int) -> Int {
        // D&D 5e experience table (simplified)
        switch level {
        case 1: return 0
        case 2: return 300
        case 3: return 900
        case 4: return 2700
        case 5: return 6500
        case 6: return 14000
        case 7: return 23000
        case 8: return 34000
        case 9: return 48000
        case 10: return 64000
        default: return 64000 + (level - 10) * 20000
        }
    }
    
    private func levelUp() {
        level += 1
        let conModifier = abilityScores.modifier(for: .constitution)
        let hitDieRoll = Int.random(in: 1...characterClass.hitDie)
        maxHitPoints += hitDieRoll + conModifier
        hitPoints = maxHitPoints
        
        // Update resources on level up
        let resourceType = characterClass.resourceType
        switch resourceType {
        case .mana:
            let intModifier = abilityScores.modifier(for: .intelligence)
            maxMana += hitDieRoll + intModifier
            mana = maxMana
        case .rage:
            // Rage max stays at 100, but could increase with level
            maxRage = 100
        case .energy:
            let dexModifier = abilityScores.modifier(for: .dexterity)
            maxEnergy += hitDieRoll + dexModifier
            energy = maxEnergy
        }
        
        // Grant skill points and attribute points on level up
        skillPoints += 3
        attributePoints += 5
        
        // Update proficiency bonus for all skills
        for i in 0..<skills.count {
            skills[i].proficiencyBonus = proficiencyBonus
        }
    }
    
    // Spend attribute points to increase an ability score
    func spendAttributePoint(on ability: Ability) -> Bool {
        guard attributePoints > 0 else { return false }
        guard abilityScores.score(for: ability) < 20 else { return false } // Max 20
        
        attributePoints -= 1
        switch ability {
        case .strength: abilityScores.strength += 1
        case .dexterity: abilityScores.dexterity += 1
        case .constitution: abilityScores.constitution += 1
        case .intelligence: abilityScores.intelligence += 1
        case .wisdom: abilityScores.wisdom += 1
        case .charisma: abilityScores.charisma += 1
        }
        
        // Recalculate HP if constitution changed
        if ability == .constitution {
            let conModifier = abilityScores.modifier(for: .constitution)
            let oldConModifier = (abilityScores.constitution - 1 - 10) / 2
            let conDiff = conModifier - oldConModifier
            maxHitPoints += conDiff * level
            hitPoints = min(hitPoints + conDiff * level, maxHitPoints)
        }
        
        return true
    }
    
    // Learn a new skill (spend skill point)
    func learnSkill(skillId: String) -> Bool {
        guard skillPoints > 0 else { return false }
        guard !learnedSkills.contains(skillId) else { return false }
        
        skillPoints -= 1
        learnedSkills.append(skillId)
        return true
    }
    
    func rollInitiative() -> Int {
        let dexModifier = abilityScores.modifier(for: .dexterity)
        return Int.random(in: 1...20) + dexModifier
    }
    
    func attackRoll() -> Int {
        let abilityModifier = abilityScores.modifier(for: characterClass.primaryAbility)
        let proficiency = proficiencyBonus
        return Int.random(in: 1...20) + abilityModifier + proficiency
    }
    
    func damageRoll() -> Int {
        guard let weapon = equippedWeapon else {
            // Unarmed strike
            let strModifier = abilityScores.modifier(for: .strength)
            return max(1, 1 + strModifier)
        }
        
        let abilityModifier = abilityScores.modifier(for: characterClass.primaryAbility)
        let weaponDamage = Int.random(in: 1...weapon.damageDie)
        return weaponDamage + abilityModifier
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        characterClass = try container.decode(CharacterClass.self, forKey: .characterClass)
        level = try container.decode(Int.self, forKey: .level)
        experiencePoints = try container.decode(Int.self, forKey: .experiencePoints)
        abilityScores = try container.decode(AbilityScores.self, forKey: .abilityScores)
        hitPoints = try container.decode(Int.self, forKey: .hitPoints)
        maxHitPoints = try container.decode(Int.self, forKey: .maxHitPoints)
        armorClass = try container.decode(Int.self, forKey: .armorClass)
        skills = try container.decode([SkillProficiency].self, forKey: .skills)
        inventory = try container.decode([Item].self, forKey: .inventory)
        equippedWeapon = try container.decodeIfPresent(Weapon.self, forKey: .equippedWeapon)
        equippedArmor = try container.decodeIfPresent(Armor.self, forKey: .equippedArmor)
        companions = try container.decodeIfPresent([Animal].self, forKey: .companions) ?? []
        positionX = try container.decode(CGFloat.self, forKey: .positionX)
        positionY = try container.decode(CGFloat.self, forKey: .positionY)
        buildingSkills = try container.decode([BuildingSkill: Int].self, forKey: .buildingSkills)
        equippedHead = try container.decodeIfPresent(Armor.self, forKey: .equippedHead)
        equippedChest = try container.decodeIfPresent(Armor.self, forKey: .equippedChest)
        equippedLegs = try container.decodeIfPresent(Armor.self, forKey: .equippedLegs)
        equippedHands = try container.decodeIfPresent(Armor.self, forKey: .equippedHands)
        equippedFeet = try container.decodeIfPresent(Armor.self, forKey: .equippedFeet)
        equippedNeck = try container.decodeIfPresent(Item.self, forKey: .equippedNeck)
        equippedRing1 = try container.decodeIfPresent(Item.self, forKey: .equippedRing1)
        equippedRing2 = try container.decodeIfPresent(Item.self, forKey: .equippedRing2)
        equippedWeaponLeft = try container.decodeIfPresent(Weapon.self, forKey: .equippedWeaponLeft)
        equippedWeaponRight = try container.decodeIfPresent(Weapon.self, forKey: .equippedWeaponRight)
        skillPoints = try container.decodeIfPresent(Int.self, forKey: .skillPoints) ?? 0
        attributePoints = try container.decodeIfPresent(Int.self, forKey: .attributePoints) ?? 0
        learnedSkills = try container.decodeIfPresent([String].self, forKey: .learnedSkills) ?? []
        mana = try container.decodeIfPresent(Int.self, forKey: .mana) ?? 0
        maxMana = try container.decodeIfPresent(Int.self, forKey: .maxMana) ?? 0
        rage = try container.decodeIfPresent(Int.self, forKey: .rage) ?? 0
        maxRage = try container.decodeIfPresent(Int.self, forKey: .maxRage) ?? 0
        energy = try container.decodeIfPresent(Int.self, forKey: .energy) ?? 0
        maxEnergy = try container.decodeIfPresent(Int.self, forKey: .maxEnergy) ?? 0
        super.init()
        // Recalculate proficiency bonus for skills
        for i in 0..<skills.count {
            skills[i].proficiencyBonus = proficiencyBonus
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(characterClass, forKey: .characterClass)
        try container.encode(level, forKey: .level)
        try container.encode(experiencePoints, forKey: .experiencePoints)
        try container.encode(abilityScores, forKey: .abilityScores)
        try container.encode(hitPoints, forKey: .hitPoints)
        try container.encode(maxHitPoints, forKey: .maxHitPoints)
        try container.encode(armorClass, forKey: .armorClass)
        try container.encode(skills, forKey: .skills)
        try container.encode(inventory, forKey: .inventory)
        try container.encodeIfPresent(equippedWeapon, forKey: .equippedWeapon)
        try container.encodeIfPresent(equippedArmor, forKey: .equippedArmor)
        try container.encode(companions, forKey: .companions)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(buildingSkills, forKey: .buildingSkills)
        try container.encodeIfPresent(equippedHead, forKey: .equippedHead)
        try container.encodeIfPresent(equippedChest, forKey: .equippedChest)
        try container.encodeIfPresent(equippedLegs, forKey: .equippedLegs)
        try container.encodeIfPresent(equippedHands, forKey: .equippedHands)
        try container.encodeIfPresent(equippedFeet, forKey: .equippedFeet)
        try container.encodeIfPresent(equippedNeck, forKey: .equippedNeck)
        try container.encodeIfPresent(equippedRing1, forKey: .equippedRing1)
        try container.encodeIfPresent(equippedRing2, forKey: .equippedRing2)
        try container.encodeIfPresent(equippedWeaponLeft, forKey: .equippedWeaponLeft)
        try container.encodeIfPresent(equippedWeaponRight, forKey: .equippedWeaponRight)
        try container.encode(skillPoints, forKey: .skillPoints)
        try container.encode(attributePoints, forKey: .attributePoints)
        try container.encode(learnedSkills, forKey: .learnedSkills)
        try container.encode(mana, forKey: .mana)
        try container.encode(maxMana, forKey: .maxMana)
        try container.encode(rage, forKey: .rage)
        try container.encode(maxRage, forKey: .maxRage)
        try container.encode(energy, forKey: .energy)
        try container.encode(maxEnergy, forKey: .maxEnergy)
    }
}

// Building Skills
enum BuildingSkill: String, CaseIterable, Codable {
    case carpentry = "Carpentry"
    case masonry = "Masonry"
    case farming = "Farming"
    case animalHusbandry = "Animal Husbandry"
    case engineering = "Engineering"
    case smithing = "Smithing"
}

