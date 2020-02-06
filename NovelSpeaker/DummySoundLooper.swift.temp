//
//  DummySoundLooper.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/10/04.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//
// バックグラウンド時に(聞き取れないような)音声を延々と流し続けるためのclass

import UIKit
import AVFoundation

class DummySoundLooper: NSObject {
    var audioPlayer:AVAudioPlayer? = nil
    var mediaFileURL:NSURL? = nil
    let dispatchQueue = DispatchQueue(label: "NovelSpeaker.DummySoundLoader", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    
    @discardableResult
    @objc public func setMediaFile(forResource:String, ofType:String) -> Bool {
        if let path = Bundle.main.path(forResource: forResource, ofType: ofType) {
            let audioURL = NSURL(fileURLWithPath: path)
            var error:NSError?
            if !audioURL.checkResourceIsReachableAndReturnError(&error) {
                print("setMediaFile failed. target file is not reachable.")
                return false
            }
            mediaFileURL = audioURL
        }else{
            print("setMediaFile failed by path")
            return false
        }
        return true
    }
    
    func isPlaying() -> Bool {
        if let player = self.audioPlayer {
            return player.isPlaying
        }
        return false
    }
    
    func getPlayer() -> AVAudioPlayer? {
        if let player = self.audioPlayer {
            return player
        }
        if let mediaFileURL = self.mediaFileURL {
            do {
                let player = try AVAudioPlayer(contentsOf: mediaFileURL as URL)
                player.prepareToPlay()
                audioPlayer = player;
            } catch {
                print("setMediaFile failed by exception")
                return nil
            }
        }
        return nil
    }
    
    @objc public func startPlay(){
        dispatchQueue.async {
            if let audioPlayer = self.getPlayer() {
                audioPlayer.numberOfLoops = -1
                audioPlayer.play()
            }
        }
    }
    
    @objc public func stopPlay(){
        dispatchQueue.async {
            if !self.isPlaying() {
                return
            }
            if let audioPlayer = self.getPlayer() {
                audioPlayer.stop()
            }
        }
    }
}
