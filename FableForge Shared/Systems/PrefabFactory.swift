//
//  PrefabFactory.swift
//  FableForge Shared
//
//  Factory for spawning prefab entities (trees, rocks, buildings, etc.)
//

import Foundation
import SpriteKit

// MARK: - CGPoint and CGSize Codable Extensions
// These MUST be defined at the top so they're available for all structs

extension CGPoint: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        self.init(x: x, y: y)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
    
    private enum CodingKeys: String, CodingKey {
        case x, y
    }
}

extension CGSize: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(width: width, height: height)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
    
    private enum CodingKeys: String, CodingKey {
        case width, height
    }
}

// MARK: - Terrain Types

enum TerrainType {
    case water
    case grass
    case dirt
    case stone
}

// MARK: - Ground Tile GIDs

/// Ground tile GID configuration struct (top-level for accessibility)
struct GroundTileGIDs {
    // Ground tile GIDs - use simple format: "tileset-localIndex" or direct GID number
    // 
    // FORMAT OPTIONS:
    // 1. "exterior-0" → Looks up exterior tileset (firstGID=757), adds 0 → GID 757
    // 2. "exterior-78" → Looks up exterior tileset, adds 78 → GID 835
    // 3. "757" or 757 → Uses GID directly (no lookup needed)
    //
    // HOW TO USE:
    // In Tiled, look at the tileset panel - see the local index (0, 1, 2, ...)
    // Use format: "tilesetName-localIndex"
    // Example: If exterior tileset shows index 0 → use "exterior-0"
    //          If exterior tileset shows index 78 → use "exterior-78"
    
    // Legacy flat arrays (for backward compatibility)
    let water: [String]
    let grass: [String]
    let dirt: [String]
    let stone: [String]
    
    // Variant-based configuration (optional - falls back to flat arrays if not provided)
    let waterVariants: TileVariantConfig?
    let grassVariants: TileVariantConfig?
    let dirtVariants: TileVariantConfig?
    let stoneVariants: TileVariantConfig?
    
    // Helper initializer to create from world config
    init(water: [String] = [], grass: [String] = [], dirt: [String] = [], stone: [String] = [],
         waterVariants: TileVariantConfig? = nil,
         grassVariants: TileVariantConfig? = nil,
         dirtVariants: TileVariantConfig? = nil,
         stoneVariants: TileVariantConfig? = nil) {
        self.water = water
        self.grass = grass
        self.dirt = dirt
        self.stone = stone
        self.waterVariants = waterVariants
        self.grassVariants = grassVariants
        self.dirtVariants = dirtVariants
        self.stoneVariants = stoneVariants
    }
    
    // Default initializer (uses default values)
    init() {
        self.water = ["exterior-257"]
        self.grass = ["exterior-257"]
        self.dirt = ["exterior-357"]
        self.stone = ["exterior-852", "exterior-853", "exterior-839"]
        self.waterVariants = nil
        self.grassVariants = nil
        self.dirtVariants = nil
        self.stoneVariants = nil
    }
    
    // Helper to get variant config for a terrain type
    func getVariantConfig(for terrainType: TerrainType) -> TileVariantConfig? {
        switch terrainType {
        case .water: return waterVariants
        case .grass: return grassVariants
        case .dirt: return dirtVariants
        case .stone: return stoneVariants
        }
    }
    
    /// Convert a tile specifier to actual GID
    /// Supports: "tileset-localIndex" format, "atlasName-frameNumber" format, or direct GID number (as string or int)
    /// For sprite atlases, this returns nil (handled separately in chunk rendering)
    private func parseTileSpec(_ spec: String) -> Int? {
        // Check if it's "tileset-localIndex" or "atlasName-frameNumber" format
        if let dashIndex = spec.firstIndex(of: "-") {
            let name = String(spec[..<dashIndex])
            guard let index = Int(String(spec[spec.index(after: dashIndex)...])) else {
                print("⚠️ PrefabFactory: Invalid local index in '\(spec)'")
                return nil
            }
            
            // First, try to find a Tiled tileset by name
            let tilesets = TileManager.shared.getTiledTilesets()
            if let tileset = tilesets.first(where: { $0.name == name }) {
                // It's a Tiled tileset: calculate GID
                let gid = tileset.firstGID + index
                return gid
            }
            
            // If not a tileset, assume it's a sprite atlas (name might have "_atlas" suffix or not)
            // For sprite atlas specs like "grasslands-3" or "grasslands_atlas-3", we can't convert to GID
            // Return nil to indicate it's a sprite atlas spec (handled separately in chunk rendering)
            // The system will use the original spec string for sprite atlas tiles
            return nil
        }
        
        // Otherwise, treat as direct GID number
        return Int(spec)
    }
    
    /// Store tile specs for sprite atlases (since they can't be converted to GIDs)
    /// Maps original spec string to itself for sprite atlas handling
    private var spriteAtlasSpecs: Set<String> = []
    
    /// Check if a spec is a sprite atlas spec (not a GID)
    func isSpriteAtlasSpec(_ spec: String) -> Bool {
        if let dashIndex = spec.firstIndex(of: "-") {
            let name = String(spec[..<dashIndex])
            // Check if it's NOT a Tiled tileset (then it might be a sprite atlas)
            let tilesets = TileManager.shared.getTiledTilesets()
            if tilesets.contains(where: { $0.name == name }) {
                return false  // It's a tileset
            }
            // If name doesn't match a tileset, assume it's a sprite atlas
            return !name.isEmpty && Int(name) == nil  // Not a direct GID number
        }
        return false  // Direct GID number
    }
    
    /// Get a random GID for a terrain type using the provided RNG
    func randomGID(for terrainType: TerrainType, using rng: inout SeededRandomNumberGenerator) -> Int {
        let specs: [String]
        switch terrainType {
        case .water:
            specs = water
        case .grass:
            specs = grass
        case .dirt:
            specs = dirt
        case .stone:
            specs = stone
        }
        
        // Use seeded random to pick from available specs
        guard !specs.isEmpty else { return 757 }  // Fallback to exterior-0
        let index = Int.random(in: 0..<specs.count, using: &rng)
        
        // Parse the spec to get actual GID
        let selectedSpec = specs[index]
        if let gid = parseTileSpec(selectedSpec) {
            return gid
        }
        
        // Fallback if parsing fails
        print("⚠️ PrefabFactory: Failed to parse tile spec '\(selectedSpec)' for \(terrainType), using fallback GID 757")
        return 757
    }
    
    /// Resolve a tile spec that might be a class name to an actual tile spec
    /// Supports: "className", "tilesetName-className", or "tilesetName-localID" formats
    /// If the spec is a class name, looks it up in TileManager and prefers consecutive tiles
    /// lastUsedTileID: Optional context for consecutive tile selection (local tile ID within tileset)
    /// Returns the resolved spec or the original spec if it's already a valid spec
    private func resolveTileSpec(_ spec: String, lastUsedTileID: Int? = nil, using rng: inout SeededRandomNumberGenerator) -> String? {
        // Check if it's a class name format: "className" or "tilesetName-className"
        // A class name spec is one that:
        // 1. Contains a dash but the part after dash is not a number (e.g., "terrain1-grass_full")
        // 2. OR has no dash and is not a number (e.g., "grass_full")
        
        if let dashIndex = spec.firstIndex(of: "-") {
            let tilesetName = String(spec[..<dashIndex])
            let afterDash = String(spec[spec.index(after: dashIndex)...])
            
            // If after dash is a number, it's already a valid spec (e.g., "terrain1-445")
            if Int(afterDash) != nil {
                return spec
            }
            
            // Otherwise, it's a class name (e.g., "terrain1-grass_full")
            // Extract last used tile ID from context if available
            if let resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(spec, lastUsedTileID: lastUsedTileID, using: &rng) {
                return resolvedSpec
            }
            return nil
        } else {
            // No dash - check if it's a number (direct GID) or class name
            if Int(spec) != nil {
                // It's a direct GID number
                return spec
            }
            
            // It's a class name without tileset prefix (e.g., "grass_full")
            // Try to resolve as class name (searches all tilesets)
            if let resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(spec, lastUsedTileID: lastUsedTileID, using: &rng) {
                return resolvedSpec
            }
            return nil
        }
    }
    
    /// Extract tileset name and local tile ID from a tile spec
    /// Returns (tilesetName, localTileID) or nil if parsing fails
    private func parseTileSpecComponents(_ spec: String) -> (tilesetName: String, localTileID: Int)? {
        guard let dashIndex = spec.firstIndex(of: "-") else { return nil }
        let tilesetName = String(spec[..<dashIndex])
        guard let localTileID = Int(String(spec[spec.index(after: dashIndex)...])) else { return nil }
        return (tilesetName, localTileID)
    }
    
    /// Get a tile spec string for a specific terrain type and variant
    /// Returns the tile spec string (e.g., "grasslands_atlas-3" or "exterior-257")
    /// Supports class names (e.g., "grass_full" or "terrain1-grass_full") which are resolved to actual tile specs
    /// lastUsedTileSpec: Optional previous tile spec to maintain visual continuity (e.g., "terrain1-445")
    func getTileSpec(for terrainType: TerrainType, variant: TileVariant, lastUsedTileSpec: String? = nil, using rng: inout SeededRandomNumberGenerator) -> String? {
        // Extract last used tile ID from context if available
        var lastUsedTileID: Int? = nil
        if let lastSpec = lastUsedTileSpec, let components = parseTileSpecComponents(lastSpec) {
            // Check if last used tile is from the same tileset we might use
            let tilesets = TileManager.shared.getTiledTilesets()
            if let tileset = tilesets.first(where: { $0.name == components.tilesetName }) {
                lastUsedTileID = components.localTileID
            }
        }
        
        // For .base variant, prefer the flat array first, then variant-specific base array
        // For all other variants, prefer variant-specific arrays, then fall back to flat array
        
        if variant == .base {
            // For base tiles, use flat array first (more common case)
            let specs: [String]
            switch terrainType {
            case .water: specs = water
            case .grass: specs = grass
            case .dirt: specs = dirt
            case .stone: specs = stone
            }
            
            if !specs.isEmpty {
                let index = Int.random(in: 0..<specs.count, using: &rng)
                let selectedSpec = specs[index]
                // Resolve class names if needed, maintaining continuity
                return resolveTileSpec(selectedSpec, lastUsedTileID: lastUsedTileID, using: &rng)
            }
            
            // Fall back to variant-specific base array if flat array is empty
            if let variantConfig = getVariantConfig(for: terrainType),
               let baseSpecs = variantConfig.base, !baseSpecs.isEmpty {
                let index = Int.random(in: 0..<baseSpecs.count, using: &rng)
                let selectedSpec = baseSpecs[index]
                // Resolve class names if needed, maintaining continuity
                return resolveTileSpec(selectedSpec, lastUsedTileID: lastUsedTileID, using: &rng)
            }
            
            return nil
        }
        
        // For non-base variants, try variant-specific spec first
        if let variantConfig = getVariantConfig(for: terrainType) {
            let specs: [String]?
            
            // Get specs for the specific variant
            switch variant {
            case .base: specs = nil  // Already handled above
            case .edgeN: specs = variantConfig.edgeN
            case .edgeS: specs = variantConfig.edgeS
            case .edgeE: specs = variantConfig.edgeE
            case .edgeW: specs = variantConfig.edgeW
            case .cornerNE: specs = variantConfig.cornerNE
            case .cornerNW: specs = variantConfig.cornerNW
            case .cornerSE: specs = variantConfig.cornerSE
            case .cornerSW: specs = variantConfig.cornerSW
            case .innerCornerNE: specs = variantConfig.innerCornerNE
            case .innerCornerNW: specs = variantConfig.innerCornerNW
            case .innerCornerSE: specs = variantConfig.innerCornerSE
            case .innerCornerSW: specs = variantConfig.innerCornerSW
            case .transitionN: specs = variantConfig.transitionN
            case .transitionS: specs = variantConfig.transitionS
            case .transitionE: specs = variantConfig.transitionE
            case .transitionW: specs = variantConfig.transitionW
            case .transitionNE: specs = variantConfig.transitionNE
            case .transitionNW: specs = variantConfig.transitionNW
            case .transitionSE: specs = variantConfig.transitionSE
            case .transitionSW: specs = variantConfig.transitionSW
            }
            
            // If we have variant-specific specs, use them
            if let variantSpecs = specs, !variantSpecs.isEmpty {
                let index = Int.random(in: 0..<variantSpecs.count, using: &rng)
                let selectedSpec = variantSpecs[index]
                // Resolve class names if needed, maintaining continuity
                return resolveTileSpec(selectedSpec, lastUsedTileID: lastUsedTileID, using: &rng)
            }
        }
        
        // Fall back to base terrain type (flat array) for non-base variants
        let specs: [String]
        switch terrainType {
        case .water: specs = water
        case .grass: specs = grass
        case .dirt: specs = dirt
        case .stone: specs = stone
        }
        
        guard !specs.isEmpty else { return nil }
        let index = Int.random(in: 0..<specs.count, using: &rng)
        let selectedSpec = specs[index]
        // Resolve class names if needed, maintaining continuity
        return resolveTileSpec(selectedSpec, lastUsedTileID: lastUsedTileID, using: &rng)
    }
    
