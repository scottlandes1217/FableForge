//
//  GameScene_EntitySpawning.swift
//  FableForge Shared
//
//  Entity spawning functionality for GameScene (enemies, animals, NPCs)
//

import SpriteKit

extension GameScene {
    
    // MARK: - Entity Spawning from TMX Objects
    
    /// Spawn an enemy from a prefab at a TMX object position
    func spawnEnemyFromPrefab(_ prefab: EnemyPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create Enemy instance from prefab
        guard let player = gameState?.player else { return }
        let enemy = createEnemyFromPrefab(prefab, level: player.level)
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createEnemySprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            sprite.name = "enemy"
            container.addChild(sprite)
            
            // Store reference to enemy (use first sprite as primary)
            if enemySprites[sprite] == nil {
                enemySprites[sprite] = enemy
            }
        }
        
        print("✅ Spawned enemy from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
    }
    
    /// Spawn an animal from a prefab at a TMX object position
    func spawnAnimalFromPrefab(_ prefab: AnimalPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create Animal instance from prefab
        let animal = createAnimalFromPrefab(prefab)
        animal.position = position
        
        // Add to world if available
        if let world = gameState?.world {
            _ = world.spawnAnimal(animal, at: position)
        }
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createAnimalSprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            sprite.name = "animal"
            container.addChild(sprite)
            
            // Store reference to animal (use first sprite as primary)
            if animalSprites[sprite] == nil {
                animalSprites[sprite] = animal
            }
        }
        
        print("✅ Spawned animal from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
    }
    
    /// Spawn an NPC from a prefab at a TMX object position
    func spawnNPCFromPrefab(_ prefab: NPCPrefab, at object: TiledObject, tileSize: CGSize, yFlipOffset: CGFloat, container: SKNode) {
        let baseTileWidth: CGFloat = 16.0
        let scaleFactor = tileSize.width / baseTileWidth
        let scaledX = object.x * scaleFactor
        let scaledY = object.y * scaleFactor
        let worldX = scaledX
        let worldY = yFlipOffset - scaledY
        let position = CGPoint(x: worldX, y: worldY)
        
        // Create sprites from prefab
        let sprites = PrefabFactory.shared.createNPCSprites(prefab, position: position)
        for sprite in sprites {
            sprite.zPosition = prefab.zPosition
            container.addChild(sprite)
        }
        
        // TODO: Create NPC instance and add to game state
        print("✅ Spawned NPC from prefab: \(prefab.name) (id: \(prefab.id)) at (\(Int(position.x)), \(Int(position.y)))")
    }
    
    // MARK: - Random Spawning
    
    /// Spawn initial animals and enemies randomly in the procedural world
    func spawnInitialAnimals() {
        guard let world = gameState?.world else { return }
        
        // Get world config to check blocked terrain types
        let worldConfig = PrefabFactory.shared.getWorldConfig()
        let animalBlockedTerrainTypes = worldConfig?.animals?.blockedTerrainTypes ?? []
        let enemyBlockedTerrainTypes = worldConfig?.enemies?.blockedTerrainTypes ?? []
        
        // Helper to convert TerrainType enum to string
        func terrainTypeToString(_ terrainType: TerrainType) -> String {
            switch terrainType {
            case .water: return "water"
            case .grass: return "grass"
            case .dirt: return "dirt"
            case .stone: return "stone"
            }
        }
        
        // Get all available animal prefabs
        let allAnimalPrefabs = PrefabFactory.shared.getAllAnimalPrefabs()
        guard !allAnimalPrefabs.isEmpty else {
            print("⚠️ No animal prefabs loaded, skipping animal spawning")
            return
        }
        
        // Spawn a few animals randomly using prefabs
        var animalSpawnAttempts = 0
        var animalsSpawned = 0
        while animalsSpawned < 10 && animalSpawnAttempts < 100 {
            animalSpawnAttempts += 1
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            // Check terrain type if using chunk system
            if let chunkManager = chunkManager {
                if let terrainType = chunkManager.getTerrainTypeAt(position: position) {
                    let terrainTypeString = terrainTypeToString(terrainType)
                    if animalBlockedTerrainTypes.contains(terrainTypeString) {
                        continue  // Skip blocked terrain
                    }
                } else {
                    continue  // Skip if terrain type cannot be determined (chunk not loaded)
                }
            }
            
            // Pick random animal prefab
            let prefabArray = Array(allAnimalPrefabs.values)
            if let randomPrefab = prefabArray.randomElement() {
                // Create Animal instance from prefab
                let animal = createAnimalFromPrefab(randomPrefab)
                animal.position = position
                _ = world.spawnAnimal(animal, at: position)
                
                // Create visual representation using prefab's tileGrid
                let sprites = PrefabFactory.shared.createAnimalSprites(randomPrefab, position: position)
                for sprite in sprites {
                    sprite.zPosition = randomPrefab.zPosition
                    sprite.name = "animal"
                    addChild(sprite)
                    
                    // Store reference to animal (use first sprite as primary)
                    if animalSprites[sprite] == nil {
                        animalSprites[sprite] = animal
                    }
                }
                animalsSpawned += 1
            }
        }
        
        // Spawn some enemies too using prefabs
        let allEnemyPrefabs = PrefabFactory.shared.getAllEnemyPrefabs()
        guard !allEnemyPrefabs.isEmpty else {
            print("⚠️ No enemy prefabs loaded, skipping enemy spawning")
            return
        }
        
        guard let player = gameState?.player else { return }
        
        var enemySpawnAttempts = 0
        var enemiesSpawned = 0
        while enemiesSpawned < 5 && enemySpawnAttempts < 100 {
            enemySpawnAttempts += 1
            let x = Int.random(in: 0..<world.width)
            let y = Int.random(in: 0..<world.height)
            let position = CGPoint(x: CGFloat(x) * world.tileSize, y: CGFloat(y) * world.tileSize)
            
            // Make sure not too close to player start position
            let playerStart = gameState?.player.position ?? CGPoint.zero
            let distance = sqrt(pow(position.x - playerStart.x, 2) + pow(position.y - playerStart.y, 2))
            if distance < 200 { continue } // Skip if too close to player
            
            // Check terrain type if using chunk system
            if let chunkManager = chunkManager {
                if let terrainType = chunkManager.getTerrainTypeAt(position: position) {
                    let terrainTypeString = terrainTypeToString(terrainType)
                    if enemyBlockedTerrainTypes.contains(terrainTypeString) {
                        continue  // Skip blocked terrain
                    }
                } else {
                    continue  // Skip if terrain type cannot be determined (chunk not loaded)
                }
            }
            
            // Pick random enemy prefab (filter by level if needed)
            let prefabArray = Array(allEnemyPrefabs.values)
            if let randomPrefab = prefabArray.randomElement() {
                // Create Enemy instance from prefab
                let enemy = createEnemyFromPrefab(randomPrefab, level: player.level)
                
                // Create visual representation using prefab's tileGrid
                let sprites = PrefabFactory.shared.createEnemySprites(randomPrefab, position: position)
                for sprite in sprites {
                    sprite.zPosition = randomPrefab.zPosition
                    sprite.name = "enemy"
                    addChild(sprite)
                    
                    // Store reference to enemy (use first sprite as primary)
                    if enemySprites[sprite] == nil {
                        enemySprites[sprite] = enemy
                    }
                }
                enemiesSpawned += 1
            }
        }
    }
    
