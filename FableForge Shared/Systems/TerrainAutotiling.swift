//
//  TerrainAutotiling.swift
//  FableForge Shared
//
//  Autotiling system for seamless terrain blending
//

import Foundation

// TerrainType is defined in PrefabFactory.swift - we'll use that one

/// Tile variant types for autotiling
enum TileVariant: String, Codable {
    case base = "base"              // Solid interior tile (all neighbors same type)
    case edgeN = "edgeN"            // Edge piece - north edge exposed
    case edgeS = "edgeS"            // Edge piece - south edge exposed
    case edgeE = "edgeE"            // Edge piece - east edge exposed
    case edgeW = "edgeW"            // Edge piece - west edge exposed
    case cornerNE = "cornerNE"      // Outer corner - northeast
    case cornerNW = "cornerNW"      // Outer corner - northwest
    case cornerSE = "cornerSE"      // Outer corner - southeast
    case cornerSW = "cornerSW"      // Outer corner - southwest
    case innerCornerNE = "innerCornerNE"  // Inner corner (concave) - northeast
    case innerCornerNW = "innerCornerNW"  // Inner corner (concave) - northwest
    case innerCornerSE = "innerCornerSE"  // Inner corner (concave) - southeast
    case innerCornerSW = "innerCornerSW"  // Inner corner (concave) - southwest
    case transitionN = "transitionN"      // Transition piece - blends to different type to north
    case transitionS = "transitionS"      // Transition piece - blends to different type to south
    case transitionE = "transitionE"      // Transition piece - blends to different type to east
    case transitionW = "transitionW"      // Transition piece - blends to different type to west
    case transitionNE = "transitionNE"    // Transition corner - northeast
    case transitionNW = "transitionNW"    // Transition corner - northwest
    case transitionSE = "transitionSE"    // Transition corner - southeast
    case transitionSW = "transitionSW"    // Transition corner - southwest
}

/// Neighbor mask for autotiling (8-bit mask)
/// Bits represent neighbors: [NW] [N] [NE]
///                          [W]  [X]  [E]
///                          [SW] [S] [SE]
/// Where X is the current tile and 1 = same terrain type, 0 = different
struct NeighborMask: OptionSet {
    let rawValue: UInt8
    
    static let north = NeighborMask(rawValue: 1 << 0)      // Bit 0: North
    static let northeast = NeighborMask(rawValue: 1 << 1)  // Bit 1: Northeast
    static let east = NeighborMask(rawValue: 1 << 2)       // Bit 2: East
    static let southeast = NeighborMask(rawValue: 1 << 3)  // Bit 3: Southeast
    static let south = NeighborMask(rawValue: 1 << 4)      // Bit 4: South
    static let southwest = NeighborMask(rawValue: 1 << 5)  // Bit 5: Southwest
    static let west = NeighborMask(rawValue: 1 << 6)       // Bit 6: West
    static let northwest = NeighborMask(rawValue: 1 << 7)  // Bit 7: Northwest
    
    /// All neighbors are same type
    static let all = NeighborMask(rawValue: 0xFF)
    
    /// Cardinal directions only
    static let cardinals = NeighborMask([.north, .south, .east, .west])
}

/// Terrain autotiling system
class TerrainAutotiling {
    