    /// Get a GID for a specific terrain type and variant
    /// Note: For sprite atlas specs, returns nil (use getTileSpec() instead)
    func getGID(for terrainType: TerrainType, variant: TileVariant, using rng: inout SeededRandomNumberGenerator) -> Int? {
        // Get tile spec first
        guard let spec = getTileSpec(for: terrainType, variant: variant, using: &rng) else {
            return nil
        }
        
        // Try to parse as GID
        return parseTileSpec(spec)
    }
}

// MARK: - Prefab Definitions

// JSON-compatible collision spec (defined outside class for use in JSON parsing)
struct CollisionSpec: Codable {
    let type: String  // "rectangle", "circle", or "none"
    let size: CGSize
}

// MARK: - Enemy, Animal, NPC Prefab Definitions

/// Prefab part for visual representation (supports low/high layers)
struct EntityPrefabPart: Codable {
    let layer: String  // "low" (rendered below player) or "high" (rendered above player)
    let tileGrid: [[String?]]  // 2D grid of GID specs (supports "tileset-localIndex" format)
    let offset: CGPoint  // Offset from entity center
    let size: CGSize  // Size of this part
    let zOffset: CGFloat  // Z-offset relative to base z-position
    let tileSize: CGFloat  // Size of individual tiles in the grid
}

/// Enemy prefab definition (loaded from enemies.json)
struct EnemyPrefab: Codable {
    let id: String  // Unique identifier (e.g., "goblin_01", "orc_warrior")
    let name: String  // Display name
    let description: String?  // Description for AI parsing
    let parts: [EntityPrefabPart]  // Visual parts (low/high layers)
    let size: CGSize  // Overall entity size
    let hitPoints: Int  // Maximum HP
    let attackPoints: Int  // Attack bonus/damage
    let defensePoints: Int  // Armor class/defense
    let energyPoints: Int?  // Energy/stamina (optional)
    let manaPoints: Int?  // Magic points (optional)
    let ragePoints: Int?  // Rage/fury points (optional)
    let friendPoints: Int?  // Friendliness/friendship (0-100, optional)
    let zOffset: CGFloat  // Base z-offset
    let tileSize: CGFloat  // Tile size for rendering
    let collision: CollisionSpec  // Collision specification
    let zPosition: CGFloat  // Base z-position
    
    // Additional optional properties
    let level: Int?  // Enemy level (optional, defaults to 1)
    let experienceReward: Int?  // XP given on defeat
    let goldReward: Int?  // Gold given on defeat
    let speed: Int?  // Movement speed
    let lootTable: [String]?  // Item IDs that can be dropped (optional)
}

/// Animal prefab definition (loaded from animals.json)
struct AnimalPrefab: Codable {
    let id: String  // Unique identifier (e.g., "wolf_01", "deer_01")
    let name: String  // Display name
    let description: String?  // Description for AI parsing
    let parts: [EntityPrefabPart]  // Visual parts (low/high layers)
    let size: CGSize  // Overall entity size
    let hitPoints: Int  // Maximum HP
    let attackPoints: Int  // Attack bonus/damage
    let defensePoints: Int  // Armor class/defense
    let energyPoints: Int?  // Energy/stamina (optional)
    let manaPoints: Int?  // Magic points (optional)
    let ragePoints: Int?  // Rage/fury points (optional)
    let friendPoints: Int  // Friendliness/friendship (0-100, required for animals)
    let zOffset: CGFloat  // Base z-offset
    let tileSize: CGFloat  // Tile size for rendering
    let collision: CollisionSpec  // Collision specification
    let zPosition: CGFloat  // Base z-position
    
    // Additional optional properties
    let level: Int?  // Animal level (optional, defaults to 1)
    let speed: Int?  // Movement speed
    let requiredBefriendingItem: String?  // Item type needed to befriend (optional)
    let skillIds: [String]?  // Available skill IDs (replaces moves, optional)
    let moves: [String]?  // Legacy: Available combat moves (deprecated, use skillIds instead)
}

/// NPC prefab definition (loaded from npcs.json)
struct NPCPrefab: Codable {
    let id: String  // Unique identifier (e.g., "merchant_01", "guard_01")
    let name: String  // Display name
    let description: String?  // Description for AI parsing
    let parts: [EntityPrefabPart]  // Visual parts (low/high layers)
    let size: CGSize  // Overall entity size
    let hitPoints: Int?  // Maximum HP (optional, NPCs may not fight)
    let attackPoints: Int?  // Attack bonus (optional)
    let defensePoints: Int?  // Armor class (optional)
    let energyPoints: Int?  // Energy/stamina (optional)
    let manaPoints: Int?  // Magic points (optional)
    let ragePoints: Int?  // Rage/fury points (optional)
    let friendPoints: Int  // Friendliness/reputation (0-100, required for NPCs)
    let zOffset: CGFloat  // Base z-offset
    let tileSize: CGFloat  // Tile size for rendering
    let collision: CollisionSpec  // Collision specification
    let zPosition: CGFloat  // Base z-position
    
    // Additional optional properties
    let level: Int?  // NPC level (optional)
    let speed: Int?  // Movement speed
    let dialogueId: String?  // Reference to dialogue tree (optional)
    let faction: String?  // Faction/alignment (optional)
    let quests: [String]?  // Quest IDs this NPC offers (optional)
    let shopItems: [String]?  // Item IDs this NPC sells (optional)
}

// MARK: - Skill Prefab Definitions

/// Skill prefab definition (loaded from skills.json)
/// Skills can be shared between enemies, animals, and players
struct SkillPrefab: Codable {
    let id: String  // Unique identifier (e.g., "bite", "fireball", "heal")
    let name: String  // Display name
    let description: String  // Skill description
    let type: SkillType  // Type of skill (attack, status, heal, etc.)
    let damageMultiplier: Double?  // Damage multiplier (1.0 = normal, 1.5 = 50% more, etc.)
    let baseDamage: Int?  // Base damage amount (alternative to multiplier)
    let energyCost: Int?  // Energy/stamina cost
    let manaCost: Int?  // Mana cost
    let cooldown: Int?  // Cooldown in turns
    let range: Int?  // Range (1 = melee, 5 = ranged, etc.)
    let effects: [SkillEffect]?  // Status effects or other effects
    let targetType: SkillTargetType  // Who can this skill target
    let animationId: String?  // Animation reference (optional)
    
    // Visual representation for skill animations on map
    let parts: [EntityPrefabPart]?  // Optional visual parts for skill animations (multi-tile support)
    let size: CGSize?  // Overall animation size (optional)
    let zPosition: CGFloat?  // Z-position for skill animation (optional)
}

enum SkillType: String, Codable {
    case attack = "attack"  // Physical/magical attack
    case status = "status"  // Status effect (buff/debuff)
    case heal = "heal"  // Healing skill
    case utility = "utility"  // Utility skill (movement, etc.)
}

enum SkillTargetType: String, Codable {
    case `self` = "self"  // Can only target self (backticks needed because self is a Swift keyword)
    case ally = "ally"  // Can target allies
    case enemy = "enemy"  // Can target enemies
    case any = "any"  // Can target anyone
    case area = "area"  // Area of effect
}

struct SkillEffect: Codable {
    let type: String  // Effect type (e.g., "stun", "poison", "buff_attack")
    let duration: Int?  // Duration in turns (nil = permanent until removed)
    let value: Int?  // Effect value (damage per turn, stat bonus, etc.)
    let description: String?  // Effect description
}

// MARK: - Item Prefab Definitions

/// Item prefab definition (loaded from items.json)
struct ItemPrefab: Codable {
    let id: String  // Unique identifier (e.g., "health_potion", "iron_sword")
    let name: String  // Display name
    let description: String  // Item description
    let type: ItemTypeString  // Item type category
    let value: Int  // Gold value
    let stackable: Bool  // Whether item can stack
    let inventorySize: CGSize  // How many inventory slots this item takes (width x height in tiles)
    
    // Visual representation (multi-tile support)
    let parts: [EntityPrefabPart]  // Visual parts for item rendering (supports multi-tile)
    let size: CGSize  // Overall item size
    let zPosition: CGFloat  // Z-position for item rendering
    
    // Legacy support: gid for backwards compatibility (deprecated, use parts instead)
    let gid: String?  // Tile GID spec (supports "tileset-localIndex" format) - DEPRECATED
    
    // Item-specific properties (optional, based on type)
    let weaponData: WeaponData?  // Weapon-specific data
    let armorData: ArmorData?  // Armor-specific data
    let consumableData: ConsumableData?  // Consumable-specific data
    let materialData: MaterialData?  // Material-specific data
}

enum ItemTypeString: String, Codable {
    case weapon = "weapon"
    case armor = "armor"
    case consumable = "consumable"
    case material = "material"
    case befriending = "befriending"
    case misc = "misc"
}

struct WeaponData: Codable {
    let weaponType: String  // "sword", "axe", "bow", etc.
    let damageDie: Int  // Damage die (e.g., 8 for d8)
    let range: Int  // Attack range
    let isMagical: Bool?  // Whether weapon is magical
    let requiredStrength: Int?  // Strength requirement
    let requiredDexterity: Int?  // Dexterity requirement
}

struct ArmorData: Codable {
    let armorType: String  // "light", "medium", "heavy", "shield"
    let armorClass: Int  // AC bonus
    let requiredStrength: Int  // Strength requirement
    let slot: String?  // Equipment slot (e.g., "chest", "head", "legs")
}

struct ConsumableData: Codable {
    let effectType: String  // "heal", "restoreMana", "buff", etc.
    let effectValue: Int  // Effect amount
    let duration: Int?  // Duration in turns (for buffs)
}

struct MaterialData: Codable {
    let materialType: String  // "wood", "stone", "iron", etc.
    let baseValue: Int  // Base gold value
}

// MARK: - Chest Prefab Definitions

/// Loot item entry in a chest's loot table
struct ChestLootItem: Codable {
    let itemId: String  // Item prefab ID (from items.json)
    let dropRate: Double  // Drop rate (0.0-1.0, probability of dropping)
    let minQuantity: Int  // Minimum quantity if item drops
    let maxQuantity: Int  // Maximum quantity if item drops
}

/// Fixed item that always appears in a chest
struct ChestFixedItem: Codable {
    let itemId: String  // Item prefab ID (from items.json)
    let quantity: Int  // Exact quantity of this item
}

/// Rules for random item generation
struct ChestRandomItems: Codable {
    let count: String  // Number of random items to generate, can be "3" or "1-3" (range)
    let categories: [String]?  // Optional: item categories to filter by (e.g., ["consumable", "material"])
    let types: [String]?  // Optional: specific item types to filter by (e.g., ["weapon", "armor"])
    let minValue: Double?  // Optional: minimum item value
    let maxValue: Double?  // Optional: maximum item value
    let excludeItemIds: [String]?  // Optional: item IDs to exclude from random selection
}

/// Chest prefab definition (loaded from chests.json)
/// Chests are map-only entities that contain loot tables and cannot be added to inventory
struct ChestPrefab: Codable {
    let id: String  // Unique identifier (e.g., "chest_wooden_01", "chest_treasure_01")
    let name: String  // Display name
    let description: String?  // Description for AI parsing
    let parts: [EntityPrefabPart]  // Visual parts (supports multi-tile)
    let size: CGSize  // Overall chest size
    let zOffset: CGFloat  // Base z-offset
    let tileSize: CGFloat  // Tile size for rendering
    let collision: CollisionSpec  // Collision specification
    let zPosition: CGFloat  // Base z-position
    
