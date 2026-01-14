//
//  TiledMapParser.swift
//  Domaterra Shared
//
//  Created by Scott Landes on 1/7/26.
//

import Foundation
import SpriteKit

/// Represents animation frame data for a tile
struct TiledAnimationFrame {
    let tileID: Int  // Local tile ID (relative to tileset, 0-indexed)
    let duration: Int  // Duration in milliseconds
}

/// Represents animation data for a tile
struct TiledTileAnimation {
    let tileID: Int  // Local tile ID this animation belongs to (0-indexed)
    let frames: [TiledAnimationFrame]  // Sequence of frames to animate through
}

/// Represents a single tileset from a Tiled map
struct TiledTileset {
    let firstGID: Int  // First Global ID for this tileset (1-indexed)
    let name: String
    let tileWidth: Int
    let tileHeight: Int
    let tileCount: Int
    let columns: Int
    let imageName: String  // Name of the image file (without path)
    let imageWidth: Int
    let imageHeight: Int
    let animations: [Int: TiledTileAnimation]  // Map of local tile ID -> animation data
    
    /// Calculate which tile in this tileset a GID refers to
    func localTileID(for gid: Int) -> Int {
        return gid - firstGID
    }
    
    /// Check if a GID belongs to this tileset
    func contains(gid: Int) -> Bool {
        let localID = localTileID(for: gid)
        return localID >= 0 && localID < tileCount
    }
    
    /// Get row and column for a GID in this tileset
    func getRowCol(for gid: Int) -> (row: Int, col: Int)? {
        guard contains(gid: gid) else { return nil }
        let localID = localTileID(for: gid)
        let row = localID / columns
        let col = localID % columns
        return (row: row, col: col)
    }
}

/// Represents a parsed Tiled map
struct TiledMap {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let tilesets: [TiledTileset]
    let layers: [TiledLayer]
    let objectGroups: [TiledObjectGroup]  // Object layers (objectgroups)
}

/// Represents a chunk in an infinite map
struct TiledChunk {
    let x: Int  // Chunk X coordinate in tiles
    let y: Int  // Chunk Y coordinate in tiles
    let width: Int
    let height: Int
    let data: [Int]  // Array of GIDs (1-indexed, 0 means empty)
}

/// Represents a layer in a Tiled map
struct TiledLayer {
    let name: String
    let width: Int
    let height: Int
    let data: [Int]?  // Array of GIDs for non-infinite maps (1-indexed, 0 means empty)
    let chunks: [TiledChunk]?  // Chunks for infinite maps
    let isInfinite: Bool
    let properties: [String: String]  // Custom properties from Tiled (property name -> value)
    
    /// Get a boolean property, defaulting to false if not found
    func boolProperty(_ name: String, default: Bool = false) -> Bool {
        guard let value = properties[name] else { return `default` }
        return value.lowercased() == "true" || value == "1"
    }
    
    /// Get a float property, defaulting to 0 if not found
    func floatProperty(_ name: String, default: Float = 0) -> Float {
        guard let value = properties[name], let floatValue = Float(value) else { return `default` }
        return floatValue
    }
    
    /// Get a string property, defaulting to nil if not found
    func stringProperty(_ name: String) -> String? {
        return properties[name]
    }
}

/// Represents an object in a Tiled object layer
struct TiledObject {
    let id: Int
    let name: String
    let type: String?  // Object type (optional)
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let gid: Int?  // Global ID if object uses a tile (optional)
    let properties: [String: String]  // Custom properties from Tiled
    
    /// Get a boolean property, defaulting to false if not found
    func boolProperty(_ name: String, default: Bool = false) -> Bool {
        guard let value = properties[name] else { return `default` }
        return value.lowercased() == "true" || value == "1"
    }
    
    /// Get a float property, defaulting to 0 if not found
    func floatProperty(_ name: String, default: Float = 0) -> Float {
        guard let value = properties[name], let floatValue = Float(value) else { return `default` }
        return floatValue
    }
    
    /// Get a string property, defaulting to nil if not found
    func stringProperty(_ name: String) -> String? {
        return properties[name]
    }
}

