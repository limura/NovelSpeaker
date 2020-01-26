//
//  DuplicateSoundPlayer.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/11/03.
//  Copyright © 2018 IIMURA Takuji. All rights reserved.
//

import UIKit
import AVFoundation

class DuplicateSoundPlayer: NSObject, AVAudioPlayerDelegate {
    var playerArray:[AVAudioPlayer] = []
    let dispatchQueue = DispatchQueue(label: "NovelSpeaker.DuplicateSoundPlayer", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    var mediaFileURL:NSURL? = nil
    var maxDuplicateCount:Int = 1

    @objc public func setMediaFile(forResource:String, ofType:String, maxDuplicateCount:Int) -> Bool {
        if let path = Bundle.main.path(forResource: forResource, ofType: ofType) {
            self.mediaFileURL = NSURL(fileURLWithPath: path)
        }else{
            print("setMediaFile failed by path")
            return false
        }
        return true
    }
    
    func getPlayerArray() -> [AVAudioPlayer] {
        if playerArray.count > 0 {
            return playerArray
        }
        
        if let mediaFileURL = self.mediaFileURL {
            for _ in (1 ... self.maxDuplicateCount) {
                do {
                    let player = try AVAudioPlayer(contentsOf: mediaFileURL as URL)
                    player.prepareToPlay()
                    player.delegate = self
                    self.playerArray.append(player)
                } catch {
                    if let urlString = mediaFileURL.absoluteString {
                        print("setMediaFile failed by exception", urlString)
                    }else{
                        print("setMediaFile failed by exception")
                    }
                    return []
                }
            }
        }
        return self.playerArray
    }
    
    func isPlaying() -> Bool {
        for player in self.playerArray {
            if player.isPlaying {
                return true
            }
        }
        return false
    }
    
    @objc public func startPlay(){
        dispatchQueue.async {
            for player in self.getPlayerArray() {
                if !player.isPlaying {
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
            if !self.isPlaying() {
                return
            }
            for player in self.getPlayerArray() {
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
