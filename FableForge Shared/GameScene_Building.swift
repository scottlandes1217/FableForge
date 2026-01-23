//
//  GameScene_Building.swift
//  FableForge Shared
//
//  Building placement functionality for GameScene
//

import SpriteKit

extension GameScene {
    
    // MARK: - Build Placement Mode
    
    /// Enter build placement mode - shows zoomed out map and allows placing structures
    func enterBuildPlacementMode(structureData: StructureData) {
        guard let player = gameState?.player else { return }
        
        // Convert structureType string to enum for compatibility
        guard let structureType = StructureType(rawValue: structureData.structureType) else {
            showMessage("Unknown structure type: \(structureData.structureType)", color: .red)
            return
        }
        
        // Check if player can build this structure using JSON requirements
        for skillReq in structureData.requirements.skills {
            // Skip empty skill requirements
            guard !skillReq.type.isEmpty else { continue }
            
            // Convert skill string to BuildingSkill enum
            let skillName = skillReq.type.capitalized
            guard let skill = BuildingSkill(rawValue: skillName) ?? BuildingSkill.allCases.first(where: { $0.rawValue.lowercased() == skillReq.type.lowercased() }) else {
                print("⚠️ Unknown skill type: \(skillReq.type)")
                continue
            }
            
            let playerLevel = player.buildingSkills[skill] ?? 0
            if playerLevel < skillReq.level {
                showMessage("You need \(skillReq.type) level \(skillReq.level) to build \(structureData.name)", color: .red)
                return
            }
        }
        
        // Check materials using JSON requirements
        for materialReq in structureData.requirements.materials {
            // Convert material string to MaterialType
            guard let materialType = MaterialType(rawValue: materialReq.type) ?? MaterialType.allCases.first(where: { $0.rawValue.lowercased() == materialReq.type.lowercased() }) else {
                print("⚠️ Unknown material type: \(materialReq.type)")
                continue
            }
            
            // Count materials (both Material instances and Item instances with matching type)
            var totalQuantity = 0
            
            // Check Material instances
            let materialInstances = player.inventory.compactMap { $0 as? Material }
            let matchingMaterials = materialInstances.filter { $0.materialType == materialType }
            totalQuantity += matchingMaterials.reduce(0) { $0 + $1.quantity }
            
            // Also check Item instances with matching ItemType
            let itemType: ItemType?
            switch materialType {
            case .wood: itemType = .wood
            case .stone: itemType = .stone
            case .iron: itemType = .iron
            case .cloth: itemType = .cloth
            case .rope: itemType = .rope
            case .nails: itemType = .nails
            }
            
            if let itemType = itemType {
                let matchingItems = player.inventory.filter { 
                    $0.type == itemType && !($0 is Material)
                }
                totalQuantity += matchingItems.reduce(0) { $0 + $1.quantity }
            }
            
            if totalQuantity < materialReq.quantity {
                showMessage("You need \(materialReq.quantity) \(materialReq.type) to build \(structureData.name)", color: .red)
                return
            }
        }
        
        // Set placement mode state
        isBuildPlacementMode = true
        selectedStructureType = structureType
        selectedStructureData = structureData
        isGamePaused = true
        
        // Store original camera scale and zoom out for better overview
        guard let camera = cameraNode else { return }
        originalCameraScale = camera.xScale
        
        // Zoom out to show more of the map (0.5 = zoom out 2x, showing 4x more area)
        // Use a moderate zoom that's not too extreme
        camera.setScale(2.0)  // Zoom out 2x to show more of the map
        
        // Center camera on player position for better overview
        if let player = gameState?.player {
            let playerPosition = player.position
            // Smoothly move camera to player position
            let moveAction = SKAction.move(to: playerPosition, duration: 0.3)
            camera.run(moveAction)
        }
        
        // Create placement preview sprite
        createPlacementPreview(structureData: structureData)
        
        // Show instructions UI
        showBuildPlacementInstructions()
    }
    
    /// Exit build placement mode
    func exitBuildPlacementMode() {
        isBuildPlacementMode = false
        selectedStructureType = nil
        selectedStructureData = nil
        
        // Restore camera scale
        if let camera = cameraNode {
            camera.setScale(originalCameraScale)
        }
        
        // Remove preview
        placementPreview?.removeFromParent()
        placementPreview = nil
        
        // Remove instructions
        cameraNode?.childNode(withName: "buildPlacementInstructions")?.removeFromParent()
        
        // Resume game
        if characterUI?.isVisible != true {
            isGamePaused = false
        }
    }
    
