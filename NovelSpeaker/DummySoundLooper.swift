//
//  DummySoundLooper.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/10/04.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//
// バックグラウンド時に(聞き取れないような)音声を延々と流し続けるためのclass

import UIKit

class DummySoundLooper: NSObject {
    var audioPlayer:AVAudioPlayer = AVAudioPlayer()
    let dispatchQueue = DispatchQueue(label: "NovelSpeaker.DummySoundLoader", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    
    @objc public func setMediaFile(forResource:String, ofType:String) -> Bool {
        if let path = Bundle.main.path(forResource: forResource, ofType: ofType) {
            let audio = NSURL(fileURLWithPath: path)
            do {
                let player = try AVAudioPlayer(contentsOf: audio as URL)
                audioPlayer = player;
                audioPlayer.prepareToPlay()
            } catch {
                print("setMediaFile failed by exception")
                return false
            }
        }else{
            print("setMediaFile failed by path")
            return false
        }
        return true
    }
    
    @objc public func startPlay(){
        dispatchQueue.async {
            self.audioPlayer.numberOfLoops = -1
            self.audioPlayer.play()
        }
    }
    
    @objc public func stopPlay(){
        dispatchQueue.async {
            self.audioPlayer.stop()
        }
    }
}
