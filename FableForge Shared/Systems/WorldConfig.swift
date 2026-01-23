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
    let exitConfig: ExitConfig?  // Optional exit configuration
}

struct TerrainConfig: Codable {
    let waterThreshold: Double  // Noise value below this = water (0.0-1.0)
    let grassThreshold: Double  // Noise value below this = grass (0.0-1.0)
    let dirtThreshold: Double   // Noise value below this = dirt (0.0-1.0)
    // Stone is everything above dirtThreshold
    
    let groundTiles: GroundTileConfig
}

/// Tile variant configuration - maps tile variants to GID specs
struct TileVariantConfig: Codable {
    let base: [String]?              // Base/interior tiles (optional)
    let edgeN: [String]?             // North edge tiles (optional)
    let edgeS: [String]?             // South edge tiles (optional)
    let edgeE: [String]?             // East edge tiles (optional)
    let edgeW: [String]?             // West edge tiles (optional)
    let cornerNE: [String]?          // Northeast corner tiles (optional)
    let cornerNW: [String]?          // Northwest corner tiles (optional)
    let cornerSE: [String]?          // Southeast corner tiles (optional)
    let cornerSW: [String]?          // Southwest corner tiles (optional)
    let innerCornerNE: [String]?     // Inner corner NE tiles (optional)
    let innerCornerNW: [String]?     // Inner corner NW tiles (optional)
    let innerCornerSE: [String]?     // Inner corner SE tiles (optional)
    let innerCornerSW: [String]?     // Inner corner SW tiles (optional)
    let transitionN: [String]?       // Transition tiles to north (optional)
    let transitionS: [String]?       // Transition tiles to south (optional)
    let transitionE: [String]?       // Transition tiles to east (optional)
    let transitionW: [String]?       // Transition tiles to west (optional)
    let transitionNE: [String]?      // Transition corner NE (optional)
    let transitionNW: [String]?      // Transition corner NW (optional)
    let transitionSE: [String]?      // Transition corner SE (optional)
    let transitionSW: [String]?      // Transition corner SW (optional)
    
    // Custom decoder to handle both string and object formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Helper function to decode an array that can contain either strings or objects
        func decodeTileArray(forKey key: CodingKeys) throws -> [String]? {
            if let array = try? container.decode([TileIDOrObject].self, forKey: key) {
                return array.map { $0.tile_id }
            }
            return try? container.decode([String].self, forKey: key)
        }
        
        self.base = try decodeTileArray(forKey: .base)
        self.edgeN = try decodeTileArray(forKey: .edgeN)
        self.edgeS = try decodeTileArray(forKey: .edgeS)
        self.edgeE = try decodeTileArray(forKey: .edgeE)
        self.edgeW = try decodeTileArray(forKey: .edgeW)
        self.cornerNE = try decodeTileArray(forKey: .cornerNE)
        self.cornerNW = try decodeTileArray(forKey: .cornerNW)
        self.cornerSE = try decodeTileArray(forKey: .cornerSE)
        self.cornerSW = try decodeTileArray(forKey: .cornerSW)
        self.innerCornerNE = try decodeTileArray(forKey: .innerCornerNE)
        self.innerCornerNW = try decodeTileArray(forKey: .innerCornerNW)
        self.innerCornerSE = try decodeTileArray(forKey: .innerCornerSE)
        self.innerCornerSW = try decodeTileArray(forKey: .innerCornerSW)
        self.transitionN = try decodeTileArray(forKey: .transitionN)
        self.transitionS = try decodeTileArray(forKey: .transitionS)
        self.transitionE = try decodeTileArray(forKey: .transitionE)
        self.transitionW = try decodeTileArray(forKey: .transitionW)
        self.transitionNE = try decodeTileArray(forKey: .transitionNE)
        self.transitionNW = try decodeTileArray(forKey: .transitionNW)
        self.transitionSE = try decodeTileArray(forKey: .transitionSE)
        self.transitionSW = try decodeTileArray(forKey: .transitionSW)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(base, forKey: .base)
        try container.encodeIfPresent(edgeN, forKey: .edgeN)
        try container.encodeIfPresent(edgeS, forKey: .edgeS)
        try container.encodeIfPresent(edgeE, forKey: .edgeE)
        try container.encodeIfPresent(edgeW, forKey: .edgeW)
        try container.encodeIfPresent(cornerNE, forKey: .cornerNE)
        try container.encodeIfPresent(cornerNW, forKey: .cornerNW)
        try container.encodeIfPresent(cornerSE, forKey: .cornerSE)
        try container.encodeIfPresent(cornerSW, forKey: .cornerSW)
        try container.encodeIfPresent(innerCornerNE, forKey: .innerCornerNE)
        try container.encodeIfPresent(innerCornerNW, forKey: .innerCornerNW)
        try container.encodeIfPresent(innerCornerSE, forKey: .innerCornerSE)
        try container.encodeIfPresent(innerCornerSW, forKey: .innerCornerSW)
        try container.encodeIfPresent(transitionN, forKey: .transitionN)
        try container.encodeIfPresent(transitionS, forKey: .transitionS)
        try container.encodeIfPresent(transitionE, forKey: .transitionE)
        try container.encodeIfPresent(transitionW, forKey: .transitionW)
        try container.encodeIfPresent(transitionNE, forKey: .transitionNE)
        try container.encodeIfPresent(transitionNW, forKey: .transitionNW)
        try container.encodeIfPresent(transitionSE, forKey: .transitionSE)
        try container.encodeIfPresent(transitionSW, forKey: .transitionSW)
    }
    
    private enum CodingKeys: String, CodingKey {
        case base, edgeN, edgeS, edgeE, edgeW
        case cornerNE, cornerNW, cornerSE, cornerSW
        case innerCornerNE, innerCornerNW, innerCornerSE, innerCornerSW
        case transitionN, transitionS, transitionE, transitionW
        case transitionNE, transitionNW, transitionSE, transitionSW
    }
}

