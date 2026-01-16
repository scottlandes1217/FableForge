//
//  DeltaPersistence.swift
//  FableForge Shared
//
//  Persistence for player changes to chunks (base + delta model)
//

import Foundation

/// Manages saving/loading chunk deltas (player modifications)
class DeltaPersistence {
    private let documentsURL: URL
    private let deltasDirectory: URL
    
    init() {
        // Get documents directory
        let fileManager = FileManager.default
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create deltas subdirectory
        deltasDirectory = documentsURL.appendingPathComponent("WorldDeltas", isDirectory: true)
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: deltasDirectory.path) {
            try? fileManager.createDirectory(at: deltasDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Get file path for a chunk's delta
    private func deltaFilePath(for chunkKey: ChunkKey) -> URL {
        let fileName = "chunk_\(chunkKey.x)_\(chunkKey.y).json"
        return deltasDirectory.appendingPathComponent(fileName)
    }
    
    /// Load delta for a chunk (returns empty delta if not found)
    func loadDelta(for chunkKey: ChunkKey) -> ChunkDelta {
        let fileURL = deltaFilePath(for: chunkKey)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return ChunkDelta()  // Return empty delta if file doesn't exist
        }
        
        let decoder = JSONDecoder()
        if let delta = try? decoder.decode(ChunkDelta.self, from: data) {
            return delta
        }
        
        print("⚠️ DeltaPersistence: Failed to decode delta for chunk \(chunkKey.x),\(chunkKey.y)")
        return ChunkDelta()
    }
    
    /// Save delta for a chunk
    func saveDelta(_ delta: ChunkDelta, for chunkKey: ChunkKey) {
        let fileURL = deltaFilePath(for: chunkKey)
        
        // If delta is empty, delete the file instead
        if delta.addedEntities.isEmpty && delta.removedEntityKeys.isEmpty && delta.tileOverrides.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(delta)
            try data.write(to: fileURL)
        } catch {
            print("❌ DeltaPersistence: Failed to save delta for chunk \(chunkKey.x),\(chunkKey.y): \(error)")
        }
    }
    
    /// Delete delta for a chunk (revert to base)
    func deleteDelta(for chunkKey: ChunkKey) {
        let fileURL = deltaFilePath(for: chunkKey)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Get all chunk keys that have deltas
    func getAllDeltas() -> [ChunkKey] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: deltasDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var chunkKeys: [ChunkKey] = []
        for fileURL in files {
            if fileURL.pathExtension == "json" {
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                // Parse "chunk_X_Y" format
                let components = fileName.components(separatedBy: "_")
                if components.count == 3, components[0] == "chunk",
                   let x = Int(components[1]), let y = Int(components[2]) {
                    chunkKeys.append(ChunkKey(x: x, y: y))
                }
            }
        }
        
        return chunkKeys
    }
    
    /// Clear all deltas (for testing/debugging)
    func clearAllDeltas() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: deltasDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for fileURL in files {
            if fileURL.pathExtension == "json" {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
