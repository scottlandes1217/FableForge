//
//  TMXInstanceLoader.swift
//  FableForge Shared
//
//  Loads and mounts TMX maps at specific world coordinates
//

import Foundation
import SpriteKit

/// Represents a TMX map instance placed in the world
struct TMXInstance {
    let fileName: String  // TMX file name (without extension)
    let worldTileOrigin: (x: Int, y: Int)  // World tile coordinates of bottom-left corner
    var worldBounds: CGRect?  // Calculated world-space bounds (set after loading)
    var tiledMap: TiledMap?  // Parsed TMX map (loaded on demand)
    
    /// Get the world position (CGPoint) of the instance origin
    func worldPosition(tileSize: CGFloat) -> CGPoint {
        return CGPoint(
            x: CGFloat(worldTileOrigin.x) * tileSize,
            y: CGFloat(worldTileOrigin.y) * tileSize
        )
    }
}

/// Loads and renders TMX map instances into the world
class TMXInstanceLoader {
    static let shared = TMXInstanceLoader()
    
    private var loadedInstances: [TMXInstance] = []
    private var instanceNodes: [String: SKNode] = [:]  // Map of instance key to scene node
    
    private init() {}
    
    /// Load and mount a TMX map at a world position
    func loadInstance(_ instance: TMXInstance, tileSize: CGFloat, scaleFactor: CGFloat, scene: SKScene, yFlipOffset: CGFloat) -> TMXInstance? {
        // Parse TMX file
        guard let tiledMap = TiledMapParser.parse(fileName: instance.fileName) else {
            print("❌ TMXInstanceLoader: Failed to parse '\(instance.fileName).tmx'")
            return nil
        }
        
        // Calculate world bounds
        let instanceWorldPos = instance.worldPosition(tileSize: tileSize)
        let scaledTileSize = CGSize(width: CGFloat(tiledMap.tileWidth) * scaleFactor, height: CGFloat(tiledMap.tileHeight) * scaleFactor)
        
        var bounds: CGRect?
        if tiledMap.layers.contains(where: { $0.isInfinite }) {
            // Calculate bounds from chunks
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            
            for layer in tiledMap.layers {
                if let chunks = layer.chunks {
                    for chunk in chunks {
                        let chunkWorldX = instanceWorldPos.x + CGFloat(chunk.x) * scaledTileSize.width
                        let chunkWorldY = instanceWorldPos.y + CGFloat(chunk.y) * scaledTileSize.height
                        minX = min(minX, chunkWorldX)
                        minY = min(minY, chunkWorldY)
                        maxX = max(maxX, chunkWorldX + CGFloat(chunk.width) * scaledTileSize.width)
                        maxY = max(maxY, chunkWorldY + CGFloat(chunk.height) * scaledTileSize.height)
                    }
                }
            }
            
            if minX != CGFloat.greatestFiniteMagnitude {
                bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
        } else {
            // Regular map: use width/height
            bounds = CGRect(
                x: instanceWorldPos.x,
                y: instanceWorldPos.y,
                width: CGFloat(tiledMap.width) * scaledTileSize.width,
                height: CGFloat(tiledMap.height) * scaledTileSize.height
            )
        }
        
        var updatedInstance = instance
        updatedInstance.worldBounds = bounds
        updatedInstance.tiledMap = tiledMap
        
        // Render the instance into the scene
        renderInstance(updatedInstance, tileSize: scaledTileSize, scene: scene, yFlipOffset: yFlipOffset, instanceWorldPos: instanceWorldPos)
        
        // Store instance
        let instanceKey = instanceKey(instance)
        instanceNodes[instanceKey] = scene.childNode(withName: "tmxInstance_\(instanceKey)")
        loadedInstances.append(updatedInstance)
        
        return updatedInstance
    }
    
    /// Render a TMX instance into the scene
    private func renderInstance(_ instance: TMXInstance, tileSize: CGSize, scene: SKScene, yFlipOffset: CGFloat, instanceWorldPos: CGPoint) {
        guard let tiledMap = instance.tiledMap else { return }
        
        let instanceKey = instanceKey(instance)
        let containerNode = SKNode()
        containerNode.name = "tmxInstance_\(instanceKey)"
        scene.addChild(containerNode)
        
        // Render layers
        for (layerIndex, layer) in tiledMap.layers.enumerated() {
            let layerZPosition = CGFloat(layerIndex)
            
            if layer.isInfinite, let chunks = layer.chunks {
                // Render chunks
                for chunk in chunks {
                    renderTiledChunk(
                        chunk,
                        tileSize: tileSize,
                        zPosition: layerZPosition,
                        yFlipOffset: yFlipOffset,
                        container: containerNode,
                        instanceOffset: instanceWorldPos
                    )
                }
            } else if let data = layer.data {
                // Render regular layer
                renderTiledLayer(
                    layer,
                    data: data,
                    tileSize: tileSize,
                    zPosition: layerZPosition,
                    yFlipOffset: yFlipOffset,
                    container: containerNode,
                    instanceOffset: instanceWorldPos
                )
            }
        }
        
        // Render object groups
        let objectZPosition: CGFloat = 70
        for objectGroup in tiledMap.objectGroups {
            renderTiledObjectGroup(
                objectGroup,
                tileSize: tileSize,
                zPosition: objectZPosition,
                yFlipOffset: yFlipOffset,
                container: containerNode,
                instanceOffset: instanceWorldPos
            )
        }
    }
    
    /// Render a chunk from a TMX instance
    private func renderTiledChunk(_ chunk: TiledChunk, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat, container: SKNode, instanceOffset: CGPoint) {
        var index = 0
        for y in 0..<chunk.height {
            for x in 0..<chunk.width {
                guard index < chunk.data.count else { break }
                let gid = chunk.data[index]
                index += 1
                
                guard gid > 0, let sprite = TileManager.shared.createSprite(for: gid, size: tileSize) else { continue }
                
                // Calculate position relative to instance origin
                let chunkWorldX = instanceOffset.x + CGFloat(chunk.x + x) * tileSize.width
                let tiledY = CGFloat(chunk.y + y) * tileSize.height
                let chunkWorldY = yFlipOffset - tiledY + instanceOffset.y - (yFlipOffset - instanceOffset.y)  // Adjust for instance offset
                
                // Simplified: use instance offset directly
                let finalWorldX = instanceOffset.x + CGFloat(chunk.x + x) * tileSize.width
                let finalWorldY = instanceOffset.y + CGFloat(chunk.y + y) * tileSize.height
                
                sprite.position = CGPoint(x: finalWorldX, y: finalWorldY)
                sprite.anchorPoint = CGPoint(x: 0, y: 0)
                sprite.zPosition = zPosition
                container.addChild(sprite)
            }
        }
    }
    
    /// Render a regular layer from a TMX instance
    private func renderTiledLayer(_ layer: TiledLayer, data: [Int], tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat, container: SKNode, instanceOffset: CGPoint) {
        var index = 0
        for y in 0..<layer.height {
            for x in 0..<layer.width {
                guard index < data.count else { break }
                let gid = data[index]
                index += 1
                
                guard gid > 0, let sprite = TileManager.shared.createSprite(for: gid, size: tileSize) else { continue }
                
                let worldX = instanceOffset.x + CGFloat(x) * tileSize.width
                let worldY = instanceOffset.y + CGFloat(layer.height - y - 1) * tileSize.height
                
                sprite.position = CGPoint(x: worldX, y: worldY)
                sprite.anchorPoint = CGPoint(x: 0, y: 0)
                sprite.zPosition = zPosition
                container.addChild(sprite)
            }
        }
    }
    
    /// Render an object group from a TMX instance
    private func renderTiledObjectGroup(_ objectGroup: TiledObjectGroup, tileSize: CGSize, zPosition: CGFloat, yFlipOffset: CGFloat, container: SKNode, instanceOffset: CGPoint) {
        // Similar to GameScene's renderTiledObjectGroup, but with instance offset
        // Implementation would mirror the existing object rendering code
        // For now, this is a placeholder - full implementation would render objects
    }
    
    /// Get all loaded instances
    func getLoadedInstances() -> [TMXInstance] {
        return loadedInstances
    }
    
    /// Check if a world position is inside any TMX instance
    func isPositionInInstance(_ position: CGPoint) -> Bool {
        return loadedInstances.contains { instance in
            guard let bounds = instance.worldBounds else { return false }
            return bounds.contains(position)
        }
    }
    
    /// Get instance key for identification
    private func instanceKey(_ instance: TMXInstance) -> String {
        return "\(instance.fileName)_\(instance.worldTileOrigin.x)_\(instance.worldTileOrigin.y)"
    }
}
