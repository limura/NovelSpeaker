//
//  WKInterfaceVolumeControlView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/08.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct WKInterfaceVolumeControlView: WKInterfaceObjectRepresentable {
    typealias WKInterfaceObjectType = WKInterfaceVolumeControl
    
    func makeWKInterfaceObject(context: Self.Context) -> Self.WKInterfaceObjectType {
        return WKInterfaceVolumeControl.init(origin: .local)
    }

    func updateWKInterfaceObject(_ wkInterfaceObject: Self.WKInterfaceObjectType, context: Self.Context) {
    }
}

struct WKInterfaceVolumeControlView_Previews: PreviewProvider {
    static var previews: some View {
        WKInterfaceVolumeControlView()
    }
}