/// Helper type to decode either a string or an object with tile_id and description
private struct TileIDOrObject: Codable {
    let tile_id: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as a string first
        if let stringValue = try? container.decode(String.self) {
            self.tile_id = stringValue
            return
        }
        
        // If that fails, try to decode as an object
        let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.tile_id = try objectContainer.decode(String.self, forKey: .tile_id)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tile_id)
    }
    
    private enum CodingKeys: String, CodingKey {
        case tile_id
    }
}

struct GroundTileConfig: Codable {
    // Legacy support - flat arrays for backward compatibility
    let water: [String]?  // GID specs for water tiles (optional, for backward compat)
    let grass: [String]?  // GID specs for grass tiles (optional, for backward compat)
    let dirt: [String]?   // GID specs for dirt tiles (optional, for backward compat)
    let stone: [String]?  // GID specs for stone tiles (optional, for backward compat)
    
    // New variant-based configuration (optional - falls back to flat arrays if not provided)
    let waterVariants: TileVariantConfig?  // Water tile variants
    let grassVariants: TileVariantConfig?  // Grass tile variants
    let dirtVariants: TileVariantConfig?   // Dirt tile variants
    let stoneVariants: TileVariantConfig?  // Stone tile variants
    
    // Decoration tiles (placed on top of terrain)
    let decorations: [TerrainDecorationConfig]?  // Optional terrain decorations
    
    // Custom decoder to handle both string and object formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode arrays that can contain either strings or objects
        if let waterArray = try? container.decode([TileIDOrObject].self, forKey: .water) {
            self.water = waterArray.map { $0.tile_id }
        } else {
            self.water = try? container.decode([String].self, forKey: .water)
        }
        
        if let grassArray = try? container.decode([TileIDOrObject].self, forKey: .grass) {
            self.grass = grassArray.map { $0.tile_id }
        } else {
            self.grass = try? container.decode([String].self, forKey: .grass)
        }
        
        if let dirtArray = try? container.decode([TileIDOrObject].self, forKey: .dirt) {
            self.dirt = dirtArray.map { $0.tile_id }
        } else {
            self.dirt = try? container.decode([String].self, forKey: .dirt)
        }
        
        if let stoneArray = try? container.decode([TileIDOrObject].self, forKey: .stone) {
            self.stone = stoneArray.map { $0.tile_id }
        } else {
            self.stone = try? container.decode([String].self, forKey: .stone)
        }
        
        // Decode variant configs (these also need to handle mixed formats)
        self.waterVariants = try? container.decode(TileVariantConfig.self, forKey: .waterVariants)
        self.grassVariants = try? container.decode(TileVariantConfig.self, forKey: .grassVariants)
        self.dirtVariants = try? container.decode(TileVariantConfig.self, forKey: .dirtVariants)
        self.stoneVariants = try? container.decode(TileVariantConfig.self, forKey: .stoneVariants)
        
        self.decorations = try? container.decode([TerrainDecorationConfig].self, forKey: .decorations)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(water, forKey: .water)
        try container.encodeIfPresent(grass, forKey: .grass)
        try container.encodeIfPresent(dirt, forKey: .dirt)
        try container.encodeIfPresent(stone, forKey: .stone)
        try container.encodeIfPresent(waterVariants, forKey: .waterVariants)
        try container.encodeIfPresent(grassVariants, forKey: .grassVariants)
        try container.encodeIfPresent(dirtVariants, forKey: .dirtVariants)
        try container.encodeIfPresent(stoneVariants, forKey: .stoneVariants)
        try container.encodeIfPresent(decorations, forKey: .decorations)
    }
    
    private enum CodingKeys: String, CodingKey {
        case water, grass, dirt, stone
        case waterVariants, grassVariants, dirtVariants, stoneVariants
        case decorations
    }
}