    // Loot configuration - can use any combination of these
    let lootTable: [ChestLootItem]?  // Optional: Items that can drop with drop rates (legacy system)
    let fixedItems: [ChestFixedItem]?  // Optional: Items that always appear in this chest
    let randomItems: ChestRandomItems?  // Optional: Rules for generating random items
    
    let lockLevel: Int?  // Optional lock level (0 = unlocked, 1+ = requires lockpicking skill)
    let requiredKey: String?  // Optional key item ID required to open
}

/// Factory for creating entity sprites and physics bodies from prefabs
class PrefabFactory {
    static let shared = PrefabFactory()
    
    /// Register of available prefabs
    struct PrefabDefinition: Codable {
        let id: String
        let type: ProceduralEntityType
        let description: String?  // Description for AI parsing and map building
        let parts: [PrefabPart]  // Multi-part entities (low layer + high layer)
        let collision: CollisionSpec  // Collision specification
        let zPosition: CGFloat  // Base z-position (entitiesBelow vs entitiesAbove handled separately)
        
        // Convert to internal CollisionShape enum
        var collisionShape: CollisionShape {
            switch collision.type {
            case "rectangle":
                return .rectangle(size: collision.size)
            case "circle":
                return .circle(radius: collision.size.width / 2)  // Assume width is diameter
            case "none":
                return .none
            default:
                return .none
            }
        }
    }
    
    struct PrefabPart: Codable {
        let layer: String  // "low" (rendered below player) or "high" (rendered above player)
        let tileGrid: [[String?]]  // 2D grid of GID specs (supports "tileset-localIndex" format)
        // Single tile: [["exterior-100"]] (1x1 grid)
        // Multi-tile: [["exterior-100", "exterior-101"], ["exterior-102", "exterior-103"]] (2x2 grid)
        // nil values in grid mean "skip this tile"
        let assetName: String?  // Asset catalog name (optional, overrides GID if provided)
        let offset: CGPoint  // Offset from entity center (for single-tile) or top-left corner (for multi-tile)
        let size: CGSize  // Size of this part (for single-tile) or bounding box (for multi-tile)
        let zOffset: CGFloat  // Z-offset relative to base z-position
        let tileSize: CGFloat  // Size of individual tiles in the grid (defaults to size if not specified)
    }
    
    enum CollisionShape {
        case rectangle(size: CGSize)
        case circle(radius: CGFloat)
        case none
    }
    
    private var prefabs: [String: PrefabDefinition] = [:]
    private var enemyPrefabs: [String: EnemyPrefab] = [:]
    private var animalPrefabs: [String: AnimalPrefab] = [:]
    private var npcPrefabs: [String: NPCPrefab] = [:]
    private var skillPrefabs: [String: SkillPrefab] = [:]
    private var itemPrefabs: [String: ItemPrefab] = [:]
    private var chestPrefabs: [String: ChestPrefab] = [:]
    private var worldConfig: WorldConfig?  // World configuration from JSON
    
    // Ground tile GID configurations (from exterior tileset: GID range 757-1725)
    // The exterior tileset starts at GID 757 and has 969 tiles (17 columns)
    // To find GIDs: Open Tiled, select a tile from the exterior tileset, check its GID in the properties panel
    private let groundTileGIDs: GroundTileGIDs = GroundTileGIDs()
    
    private var currentPrefabsFile: String = "prefabs_grassland"  // Default to grassland map (without .json extension)
    
    private init() {
        // Try to load default map prefabs from Maps/ subdirectory
        var loaded = false
        
        // Try default map file (prefabs_grassland.json in Maps/)
        if let url = Bundle.main.url(forResource: currentPrefabsFile, withExtension: "json", subdirectory: "Prefabs/Maps") {
            if loadPrefabsFromJSON(url: url) {
                print("✅ PrefabFactory: Loaded default map prefabs from Maps/\(currentPrefabsFile).json")
                loaded = true
            }
        }
        
        // If that fails, try root Prefabs/ directory
        if !loaded {
            if loadPrefabsFromJSON(fileName: currentPrefabsFile) {
                print("✅ PrefabFactory: Loaded default prefabs from \(currentPrefabsFile).json")
                loaded = true
            }
        }
        
        // Fall back to default hardcoded prefabs if no JSON found
        if !loaded {
            print("⚠️ PrefabFactory: Could not load \(currentPrefabsFile).json from Maps/ or Prefabs/, using default prefabs")
            registerDefaultPrefabs()
        }
        
        // Load enemy, animal, NPC, skill, item, and chest prefabs
        loadEnemyPrefabs()
        loadAnimalPrefabs()
        loadNPCPrefabs()
        loadSkillPrefabs()
        loadItemPrefabs()
        loadChestPrefabs()
    }
    
    /// Reload prefabs from a different JSON file (for switching between worlds)
    /// Looks in Maps/ subdirectory first, then root Prefabs/ directory
    func loadPrefabsFromFile(_ fileName: String) -> Bool {
        // Clear existing prefabs
        let previousCount = prefabs.count
        prefabs.removeAll()
        worldConfig = nil
        
        print("🔄 PrefabFactory: Loading prefabs from '\(fileName).json' (cleared \(previousCount) existing prefabs)")
        
        // Update current file name
        currentPrefabsFile = fileName
        
        // Try to load from Maps/ subdirectory first (for map-specific prefabs)
        if let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "Prefabs/Maps") {
            print("🔍 PrefabFactory: Found file in Maps/ subdirectory: \(url.lastPathComponent)")
            if loadPrefabsFromJSON(url: url) {
                print("✅ PrefabFactory: Reloaded \(prefabs.count) prefabs from Maps/\(fileName).json")
                print("   Loaded prefab IDs: \(prefabs.keys.sorted().joined(separator: ", "))")
                return true
            } else {
                print("⚠️ PrefabFactory: Failed to parse Maps/\(fileName).json")
            }
        } else {
            print("🔍 PrefabFactory: File not found in Maps/ subdirectory, trying root Prefabs/")
        }
        
