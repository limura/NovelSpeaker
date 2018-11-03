//
//  DuplicateSoundPlayer.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/11/03.
//  Copyright © 2018 IIMURA Takuji. All rights reserved.
//

import UIKit

class DuplicateSoundPlayer: NSObject, AVAudioPlayerDelegate {
    var playerArray:[AVAudioPlayer] = []
    let dispatchQueue = DispatchQueue(label: "NovelSpeaker.DuplicateSoundPlayer", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)

    @objc public func setMediaFile(forResource:String, ofType:String, maxDuplicateCount:Int) -> Bool {
        if let path = Bundle.main.path(forResource: forResource, ofType: ofType) {
            let audio = NSURL(fileURLWithPath: path)
            for _ in (1 ... maxDuplicateCount) {
                do {
                    let player = try AVAudioPlayer(contentsOf: audio as URL)
                    player.prepareToPlay()
                    player.delegate = self
                    playerArray.append(player)
                } catch {
                    print("setMediaFile failed by exception")
                    return false
                }
            }
        }else{
            print("setMediaFile failed by path")
            return false
        }
        return true
    }
    
    @objc public func startPlay(){
        dispatchQueue.async {
            for player in self.playerArray {
                if !player.isPlaying {
                    print("play")
                    player.numberOfLoops = 0
                    player.play()
                    return
                }
            }
            print("no playable player.")
            self.stopPlay()
        }
    }
    
    @objc public func stopPlay(){
        dispatchQueue.async {
            for player in self.playerArray {
                player.stop()
            }
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        player.stop()
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        player.stop()
    }
}