    /// Create preview sprite for structure placement
    func createPlacementPreview(structureData: StructureData) {
        // Remove existing preview
        placementPreview?.removeFromParent()
        
        // Use size from JSON (already in points, not tiles)
        let previewSize = structureData.size
        
        // Create semi-transparent preview rectangle
        let preview = SKShapeNode(rectOf: previewSize, cornerRadius: 4)
        preview.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.5)
        preview.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 0.8)
        preview.lineWidth = 2
        preview.zPosition = 1000
        preview.name = "placementPreview"
        
        addChild(preview)
        placementPreview = preview
    }
    
    /// Snap position to tile grid
    func snapToTileGrid(_ position: CGPoint) -> CGPoint {
        let tileSize: CGFloat = 32.0
        let snappedX = round(position.x / tileSize) * tileSize
        let snappedY = round(position.y / tileSize) * tileSize
        return CGPoint(x: snappedX, y: snappedY)
    }
    
    /// Update placement preview position
    func updatePlacementPreview(at position: CGPoint) {
        guard let preview = placementPreview else { return }
        // Snap to tile grid for cleaner placement
        let snappedPosition = snapToTileGrid(position)
        preview.position = snappedPosition
        
        // Check if position is valid (not colliding with existing structures)
        let isValid = isValidPlacementPosition(snappedPosition)
        
        // Update preview color based on validity
        if isValid {
            preview.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.5)
            preview.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 0.8)
        } else {
            preview.fillColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.5)
            preview.strokeColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.8)
        }
    }
    
    /// Check if a position is valid for placing the selected structure
    func isValidPlacementPosition(_ position: CGPoint) -> Bool {
        guard let structureType = selectedStructureType,
              let structureData = selectedStructureData,
              let world = gameState?.world else { return false }
        
        // Create structure with size from JSON
        let structure = Structure(type: structureType, position: position)
        structure.size = structureData.size
        return world.canPlaceStructure(structure, at: position)
    }
    
    /// Attempt to place structure at current position
    func placeStructureAtPosition(_ position: CGPoint) -> Bool {
        guard let structureType = selectedStructureType,
              let player = gameState?.player,
              let world = gameState?.world else { return false }
        
        // Snap to tile grid for cleaner placement
        let snappedPosition = snapToTileGrid(position)
        
        // Validate position
        if !isValidPlacementPosition(snappedPosition) {
            showMessage("Cannot place structure here", color: .red)
            return false
        }
        
        // Create and place structure
        let structure = Structure(type: structureType, position: snappedPosition)
        if let structureData = selectedStructureData {
            structure.size = structureData.size
        }
        
        if world.placeStructure(structure, at: snappedPosition) {
            gameState?.structures.append(structure)
            
            // Consume materials using JSON requirements
            guard let structureData = selectedStructureData else {
                showMessage("Structure data missing", color: .red)
                return false
            }
            
            for materialReq in structureData.requirements.materials {
                // Convert material string to MaterialType
                guard let materialType = MaterialType(rawValue: materialReq.type) ?? MaterialType.allCases.first(where: { $0.rawValue.lowercased() == materialReq.type.lowercased() }) else {
                    print("⚠️ Unknown material type: \(materialReq.type)")
                    continue
                }
                
                var remaining = materialReq.quantity
                
                // Consume from Material instances first
                for item in player.inventory {
                    if let mat = item as? Material, mat.materialType == materialType {
                        if mat.quantity <= remaining {
                            remaining -= mat.quantity
                            player.inventory.removeAll { $0.id == item.id }
                            if remaining == 0 { break }
                        } else {
                            mat.quantity -= remaining
                            remaining = 0
                            break
                        }
                    }
                }
                
                // If still need more, consume from Item instances with matching ItemType
                if remaining > 0 {
                    let itemType: ItemType?
                    switch materialType {
                    case .wood: itemType = .wood
                    case .stone: itemType = .stone
                    case .iron: itemType = .iron
                    case .cloth: itemType = .cloth
                    case .rope: itemType = .rope
                    case .nails: itemType = .nails
                    }
                    
                    if let itemType = itemType {
                        for item in player.inventory {
                            if item.type == itemType && !(item is Material) {
                                if item.quantity <= remaining {
                                    remaining -= item.quantity
                                    player.inventory.removeAll { $0.id == item.id }
                                    if remaining == 0 { break }
                                } else {
                                    item.quantity -= remaining
                                    remaining = 0
                                    break
                                }
                            }
                        }
                    }
                }
            }
            
            // Re-render the world
            if useTiledMap {
                loadAndRenderTiledMap(fileName: tiledMapFileName)
            } else {
                renderWorld()
            }
            
            let structureName = selectedStructureData?.name ?? structureType.rawValue
            showMessage("\(structureName) placed!", color: .green)
            exitBuildPlacementMode()
            return true
        }
        
        return false
    }
    
    /// Show instructions for build placement mode
    func showBuildPlacementInstructions() {
        guard let camera = cameraNode else { return }
        
        // Remove existing instructions
        camera.childNode(withName: "buildPlacementInstructions")?.removeFromParent()
        
        // Create instructions panel
        let instructions = SKShapeNode(rectOf: CGSize(width: size.width * 0.8, height: 100), cornerRadius: 8)
        instructions.fillColor = SKColor(white: 0.1, alpha: 0.9)
        instructions.strokeColor = .white
        instructions.lineWidth = 2
        instructions.position = CGPoint(x: 0, y: size.height / 2 - 80)
        instructions.zPosition = 2100
        instructions.name = "buildPlacementInstructions"
        
        let instructionText = SKLabelNode(fontNamed: "Arial-BoldMT")
        instructionText.text = "Tap/Click to place structure | ESC/Cancel to exit"
        instructionText.fontSize = 18
        instructionText.fontColor = .white
        instructionText.verticalAlignmentMode = .center
        instructionText.zPosition = 2101
        
        instructions.addChild(instructionText)
        camera.addChild(instructions)
    }
    
}