/// Represents an object group (object layer) in a Tiled map
struct TiledObjectGroup {
    let id: Int
    let name: String
    let objects: [TiledObject]
    let properties: [String: String]  // Custom properties from Tiled
    
    /// Get a boolean property, defaulting to false if not found
    func boolProperty(_ name: String, default: Bool = false) -> Bool {
        guard let value = properties[name] else { return `default` }
        return value.lowercased() == "true" || value == "1"
    }
}

/// Parser for Tiled map files (TMX format)
class TiledMapParser {
    
    /// Parse a Tiled map XML file
    static func parse(fileName: String) -> TiledMap? {
        print("Looking for Tiled map file: \(fileName).tmx")
        
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "tmx") else {
            print("ERROR: Could not find '\(fileName).tmx' in app bundle")
            print("  Make sure the file is added to your target in Xcode")
            print("  Check: Target → Build Phases → Copy Bundle Resources")
            return nil
        }
        
        print("Found TMX file at: \(url.path)")
        
        guard let data = try? Data(contentsOf: url) else {
            print("ERROR: Could not read data from '\(fileName).tmx'")
            return nil
        }
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            print("ERROR: Could not decode '\(fileName).tmx' as UTF-8")
            return nil
        }
        
        print("Successfully loaded TMX file (\(data.count) bytes)")
        return parse(xmlString: xmlString)
    }
    
    /// Parse a Tiled map from XML string
    static func parse(xmlString: String) -> TiledMap? {
        // Simple XML parsing using string operations
        // For production, consider using XMLParser or a proper XML library
        
        guard let mapTag = extractTag(xmlString, tag: "map") else {
            print("Error: Could not find <map> tag")
            return nil
        }
        
        // Parse map attributes
        let width = Int(extractAttribute(mapTag, name: "width") ?? "0") ?? 0
        let height = Int(extractAttribute(mapTag, name: "height") ?? "0") ?? 0
        let tileWidth = Int(extractAttribute(mapTag, name: "tilewidth") ?? "32") ?? 32
        let tileHeight = Int(extractAttribute(mapTag, name: "tileheight") ?? "32") ?? 32
        
        // Parse tilesets
        var tilesets: [TiledTileset] = []
        var tilesetStrings = extractAllTags(xmlString, tag: "tileset")
        for tilesetString in tilesetStrings {
            if let tileset = parseTileset(tilesetString) {
                tilesets.append(tileset)
            }
        }
        
        // Sort tilesets by firstGID to ensure correct lookup
        tilesets.sort { $0.firstGID < $1.firstGID }
        
        // Parse layers
        var layers: [TiledLayer] = []
        let layerStrings = extractAllTags(xmlString, tag: "layer")
        for layerString in layerStrings {
            if let layer = parseLayer(layerString) {
                layers.append(layer)
            }
        }
        
        // Parse object groups (object layers)
        var objectGroups: [TiledObjectGroup] = []
        let objectGroupStrings = extractAllTags(xmlString, tag: "objectgroup")
        print("🔍 Found \(objectGroupStrings.count) objectgroup tags in TMX file")
        for objectGroupString in objectGroupStrings {
            if let objectGroup = parseObjectGroup(objectGroupString) {
                print("✅ Parsed object group '\(objectGroup.name)' with \(objectGroup.objects.count) objects")
                objectGroups.append(objectGroup)
            } else {
                print("⚠️ Failed to parse object group")
            }
        }
        
        return TiledMap(
            width: width,
            height: height,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            tilesets: tilesets,
            layers: layers,
            objectGroups: objectGroups
        )
    }
    
    /// Parse a tileset tag
    private static func parseTileset(_ tilesetString: String) -> TiledTileset? {
        let firstGID = Int(extractAttribute(tilesetString, name: "firstgid") ?? "1") ?? 1
        let name = extractAttribute(tilesetString, name: "name") ?? "unknown"
        let tileWidth = Int(extractAttribute(tilesetString, name: "tilewidth") ?? "32") ?? 32
        let tileHeight = Int(extractAttribute(tilesetString, name: "tileheight") ?? "32") ?? 32
        let tileCount = Int(extractAttribute(tilesetString, name: "tilecount") ?? "0") ?? 0
        let columns = Int(extractAttribute(tilesetString, name: "columns") ?? "0") ?? 0
        
        // Parse image tag
        guard let imageTag = extractTag(tilesetString, tag: "image") else {
            print("Warning: Tileset '\(name)' has no image tag")
            return nil
        }
        
        let source = extractAttribute(imageTag, name: "source") ?? ""
        // Extract just the filename (remove path and extension)
        // Handle both "exterior.png" and "../path/exterior.png" cases
        var imageName = (source as NSString).lastPathComponent
        // Remove extension if present (.png, .jpg, etc.)
        if let dotIndex = imageName.lastIndex(of: ".") {
            imageName = String(imageName[..<dotIndex])
        }
        let imageWidth = Int(extractAttribute(imageTag, name: "width") ?? "0") ?? 0
        let imageHeight = Int(extractAttribute(imageTag, name: "height") ?? "0") ?? 0
        
        // Debug: Log extracted image name
        if imageName.isEmpty {
            print("⚠️ WARNING: Empty image name extracted from source '\(source)' for tileset '\(name)'")
        } else {
            print("📋 Parsed tileset '\(name)': imageName='\(imageName)', source='\(source)'")
        }
        
        // Parse animation data for tiles in this tileset
        var animations: [Int: TiledTileAnimation] = [:]
        
        // Find all <tile> tags with animations in this tileset
        // Pattern: <tile id="0"> ... <animation> ... <frame tileid="..." duration="..."/> ... </animation> ... </tile>
        var searchStart = tilesetString.startIndex
        while let tileStartRange = tilesetString.range(of: "<tile id=\"", range: searchStart..<tilesetString.endIndex) {
            // Find the tile ID
            let idStart = tileStartRange.upperBound
            guard let idEndRange = tilesetString.range(of: "\"", range: idStart..<tilesetString.endIndex),
                  let tileID = Int(tilesetString[idStart..<idEndRange.lowerBound]) else {
                searchStart = tileStartRange.upperBound
                continue
            }
            
            // Find the end of this tile tag
            guard let tileEndRange = tilesetString.range(of: "</tile>", range: idEndRange.upperBound..<tilesetString.endIndex) else {
                searchStart = tileStartRange.upperBound
                continue
            }
            
            // Extract the tile content
            let tileContent = String(tilesetString[idEndRange.upperBound..<tileEndRange.lowerBound])
            
            // Look for animation tag
            if let animStartRange = tileContent.range(of: "<animation>"),
               let animEndRange = tileContent.range(of: "</animation>", range: animStartRange.upperBound..<tileContent.endIndex) {
                let animContent = String(tileContent[animStartRange.upperBound..<animEndRange.lowerBound])
                
                // Parse all frame tags
                var frames: [TiledAnimationFrame] = []
                var frameSearchStart = animContent.startIndex
                while let frameStart = animContent.range(of: "<frame", range: frameSearchStart..<animContent.endIndex) {
                    // Find end of frame tag
                    guard let frameEnd = animContent.range(of: "/>", range: frameStart.upperBound..<animContent.endIndex) else {
                        break
                    }
                    
                    let frameTag = String(animContent[frameStart.lowerBound..<frameEnd.upperBound])
                    
                    // Extract tileid and duration attributes
                    let frameTileID = extractAttribute(frameTag, name: "tileid") ?? "0"
                    let frameDuration = extractAttribute(frameTag, name: "duration") ?? "150"
                    
                    if let frameTileIDInt = Int(frameTileID),
                       let frameDurationInt = Int(frameDuration) {
                        frames.append(TiledAnimationFrame(tileID: frameTileIDInt, duration: frameDurationInt))
                    }
                    
                    frameSearchStart = frameEnd.upperBound
                }
                
                if !frames.isEmpty {
                    animations[tileID] = TiledTileAnimation(tileID: tileID, frames: frames)
                    print("   📋 Found animation for tile \(tileID): \(frames.count) frames")
                }
            }
            
            searchStart = tileEndRange.upperBound
        }
        
        if !animations.isEmpty {
            print("📋 Parsed \(animations.count) animations for tileset '\(name)'")
        }
        
        return TiledTileset(
            firstGID: firstGID,
            name: name,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            tileCount: tileCount,
            columns: columns,
            imageName: imageName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            animations: animations
        )
    }
    
    /// Parse a layer tag
    private static func parseLayer(_ layerString: String) -> TiledLayer? {
        let name = extractAttribute(layerString, name: "name") ?? "layer"
        let width = Int(extractAttribute(layerString, name: "width") ?? "0") ?? 0
        let height = Int(extractAttribute(layerString, name: "height") ?? "0") ?? 0
        
        // Parse properties
        let properties = parseProperties(layerString)
        
        // Parse data tag
        guard let dataTag = extractTag(layerString, tag: "data") else {
            print("Warning: Layer '\(name)' has no data tag")
            return nil
        }
        
        // Check if this is an infinite map with chunks
        let chunkStrings = extractAllTags(dataTag, tag: "chunk")
        
        if !chunkStrings.isEmpty {
            // Parse chunks for infinite maps
            var chunks: [TiledChunk] = []
            for chunkString in chunkStrings {
                if let chunk = parseChunk(chunkString) {
                    chunks.append(chunk)
                }
            }
            return TiledLayer(name: name, width: width, height: height, data: nil, chunks: chunks, isInfinite: true, properties: properties)
        } else {
            // Parse regular data for non-infinite maps
            let encoding = extractAttribute(dataTag, name: "encoding") ?? "csv"
            var gids: [Int] = []
            
            if encoding == "csv" {
                // Remove whitespace and split by comma
                let content = dataTag
                    .replacingOccurrences(of: "<data[^>]*>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</data>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let values = content.components(separatedBy: ",")
                gids = values.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            } else {
                print("Warning: Unsupported encoding '\(encoding)' for layer '\(name)'")
            }
            
            return TiledLayer(name: name, width: width, height: height, data: gids, chunks: nil, isInfinite: false, properties: properties)
        }
    }
    
    /// Parse an objectgroup tag
    private static func parseObjectGroup(_ objectGroupString: String) -> TiledObjectGroup? {
        let id = Int(extractAttribute(objectGroupString, name: "id") ?? "0") ?? 0
        let name = extractAttribute(objectGroupString, name: "name") ?? "objectgroup"
        
        // Parse properties
        let properties = parseProperties(objectGroupString)
        
        // Parse all object tags within this objectgroup
        // Objects can be either <object ... /> (self-closing) or <object ...></object>
        var objects: [TiledObject] = []
        var foundObjectIDs: Set<Int> = []
        
        // First try self-closing tags: <object ... />
        let selfClosingPattern = "<object([^>]*)/>"
        if let regex = try? NSRegularExpression(pattern: selfClosingPattern, options: []) {
            let matches = regex.matches(in: objectGroupString, range: NSRange(objectGroupString.startIndex..., in: objectGroupString))
            for match in matches {
                if match.numberOfRanges > 0 {
                    let range = Range(match.range(at: 0), in: objectGroupString)!
                    let objectTag = String(objectGroupString[range])
                    if let object = parseObject(objectTag) {
                        if !foundObjectIDs.contains(object.id) {
                            objects.append(object)
                            foundObjectIDs.insert(object.id)
                            print("   ✅ Parsed self-closing object: id=\(object.id), name='\(object.name)', gid=\(object.gid?.description ?? "nil")")
                        }
                    } else {
                        print("   ⚠️ Failed to parse self-closing object tag: \(objectTag.prefix(100))")
                    }
                }
            }
        }
        
        // Then try regular tags with content (to catch any we might have missed)
        let objectStrings = extractAllTags(objectGroupString, tag: "object")
        for objectString in objectStrings {
            // Extract just the opening tag (before any content)
            if let tagStart = objectString.range(of: "<object"),
               let tagEnd = objectString.range(of: ">", range: tagStart.upperBound..<objectString.endIndex) {
                let objectTag = String(objectString[tagStart.lowerBound..<tagEnd.upperBound])
                // Only add if we haven't already added this object (avoid duplicates)
                if let object = parseObject(objectTag),
                   !foundObjectIDs.contains(object.id) {
                    objects.append(object)
                    foundObjectIDs.insert(object.id)
                    print("   ✅ Parsed object with content: id=\(object.id), name='\(object.name)', gid=\(object.gid?.description ?? "nil")")
                }
            } else if let object = parseObject(objectString),
                      !foundObjectIDs.contains(object.id) {
                objects.append(object)
                foundObjectIDs.insert(object.id)
                print("   ✅ Parsed object (fallback): id=\(object.id), name='\(object.name)', gid=\(object.gid?.description ?? "nil")")
            }
        }
        
        print("   📦 Parsed \(objects.count) objects from object group '\(name)'")
        
        return TiledObjectGroup(id: id, name: name, objects: objects, properties: properties)
    }
    
    /// Parse an object tag
    private static func parseObject(_ objectString: String) -> TiledObject? {
        let id = Int(extractAttribute(objectString, name: "id") ?? "0") ?? 0
        let name = extractAttribute(objectString, name: "name") ?? ""
        let type = extractAttribute(objectString, name: "type")
        
        // Parse position and size (required)
        let x = CGFloat(Double(extractAttribute(objectString, name: "x") ?? "0") ?? 0)
        let y = CGFloat(Double(extractAttribute(objectString, name: "y") ?? "0") ?? 0)
        let width = CGFloat(Double(extractAttribute(objectString, name: "width") ?? "0") ?? 0)
        let height = CGFloat(Double(extractAttribute(objectString, name: "height") ?? "0") ?? 0)
        
        // Parse GID if present (object uses a tile)
        let gid: Int?
        if let gidString = extractAttribute(objectString, name: "gid") {
            gid = Int(gidString)
        } else {
            gid = nil
        }
        
        // Parse properties
        let properties = parseProperties(objectString)
        
        return TiledObject(
            id: id,
            name: name,
            type: type,
            x: x,
            y: y,
            width: width,
            height: height,
            gid: gid,
            properties: properties
        )
    }
    
    /// Parse properties from a tag (works for layers, objects, etc.)
    private static func parseProperties(_ tagString: String) -> [String: String] {
        var properties: [String: String] = [:]
        
        // Look for <properties> tag
        guard let propertiesTag = extractTag(tagString, tag: "properties") else {
            return properties
        }
        
        // Find all <property> tags within <properties>
        var searchStart = propertiesTag.startIndex
        while let propStart = propertiesTag.range(of: "<property", range: searchStart..<propertiesTag.endIndex) {
            // Find the end of this property tag
            guard let propEnd = propertiesTag.range(of: "/>", range: propStart.upperBound..<propertiesTag.endIndex) else {
                // Try closing tag instead
                guard let propEndTag = propertiesTag.range(of: "</property>", range: propStart.upperBound..<propertiesTag.endIndex) else {
                    break
                }
                searchStart = propEndTag.upperBound
                continue
            }
            
            let propTag = String(propertiesTag[propStart.lowerBound..<propEnd.upperBound])
            
            // Extract name and value attributes
            if let propName = extractAttribute(propTag, name: "name"),
               let propValue = extractAttribute(propTag, name: "value") {
                properties[propName] = propValue
            }
            
            searchStart = propEnd.upperBound
        }
        
        return properties
    }
    
    /// Parse a chunk tag (for infinite maps)
    private static func parseChunk(_ chunkString: String) -> TiledChunk? {
        let x = Int(extractAttribute(chunkString, name: "x") ?? "0") ?? 0
        let y = Int(extractAttribute(chunkString, name: "y") ?? "0") ?? 0
        let width = Int(extractAttribute(chunkString, name: "width") ?? "0") ?? 0
        let height = Int(extractAttribute(chunkString, name: "height") ?? "0") ?? 0
        
        // Parse CSV data from chunk
        // Extract content between <chunk...> and </chunk>
        let content = chunkString
            .replacingOccurrences(of: "<chunk[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</chunk>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split by comma and filter out empty strings and invalid values
        let values = content.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        
        // If we have fewer values than expected, pad with zeros (or log warning)
        let expectedCount = width * height
        var gids = values
        if gids.count < expectedCount {
            print("Warning: Chunk at (\(x), \(y)) has \(gids.count) values, expected \(expectedCount). Padding with zeros.")
            gids.append(contentsOf: Array(repeating: 0, count: expectedCount - gids.count))
        } else if gids.count > expectedCount {
            print("Warning: Chunk at (\(x), \(y)) has \(gids.count) values, expected \(expectedCount). Truncating.")
            gids = Array(gids.prefix(expectedCount))
        }
        
        return TiledChunk(x: x, y: y, width: width, height: height, data: gids)
    }
    
    /// Find which tileset contains a given GID
    static func findTileset(for gid: Int, in tilesets: [TiledTileset]) -> TiledTileset? {
        // GIDs are 1-indexed, 0 means empty
        guard gid > 0 else { return nil }
        
        // Find the tileset with the highest firstGID that's still <= gid
        // Since tilesets are sorted by firstGID, we can iterate backwards
        for tileset in tilesets.reversed() {
            if tileset.contains(gid: gid) {
                return tileset
            }
        }
        
        return nil
    }
    
    // MARK: - Helper functions for XML parsing
    
    /// Extract a tag and its content from XML string
    /// Handles both self-closing tags (<tag/>) and tags with content (<tag>content</tag>)
    private static func extractTag(_ xml: String, tag: String) -> String? {
        // First try self-closing tag pattern: <tag .../>
        let selfClosingPattern = "<\(tag)([^>]*)/>"
        if let regex = try? NSRegularExpression(pattern: selfClosingPattern, options: []),
           let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
           match.numberOfRanges > 1 {
            // Return the full self-closing tag for attribute extraction
            let range = Range(match.range(at: 0), in: xml)!
            return String(xml[range])
        }
        
        // Then try regular tag with content: <tag>content</tag>
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = Range(match.range(at: 1), in: xml)!
        return String(xml[range])
    }
    
    /// Extract all occurrences of a tag
    /// Handles both self-closing tags (<tag .../>) and tags with content (<tag>content</tag>)
    private static func extractAllTags(_ xml: String, tag: String) -> [String] {
        var results: [String] = []
        
        // First, find all self-closing tags: <tag .../>
        let selfClosingPattern = "<\(tag)([^>]*)/>"
        if let regex = try? NSRegularExpression(pattern: selfClosingPattern, options: []) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if match.numberOfRanges > 0 {
                    let range = Range(match.range(at: 0), in: xml)!
                    results.append(String(xml[range]))
                }
            }
        }
        
        // Then, find all tags with content: <tag>content</tag>
        let contentPattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        if let regex = try? NSRegularExpression(pattern: contentPattern, options: []) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if match.numberOfRanges > 0 {
                    let range = Range(match.range(at: 0), in: xml)!
                    let tagString = String(xml[range])
                    // Only add if we haven't already added this tag (avoid duplicates from self-closing)
                    // Check by comparing the opening tag portion
                    if !results.contains(where: { existingTag in
                        // Extract opening tag from both and compare
                        if let existingStart = existingTag.range(of: "<\(tag)"),
                           let newStart = tagString.range(of: "<\(tag)") {
                            // Get up to 200 characters from the opening tag, or to the end if shorter
                            let existingEnd = existingTag.index(existingStart.upperBound, offsetBy: 200, limitedBy: existingTag.endIndex) ?? existingTag.endIndex
                            let newEnd = tagString.index(newStart.upperBound, offsetBy: 200, limitedBy: tagString.endIndex) ?? tagString.endIndex
                            let existingOpening = String(existingTag[existingStart.lowerBound..<existingEnd])
                            let newOpening = String(tagString[newStart.lowerBound..<newEnd])
                            return existingOpening == newOpening
                        }
                        return false
                    }) {
                        results.append(tagString)
                    }
                }
            }
        }
        
        return results
    }
    
    /// Extract an attribute value from a tag
    private static func extractAttribute(_ tag: String, name: String) -> String? {
        let pattern = "\(name)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = Range(match.range(at: 1), in: tag)!
        return String(tag[range])
    }
}

