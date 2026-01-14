//
//  TileManager.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Configuration for a tileset image
struct TilesetConfig {
    /// Name of the tileset image in the asset catalog
    let imageName: String
    /// Number of tiles per row in the tileset
    let tilesPerRow: Int
    /// Size of each tile in pixels (assumes square tiles)
    let tileSizeInPixels: CGFloat
    
    /// Default tileset configuration
    static let `default` = TilesetConfig(
        imageName: "tileset",
        tilesPerRow: 8,
        tileSizeInPixels: 32.0
    )
}

/// Manages tile textures and sprites for the game world.
/// Supports both individual tile images and tileset images.
/// Provides an easy way to add new tiles by simply adding images to the asset catalog.
class TileManager {
    
    static let shared = TileManager()
    
    // Cache for loaded textures
    private var textureCache: [TileType: SKTexture] = [:]
    
    // Tileset support (legacy single tileset)
    private var tilesetTexture: SKTexture?
    private var tilesetConfig: TilesetConfig?
    
    // Multiple tilesets support (for Tiled maps)
    private var tiledTilesets: [TiledTileset] = []
    private var tiledTextures: [String: SKTexture] = [:]  // Cache tileset textures by image name
    private var extractedTextureCache: [String: SKTexture] = [:]  // Cache extracted tile textures by "tilesetName_row_col"
    private var tilesetDimensionsCache: [String: (tilesPerRow: Int, tilesPerCol: Int)] = [:]  // Cache tileset dimensions to avoid calling cgImage() repeatedly
    
    // Mapping of tile types to positions in tileset (row, column)
    // If nil, will try individual images first, then fall back to colors
    // Update these coordinates to match your tileset layout
    // Coordinates are 0-indexed: (row, column)
    // Default mapping for ground_grass_details tileset (21 columns, 16x16 tiles)
    // You may need to adjust these based on your actual tileset layout
    private var tilesetMapping: [TileType: (row: Int, col: Int)] = [
        .grass: (3, 1),   // Start with first tile - adjust based on your tileset
        .dirt: (5, 6),
        .water: (12, 2),
        .stone: (28, 8),
        .forest: (1, 0),  // Second row for forest
        .path: (0, 4)
    ]
    
    // Optional mapping from GID to TileType (for Tiled maps)
    // Set this if you want to use GIDs directly with TileType
    private var gidToTileType: [Int: TileType] = [:]
    
