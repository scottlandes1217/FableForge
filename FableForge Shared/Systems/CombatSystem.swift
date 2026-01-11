//
//  CombatSystem.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

enum CombatAction {
    case attack
    case useMove(AnimalMove)
    case useItem(Item)
    case defend
    case flee
}

struct CombatResult {
    var damage: Int
    var hit: Bool
    var critical: Bool
    var message: String
}

class CombatSystem {
    
    static func initiateCombat(player: Player, enemy: Enemy) -> Combat {
        return Combat(player: player, enemy: enemy)
    }
    
    static func playerAttack(player: Player, target: Enemy) -> CombatResult {
        let attackRoll = player.attackRoll()
        let hit = attackRoll >= target.armorClass
        
        if hit {
            let damage = player.damageRoll()
            let critical = attackRoll >= 20
            let finalDamage = critical ? damage * 2 : damage
            
            target.takeDamage(finalDamage)
            
            let message = critical ? 
                "Critical hit! \(player.name) deals \(finalDamage) damage to \(target.name)!" :
                "\(player.name) hits \(target.name) for \(finalDamage) damage!"
            
            return CombatResult(damage: finalDamage, hit: true, critical: critical, message: message)
        } else {
            return CombatResult(damage: 0, hit: false, critical: false, message: "\(player.name) misses \(target.name)!")
        }
    }
    
    static func animalAttack(animal: Animal, move: AnimalMove, target: Enemy) -> CombatResult {
        let attackRoll = animal.attackRoll()
        let hit = attackRoll >= target.armorClass
        
        if hit {
            let damage = animal.damageRoll(move: move)
            let critical = attackRoll >= 20
            let finalDamage = critical ? damage * 2 : damage
            
            target.takeDamage(finalDamage)
            
            let message = critical ?
                "Critical hit! \(animal.name) uses \(move.rawValue) and deals \(finalDamage) damage!" :
                "\(animal.name) uses \(move.rawValue) and deals \(finalDamage) damage!"
            
            return CombatResult(damage: finalDamage, hit: true, critical: critical, message: message)
        } else {
            return CombatResult(damage: 0, hit: false, critical: false, message: "\(animal.name) misses with \(move.rawValue)!")
        }
    }
    
    static func enemyAttack(enemy: Enemy, target: Player) -> CombatResult {
        let attackRoll = enemy.attackRoll()
        let hit = attackRoll >= target.armorClass
        
        if hit {
            let damage = enemy.damageRoll()
            let critical = attackRoll >= 20
            let finalDamage = critical ? damage * 2 : damage
            
            target.hitPoints -= finalDamage
            
            let message = critical ?
                "Critical hit! \(enemy.name) deals \(finalDamage) damage to \(target.name)!" :
                "\(enemy.name) hits \(target.name) for \(finalDamage) damage!"
            
            return CombatResult(damage: finalDamage, hit: true, critical: critical, message: message)
        } else {
            return CombatResult(damage: 0, hit: false, critical: false, message: "\(enemy.name) misses \(target.name)!")
        }
    }
}

class Enemy: NSObject, Codable {
    var id: UUID
    var name: String
    var hitPoints: Int
    var maxHitPoints: Int
    var armorClass: Int
    var attackBonus: Int
    var damageDie: Int
    var experienceReward: Int
    var goldReward: Int
    var loot: [Item] = []
    
    init(name: String, hitPoints: Int, armorClass: Int, attackBonus: Int, damageDie: Int, experienceReward: Int, goldReward: Int = 0) {
        self.id = UUID()
        self.name = name
        self.hitPoints = hitPoints
        self.maxHitPoints = hitPoints
        self.armorClass = armorClass
        self.attackBonus = attackBonus
        self.damageDie = damageDie
        self.experienceReward = experienceReward
        self.goldReward = goldReward
        super.init()
    }
    
    func attackRoll() -> Int {
        return Int.random(in: 1...20) + attackBonus
    }
    
    func damageRoll() -> Int {
        return Int.random(in: 1...damageDie) + attackBonus
    }
    
    func takeDamage(_ amount: Int) {
        hitPoints = max(0, hitPoints - amount)
    }
    
    var isDefeated: Bool {
        return hitPoints <= 0
    }
}

class Combat {
    var player: Player
    var companion: Animal?
    var enemy: Enemy
    var turnOrder: [Combatant] = []
    var currentTurn: Int = 0
    var isComplete: Bool = false
    var winner: CombatSide?
    
    enum CombatSide {
        case player
        case enemy
    }
    
    enum Combatant {
        case player
        case companion
        case enemy
    }
    
    init(player: Player, enemy: Enemy) {
        self.player = player
        self.companion = player.companions.first
        self.enemy = enemy
        
        // Determine turn order based on initiative
        var initiatives: [(Combatant, Int)] = []
        initiatives.append((.player, player.rollInitiative()))
        if let companion = companion {
            initiatives.append((.companion, companion.rollInitiative()))
        }
        initiatives.append((.enemy, enemy.attackRoll())) // Using attack roll as initiative
        
        turnOrder = initiatives.sorted { $0.1 > $1.1 }.map { $0.0 }
    }
    
    func executeAction(_ action: CombatAction) -> [CombatResult] {
        var results: [CombatResult] = []
        
        switch action {
        case .attack:
            let result = CombatSystem.playerAttack(player: player, target: enemy)
            results.append(result)
            
        case .useMove(let move):
            if let companion = companion {
                let result = CombatSystem.animalAttack(animal: companion, move: move, target: enemy)
                results.append(result)
            }
            
        case .useItem(let item):
            // Handle item usage
            if let consumable = item as? Consumable {
                _ = consumable.use(on: player)
                results.append(CombatResult(damage: 0, hit: true, critical: false, message: "\(player.name) uses \(item.name)"))
            }
            
        case .defend:
            // Increase AC for this turn
            player.armorClass += 2
            results.append(CombatResult(damage: 0, hit: true, critical: false, message: "\(player.name) takes a defensive stance"))
            
        case .flee:
            // Attempt to flee
            let fleeRoll = Int.random(in: 1...20) + player.abilityScores.modifier(for: .dexterity)
            if fleeRoll >= 15 {
                isComplete = true
                results.append(CombatResult(damage: 0, hit: true, critical: false, message: "\(player.name) successfully flees!"))
            } else {
                results.append(CombatResult(damage: 0, hit: false, critical: false, message: "\(player.name) fails to flee!"))
            }
        }
        
        // Check if enemy is defeated
        if enemy.isDefeated {
            isComplete = true
            winner = .player
            player.gainExperience(enemy.experienceReward)
            results.append(CombatResult(damage: 0, hit: true, critical: false, message: "\(enemy.name) is defeated! Gained \(enemy.experienceReward) XP"))
            return results
        }
        
        // Enemy's turn
        let enemyResult = CombatSystem.enemyAttack(enemy: enemy, target: player)
        results.append(enemyResult)
        
        // Check if player is defeated
        if player.hitPoints <= 0 {
            isComplete = true
            winner = .enemy
            results.append(CombatResult(damage: 0, hit: true, critical: false, message: "\(player.name) is defeated!"))
        }
        
        // Companion's turn if alive
        if let companion = companion, companion.hitPoints > 0, !enemy.isDefeated {
            // Simple AI: companion attacks
            if let move = companion.moves.first {
                let companionResult = CombatSystem.animalAttack(animal: companion, move: move, target: enemy)
                results.append(companionResult)
            }
        }
        
        return results
    }
}