/// Configuration for terrain decorations (placed on top of terrain tiles)
struct TerrainDecorationConfig: Codable {
    let terrainTypes: [String]  // Which terrain types can have this decoration (e.g., ["grass", "dirt"])
    let tileGIDs: [String]      // GID specs for decoration tiles
    let density: Double         // Probability of decoration appearing (0.0-1.0)
    let allowOnEdges: Bool?     // Whether decoration can appear on edge tiles (default: false)
}

struct EntityConfig: Codable {
    let treeDensity: Double  // Percentage of tiles that have trees (0.0-1.0)
    let rockDensity: Double  // Percentage of tiles that have rocks (0.0-1.0)
    let treePrefabs: [String]  // List of tree prefab IDs to use
    let rockPrefabs: [String]   // List of rock prefab IDs to use
    let decorationDensity: Double?  // Optional: decorations density
    let decorationPrefabs: [String]?  // Optional: decoration prefab IDs
    let chests: [ChestSpawnConfig]?  // Optional: chests to spawn on map
    let treeBlockedTerrainTypes: [String]?  // Optional: terrain types where trees cannot spawn (e.g., ["water", "stone"])
    let rockBlockedTerrainTypes: [String]?  // Optional: terrain types where rocks cannot spawn
}

struct ChestSpawnConfig: Codable {
    let chestId: String  // Chest prefab ID (from chests.json)
    let count: Int  // Number of this chest type to spawn per map
    let spawnDensity: Double?  // Optional: override density (alternative to count)
    let blockedTerrainTypes: [String]?  // Optional: terrain types where this chest cannot spawn (e.g., ["water"])
}

struct EnemyConfig: Codable {
    let spawnRate: Double  // Probability of enemy spawn per tile (0.0-1.0)
    let types: [String]    // Enemy type names (e.g., ["Goblin", "Orc", "Bandit"])
    let minLevel: Int      // Minimum enemy level
    let maxLevel: Int       // Maximum enemy level
    let blockedTerrainTypes: [String]?  // Optional: terrain types where enemies cannot spawn (e.g., ["water"])
}

struct AnimalConfig: Codable {
    let spawnRate: Double  // Probability of animal spawn per tile (0.0-1.0)
    let types: [String]    // Animal type names (e.g., ["deer", "rabbit", "fox"])
    let friendlyChance: Double?  // Chance animal is friendly (0.0-1.0), nil = all friendly
    let blockedTerrainTypes: [String]?  // Optional: terrain types where animals cannot spawn (e.g., ["water"])
}

struct WaterFeatureConfig: Codable {
    let type: String  // "none", "rivers", "lakes", "islands", "ocean"
    let density: String?  // "low", "medium", "high" (optional)
}

struct ExitConfig: Codable {
    let hasExit: Bool  // Whether this world has exits
    let exits: [ExitDefinition]?  // Array of exit definitions (each exit can go to different worlds)
    // Legacy support - these are used if exits array is not provided
    let exitTiles: [ExitTileConfig]?  // Optional: specific exit tile positions (relative to entry point)
    let defaultExitOffset: ExitOffset?  // Optional: default exit position relative to entry (if exitTiles not specified)
}

struct ExitDefinition: Codable {
    let x: Int  // X offset in tiles from entry point (negative = west, positive = east)
    let y: Int  // Y offset in tiles from entry point (negative = south, positive = north)
    let tileGID: String?  // Optional: specific tile GID to use for exit (e.g., "exterior-123")
    let targetPrefabFile: String?  // Optional: which prefab file to load when exit is hit (e.g., "prefabs_desert"). If nil, returns to TMX map
    let targetEntryOffset: ExitOffset?  // Optional: where to spawn in the target world (relative to its entry point)
    // TMX map return options (only used when targetPrefabFile is nil)
    let targetTmxFile: String?  // Optional: which TMX file to return to (e.g., "Exterior"). If nil, uses current TMX file
    let targetDoorId: String?  // Optional: which door/exit ID to use in the target TMX file. If nil, uses entry position
}

struct ExitTileConfig: Codable {
    let x: Int  // X offset in tiles from entry point (negative = west, positive = east)
    let y: Int  // Y offset in tiles from entry point (negative = south, positive = north)
    let tileGID: String?  // Optional: specific tile GID to use for exit (e.g., "exterior-123")
}

struct ExitOffset: Codable {
    let x: Int  // X offset in tiles from entry point
    let y: Int  // Y offset in tiles from entry point
}
