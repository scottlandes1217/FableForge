//
//  WorldConfig.swift
//  FableForge Shared
//
//  World configuration for procedural generation
//

import Foundation

/// Configuration for a procedural world
struct WorldConfig: Codable {
    let id: String
    let name: String
    let description: String?
    let seed: Int  // World seed for deterministic generation (same seed = same world)
    
    let terrain: TerrainConfig
    let entities: EntityConfig
    let enemies: EnemyConfig?
    let animals: AnimalConfig?
    let waterFeatures: WaterFeatureConfig?
}

struct TerrainConfig: Codable {
    let waterThreshold: Double  // Noise value below this = water (0.0-1.0)
    let grassThreshold: Double  // Noise value below this = grass (0.0-1.0)
    let dirtThreshold: Double   // Noise value below this = dirt (0.0-1.0)
    // Stone is everything above dirtThreshold
    
    let groundTiles: GroundTileConfig
}

struct GroundTileConfig: Codable {
    let water: [String]  // GID specs for water tiles
    let grass: [String]  // GID specs for grass tiles
    let dirt: [String]   // GID specs for dirt tiles
    let stone: [String]  // GID specs for stone tiles
}

struct EntityConfig: Codable {
    let treeDensity: Double  // Percentage of tiles that have trees (0.0-1.0)
    let rockDensity: Double  // Percentage of tiles that have rocks (0.0-1.0)
    let treePrefabs: [String]  // List of tree prefab IDs to use
    let rockPrefabs: [String]   // List of rock prefab IDs to use
    let decorationDensity: Double?  // Optional: decorations density
    let decorationPrefabs: [String]?  // Optional: decoration prefab IDs
    let chests: [ChestSpawnConfig]?  // Optional: chests to spawn on map
}

struct ChestSpawnConfig: Codable {
    let chestId: String  // Chest prefab ID (from chests.json)
    let count: Int  // Number of this chest type to spawn per map
    let spawnDensity: Double?  // Optional: override density (alternative to count)
}

struct EnemyConfig: Codable {
    let spawnRate: Double  // Probability of enemy spawn per tile (0.0-1.0)
    let types: [String]    // Enemy type names (e.g., ["Goblin", "Orc", "Bandit"])
    let minLevel: Int      // Minimum enemy level
    let maxLevel: Int       // Maximum enemy level
}

struct AnimalConfig: Codable {
    let spawnRate: Double  // Probability of animal spawn per tile (0.0-1.0)
    let types: [String]    // Animal type names (e.g., ["deer", "rabbit", "fox"])
    let friendlyChance: Double?  // Chance animal is friendly (0.0-1.0), nil = all friendly
}

struct WaterFeatureConfig: Codable {
    let type: String  // "none", "rivers", "lakes", "islands", "ocean"
    let density: String?  // "low", "medium", "high" (optional)
}