        // Fall back to root Prefabs/ directory
        if loadPrefabsFromJSON(fileName: fileName) {
            print("✅ PrefabFactory: Reloaded \(prefabs.count) prefabs from \(fileName).json")
            print("   Loaded prefab IDs: \(prefabs.keys.sorted().joined(separator: ", "))")
            return true
        } else {
            print("⚠️ PrefabFactory: Failed to load \(fileName).json from any location, keeping existing prefabs")
            // Re-register default prefabs as fallback
            if prefabs.isEmpty {
                print("⚠️ PrefabFactory: No prefabs loaded, registering default prefabs")
                registerDefaultPrefabs()
            }
            return false
        }
    }
    
    /// Get the current world configuration (loaded from prefabs JSON)
    func getWorldConfig() -> WorldConfig? {
        return worldConfig
    }
    
    /// Get ground tile GIDs configuration
    func getGroundTileGIDs() -> GroundTileGIDs {
        return groundTileGIDs
    }
    
    /// Get enemy prefab by ID
    func getEnemyPrefab(_ id: String) -> EnemyPrefab? {
        return enemyPrefabs[id]
    }
    
    /// Get animal prefab by ID
    func getAnimalPrefab(_ id: String) -> AnimalPrefab? {
        return animalPrefabs[id]
    }
    
    /// Get NPC prefab by ID
    func getNPCPrefab(_ id: String) -> NPCPrefab? {
        return npcPrefabs[id]
    }
    
    /// Get all enemy prefabs
    func getAllEnemyPrefabs() -> [String: EnemyPrefab] {
        return enemyPrefabs
    }
    
    /// Get all animal prefabs
    func getAllAnimalPrefabs() -> [String: AnimalPrefab] {
        return animalPrefabs
    }
    
    /// Get all NPC prefabs
    func getAllNPCPrefabs() -> [String: NPCPrefab] {
        return npcPrefabs
    }
    
    /// Get skill prefab by ID
    func getSkillPrefab(_ id: String) -> SkillPrefab? {
        return skillPrefabs[id]
    }
    
    /// Get item prefab by ID
    func getItemPrefab(_ id: String) -> ItemPrefab? {
        return itemPrefabs[id]
    }
    
    /// Get all skill prefabs
    func getAllSkillPrefabs() -> [String: SkillPrefab] {
        return skillPrefabs
    }
    
    /// Get all item prefabs
    func getAllItemPrefabs() -> [String: ItemPrefab] {
        return itemPrefabs
    }
    
    /// Create sprite nodes for an enemy prefab
    func createEnemySprites(_ prefab: EnemyPrefab, position: CGPoint, rotation: CGFloat = 0) -> [SKSpriteNode] {
        return createEntitySprites(from: prefab.parts, position: position, rotation: rotation, zPosition: prefab.zPosition)
    }
    
    /// Create sprite nodes for an animal prefab
    func createAnimalSprites(_ prefab: AnimalPrefab, position: CGPoint, rotation: CGFloat = 0) -> [SKSpriteNode] {
        return createEntitySprites(from: prefab.parts, position: position, rotation: rotation, zPosition: prefab.zPosition)
    }
    
    /// Create sprite nodes for an NPC prefab
    func createNPCSprites(_ prefab: NPCPrefab, position: CGPoint, rotation: CGFloat = 0) -> [SKSpriteNode] {
        return createEntitySprites(from: prefab.parts, position: position, rotation: rotation, zPosition: prefab.zPosition)
    }
    
    /// Create sprite nodes for a skill prefab animation
    func createSkillSprites(_ prefab: SkillPrefab, position: CGPoint, rotation: CGFloat = 0) -> [SKSpriteNode] {
        guard let parts = prefab.parts else { return [] }
        let zPosition = prefab.zPosition ?? 50.0  // Default skill animation z-position above entities
        return createEntitySprites(from: parts, position: position, rotation: rotation, zPosition: zPosition)
    }
    
    /// Create sprite nodes for an item prefab
    func createItemSprites(_ prefab: ItemPrefab, position: CGPoint, rotation: CGFloat = 0) -> [SKSpriteNode] {
        return createEntitySprites(from: prefab.parts, position: position, rotation: rotation, zPosition: prefab.zPosition)
    }
    
    /// Get chest prefab by ID
    func getChestPrefab(_ id: String) -> ChestPrefab? {
        return chestPrefabs[id]
    }
    
    /// Get all chest prefabs
    func getAllChestPrefabs() -> [String: ChestPrefab] {
        return chestPrefabs
    }
    
    /// Generate loot from a chest's configuration
    /// Returns an array of Item instances based on fixed items, random items, and loot table
    func generateChestLoot(for chest: ChestPrefab) -> [Item] {
        var loot: [Item] = []
        
        // 1. Add fixed items (always appear)
        if let fixedItems = chest.fixedItems {
            for fixedItem in fixedItems {
                if let itemPrefab = getItemPrefab(fixedItem.itemId) {
                    let item = createItemFromPrefab(itemPrefab, quantity: fixedItem.quantity)
                    loot.append(item)
                } else {
                    print("⚠️ PrefabFactory: Fixed item '\(fixedItem.itemId)' not found in chest '\(chest.id)'")
                }
            }
        }
        
        // 2. Generate random items based on rules
        if let randomRules = chest.randomItems {
            let randomItems = generateRandomItems(rules: randomRules)
            loot.append(contentsOf: randomItems)
        }
        
        // 3. Legacy loot table system (drop rate based)
        if let lootTable = chest.lootTable {
            for lootEntry in lootTable {
                let roll = Double.random(in: 0...1)
                if roll <= lootEntry.dropRate {
                    if let itemPrefab = getItemPrefab(lootEntry.itemId) {
                        let quantity = Int.random(in: lootEntry.minQuantity...lootEntry.maxQuantity)
                        let item = createItemFromPrefab(itemPrefab, quantity: quantity)
                        loot.append(item)
                    } else {
                        print("⚠️ PrefabFactory: Loot table item '\(lootEntry.itemId)' not found in chest '\(chest.id)'")
                    }
                }
            }
        }
        
        return loot
    }
    
    /// Generate random items based on rules
    private func generateRandomItems(rules: ChestRandomItems) -> [Item] {
        var randomLoot: [Item] = []
        
        // Parse count (can be "3" or "1-3")
        let count: Int
        if let dashIndex = rules.count.firstIndex(of: "-") {
            let minStr = String(rules.count[..<dashIndex])
            let maxStr = String(rules.count[rules.count.index(after: dashIndex)...])
            if let min = Int(minStr), let max = Int(maxStr) {
                count = Int.random(in: min...max)
            } else {
                count = 1
            }
        } else {
            count = Int(rules.count) ?? 1
        }
        
        // Filter available items based on rules
        var eligibleItems: [ItemPrefab] = []
        for (_, itemPrefab) in itemPrefabs {
            // Check category filter (if provided) - categories match ItemTypeString enum values
            if let categories = rules.categories, !categories.isEmpty {
                let itemTypeString = itemPrefab.type.rawValue.lowercased()
                let categoryMatches = categories.contains { $0.lowercased() == itemTypeString }
                if !categoryMatches {
                    continue
                }
            }
            
            // Check type filter (if provided) - types also match ItemTypeString enum values
            if let types = rules.types, !types.isEmpty {
                let itemTypeString = itemPrefab.type.rawValue.lowercased()
                let typeMatches = types.contains { $0.lowercased() == itemTypeString }
                if !typeMatches {
                    continue
                }
            }
            
            // Check value range (if provided)
            if let minValue = rules.minValue, Double(itemPrefab.value) < minValue {
                continue
            }
            if let maxValue = rules.maxValue, Double(itemPrefab.value) > maxValue {
                continue
            }
            
            // Check exclusion list
            if let excludeIds = rules.excludeItemIds, excludeIds.contains(itemPrefab.id) {
                continue
            }
            
            eligibleItems.append(itemPrefab)
        }
        
        // Randomly select items
        guard !eligibleItems.isEmpty else {
            print("⚠️ PrefabFactory: No eligible items found for random generation rules")
            return randomLoot
        }
        
        for _ in 0..<count {
            if let randomPrefab = eligibleItems.randomElement() {
                let item = createItemFromPrefab(randomPrefab, quantity: 1)
                randomLoot.append(item)
            }
        }
        
        return randomLoot
    }
    
    /// Create an Item instance from an ItemPrefab
    private func createItemFromPrefab(_ prefab: ItemPrefab, quantity: Int = 1) -> Item {
        // Map item prefab type to ItemType enum
        let itemType: ItemType
        switch prefab.type {
        case .consumable:
            // Try to determine specific consumable type from name/ID
            if prefab.id.contains("health") || prefab.name.lowercased().contains("health") {
                itemType = .healthPotion
            } else {
                itemType = .food
            }
        case .weapon:
            itemType = .weapon
        case .armor:
            itemType = .armor
        case .material:
            // Try to determine material type
            if prefab.id.contains("wood") || prefab.name.lowercased().contains("wood") {
                itemType = .wood
            } else if prefab.id.contains("stone") || prefab.name.lowercased().contains("stone") {
                itemType = .stone
            } else if prefab.id.contains("iron") || prefab.name.lowercased().contains("iron") {
                itemType = .iron
            } else {
                itemType = .wood  // Default fallback
            }
        case .befriending:
            // Map befriending items
            if prefab.id.contains("meat") || prefab.name.lowercased().contains("meat") {
                itemType = .meat
            } else if prefab.id.contains("honey") || prefab.name.lowercased().contains("honey") {
                itemType = .honey
            } else if prefab.id.contains("berries") || prefab.name.lowercased().contains("berries") {
                itemType = .berries
            } else {
                itemType = .food  // Default fallback
            }
        default:
            itemType = .food  // Default fallback
        }
        
        // Parse GID if available
        let gid: Int? = parseGIDSpec(prefab.gid)
        
        let item = Item(
            name: prefab.name,
            type: itemType,
            quantity: quantity,
            description: prefab.description ?? "",
            value: prefab.value,
            gid: gid,
            stackable: prefab.stackable
        )
        
        return item
    }
    
    /// Get a prefab definition by ID (for procedural entities like trees, rocks, etc.)
    func getPrefab(_ id: String) -> PrefabDefinition? {
        let baseId = id.replacingOccurrences(of: "_low", with: "")
            .replacingOccurrences(of: "_high", with: "")
        return prefabs[baseId]
    }
    
    /// Create sprite nodes for a chest prefab
    func createChestSprites(_ prefab: ChestPrefab, position: CGPoint, rotation: CGFloat = 0, tileSize: CGFloat = 32.0) -> [SKSpriteNode] {
        return createEntitySprites(from: prefab.parts, position: position, rotation: rotation, zPosition: prefab.zPosition, tileSize: tileSize)
    }
    
    /// Helper method to create sprites from entity prefab parts
    private func createEntitySprites(from parts: [EntityPrefabPart], position: CGPoint, rotation: CGFloat, zPosition: CGFloat, tileSize: CGFloat = 32.0) -> [SKSpriteNode] {
        var sprites: [SKSpriteNode] = []
        var rng = SeededRandomNumberGenerator(seed: UInt64(Date().timeIntervalSince1970))
        
        for part in parts {
            let sourceTileSize = part.tileSize > 0 ? part.tileSize : 16.0
            let scaleFactor = tileSize / sourceTileSize
            
            // Track last used tile info for class name continuity (same tileset, sequential tiles)
            var lastUsedTilesetName: String? = nil
            var lastUsedTileID: Int? = nil
            var lastUsedClassName: String? = nil  // Track class name to reset continuity when it changes
            
            for (rowIndex, row) in part.tileGrid.enumerated() {
                for (colIndex, gidSpec) in row.enumerated() {
                    guard let gidSpec = gidSpec else { continue }
                    
                    // Try to create sprite directly (handles both GIDs and sprite atlases)
                    let sprite: SKSpriteNode?
                    
                    // Check if this is a class name
                    let isClassName = isClassSpec(gidSpec)
                    
                    if isClassName {
                        // Reset continuity if class name changed
                        if let lastClassName = lastUsedClassName, lastClassName != gidSpec {
                            lastUsedTilesetName = nil
                            lastUsedTileID = nil
                        }
                        lastUsedClassName = gidSpec
                        
                        // Resolve class name with continuity tracking
                        let resolvedSpec: String?
                        if let tilesetName = lastUsedTilesetName, let lastID = lastUsedTileID {
                            // Try to maintain continuity with last used tile (same class)
                            resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: lastID, using: &rng)
                        } else {
                            // First tile in grid or class name changed, no continuity context
                            resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: nil, using: &rng)
                        }
                        
                        if let resolved = resolvedSpec {
                            // Extract tileset name and local tile ID from resolved spec for next iteration
                            if let dashIndex = resolved.firstIndex(of: "-") {
                                lastUsedTilesetName = String(resolved[..<dashIndex])
                                if let tileID = Int(String(resolved[resolved.index(after: dashIndex)...])) {
                                    lastUsedTileID = tileID
                                }
                            }
                            
                            // Create sprite from resolved spec - create at source size then scale
                            if let directGID = Int(resolved) {
                                if let createdSprite = TileManager.shared.createSprite(for: directGID, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                    if scaleFactor != 1.0 {
                                        createdSprite.xScale = scaleFactor
                                        createdSprite.yScale = scaleFactor
                                    }
                                    sprite = createdSprite
                                } else {
                                    sprite = nil
                                }
                            } else {
                                if let createdSprite = createSpriteFromGIDSpec(resolved, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                    if scaleFactor != 1.0 {
                                        createdSprite.xScale = scaleFactor
                                        createdSprite.yScale = scaleFactor
                                    }
                                    sprite = createdSprite
                                } else {
                                    sprite = nil
                                }
                            }
                        } else {
                            // Class name resolution failed - try as regular GID spec as fallback
                            if let createdSprite = createSpriteFromGIDSpec(gidSpec, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                if scaleFactor != 1.0 {
                                    createdSprite.xScale = scaleFactor
                                    createdSprite.yScale = scaleFactor
                                }
                                sprite = createdSprite
                            } else {
                                sprite = nil
                            }
                        }
                    } else {
                        // Not a class name, handle as regular GID spec
                        if let directGID = Int(gidSpec) {
                            // Direct GID number
                            if let createdSprite = TileManager.shared.createSprite(for: directGID, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                if scaleFactor != 1.0 {
                                    createdSprite.xScale = scaleFactor
                                    createdSprite.yScale = scaleFactor
                                }
                                sprite = createdSprite
                            } else {
                                sprite = nil
                            }
                        } else {
                            // Try sprite atlas or parsed GID
                            if let createdSprite = createSpriteFromGIDSpec(gidSpec, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                if scaleFactor != 1.0 {
                                    createdSprite.xScale = scaleFactor
                                    createdSprite.yScale = scaleFactor
                                }
                                sprite = createdSprite
                            } else {
                                sprite = nil
                            }
                        }
                    }
                    
                    guard let sprite = sprite else {
                        print("⚠️ PrefabFactory: Failed to create sprite for GID spec '\(gidSpec)'")
                        continue
                    }
                    
                    // Calculate position for this tile - use tileSize for spacing since sprites are scaled
                    let tileOffsetX = CGFloat(colIndex) * tileSize
                    let tileOffsetY = -CGFloat(rowIndex) * tileSize
                    
                    sprite.position = CGPoint(
                        x: position.x + part.offset.x + tileOffsetX,
                        y: position.y + part.offset.y + tileOffsetY
                    )
                    sprite.zPosition = zPosition + part.zOffset
                    sprite.anchorPoint = CGPoint(x: 0, y: 1)
                    sprite.zRotation = rotation
                    
                    sprites.append(sprite)
                }
            }
        }
        
        return sprites
    }
    
    /// Register a prefab definition
    func registerPrefab(_ prefab: PrefabDefinition) {
        prefabs[prefab.id] = prefab
    }
    
    /// Create sprite nodes for an entity, separated by layer
    /// Returns a tuple: (lowLayerSprites, highLayerSprites)
    func createEntitySpritesByLayer(_ entity: ProceduralEntity, tileSize: CGFloat) -> (low: [SKSpriteNode], high: [SKSpriteNode]) {
        // Handle chests separately (they're stored in chestPrefabs, not prefabs)
        if entity.type == .chest {
            if let chestPrefab = chestPrefabs[entity.prefabId] {
                let allSprites = createChestSprites(chestPrefab, position: entity.position, rotation: entity.rotation, tileSize: tileSize)
                // Chests typically only have low layer parts, but check anyway
                var lowSprites: [SKSpriteNode] = []
                var highSprites: [SKSpriteNode] = []
                for part in chestPrefab.parts {
                    let partSprites = createSpritesForPart(part, entity: entity, tileSize: tileSize)
                    if part.layer == "high" {
                        highSprites.append(contentsOf: partSprites)
                    } else {
                        lowSprites.append(contentsOf: partSprites)
                    }
                }
                return (low: lowSprites, high: highSprites)
            } else {
                print("⚠️ PrefabFactory: Unknown chest prefab ID '\(entity.prefabId)'")
                let fallback = createFallbackSprite(entity: entity, tileSize: tileSize)
                return (low: fallback, high: [])
            }
        }
        
        // Determine which prefab to use based on prefabId
        // Handle suffix stripping (e.g., "tree_oak_01_low" -> "tree_oak_01")
        let basePrefabId = entity.prefabId.replacingOccurrences(of: "_low", with: "")
            .replacingOccurrences(of: "_high", with: "")
        
        guard let prefab = prefabs[basePrefabId] else {
            print("⚠️ PrefabFactory: Unknown prefab ID '\(basePrefabId)' (available: \(prefabs.keys.sorted().joined(separator: ", ")))")
            let fallback = createFallbackSprite(entity: entity, tileSize: tileSize)
            return (low: fallback, high: [])
        }
        
        var lowSprites: [SKSpriteNode] = []
        var highSprites: [SKSpriteNode] = []
        
        // Track shared starting column across all parts for vertical alignment
        // (e.g., trunk and canopy should align to the same column)
        var sharedStartingColumn: Int? = nil
        
        // Always render all parts and separate them by their actual layer
        // This ensures that entities with both low and high parts are properly split
        // regardless of which container they're being rendered in
        for part in prefab.parts {
            // Pass shared starting column to ensure parts align vertically
            let (partSprites, usedColumn) = createSpritesForPartWithColumn(part, entity: entity, tileSize: tileSize, sharedStartingColumn: sharedStartingColumn)
            
            // Store the starting column from first part for subsequent parts
            if sharedStartingColumn == nil, let column = usedColumn {
                sharedStartingColumn = column
            }
            
            // Separate by actual part layer
            // CORRECT: "low" = bottom/trunk parts → go to entitiesAbove (zPosition 110, IN FRONT of player)
            //          "high" = top/canopy parts → go to entitiesBelow (zPosition 40, BEHIND player)
            if part.layer == "high" {
                highSprites.append(contentsOf: partSprites)
            } else {
                // Default to low for "low" layer or any other value
                lowSprites.append(contentsOf: partSprites)
            }
        }
        
        return (low: lowSprites, high: highSprites)
    }
    
    /// Helper to create sprites for a single part (EntityPrefabPart version for chests, enemies, etc.)
    private func createSpritesForPart(_ part: EntityPrefabPart, entity: ProceduralEntity, tileSize: CGFloat) -> [SKSpriteNode] {
        // Convert EntityPrefabPart to PrefabPart format
        let prefabPart = PrefabPart(
            layer: part.layer,
            tileGrid: part.tileGrid,
            assetName: nil,  // EntityPrefabPart doesn't have assetName
            offset: part.offset,
            size: part.size,
            zOffset: part.zOffset,
            tileSize: part.tileSize
        )
        let (sprites, _) = createSpritesForPart(prefabPart, entity: entity, tileSize: tileSize)
        return sprites
    }
    
    /// Helper to create sprites for a single part with column alignment support
    /// Returns (sprites, startingColumnUsed)
    private func createSpritesForPartWithColumn(_ part: PrefabPart, entity: ProceduralEntity, tileSize: CGFloat, sharedStartingColumn: Int?) -> ([SKSpriteNode], Int?) {
        let (sprites, usedColumn) = createSpritesForPart(part, entity: entity, tileSize: tileSize, sharedStartingColumn: sharedStartingColumn)
        return (sprites, usedColumn)
    }
    
    /// Helper to create sprites for a single part (PrefabPart version for map prefabs)
    /// Returns (sprites, startingColumnUsed)
    private func createSpritesForPart(_ part: PrefabPart, entity: ProceduralEntity, tileSize: CGFloat, sharedStartingColumn: Int? = nil) -> ([SKSpriteNode], Int?) {
        var sprites: [SKSpriteNode] = []
        
        // Determine tile size for this part - use part's tileSize if specified, otherwise use world tileSize
        let sourceTileSize = part.tileSize > 0 ? part.tileSize : tileSize
        let partTileSize = sourceTileSize  // Use for grid calculations
        // For tilesets with 16x16 tiles, we need to scale them to match world tile size (32x32)
        let scaleFactor = tileSize / sourceTileSize
        
        // AUTO-EXPAND: If tileGrid has only one entry and it's a class name, automatically expand it to fill the size
        // The existing loop below will handle sequential tile selection from the class
        var grid = part.tileGrid
        let gridHeight = grid.count
        let gridWidth = grid.first?.count ?? 0
        
        // Check if we should auto-expand: single entry that needs multiple tiles based on size
        // For class names, we'll expand them and let the tile selection logic pick appropriate tiles from different rows
        if gridHeight == 1 && gridWidth == 1, let singleEntry = grid[0][0] {
            let requiredCols = Int(part.size.width / partTileSize)
            let requiredRows = Int(part.size.height / partTileSize)
            
            if requiredCols > 1 || requiredRows > 1 {
                // Auto-expand: fill grid with the class name or GID spec
                // The tile selection logic will pick appropriate tiles based on position
                var expandedGrid: [[String?]] = []
                for _ in 0..<requiredRows {
                    var rowEntries: [String?] = []
                    for _ in 0..<requiredCols {
                        rowEntries.append(singleEntry)
                    }
                    expandedGrid.append(rowEntries)
                }
                
                grid = expandedGrid
            }
        }
        
        // Render tileGrid (works for both single-tile [["gid"]] and multi-tile grids)
        let finalGridHeight = grid.count
        guard finalGridHeight > 0 else { return ([], nil) }
        let finalGridWidth = grid.first?.count ?? 0
        guard finalGridWidth > 0 else { return ([], nil) }
        
        // Track last used tile info for class name continuity (same tileset, sequential tiles)
        var lastUsedTilesetName: String? = nil
        var lastUsedTileID: Int? = nil
        var firstTileID: Int? = nil  // Track the very first tile ID for arithmetic-based selection
        var lastUsedClassName: String? = nil  // Track class name to reset continuity when it changes
        var startingColumn: Int? = sharedStartingColumn  // Use shared column if provided, otherwise calculate from first part
        var startingRow: Int? = nil  // Track starting row for proper row mapping
        var rng = SeededRandomNumberGenerator(seed: UInt64(Date().timeIntervalSince1970))
        
        for (rowIndex, row) in grid.enumerated() {
            for (colIndex, gid) in row.enumerated() {
                guard let gidSpec = gid else { continue }  // Skip nil tiles
                
                // Handle "generate" as a special placeholder value
                let sprite: SKSpriteNode
                if gidSpec.lowercased() == "generate" {
                    // Create a placeholder sprite (cyan to indicate it needs a real GID)
                    sprite = SKSpriteNode(color: SKColor.cyan, size: CGSize(width: partTileSize, height: partTileSize))
                    sprite.alpha = 0.5  // Make it semi-transparent to indicate it's a placeholder
                    sprite.colorBlendFactor = 1.0
                    // Note: This is a placeholder - replace "generate" with actual GIDs in the JSON
                } else {
                    // Check if this is a class name (not a direct GID or tileset-localIndex)
                    let isClassName = isClassSpec(gidSpec)
                    
                    if isClassName {
                        // Reset continuity if class name changed
                        if let lastClassName = lastUsedClassName, lastClassName != gidSpec {
                            lastUsedTilesetName = nil
                            lastUsedTileID = nil
                            firstTileID = nil
                            startingColumn = nil
                            startingRow = nil
                        }
                        lastUsedClassName = gidSpec
                        
                        // Get tileset info first
                        let tilesetName: String
                        let className: String
                        if let dashIndex = gidSpec.firstIndex(of: "-") {
                            tilesetName = String(gidSpec[..<dashIndex])
                            className = String(gidSpec[gidSpec.index(after: dashIndex)...])
                        } else {
                            // Find first tileset with this class
                            guard let firstTileset = TileManager.shared.getTiledTilesets().first(where: { $0.classNames[gidSpec] != nil }) else {
                                continue
                            }
                            tilesetName = firstTileset.name
                            className = gidSpec
                        }
                        
                        guard let tileset = TileManager.shared.getTiledTilesets().first(where: { $0.name == tilesetName }) else {
                            continue
                        }
                        
                        // Resolve class name with row and column alignment
                        var resolvedSpec: String?
                        
                        // If we're at the start (row 0, col 0), pick a starting tile and remember its column and row
                        // Use shared column if provided, otherwise calculate from first tile
                        if rowIndex == 0 && colIndex == 0 {
                            if let sharedCol = startingColumn {
                                // Use shared column from another part (e.g., canopy uses trunk's column)
                                print("🌳 Part '\(part.layer)' using shared column: \(sharedCol) from previous part")
                                resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: nil, targetRow: nil, targetColumn: sharedCol, using: &rng)
                                if let resolved = resolvedSpec,
                                   let dashIndex = resolved.firstIndex(of: "-"),
                                   let tileID = Int(String(resolved[resolved.index(after: dashIndex)...])) {
                                    lastUsedTileID = tileID
                                    firstTileID = tileID  // Store first tile ID for arithmetic-based selection
                                    lastUsedTilesetName = tilesetName
                                    let actualColumn = tileID % tileset.columns
                                    let actualRow = tileID / tileset.columns
                                    startingRow = actualRow
                                    print("🌳 Part '\(part.layer)' selected tile ID \(tileID) at row \(actualRow), column \(actualColumn) (requested column: \(sharedCol))")
                                } else {
                                    print("⚠️ Part '\(part.layer)' failed to find tile at column \(sharedCol) for class '\(gidSpec)'")
                                }
                            } else {
                                // Calculate starting column and row from first tile
                                resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: nil, targetRow: nil, targetColumn: nil, using: &rng)
                                if let resolved = resolvedSpec,
                                   let dashIndex = resolved.firstIndex(of: "-"),
                                   let tileID = Int(String(resolved[resolved.index(after: dashIndex)...])) {
                                    let calculatedColumn = tileID % tileset.columns
                                    let calculatedRow = tileID / tileset.columns
                                    startingColumn = calculatedColumn
                                    startingRow = calculatedRow
                                    lastUsedTileID = tileID
                                    firstTileID = tileID  // Store first tile ID for arithmetic-based selection
                                    lastUsedTilesetName = tilesetName
                                    // Debug: log column and row calculation
                                    print("🌳 Part '\(part.layer)' calculated starting row: \(calculatedRow), column: \(calculatedColumn) from tile ID \(tileID) (tileset columns: \(tileset.columns))")
                                }
                            }
                        } else if let startCol = startingColumn, let startRow = startingRow, let baseTileID = firstTileID {
                            // We have a starting column, row, and tile ID - use simple arithmetic to maintain position
                            // Calculate the expected tile ID based on grid position
                            let expectedTileID = baseTileID + (rowIndex * tileset.columns) + colIndex
                            
                            // Check if this expected tile ID exists in the class
                            if let tileIDs = tileset.classNames[className], tileIDs.contains(expectedTileID) {
                                // Use the expected tile ID directly - preserves spatial relationships
                                resolvedSpec = "\(tilesetName)-\(expectedTileID)"
                                lastUsedTileID = expectedTileID
                            } else {
                                // Fallback: try to find a tile in the same row and column
                                let targetRow = startRow + rowIndex
                                let targetCol = startCol + colIndex
                                // Find any tile that matches the target row and column
                                if let tileIDs = tileset.classNames[className] {
                                    let matchingTiles = tileIDs.filter { tileID in
                                        let tileRow = tileID / tileset.columns
                                        let tileCol = tileID % tileset.columns
                                        return tileRow == targetRow && tileCol == targetCol
                                    }
                                    
                                    if let matchedTileID = matchingTiles.first {
                                        resolvedSpec = "\(tilesetName)-\(matchedTileID)"
                                        lastUsedTileID = matchedTileID
                                    } else {
                                        // Last resort: find closest tile in same column, then same row
                                        resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: lastUsedTileID, targetRow: targetRow, targetColumn: startCol, using: &rng)
                                        if let resolved = resolvedSpec,
                                           let dashIndex = resolved.firstIndex(of: "-"),
                                           let tileID = Int(String(resolved[resolved.index(after: dashIndex)...])) {
                                            lastUsedTileID = tileID
                                        }
                                    }
                                } else {
                                    // No tiles found - skip this tile
                                    continue
                                }
                            }
                        } else {
                            // No starting info yet - shouldn't happen, but handle gracefully
                            resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: lastUsedTileID, targetRow: nil, targetColumn: nil, using: &rng)
                        }
                        
                        if let resolved = resolvedSpec {
                            // Extract tileset name and local tile ID from resolved spec for next iteration
                            if let dashIndex = resolved.firstIndex(of: "-") {
                                lastUsedTilesetName = String(resolved[..<dashIndex])
                                if let tileID = Int(String(resolved[resolved.index(after: dashIndex)...])) {
                                    lastUsedTileID = tileID
                                }
                            }
                            
                            // Create sprite from resolved spec - create at source size then scale
                            if let directGID = Int(resolved) {
                                if let createdSprite = TileManager.shared.createSprite(for: directGID, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                    sprite = createdSprite
                                    if scaleFactor != 1.0 {
                                        sprite.xScale = scaleFactor
                                        sprite.yScale = scaleFactor
                                    }
                                } else if let assetName = part.assetName {
                                    let texture = SKTexture(imageNamed: assetName)
                                    sprite = SKSpriteNode(texture: texture, size: CGSize(width: tileSize, height: tileSize))
                                } else {
                                    sprite = SKSpriteNode(color: .brown, size: CGSize(width: tileSize, height: tileSize))
                                }
                            } else if let createdSprite = createSpriteFromGIDSpec(resolved, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                sprite = createdSprite
                                if scaleFactor != 1.0 {
                                    sprite.xScale = scaleFactor
                                    sprite.yScale = scaleFactor
                                }
                                sprite.alpha = 1.0
                                sprite.isHidden = false
                                sprite.colorBlendFactor = 0.0
                                sprite.color = .white
                            } else {
                                // Try as regular GID spec as fallback
                                if let assetName = part.assetName {
                                    let texture = SKTexture(imageNamed: assetName)
                                    sprite = SKSpriteNode(texture: texture, size: CGSize(width: tileSize, height: tileSize))
                                } else {
                                    sprite = SKSpriteNode(color: .brown, size: CGSize(width: tileSize, height: tileSize))
                                }
                            }
                        } else {
                            // Class name resolution failed - try as regular GID spec as fallback
                            if let createdSprite = createSpriteFromGIDSpec(gidSpec, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                                sprite = createdSprite
                                if scaleFactor != 1.0 {
                                    sprite.xScale = scaleFactor
                                    sprite.yScale = scaleFactor
                                }
                            } else if let assetName = part.assetName {
                                let texture = SKTexture(imageNamed: assetName)
                                sprite = SKSpriteNode(texture: texture, size: CGSize(width: tileSize, height: tileSize))
                            } else {
                                // Final fallback: colored rectangle to show missing tile
                                sprite = SKSpriteNode(color: .red, size: CGSize(width: tileSize, height: tileSize))
                                print("   ⚠️ Using red placeholder for missing tile '\(gidSpec)'")
                            }
                        }
                    } else {
                        // Not a class name, handle as regular GID spec (direct GID, tileset-localIndex, or atlas-frame)
                    // Try to create sprite directly (handles both GIDs and sprite atlases)
                    if let directGID = Int(gidSpec) {
                    // Direct GID number
                    if let createdSprite = TileManager.shared.createSprite(for: directGID, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                        sprite = createdSprite
                        if scaleFactor != 1.0 {
                            sprite.xScale = scaleFactor
                            sprite.yScale = scaleFactor
                        }
                    } else if let assetName = part.assetName {
                        // Fallback to asset if GID fails
                        let texture = SKTexture(imageNamed: assetName)
                        sprite = SKSpriteNode(texture: texture, size: CGSize(width: tileSize, height: tileSize))
                    } else {
                        // Final fallback: colored rectangle
                        sprite = SKSpriteNode(color: .brown, size: CGSize(width: tileSize, height: tileSize))
                    }
                } else if let createdSprite = createSpriteFromGIDSpec(gidSpec, size: CGSize(width: sourceTileSize, height: sourceTileSize)) {
                    // Sprite atlas or parsed GID
                    sprite = createdSprite
                    if scaleFactor != 1.0 {
                        sprite.xScale = scaleFactor
                        sprite.yScale = scaleFactor
                    }
                } else if let assetName = part.assetName {
                    // Fallback to asset if sprite atlas/GID fails
                    let texture = SKTexture(imageNamed: assetName)
                    sprite = SKSpriteNode(texture: texture, size: CGSize(width: tileSize, height: tileSize))
                    } else {
                        // Final fallback: colored rectangle
                        sprite = SKSpriteNode(color: .brown, size: CGSize(width: tileSize, height: tileSize))
                        }
                    }
                }
                
                // Calculate position for this tile in the grid - use tileSize for spacing since sprites are scaled
                let tileOffsetX = CGFloat(colIndex) * tileSize
                let tileOffsetY = -CGFloat(rowIndex) * tileSize  // Negative because Y increases up in SpriteKit
                
                // Position relative to entity center + part offset + tile offset
                // CRITICAL: part.offset is already in world units, do NOT scale it
                let offsetX = part.offset.x
                let offsetY = part.offset.y
                
                sprite.position = CGPoint(
                    x: entity.position.x + offsetX + tileOffsetX,
                    y: entity.position.y + offsetY + tileOffsetY
                )
                // Sprite zPosition is always 0 - layering is handled by container zPosition
                sprite.zPosition = 0
                sprite.anchorPoint = CGPoint(x: 0, y: 1)  // Top-left anchor for tile grid alignment
                sprite.zRotation = entity.rotation
                
                // Apply variant if specified
                if let variant = entity.variant {
                    applyVariant(sprite: sprite, variant: variant)
                }
                
                sprites.append(sprite)
            }
        }
        
        return (sprites, startingColumn)
    }
    
    /// Check if a spec is a class name (not a direct GID or tileset-localIndex)
    private func isClassSpec(_ spec: String) -> Bool {
        // If it's a direct number, it's not a class name
        if Int(spec) != nil {
            return false
        }
        
        // If it has a dash, check if the part after is a number
        if let dashIndex = spec.firstIndex(of: "-") {
            let afterDash = String(spec[spec.index(after: dashIndex)...])
            // If after dash is not a number, it's a class name (e.g., "terrain1-grass_full")
            return Int(afterDash) == nil
        }
        
        // No dash and not a number = class name (e.g., "grass_full")
        return true
    }
    
    /// Create sprite nodes for an entity (legacy method - returns all sprites together)
    /// Use createEntitySpritesByLayer for proper layer separation
    func createEntitySprites(_ entity: ProceduralEntity, tileSize: CGFloat) -> [SKSpriteNode] {
        let (low, high) = createEntitySpritesByLayer(entity, tileSize: tileSize)
        return low + high
    }
    
    /// Create physics body for an entity
    func createPhysicsBody(_ entity: ProceduralEntity, tileSize: CGFloat) -> SKPhysicsBody? {
        // Handle chests separately
        if entity.type == .chest {
            if let chestPrefab = chestPrefabs[entity.prefabId] {
                // Scale collision size from source tile size to world tile size
                let sourceTileSize = chestPrefab.tileSize > 0 ? chestPrefab.tileSize : 32.0
                let scale = tileSize / sourceTileSize
                
                switch chestPrefab.collision.type {
                case "rectangle":
                    let scaledSize = CGSize(width: chestPrefab.collision.size.width * scale, height: chestPrefab.collision.size.height * scale)
                    return SKPhysicsBody(rectangleOf: scaledSize)
                case "circle":
                    let radius = (chestPrefab.collision.size.width * scale) / 2
                    return SKPhysicsBody(circleOfRadius: radius)
                case "none":
                    return nil
                default:
                    return nil
                }
            }
            return nil
        }
        
        let basePrefabId = entity.prefabId.replacingOccurrences(of: "_low", with: "")
            .replacingOccurrences(of: "_high", with: "")
        
        guard let prefab = prefabs[basePrefabId] else {
            return nil
        }
        
        // Scale collision size from source tile size to world tile size
        // Get source tile size from first part (or default to 32)
        let sourceTileSize = prefab.parts.first?.tileSize ?? 32.0
        let scale = sourceTileSize > 0 ? (tileSize / sourceTileSize) : 1.0
        
        switch prefab.collisionShape {
        case .rectangle(let size):
            let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
            let physicsBody = SKPhysicsBody(rectangleOf: scaledSize)
            // Position physics body at bottom-center (tree collision should be at base of trunk)
            // SpriteKit physics bodies are centered by default, so we use an offset
            physicsBody.usesPreciseCollisionDetection = true
            return physicsBody
        case .circle(let radius):
            let scaledRadius = radius * scale
            let physicsBody = SKPhysicsBody(circleOfRadius: scaledRadius)
            physicsBody.usesPreciseCollisionDetection = true
            return physicsBody
        case .none:
            return nil
        }
    }
    
    /// Register default prefabs (trees, rocks, basic buildings)
    /// This is a fallback if JSON files cannot be loaded
    private func registerDefaultPrefabs() {
        let tileSize: CGFloat = 32.0  // Default tile size
        
        // Tree: oak_01
        registerPrefab(PrefabDefinition(
            id: "tree_oak_01",
            type: .tree,
            description: "A medium-sized oak tree",
            parts: [
                PrefabPart(
                    layer: "low",
                    tileGrid: [["4125"]],  // Single tile as 1x1 grid
                    assetName: nil,
                    offset: CGPoint(x: -tileSize * 0.25, y: 0),
                    size: CGSize(width: tileSize * 0.5, height: tileSize * 0.75),
                    zOffset: 0,
                    tileSize: 0
                ),
                PrefabPart(
                    layer: "high",
                    tileGrid: [
                        [nil, "4200", nil],
                        ["4201", "4202", "4203"],
                        [nil, "4204", nil]
                    ],
                    assetName: nil,
                    offset: CGPoint(x: -tileSize * 1.5, y: tileSize * 0.75),
                    size: CGSize(width: tileSize * 3, height: tileSize * 3),
                    zOffset: 0,
                    tileSize: tileSize
                )
            ],
            collision: CollisionSpec(type: "rectangle", size: CGSize(width: tileSize * 0.5, height: tileSize * 0.5)),
            zPosition: 0
        ))
        
        // Rock: stone_01
        registerPrefab(PrefabDefinition(
            id: "rock_stone_01",
            type: .rock,
            description: "A medium stone rock",
            parts: [
                PrefabPart(
                    layer: "low",
                    tileGrid: [["800"]],  // Single tile as 1x1 grid
                    assetName: nil,
                    offset: .zero,
                    size: CGSize(width: tileSize, height: tileSize),
                    zOffset: 0,
                    tileSize: 0
                )
            ],
            collision: CollisionSpec(type: "rectangle", size: CGSize(width: tileSize * 0.7, height: tileSize * 0.5)),
            zPosition: 0
        ))
        
        // Cabin: small_01
        registerPrefab(PrefabDefinition(
            id: "cabin_small_01",
            type: .building,
            description: "A small wooden cabin",
            parts: [
                PrefabPart(
                    layer: "low",
                    tileGrid: [
                        ["1730", "1731"],
                        ["1732", "1733"]
                    ],
                    assetName: nil,
                    offset: CGPoint(x: -tileSize, y: 0),
                    size: CGSize(width: tileSize * 2, height: tileSize * 2),
                    zOffset: 0,
                    tileSize: tileSize
                ),
                PrefabPart(
                    layer: "high",
                    tileGrid: [
                        ["1800", "1801", "1802"],
                        [nil, "1803", nil]
                    ],
                    assetName: nil,
                    offset: CGPoint(x: -tileSize * 1.5, y: tileSize * 2),
                    size: CGSize(width: tileSize * 3, height: tileSize * 2),
                    zOffset: 0,
                    tileSize: tileSize
                )
            ],
            collision: CollisionSpec(type: "rectangle", size: CGSize(width: tileSize * 2, height: tileSize * 2)),
            zPosition: 0
        ))
    }
    
    /// Create a fallback sprite when prefab is not found
    private func createFallbackSprite(entity: ProceduralEntity, tileSize: CGFloat) -> [SKSpriteNode] {
        let color: SKColor
        switch entity.type {
        case .tree: color = .brown
        case .rock: color = .gray
        case .building: color = .orange
        case .decoration: color = .yellow
        case .chest: color = .cyan
        }
        
        let sprite = SKSpriteNode(color: color, size: CGSize(width: tileSize, height: tileSize))
        sprite.position = entity.position
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return [sprite]
    }
    
    /// Apply visual variant to a sprite (color tint, etc.)
    private func applyVariant(sprite: SKSpriteNode, variant: Int) {
        // Simple color variation for now
        let tints: [SKColor] = [.white, SKColor(white: 0.9, alpha: 1.0), SKColor(white: 0.8, alpha: 1.0)]
        let tint = tints[variant % tints.count]
        sprite.color = tint
        sprite.colorBlendFactor = 0.2  // Subtle tint
    }
    
    // MARK: - JSON Loading
    
    /// Load prefabs from JSON file
    private func loadPrefabsFromJSON(fileName: String = "prefabs") -> Bool {
        // Look in Prefabs/ directory first, then root
        // Also check Maps/ subdirectory for map-specific prefabs
        var url: URL?
        
        // Try Maps/ subdirectory first (for map-specific prefabs like prefabs_grassland.json)
        if let mapsUrl = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "Prefabs/Maps") {
            url = mapsUrl
        }
        // Try root Prefabs/ directory
        else if let prefabsUrl = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "Prefabs") {
            url = prefabsUrl
        }
        // Try root bundle
        else if let rootUrl = Bundle.main.url(forResource: fileName, withExtension: "json") {
            url = rootUrl
        }
        
        guard let url = url else {
            print("⚠️ PrefabFactory: \(fileName).json not found in bundle (checked Prefabs/Maps/, Prefabs/, and root)")
            return false
        }
        
        return loadPrefabsFromJSON(url: url)
    }
    
    private func loadPrefabsFromJSON(url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            // Extract fileName from URL for logging purposes
            let fileName = url.deletingPathExtension().lastPathComponent
            
            // Custom decoder for CGPoint and CGSize (they don't conform to Codable by default)
            // We'll decode them manually from dictionaries
            
            struct PrefabsContainer: Codable {
                let worldConfig: WorldConfigJSON?
                let prefabs: [PrefabDefinitionJSON]
            }
            
            // Decode using a temporary structure that handles CGPoint/CGSize
            let container = try decoder.decode(PrefabsContainer.self, from: data)
            
            // Store world config if present
            if let jsonConfig = container.worldConfig {
                worldConfig = WorldConfig(
                    id: fileName,
                    name: jsonConfig.name,
                    description: jsonConfig.description,
                    seed: jsonConfig.seed,
                    terrain: jsonConfig.terrain,
                    entities: jsonConfig.entities,
                    enemies: jsonConfig.enemies,
                    animals: jsonConfig.animals,
                    waterFeatures: jsonConfig.waterFeatures,
                    exitConfig: jsonConfig.exitConfig
                )
                print("✅ PrefabFactory: Loaded world config from \(fileName).json: '\(jsonConfig.name)' (seed: \(jsonConfig.seed))")
            }
            
            // Convert JSON structures to internal PrefabDefinition structures
            for jsonPrefab in container.prefabs {
                let parts = jsonPrefab.parts.map { jsonPart -> PrefabPart in
                    // tileGrid is now required (no longer optional)
                    return PrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        assetName: jsonPart.assetName,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let prefab = PrefabDefinition(
                    id: jsonPrefab.id,
                    type: jsonPrefab.type,
                    description: jsonPrefab.description,
                    parts: parts,
                    collision: CollisionSpec(type: jsonPrefab.collision.type, size: CGSize(width: jsonPrefab.collision.size.width, height: jsonPrefab.collision.size.height)),
                    zPosition: jsonPrefab.zPosition
                )
                
                prefabs[prefab.id] = prefab
            }
            
            print("✅ PrefabFactory: Loaded \(prefabs.count) prefabs from \(fileName).json")
            return true
        } catch {
            print("❌ PrefabFactory: Failed to load prefabs.json: \(error)")
            return false
        }
    }
    
    /// Load enemy prefabs from enemies.json
    private func loadEnemyPrefabs() {
        guard let url = Bundle.main.url(forResource: "enemies", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "enemies", withExtension: "json") else {
            print("⚠️ PrefabFactory: enemies.json not found, skipping enemy prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct EnemiesContainer: Codable {
                let enemies: [EnemyPrefabJSON]
            }
            
            struct EnemyPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String?
                let parts: [EntityPrefabPartJSON]
                let size: CGPointSizeDict
                let hitPoints: Int
                let attackPoints: Int
                let defensePoints: Int
                let energyPoints: Int?
                let manaPoints: Int?
                let ragePoints: Int?
                let friendPoints: Int?
                let zOffset: CGFloat
                let tileSize: CGFloat
                let collision: CollisionSpecJSON
                let zPosition: CGFloat
                let level: Int?
                let experienceReward: Int?
                let goldReward: Int?
                let speed: Int?
                let lootTable: [String]?
            }
            
            let container = try decoder.decode(EnemiesContainer.self, from: data)
            
            for jsonEnemy in container.enemies {
                let parts = jsonEnemy.parts.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let enemy = EnemyPrefab(
                    id: jsonEnemy.id,
                    name: jsonEnemy.name,
                    description: jsonEnemy.description,
                    parts: parts,
                    size: CGSize(width: jsonEnemy.size.width, height: jsonEnemy.size.height),
                    hitPoints: jsonEnemy.hitPoints,
                    attackPoints: jsonEnemy.attackPoints,
                    defensePoints: jsonEnemy.defensePoints,
                    energyPoints: jsonEnemy.energyPoints,
                    manaPoints: jsonEnemy.manaPoints,
                    ragePoints: jsonEnemy.ragePoints,
                    friendPoints: jsonEnemy.friendPoints,
                    zOffset: jsonEnemy.zOffset,
                    tileSize: jsonEnemy.tileSize,
                    collision: CollisionSpec(type: jsonEnemy.collision.type, size: CGSize(width: jsonEnemy.collision.size.width, height: jsonEnemy.collision.size.height)),
                    zPosition: jsonEnemy.zPosition,
                    level: jsonEnemy.level,
                    experienceReward: jsonEnemy.experienceReward,
                    goldReward: jsonEnemy.goldReward,
                    speed: jsonEnemy.speed,
                    lootTable: jsonEnemy.lootTable
                )
                
                enemyPrefabs[enemy.id] = enemy
            }
            
            print("✅ PrefabFactory: Loaded \(enemyPrefabs.count) enemy prefabs from enemies.json")
        } catch {
            print("❌ PrefabFactory: Failed to load enemies.json: \(error)")
        }
    }
    
    /// Load animal prefabs from animals.json
    private func loadAnimalPrefabs() {
        guard let url = Bundle.main.url(forResource: "animals", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "animals", withExtension: "json") else {
            print("⚠️ PrefabFactory: animals.json not found, skipping animal prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct AnimalsContainer: Codable {
                let animals: [AnimalPrefabJSON]
            }
            
            struct AnimalPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String?
                let parts: [EntityPrefabPartJSON]
                let size: CGPointSizeDict
                let hitPoints: Int
                let attackPoints: Int
                let defensePoints: Int
                let energyPoints: Int?
                let manaPoints: Int?
                let ragePoints: Int?
                let friendPoints: Int
                let zOffset: CGFloat
                let tileSize: CGFloat
                let collision: CollisionSpecJSON
                let zPosition: CGFloat
                let level: Int?
                let speed: Int?
                let requiredBefriendingItem: String?
                let skillIds: [String]?  // New: skill IDs
                let moves: [String]?  // Legacy: kept for backwards compatibility
            }
            
            let container = try decoder.decode(AnimalsContainer.self, from: data)
            
            for jsonAnimal in container.animals {
                let parts = jsonAnimal.parts.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let animal = AnimalPrefab(
                    id: jsonAnimal.id,
                    name: jsonAnimal.name,
                    description: jsonAnimal.description,
                    parts: parts,
                    size: CGSize(width: jsonAnimal.size.width, height: jsonAnimal.size.height),
                    hitPoints: jsonAnimal.hitPoints,
                    attackPoints: jsonAnimal.attackPoints,
                    defensePoints: jsonAnimal.defensePoints,
                    energyPoints: jsonAnimal.energyPoints,
                    manaPoints: jsonAnimal.manaPoints,
                    ragePoints: jsonAnimal.ragePoints,
                    friendPoints: jsonAnimal.friendPoints,
                    zOffset: jsonAnimal.zOffset,
                    tileSize: jsonAnimal.tileSize,
                    collision: CollisionSpec(type: jsonAnimal.collision.type, size: CGSize(width: jsonAnimal.collision.size.width, height: jsonAnimal.collision.size.height)),
                    zPosition: jsonAnimal.zPosition,
                    level: jsonAnimal.level,
                    speed: jsonAnimal.speed,
                    requiredBefriendingItem: jsonAnimal.requiredBefriendingItem,
                    skillIds: jsonAnimal.skillIds ?? jsonAnimal.moves,  // Use skillIds if available, fallback to moves for backwards compatibility
                    moves: jsonAnimal.moves
                )
                
                animalPrefabs[animal.id] = animal
            }
            
            print("✅ PrefabFactory: Loaded \(animalPrefabs.count) animal prefabs from animals.json")
        } catch {
            print("❌ PrefabFactory: Failed to load animals.json: \(error)")
        }
    }
    
    /// Load NPC prefabs from npcs.json
    private func loadNPCPrefabs() {
        guard let url = Bundle.main.url(forResource: "npcs", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "npcs", withExtension: "json") else {
            print("⚠️ PrefabFactory: npcs.json not found, skipping NPC prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct NPCsContainer: Codable {
                let npcs: [NPCPrefabJSON]
            }
            
            struct NPCPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String?
                let parts: [EntityPrefabPartJSON]
                let size: CGPointSizeDict
                let hitPoints: Int?
                let attackPoints: Int?
                let defensePoints: Int?
                let energyPoints: Int?
                let manaPoints: Int?
                let ragePoints: Int?
                let friendPoints: Int
                let zOffset: CGFloat
                let tileSize: CGFloat
                let collision: CollisionSpecJSON
                let zPosition: CGFloat
                let level: Int?
                let speed: Int?
                let dialogueId: String?
                let faction: String?
                let quests: [String]?
                let shopItems: [String]?
            }
            
            let container = try decoder.decode(NPCsContainer.self, from: data)
            
            for jsonNPC in container.npcs {
                let parts = jsonNPC.parts.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let npc = NPCPrefab(
                    id: jsonNPC.id,
                    name: jsonNPC.name,
                    description: jsonNPC.description,
                    parts: parts,
                    size: CGSize(width: jsonNPC.size.width, height: jsonNPC.size.height),
                    hitPoints: jsonNPC.hitPoints,
                    attackPoints: jsonNPC.attackPoints,
                    defensePoints: jsonNPC.defensePoints,
                    energyPoints: jsonNPC.energyPoints,
                    manaPoints: jsonNPC.manaPoints,
                    ragePoints: jsonNPC.ragePoints,
                    friendPoints: jsonNPC.friendPoints,
                    zOffset: jsonNPC.zOffset,
                    tileSize: jsonNPC.tileSize,
                    collision: CollisionSpec(type: jsonNPC.collision.type, size: CGSize(width: jsonNPC.collision.size.width, height: jsonNPC.collision.size.height)),
                    zPosition: jsonNPC.zPosition,
                    level: jsonNPC.level,
                    speed: jsonNPC.speed,
                    dialogueId: jsonNPC.dialogueId,
                    faction: jsonNPC.faction,
                    quests: jsonNPC.quests,
                    shopItems: jsonNPC.shopItems
                )
                
                npcPrefabs[npc.id] = npc
            }
            
            print("✅ PrefabFactory: Loaded \(npcPrefabs.count) NPC prefabs from npcs.json")
        } catch {
            print("❌ PrefabFactory: Failed to load npcs.json: \(error)")
        }
    }
    
    // MARK: - Helper JSON Structures for Decoding
    
    struct EntityPrefabPartJSON: Codable {
        let layer: String
        let tileGrid: [[String?]]
        fileprivate let offset: CGPointDict
        fileprivate let size: CGSizeDict
        let zOffset: CGFloat
        let tileSize: CGFloat
        
        // Convert to CGPoint/CGSize after decoding
        var offsetPoint: CGPoint {
            return CGPoint(x: offset.x, y: offset.y)
        }
        
        var sizeSize: CGSize {
            return CGSize(width: size.width, height: size.height)
        }
    }
    
    /// Load skill prefabs from skills.json
    private func loadSkillPrefabs() {
        guard let url = Bundle.main.url(forResource: "skills", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "skills", withExtension: "json") else {
            print("⚠️ PrefabFactory: skills.json not found, skipping skill prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct SkillPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String
                let type: SkillType
                let damageMultiplier: Double?
                let baseDamage: Int?
                let energyCost: Int?
                let manaCost: Int?
                let cooldown: Int?
                let range: Int?
                let effects: [SkillEffect]?
                let targetType: SkillTargetType
                let animationId: String?
                let parts: [EntityPrefabPartJSON]?
                let size: CGPointSizeDict?
                let zPosition: CGFloat?
            }
            
            struct SkillsContainer: Codable {
                let skills: [SkillPrefabJSON]
            }
            
            let container = try decoder.decode(SkillsContainer.self, from: data)
            
            for jsonSkill in container.skills {
                let parts = jsonSkill.parts?.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let skill = SkillPrefab(
                    id: jsonSkill.id,
                    name: jsonSkill.name,
                    description: jsonSkill.description,
                    type: jsonSkill.type,
                    damageMultiplier: jsonSkill.damageMultiplier,
                    baseDamage: jsonSkill.baseDamage,
                    energyCost: jsonSkill.energyCost,
                    manaCost: jsonSkill.manaCost,
                    cooldown: jsonSkill.cooldown,
                    range: jsonSkill.range,
                    effects: jsonSkill.effects,
                    targetType: jsonSkill.targetType,
                    animationId: jsonSkill.animationId,
                    parts: parts,
                    size: jsonSkill.size != nil ? CGSize(width: jsonSkill.size!.width, height: jsonSkill.size!.height) : nil,
                    zPosition: jsonSkill.zPosition
                )
                
                skillPrefabs[skill.id] = skill
            }
            
            print("✅ PrefabFactory: Loaded \(skillPrefabs.count) skill prefabs from skills.json")
        } catch {
            print("❌ PrefabFactory: Failed to load skills.json: \(error)")
        }
    }
    
    /// Load item prefabs from items.json
    private func loadItemPrefabs() {
        guard let url = Bundle.main.url(forResource: "items", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "items", withExtension: "json") else {
            print("⚠️ PrefabFactory: items.json not found, skipping item prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct ItemPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String
                let type: ItemTypeString
                let value: Int
                let stackable: Bool
                let inventorySize: CGPointSizeDict  // Width x height in inventory slots
                let parts: [EntityPrefabPartJSON]  // Visual parts
                let size: CGPointSizeDict  // Overall item size
                let zPosition: CGFloat
                let gid: String?  // Legacy support (optional, deprecated)
                let weaponData: WeaponData?
                let armorData: ArmorData?
                let consumableData: ConsumableData?
                let materialData: MaterialData?
            }
            
            struct ItemsContainer: Codable {
                let items: [ItemPrefabJSON]
            }
            
            let container = try decoder.decode(ItemsContainer.self, from: data)
            
            for jsonItem in container.items {
                let parts = jsonItem.parts.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let item = ItemPrefab(
                    id: jsonItem.id,
                    name: jsonItem.name,
                    description: jsonItem.description,
                    type: jsonItem.type,
                    value: jsonItem.value,
                    stackable: jsonItem.stackable,
                    inventorySize: CGSize(width: jsonItem.inventorySize.width, height: jsonItem.inventorySize.height),
                    parts: parts,
                    size: CGSize(width: jsonItem.size.width, height: jsonItem.size.height),
                    zPosition: jsonItem.zPosition,
                    gid: jsonItem.gid,
                    weaponData: jsonItem.weaponData,
                    armorData: jsonItem.armorData,
                    consumableData: jsonItem.consumableData,
                    materialData: jsonItem.materialData
                )
                
                itemPrefabs[item.id] = item
            }
            
            print("✅ PrefabFactory: Loaded \(itemPrefabs.count) item prefabs from items.json")
        } catch {
            print("❌ PrefabFactory: Failed to load items.json: \(error)")
        }
    }
    
    /// Load chest prefabs from chests.json
    private func loadChestPrefabs() {
        guard let url = Bundle.main.url(forResource: "chests", withExtension: "json", subdirectory: "Prefabs")
           ?? Bundle.main.url(forResource: "chests", withExtension: "json") else {
            print("⚠️ PrefabFactory: chests.json not found, skipping chest prefabs")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            struct ChestPrefabJSON: Codable {
                let id: String
                let name: String
                let description: String?
                let parts: [EntityPrefabPartJSON]
                let size: CGPointSizeDict
                let zOffset: CGFloat
                let tileSize: CGFloat
                let collision: CollisionSpecJSON
                let zPosition: CGFloat
                let lootTable: [ChestLootItem]?  // Optional for backwards compatibility
                let fixedItems: [ChestFixedItem]?  // Optional fixed items
                let randomItems: ChestRandomItems?  // Optional random item rules
                let lockLevel: Int?
                let requiredKey: String?
            }
            
            struct ChestsContainer: Codable {
                let chests: [ChestPrefabJSON]
            }
            
            let container = try decoder.decode(ChestsContainer.self, from: data)
            
            for jsonChest in container.chests {
                let parts = jsonChest.parts.map { jsonPart -> EntityPrefabPart in
                    EntityPrefabPart(
                        layer: jsonPart.layer,
                        tileGrid: jsonPart.tileGrid,
                        offset: jsonPart.offsetPoint,
                        size: jsonPart.sizeSize,
                        zOffset: jsonPart.zOffset,
                        tileSize: jsonPart.tileSize
                    )
                }
                
                let chest = ChestPrefab(
                    id: jsonChest.id,
                    name: jsonChest.name,
                    description: jsonChest.description,
                    parts: parts,
                    size: CGSize(width: jsonChest.size.width, height: jsonChest.size.height),
                    zOffset: jsonChest.zOffset,
                    tileSize: jsonChest.tileSize,
                    collision: CollisionSpec(type: jsonChest.collision.type, size: CGSize(width: jsonChest.collision.size.width, height: jsonChest.collision.size.height)),
                    zPosition: jsonChest.zPosition,
                    lootTable: jsonChest.lootTable,
                    fixedItems: jsonChest.fixedItems,
                    randomItems: jsonChest.randomItems,
                    lockLevel: jsonChest.lockLevel,
                    requiredKey: jsonChest.requiredKey
                )
                
                chestPrefabs[chest.id] = chest
            }
            
            print("✅ PrefabFactory: Loaded \(chestPrefabs.count) chest prefabs from chests.json")
        } catch {
            print("❌ PrefabFactory: Failed to load chests.json: \(error)")
        }
    }
    
    /// Parse GID spec (supports "tileset-localIndex" format or direct GID number)
    /// Public method for use in GameScene and other systems
    func parseGIDSpec(_ spec: String?) -> Int? {
        guard let spec = spec, !spec.isEmpty else { return nil }
        // Check if it's "tileset-localIndex" or "atlas-frameNumber" format
        if let dashIndex = spec.firstIndex(of: "-") {
            let name = String(spec[..<dashIndex])
            guard let index = Int(String(spec[spec.index(after: dashIndex)...])) else {
                return nil
            }
            
            // First check if it's a sprite atlas (e.g., "grasslands_atlas-1")
            // Sprite atlases are loaded directly, not through GIDs
            // We'll handle this in createSpriteFromGIDSpec instead
            // For now, check if it's a Tiled tileset
            let tilesets = TileManager.shared.getTiledTilesets()
            if let tileset = tilesets.first(where: { $0.name == name }) {
                // It's a Tiled tileset: calculate GID
                return tileset.firstGID + index
            }
            
            // If not a Tiled tileset, assume it's a sprite atlas
            // Return a special GID that we can detect later (use negative or high value)
            // Actually, we should handle this differently - return nil and handle in createSprite
            return nil  // Will be handled as sprite atlas in createSpriteFromGIDSpec
        }
        
        // Otherwise, treat as direct GID number
        return Int(spec)
    }
    
    /// Create a sprite from a GID spec, handling both Tiled tilesets and sprite atlases
    /// Also supports class names: "className" or "tilesetName-className"
    func createSpriteFromGIDSpec(_ gidSpec: String?, size: CGSize) -> SKSpriteNode? {
        guard let gidSpec = gidSpec, !gidSpec.isEmpty else { return nil }
        
        // Handle "generate" as a special placeholder value
        if gidSpec.lowercased() == "generate" {
            // Create a placeholder sprite (cyan to indicate it needs a real GID)
            let sprite = SKSpriteNode(color: SKColor.cyan, size: size)
            sprite.alpha = 0.5  // Make it semi-transparent to indicate it's a placeholder
            sprite.colorBlendFactor = 1.0
            return sprite
        }
        
        // Check if it's "tileset-localIndex" or "tileset-className" format
        if let dashIndex = gidSpec.firstIndex(of: "-") {
            let name = String(gidSpec[..<dashIndex])
            let afterDash = String(gidSpec[gidSpec.index(after: dashIndex)...])
            
            // Check if the part after dash is a number (tile ID) or a class name
            if let index = Int(afterDash) {
                // It's a numeric tile ID: "tilesetName-localIndex" or "atlasName-frameNumber"
                
                // PRIORITY 1: Check if it's a Tiled tileset first (before sprite atlas)
                // This handles "terrain1-0", "water1-445", etc.
                let tilesets = TileManager.shared.getTiledTilesets()
                if let tileset = tilesets.first(where: { $0.name == name }) {
                    // It's a Tiled tileset: calculate GID and create sprite
                    let gid = tileset.firstGID + index
                    if let sprite = TileManager.shared.createSprite(for: gid, size: size) {
                        return sprite
                    } else {
                        return nil
                    }
                }
                
                // PRIORITY 2: Try sprite atlas (e.g., "grasslands_atlas-1")
                // Only try sprite atlas if it's not a Tiled tileset
                if let sprite = TileManager.shared.createSpriteFromAtlas(atlasName: name, frameNumber: index, size: size) {
                    return sprite
                }
                
                // If both fail, check if it's a known sprite atlas pattern
                if name.hasSuffix("_atlas") {
                    // This is definitely a sprite atlas, but lookup failed
                    print("⚠️ PrefabFactory: Failed to load sprite from atlas '\(name)' frame \(index)")
                    return nil
                }
                
                // Unknown format
                print("⚠️ PrefabFactory: Unknown tileset/atlas name '\(name)' in GID spec '\(gidSpec)'")
                return nil
            } else {
                // It's a class name: "tilesetName-className" (e.g., "terrain1-grass_full")
                // Resolve the class name to a tile spec, then recursively create the sprite
                var rng = SeededRandomNumberGenerator(seed: UInt64(Date().timeIntervalSince1970))
                if let resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: nil, using: &rng) {
                    // Recursively call with resolved spec
                    return createSpriteFromGIDSpec(resolvedSpec, size: size)
                } else {
                    print("⚠️ PrefabFactory: Could not resolve class name '\(gidSpec)'")
                    return nil
                }
            }
        }
        
        // No dash - check if it's a direct GID number or a class name
        if let gid = Int(gidSpec) {
            // It's a direct GID number
            return TileManager.shared.createSprite(for: gid, size: size)
        }
        
        // Try as a class name without tileset prefix (e.g., "grass_full")
        // Resolve the class name to a tile spec, then recursively create the sprite
        var rng = SeededRandomNumberGenerator(seed: UInt64(Date().timeIntervalSince1970))
        if let resolvedSpec = TileManager.shared.getConsecutiveTileSpecByClassName(gidSpec, lastUsedTileID: nil, using: &rng) {
            // Recursively call with resolved spec
            return createSpriteFromGIDSpec(resolvedSpec, size: size)
        }
        
        print("⚠️ PrefabFactory: Could not parse GID spec '\(gidSpec)'")
        return nil
    }
}