    // Fallback colors if textures aren't found
    private let fallbackColors: [TileType: SKColor] = [
        .grass: SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),
        .dirt: SKColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0),
        .water: SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
        .stone: SKColor(white: 0.5, alpha: 1.0),
        .forest: SKColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1.0),
        .path: SKColor(white: 0.7, alpha: 1.0)
    ]
    
    private init() {
        // Try to load tileset first
        loadTileset()
        // Preload all textures
        preloadTextures()
    }
    
    /// Loads the tileset image if it exists
    private func loadTileset() {
        let config = TilesetConfig.default
        let texture = SKTexture(imageNamed: config.imageName)
        // Check if texture loaded successfully by verifying size
        if texture.size().width > 0 && texture.size().height > 0 {
            tilesetTexture = texture
            tilesetConfig = config
            print("Tileset '\(config.imageName)' loaded successfully")
        }
    }
    
    /// Configures a custom tileset (call this before preloadTextures if using a custom tileset)
    func configureTileset(_ config: TilesetConfig) {
        let texture = SKTexture(imageNamed: config.imageName)
        // Check if texture loaded successfully by verifying size
        if texture.size().width > 0 && texture.size().height > 0 {
            tilesetTexture = texture
            tilesetConfig = config
            // Clear cache and reload
            clearCache()
            preloadTextures()
            print("Custom tileset '\(config.imageName)' loaded successfully")
        } else {
            print("Warning: Tileset '\(config.imageName)' not found")
        }
    }
    
    /// Preloads all tile textures into cache
    private func preloadTextures() {
        for tileType in TileType.allCases {
            loadTexture(for: tileType)
        }
    }
    
    /// Loads a texture for a given tile type.
    /// Priority: 1) Individual tile image, 2) Tileset, 3) Fallback color
    private func loadTexture(for tileType: TileType) -> SKTexture? {
        // Check cache first
        if let cached = textureCache[tileType] {
            return cached
        }
        
        // Try individual tile image first (highest priority)
        let imageName = "tile_\(tileType.rawValue)"
        let texture = SKTexture(imageNamed: imageName)
        // Check if texture loaded successfully by verifying size
        if texture.size().width > 0 && texture.size().height > 0 {
            textureCache[tileType] = texture
            return texture
        }
        
        // Try tileset if available
        if let tileset = tilesetTexture, let config = tilesetConfig,
           let mapping = tilesetMapping[tileType] {
            let texture = extractTileFromTileset(
                tileset: tileset,
                row: mapping.row,
                col: mapping.col,
                tilesPerRow: config.tilesPerRow,
                tileSize: config.tileSizeInPixels
            )
            if texture != nil {
                textureCache[tileType] = texture
                return texture
            }
        }
        
        // If texture not found, return nil (will use fallback color)
        // Only print warning if we're not using Tiled maps/tilesets (to avoid spam)
        // If we have tilesets loaded, we'll use GIDs instead, so don't warn
        // Also check if we're in the initial preload phase (before tilesets are loaded)
        if tiledTilesets.isEmpty {
            // Only warn during initial preload if we're not going to load tilesets
            // We can't know for sure, but if we have no tilesets and this is preload, it's probably fine
            // The warning will appear but it's harmless if tilesets will be loaded later
            print("Warning: Tile texture '\(imageName)' not found. Using fallback color.")
        }
        // If tilesets are loaded, we'll use GIDs, so no warning needed
        return nil
    }
    
    /// Extracts a single tile texture from a tileset image using Core Graphics
    private func extractTileFromTileset(
        tileset: SKTexture,
        row: Int,
        col: Int,
        tilesPerRow: Int,
        tileSize: CGFloat
    ) -> SKTexture? {
        // Get the base CGImage
        let baseCGImage = tileset.cgImage()
        let baseWidth = CGFloat(baseCGImage.width)
        let baseHeight = CGFloat(baseCGImage.height)
        
        // Calculate pixel coordinates
        let sourceX = CGFloat(col) * tileSize
        let sourceY = CGFloat(row) * tileSize
        
        // Validate coordinates
        guard sourceX >= 0 && sourceX + tileSize <= baseWidth &&
              sourceY >= 0 && sourceY + tileSize <= baseHeight else {
            return nil
        }
        
        // Extract the tile using Core Graphics
        guard let croppedCGImage = baseCGImage.cropping(to: CGRect(
            x: sourceX,
            y: sourceY,
            width: tileSize,
            height: tileSize
        )) else {
            return nil
        }
        
        // Create platform-specific image and then SKTexture
        #if os(macOS)
        let tileImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: croppedCGImage.width, height: croppedCGImage.height))
        let texture = SKTexture(image: tileImage)
        #else
        let tileImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .up)
        let texture = SKTexture(image: tileImage)
        #endif
        texture.filteringMode = .nearest
        return texture
    }
    
    /// Creates a sprite node for a tile type.
    /// Uses texture if available, otherwise falls back to color.
    func createTileSprite(for tileType: TileType, size: CGSize) -> SKSpriteNode {
        if let texture = loadTexture(for: tileType) {
            // Use texture
            let sprite = SKSpriteNode(texture: texture, size: size)
            return sprite
        } else {
            // Fall back to color
            let color = fallbackColors[tileType] ?? .gray
            let sprite = SKSpriteNode(color: color, size: size)
            return sprite
        }
    }
    
    /// Gets the texture for a tile type (if available)
    func getTexture(for tileType: TileType) -> SKTexture? {
        return loadTexture(for: tileType)
    }
    
    /// Gets the fallback color for a tile type
    func getFallbackColor(for tileType: TileType) -> SKColor {
        return fallbackColors[tileType] ?? .gray
    }
    
    /// Gets a texture from the tileset at a specific row and column
    /// Useful for finding the right tile positions in your tileset
    func getTileFromTileset(row: Int, col: Int) -> SKTexture? {
        guard let tileset = tilesetTexture, let config = tilesetConfig else {
            print("Warning: No tileset loaded")
            return nil
        }
        
        return extractTileFromTileset(
            tileset: tileset,
            row: row,
            col: col,
            tilesPerRow: config.tilesPerRow,
            tileSize: config.tileSizeInPixels
        )
    }
    
    /// Creates a sprite from the tileset at a specific row and column
    /// Useful for sprites that aren't terrain tiles (trees, buildings, etc.)
    func createSpriteFromTileset(row: Int, col: Int, size: CGSize) -> SKSpriteNode? {
        guard let texture = getTileFromTileset(row: row, col: col) else {
            return nil
        }
        return SKSpriteNode(texture: texture, size: size)
    }
    
    /// Updates the mapping for a specific tile type
    /// Useful for configuring your tileset layout
    func updateTileMapping(_ tileType: TileType, row: Int, col: Int) {
        tilesetMapping[tileType] = (row, col)
        // Clear cache for this tile type so it reloads with new mapping
        textureCache.removeValue(forKey: tileType)
        // Reload the texture
        _ = loadTexture(for: tileType)
        print("Updated \(tileType.rawValue) mapping to row \(row), col \(col)")
    }
    
    /// Clears the texture cache (useful for memory management)
    func clearCache() {
        textureCache.removeAll()
    }
    
    /// Reloads all textures (useful after adding new assets)
    func reloadTextures() {
        clearCache()
        preloadTextures()
    }
    
    // MARK: - Tiled Map Support (Multiple Tilesets)
    
    /// Load tilesets from a parsed Tiled map
    /// Call this after parsing a Tiled map to enable GID-based tile lookup
    func loadTiledTilesets(from tiledMap: TiledMap) {
        tiledTilesets = tiledMap.tilesets
        
        // Load textures for each tileset
        for tileset in tiledTilesets {
            if tiledTextures[tileset.imageName] == nil {
                // Try to load the texture directly - more reliable than checking UIImage first
                let texture = SKTexture(imageNamed: tileset.imageName)
                
                // Verify texture is valid by checking its size (non-blocking check)
                let textureSize = texture.size()
                if textureSize.width > 0 && textureSize.height > 0 {
                    texture.filteringMode = .nearest
                    // Preload base texture asynchronously (don't block!)
                    // SpriteKit will load textures when needed, blocking here causes save loading to be slow
                    texture.preload { }
                    
                    // Store texture - SpriteKit will load it on-demand when actually used
                    // We don't need to access cgImage() here as it's blocking and unnecessary
                    tiledTextures[tileset.imageName] = texture
                }
            }
        }
    }
    
    /// Get the loaded tilesets (for debugging/logging purposes)
    func getTiledTilesets() -> [TiledTileset] {
        return tiledTilesets
    }
    
    /// Extract flip flags from a GID
    /// Returns (actualGID, flipH, flipV, flipD)
    static func extractFlipFlags(from gid: Int) -> (gid: Int, flipH: Bool, flipV: Bool, flipD: Bool) {
        let flipH = (gid & 0x80000000) != 0
        let flipV = (gid & 0x40000000) != 0
        let flipD = (gid & 0x20000000) != 0
        let actualGID = gid & 0x1FFFFFFF  // Mask out flip flags
        return (actualGID, flipH, flipV, flipD)
    }
    
    /// Get a texture for a GID (Global Tile ID) from a Tiled map
    /// Returns nil if the GID is invalid or tileset not found
    /// Note: Tiled stores flip/rotation flags in upper bits, which are masked out
    func getTexture(for gid: Int) -> SKTexture? {
        // GID 0 means empty tile
        guard gid > 0 else { return nil }
        
        // Extract flip flags and actual GID
        let (actualGID, _, _, _) = TileManager.extractFlipFlags(from: gid)
        
        // Find the tileset that contains this GID
        guard let tileset = TiledMapParser.findTileset(for: actualGID, in: tiledTilesets) else {
            return nil
        }
        
        // Get the texture for this tileset
        guard let tilesetTexture = tiledTextures[tileset.imageName] else {
            return nil
        }
        
        // Get row and column for this GID
        guard let (row, col) = tileset.getRowCol(for: actualGID) else {
            return nil
        }
        
        // Extract the tile from the tileset
        guard let texture = extractTileFromTiledTileset(
            tilesetTexture: tilesetTexture,
            tileset: tileset,
            row: row,
            col: col
        ) else {
            return nil
        }
        
        // Debug: Log first few successful texture extractions (disabled to reduce spam)
        // if actualGID <= 10 || actualGID == 1116 {
        //     print("✓ Extracted texture for GID \(gid) (actual: \(actualGID)) from '\(tileset.name)' at row \(row), col \(col)")
        // }
        
        return texture
    }
    
    // Track GID sprite creation attempts
    private var gidAttempts: Set<Int> = []
    
    /// Create a sprite for a GID with flip transforms applied
    func createSprite(for gid: Int, size: CGSize) -> SKSpriteNode? {
        guard let texture = getTexture(for: gid) else {
            return nil
        }
        
        // Extract flip flags from the original GID
        let (_, flipH, flipV, flipD) = TileManager.extractFlipFlags(from: gid)
        
        // Verify texture is valid
        let textureSize = texture.size()
        guard textureSize.width > 0 && textureSize.height > 0 else {
            return nil
        }
        
        // Set texture filtering mode
        texture.filteringMode = .nearest
        
        // CRITICAL: Preload asynchronously (don't block!)
        // SpriteKit handles texture loading when sprites are rendered
        // Blocking here causes save loading to take forever
        texture.preload { }
        
        // Create sprite with explicit size
        let sprite = SKSpriteNode(texture: texture, size: size)
        
        // CRITICAL: Apply flip transforms
        // Horizontal flip: negate x scale
        if flipH {
            sprite.xScale = -1.0
        }
        // Vertical flip: negate y scale
        if flipV {
            sprite.yScale = -1.0
        }
        // Diagonal flip: swap axes and rotate
        // In Tiled, diagonal flip means swap X/Y and rotate 90 degrees
        // Common SpriteKit approach: rotate 90 degrees and apply flips
        if flipD {
            // Rotate 90 degrees counter-clockwise
            sprite.zRotation = CGFloat.pi / 2
            // If both H and V are flipped, we need to adjust
            if flipH && flipV {
                // Both flips + diagonal = 180 degree rotation
                sprite.zRotation = CGFloat.pi
                sprite.xScale = 1.0
                sprite.yScale = 1.0
            } else if flipH {
                // H flip + diagonal
                sprite.xScale = -1.0
                sprite.yScale = 1.0
            } else if flipV {
                // V flip + diagonal
                sprite.xScale = 1.0
                sprite.yScale = -1.0
            }
        }
        
        // CRITICAL: Ensure sprite is visible and properly configured
        sprite.alpha = 1.0
        sprite.isHidden = false
        sprite.colorBlendFactor = 0.0  // Don't blend with color, use texture as-is
        sprite.color = .white  // Ensure color is white (no tinting)
        sprite.zPosition = 0
        
        // Ensure sprite has valid size
        if size.width <= 0 || size.height <= 0 {
            sprite.size = CGSize(width: max(1, size.width), height: max(1, size.height))
        }
        
        // Verify the sprite has the texture attached
        guard sprite.texture != nil else {
            return nil
        }
        
        // CRITICAL: Add animation support for animated tilesets using ACTUAL animation data from TMX
        // Each tile in an animated tileset has specific animation frames defined in the TMX
        let (actualGID, _, _, _) = TileManager.extractFlipFlags(from: gid)
        if let tileset = TiledMapParser.findTileset(for: actualGID, in: tiledTilesets) {
            // Get the local tile ID within this tileset
            let localTileID = actualGID - tileset.firstGID
            
            // Check if this specific tile has animation data defined
            if let tileAnimation = tileset.animations[localTileID] {
                // Use the ACTUAL animation frames from the TMX
                var animationTextures: [SKTexture] = []
                var frameDurations: [TimeInterval] = []
                
                for frame in tileAnimation.frames {
                    // Convert local tile ID to GID
                    let frameGID = tileset.firstGID + frame.tileID
                    if let frameTexture = getTexture(for: frameGID) {
                        animationTextures.append(frameTexture)
                        // Convert duration from milliseconds to seconds
                        frameDurations.append(TimeInterval(frame.duration) / 1000.0)
                    }
                }
                
                // Only animate if we have multiple frames
                if animationTextures.count > 1 {
                    // Create animation with variable frame durations from TMX
                    // Use average duration if durations vary, or specific durations per frame
                    var actions: [SKAction] = []
                    for (index, texture) in animationTextures.enumerated() {
                        let duration = index < frameDurations.count ? frameDurations[index] : 0.15
                        actions.append(SKAction.setTexture(texture))
                        actions.append(SKAction.wait(forDuration: duration))
                    }
                    
                    // Remove last wait action (we don't need to wait after the last frame before looping)
                    if actions.count > 2 {
                        actions.removeLast()
                    }
                    
                    let animationSequence = SKAction.sequence(actions)
                    let repeatAction = SKAction.repeatForever(animationSequence)
                    sprite.run(repeatAction, withKey: "tileAnimation")
                }
            }
        }
        
        return sprite
    }
    
    /// Extract a tile from a Tiled tileset using Core Graphics (reliable method)
    /// This creates an actual separate texture instead of using SKTexture(rect:in:)
    private func extractTileFromTiledTileset(
        tilesetTexture: SKTexture,
        tileset: TiledTileset,
        row: Int,
        col: Int
    ) -> SKTexture? {
        // Check cache first
        let cacheKey = "\(tileset.imageName)_\(row)_\(col)"
        if let cached = extractedTextureCache[cacheKey] {
            return cached
        }
        
        // CRITICAL: Use SKTexture(rect:in:) instead of Core Graphics extraction
        // This is MUCH faster - no image cropping/copying, just creates a sub-texture reference
        // Get texture size in points (SpriteKit coordinates)
        // This already accounts for @2x/@3x scaling - if image is 272x272px @2x, size() returns 136x136 points
        let textureSize = tilesetTexture.size()
        let baseWidth = textureSize.width
        let baseHeight = textureSize.height
        
        // IMPORTANT: SKTexture(rect:in:) uses normalized coordinates (0.0 to 1.0) relative to texture size in POINTS
        // The texture size in points already accounts for @2x/@3x scaling
        // So we should normalize using the texture size in points, not the pixel dimensions
        
        // CRITICAL PERFORMANCE FIX: Cache tileset dimensions to avoid calling cgImage() for every tile!
        // cgImage() is a blocking call that's extremely slow when called thousands of times
        let (tilesPerRow, tilesPerCol): (Int, Int)
        if let cached = tilesetDimensionsCache[tileset.imageName] {
            tilesPerRow = cached.tilesPerRow
            tilesPerCol = cached.tilesPerCol
        } else {
            // Only call cgImage() once per tileset (not once per tile!)
            let cgImage = tilesetTexture.cgImage()
            let actualImageWidthPixels = CGFloat(cgImage.width)
            let actualImageHeightPixels = CGFloat(cgImage.height)
            
            // Calculate how many tiles fit in the actual image (in pixels)
            // This is the REAL layout of the image file, regardless of what TMX says
            tilesPerRow = max(1, Int(actualImageWidthPixels / CGFloat(tileset.tileWidth)))
            tilesPerCol = max(1, Int(actualImageHeightPixels / CGFloat(tileset.tileHeight)))
            
            // Cache the dimensions for this tileset
            tilesetDimensionsCache[tileset.imageName] = (tilesPerRow: tilesPerRow, tilesPerCol: tilesPerCol)
        }
        
        // Validate that row/col are within actual bounds
        guard row < tilesPerCol && col < tilesPerRow else {
            return nil
        }
        
        // Calculate tile dimensions in points based on actual texture size
        // Divide the actual texture size by the actual number of tiles
        let tileWidthPoints = baseWidth / CGFloat(tilesPerRow)
        let tileHeightPoints = baseHeight / CGFloat(tilesPerCol)
        
        // Calculate normalized coordinates (0.0 to 1.0) using point dimensions
        // X coordinate: simple division (left to right)
        let normalizedX = (CGFloat(col) * tileWidthPoints) / baseWidth
        let normalizedWidth = tileWidthPoints / baseWidth
        
        // Y coordinate: Flip for SpriteKit's bottom-left origin
        // In Tiled: row 0 is at top (Y=0), row N is at Y=N*tileHeight
        // In SpriteKit: y=0 is bottom, y=1 is top (normalized coordinates)
        // Formula: normalizedY = 1.0 - ((row + 1) * tileHeight) / baseHeight
        // This gives: row 0 -> y = 1.0 - tileHeight/baseHeight (bottom of top tile)
        let normalizedY = 1.0 - ((CGFloat(row + 1) * tileHeightPoints) / baseHeight)
        let normalizedHeight = tileHeightPoints / baseHeight
        
        // Validate normalized coordinates
        guard normalizedX >= 0 && normalizedX + normalizedWidth <= 1.0 &&
              normalizedY >= 0 && normalizedY + normalizedHeight <= 1.0 else {
            return nil
        }
        
        
        // Create the normalized rect
        let rect = CGRect(x: normalizedX, y: normalizedY, width: normalizedWidth, height: normalizedHeight)
        
        // CRITICAL: Use SKTexture(rect:in:) - this is fast (no image copying) and works reliably
        let texture = SKTexture(rect: rect, in: tilesetTexture)
        texture.filteringMode = .nearest
        
        // Preload asynchronously (don't block)
        texture.preload { }
        
        // Verify the texture has valid size
        let texSize = texture.size()
        guard texSize.width > 0 && texSize.height > 0 else {
            return nil
        }
        
        // Cache the texture
        extractedTextureCache[cacheKey] = texture
        
        // Debug logging for first few tiles (disabled to reduce spam during loading)
        // if (row == 0 && col <= 5) || (row <= 1 && col == 0) {
        //     print("✅ Extracted tile row \(row), col \(col) from '\(tileset.imageName)' using SKTexture(rect:in:)")
        //     print("   Base texture size: \(baseWidth)x\(baseHeight) points")
        //     print("   Tile size: \(tileWidth)x\(tileHeight) points")
        //     print("   Normalized rect: (\(String(format: "%.4f", normalizedX)), \(String(format: "%.4f", normalizedY)), \(String(format: "%.4f", normalizedWidth)), \(String(format: "%.4f", normalizedHeight)))")
        //     print("   Extracted texture size: \(texture.size()) points")
        // }
        
        return texture
    }
    
    /// Set a mapping from GID to TileType
    /// This allows you to use GIDs with the existing TileType system
    func setGIDMapping(_ mapping: [Int: TileType]) {
        gidToTileType = mapping
    }
    
    /// Get TileType for a GID (if mapping is set)
    func getTileType(for gid: Int) -> TileType? {
        return gidToTileType[gid]
    }
    
    /// Create a sprite for a GID, falling back to TileType if mapping exists
    func createSpriteWithFallback(for gid: Int, size: CGSize) -> SKSpriteNode {
        // Try GID first
        if let sprite = createSprite(for: gid, size: size) {
            return sprite
        }
        
        // Fall back to TileType if mapping exists
        if let tileType = getTileType(for: gid) {
            return createTileSprite(for: tileType, size: size)
        }
        
        // Final fallback: gray rectangle
        return SKSpriteNode(color: .gray, size: size)
    }
    
    // MARK: - TileType to GID Mapping for Procedural Generation
    
    // Track which tile types we've logged to avoid spam
    private var loggedTileTypes: Set<TileType> = []
    
    /// Maps TileType to GIDs from loaded tilesets for procedural generation
    /// Returns a GID that can be used with createSprite(for:size:)
    /// Returns nil if no suitable GID found
    func getGID(for tileType: TileType) -> Int? {
        // If we have loaded tilesets, try to find appropriate GIDs
        // This is a simple mapping - you can enhance this to pick random variations
        guard !tiledTilesets.isEmpty else {
            return nil
        }
        
        // Use exterior tileset (firstGID 757) for all terrain types
        // The exterior tileset has 969 tiles in a 17-column layout
        let exteriorTileset = tiledTilesets.first { $0.name == "exterior" }
        let groundTileset = tiledTilesets.first { $0.name == "ground_grass_details" && $0.firstGID == 1 }
        
        // Map tile types to GIDs in the exterior tileset
        // Note: The first tile (GID 757, row 0, col 0) might be empty/transparent
        // Try using tiles further into the tileset - adjust these offsets based on your actual tileset layout
        // The exterior tileset has 17 columns, so row = localID / 17, col = localID % 17
        let gid: Int?
        switch tileType {
        case .grass:
            // Use exterior tileset for grass
            // Skip the first tile (often empty/transparent) and use a tile that likely has content
            // Try row 0, col 2 (localID 2) or row 1, col 0 (localID 17) - these are more likely to have visible content
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 2  // Skip first 2 tiles, use third tile (row 0, col 2)
            } else {
                gid = 759  // 757 + 2
            }
        case .dirt:
            // Use exterior tileset for dirt
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 3  // Fourth tile
            } else {
                gid = 760
            }
        case .water:
            // Use exterior tileset for water
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 4  // Fifth tile
            } else {
                gid = 761
            }
        case .stone:
            // Use exterior tileset for stone
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 5  // Sixth tile
            } else {
                gid = 762
            }
        case .forest:
            // Use exterior tileset for forest (try a few rows down for tree tiles)
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 17  // Second row, first column (17 = one full row)
            } else {
                gid = 774
            }
        case .path:
            // Use exterior tileset for path
            if let firstGID = exteriorTileset?.firstGID {
                gid = firstGID + 6  // Seventh tile
            } else {
                gid = 763
            }
        }
        
        // Log once per tile type for debugging (commented out to reduce noise)
        // if !loggedTileTypes.contains(tileType) {
        //     print("DEBUG: Mapping \(tileType) - groundTileset: \(groundTileset != nil ? "found (GID \(groundTileset!.firstGID))" : "not found"), exteriorTileset: \(exteriorTileset != nil ? "found (GID \(exteriorTileset!.firstGID))" : "not found")")
        //     print("DEBUG: Using GID \(gid ?? -1) for \(tileType)")
        //     loggedTileTypes.insert(tileType)
        // }
        
        return gid
    }
    
    // Track successful GID sprite creation to avoid spam
    private var successfulGIDTypes: Set<TileType> = []
    
    /// Create a sprite for a TileType using GIDs from loaded tilesets
    /// Falls back to the old TileType system if no tilesets are loaded
    func createTileSpriteFromTilesets(for tileType: TileType, size: CGSize) -> SKSpriteNode {
        // Try to get a GID from loaded tilesets
        if let gid = getGID(for: tileType) {
            if let sprite = createSprite(for: gid, size: size) {
                // Verify sprite has valid texture and size
                if sprite.texture != nil && sprite.size.width > 0 && sprite.size.height > 0 {
                    // Success! Use the texture sprite
                    sprite.alpha = 1.0
                    sprite.isHidden = false
                    return sprite
                }
            }
        }
        let color = fallbackColors[tileType] ?? .gray
        let sprite = SKSpriteNode(color: color, size: size)
        sprite.alpha = 1.0
        sprite.isHidden = false
        sprite.zPosition = 0
        
        return sprite
    }
}

// TileType now conforms to CaseIterable, so we can use TileType.allCases directly

