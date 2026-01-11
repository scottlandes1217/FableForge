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
    }

}