    /// Get the appropriate tile variant based on neighboring tiles
    static func getTileVariant(
        terrain: TerrainType,
        neighbors: NeighborMask
    ) -> TileVariant {
        // Check all cardinal directions
        let hasNorth = neighbors.contains(.north)
        let hasSouth = neighbors.contains(.south)
        let hasEast = neighbors.contains(.east)
        let hasWest = neighbors.contains(.west)
        
        // Check diagonal neighbors
        let hasNortheast = neighbors.contains(.northeast)
        let hasNorthwest = neighbors.contains(.northwest)
        let hasSoutheast = neighbors.contains(.southeast)
        let hasSouthwest = neighbors.contains(.southwest)
        
        // All neighbors are same type - use base tile
        if neighbors == .all {
            return .base
        }
        
        // Handle cardinal edges
        if hasNorth && hasSouth && hasEast && !hasWest {
            return .edgeW
        }
        if hasNorth && hasSouth && !hasEast && hasWest {
            return .edgeE
        }
        if hasNorth && !hasSouth && hasEast && hasWest {
            return .edgeS
        }
        if !hasNorth && hasSouth && hasEast && hasWest {
            return .edgeN
        }
        
        // Handle outer corners (concave corners in the terrain)
        // Corner NE: has S and W, but not N or E
        if hasSouth && hasWest && !hasNorth && !hasEast {
            return .cornerNE
        }
        // Corner NW: has S and E, but not N or W
        if hasSouth && hasEast && !hasNorth && !hasWest {
            return .cornerNW
        }
        // Corner SE: has N and W, but not S or E
        if hasNorth && hasWest && !hasSouth && !hasEast {
            return .cornerSE
        }
        // Corner SW: has N and E, but not S or W
        if hasNorth && hasEast && !hasSouth && !hasWest {
            return .cornerSW
        }
        
        // Handle inner corners (convex corners - terrain extends into adjacent area)
        // Inner corner NE: has N, E, NE, but missing one or more of S, W, SW
        if hasNorth && hasEast && hasNortheast {
            // Check if it's an inner corner by verifying diagonals
            if !hasSouthwest || (!hasSouth && !hasWest) {
                return .innerCornerNE
            }
        }
        // Inner corner NW: has N, W, NW, but missing one or more of S, E, SE
        if hasNorth && hasWest && hasNorthwest {
            if !hasSoutheast || (!hasSouth && !hasEast) {
                return .innerCornerNW
            }
        }
        // Inner corner SE: has S, E, SE, but missing one or more of N, W, NW
        if hasSouth && hasEast && hasSoutheast {
            if !hasNorthwest || (!hasNorth && !hasWest) {
                return .innerCornerSE
            }
        }
        // Inner corner SW: has S, W, SW, but missing one or more of N, E, NE
        if hasSouth && hasWest && hasSouthwest {
            if !hasNortheast || (!hasNorth && !hasEast) {
                return .innerCornerSW
            }
        }
        
        // Handle transitions (only one direction is different)
        if hasNorth && hasSouth && hasEast && !hasWest {
            return .transitionW
        }
        if hasNorth && hasSouth && !hasEast && hasWest {
            return .transitionE
        }
        if hasNorth && !hasSouth && hasEast && hasWest {
            return .transitionS
        }
        if !hasNorth && hasSouth && hasEast && hasWest {
            return .transitionN
        }
        
        // Handle transition corners
        // Transition NE: has S, W, SW, but not N or E
        if hasSouth && hasWest && hasSouthwest && !hasNorth && !hasEast {
            return .transitionNE
        }
        // Transition NW: has S, E, SE, but not N or W
        if hasSouth && hasEast && hasSoutheast && !hasNorth && !hasWest {
            return .transitionNW
        }
        // Transition SE: has N, W, NW, but not S or E
        if hasNorth && hasWest && hasNorthwest && !hasSouth && !hasEast {
            return .transitionSE
        }
        // Transition SW: has N, E, NE, but not S or W
        if hasNorth && hasEast && hasNortheast && !hasSouth && !hasWest {
            return .transitionSW
        }
        
        // Default: use base tile if we can't determine a better variant
        return .base
    }
    
    /// Build neighbor mask from surrounding tiles
    static func buildNeighborMask(
        x: Int,
        y: Int,
        terrainType: TerrainType,
        terrainMap: [[TerrainType]],
        width: Int,
        height: Int
    ) -> NeighborMask {
        var mask = NeighborMask()
        
        // Check each neighbor (using 8-directional neighbors)
        // North
        if y + 1 < height && terrainMap[y + 1][x] == terrainType {
            mask.insert(.north)
        }
        // South
        if y - 1 >= 0 && terrainMap[y - 1][x] == terrainType {
            mask.insert(.south)
        }
        // East
        if x + 1 < width && terrainMap[y][x + 1] == terrainType {
            mask.insert(.east)
        }
        // West
        if x - 1 >= 0 && terrainMap[y][x - 1] == terrainType {
            mask.insert(.west)
        }
        // Northeast
        if y + 1 < height && x + 1 < width && terrainMap[y + 1][x + 1] == terrainType {
            mask.insert(.northeast)
        }
        // Northwest
        if y + 1 < height && x - 1 >= 0 && terrainMap[y + 1][x - 1] == terrainType {
            mask.insert(.northwest)
        }
        // Southeast
        if y - 1 >= 0 && x + 1 < width && terrainMap[y - 1][x + 1] == terrainType {
            mask.insert(.southeast)
        }
        // Southwest
        if y - 1 >= 0 && x - 1 >= 0 && terrainMap[y - 1][x - 1] == terrainType {
            mask.insert(.southwest)
        }
        
        return mask
    }
}
