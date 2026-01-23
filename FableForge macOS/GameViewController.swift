//
//  GameViewController.swift
//  FableForge macOS
//
//  Created by Scott Landes on 1/10/26.
//

import Cocoa
import SpriteKit
import GameplayKit

class GameViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Present the start screen first
        let skView = self.view as! SKView
        let startScene = StartScreenScene(size: skView.bounds.size)
        startScene.scaleMode = .aspectFill
        skView.presentScene(startScene)
        
        skView.ignoresSiblingOrder = true
        
        skView.showsFPS = true
        skView.showsNodeCount = true
        
        print("🔵 GameViewController: SKView initialized, ready for mouse events")
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Forward scroll wheel events to the scene
        if let scene = (self.view as? SKView)?.scene as? StartScreenScene {
            scene.scrollWheel(with: event)
        } else if let scene = (self.view as? SKView)?.scene as? GameScene {
            // Forward to GameScene for BuildUI scrolling
            scene.scrollWheel(with: event)
        }
    }
    

}

