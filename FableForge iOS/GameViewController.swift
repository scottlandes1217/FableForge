//
//  GameViewController.swift
//  Domaterra iOS
//
//  Created by Scott Landes on 1/7/26.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {
    
    var gameScene: GameScene?

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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update scene size when view layout changes (orientation change)
        if let skView = self.view as? SKView, let scene = gameScene {
            let newSize = skView.bounds.size
            print("GameViewController: viewDidLayoutSubviews - New size: \(newSize), Current scene size: \(scene.size)")
            if abs(scene.size.width - newSize.width) > 1 || abs(scene.size.height - newSize.height) > 1 {
                scene.size = newSize
                // Trigger UI update
                (scene as? GameScene)?.updateUIForSizeChange()
            }
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        print("GameViewController: viewWillTransition to size: \(size)")
        
        coordinator.animate(alongsideTransition: { _ in
            // Update scene size during transition
            if let skView = self.view as? SKView, let scene = self.gameScene {
                scene.size = size
                (scene as? GameScene)?.updateUIForSizeChange()
            }
        }, completion: nil)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