// MARK: - JSON Codable Extensions

// Helper structures for JSON decoding (must be outside class to be accessible)
fileprivate struct CollisionSpecJSON: Codable {
    let type: String
    let size: CGPointSizeDict
}

fileprivate struct CGPointSizeDict: Codable {
    let width: CGFloat
    let height: CGFloat
}

// Temporary JSON structure that matches the JSON file format
private struct PrefabDefinitionJSON: Codable {
    let id: String
    let type: ProceduralEntityType
    let description: String?
    let parts: [PrefabPartJSON]
    let collision: CollisionSpecJSON
    let zPosition: CGFloat
}

private struct PrefabPartJSON: Codable {
    let layer: String
    let tileGrid: [[String?]]
    let assetName: String?
    let offset: CGPointDict
    let size: CGSizeDict
    let zOffset: CGFloat
    let tileSize: CGFloat
    
    // Convert to CGPoint/CGSize after decoding
    var offsetPoint: CGPoint {
        return CGPoint(x: offset.x, y: offset.y)
    }
    
    var sizeSize: CGSize {
        return CGSize(width: size.width, height: size.height)
    }
}

fileprivate struct CGPointDict: Codable {
    let x: CGFloat
    let y: CGFloat
}

fileprivate struct CGSizeDict: Codable {
    let width: CGFloat
    let height: CGFloat
}

// JSON structure for world config in prefabs file
private struct WorldConfigJSON: Codable {
    let name: String
    let description: String?
    let seed: Int
    let terrain: TerrainConfig
    let entities: EntityConfig
    let enemies: EnemyConfig?
    let animals: AnimalConfig?
    let waterFeatures: WaterFeatureConfig?
    let exitConfig: ExitConfig?
}