    // MARK: - Entity Creation Helpers
    
    /// Create an Animal instance from an AnimalPrefab
    private func createAnimalFromPrefab(_ prefab: AnimalPrefab) -> Animal {
        // Map prefab ID to AnimalType (for backwards compatibility)
        // Try to match by name first
        let animalType: AnimalType
        switch prefab.name.lowercased() {
        case "wolf": animalType = .wolf
        case "bear": animalType = .bear
        case "eagle": animalType = .eagle
        case "deer": animalType = .deer
        case "rabbit": animalType = .rabbit
        case "fox": animalType = .fox
        case "owl": animalType = .owl
        case "boar": animalType = .boar
        case "hawk": animalType = .hawk
        case "stag": animalType = .stag
        default: animalType = .wolf // Fallback
        }
        
        let animal = Animal(type: animalType, name: prefab.name)
        
        // Override stats from prefab
        animal.hitPoints = prefab.hitPoints
        animal.maxHitPoints = prefab.hitPoints
        animal.armorClass = prefab.defensePoints
        animal.attackBonus = prefab.attackPoints
        animal.level = prefab.level ?? 1
        animal.speed = prefab.speed ?? 30
        animal.friendshipLevel = prefab.friendPoints
        
        // Convert skillIds to AnimalMove enum (for backwards compatibility)
        if let skillIds = prefab.skillIds {
            animal.moves = skillIds.compactMap { skillId -> AnimalMove? in
                switch skillId.lowercased() {
                case "bite": return .bite
                case "claw": return .claw
                case "charge": return .charge
                case "pounce": return .pounce
                case "howl": return .howl
                case "roar": return .roar
                case "dive": return .dive
                case "tackle": return .tackle
                default: return nil
                }
            }
        } else if let moves = prefab.moves {
            // Legacy support
            animal.moves = moves.compactMap { moveName -> AnimalMove? in
                AnimalMove(rawValue: moveName.capitalized)
            }
        }
        
        return animal
    }
    
    /// Create an Enemy instance from an EnemyPrefab
    private func createEnemyFromPrefab(_ prefab: EnemyPrefab, level: Int) -> Enemy {
        // Scale stats by level if prefab level is different
        let prefabLevel = prefab.level ?? 1
        let levelMultiplier = level > prefabLevel ? Double(level) / Double(prefabLevel) : 1.0
        
        let enemy = Enemy(
            name: prefab.name,
            hitPoints: Int(Double(prefab.hitPoints) * levelMultiplier),
            armorClass: Int(Double(prefab.defensePoints) * levelMultiplier),
            attackBonus: Int(Double(prefab.attackPoints) * levelMultiplier),
            damageDie: 6, // Default damage die (could be added to prefab later)
            experienceReward: prefab.experienceReward ?? (10 * level),
            goldReward: prefab.goldReward ?? (5 * level)
        )
        
        return enemy
    }
}
