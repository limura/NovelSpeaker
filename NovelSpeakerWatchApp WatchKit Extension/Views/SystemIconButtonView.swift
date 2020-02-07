//
//  SystemIconButtonView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/07.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct SystemIconButtonView: View {
    let systemIconName:String
    let action:(()->Void)
    let iconSize:CGFloat
    let foregroundColor:Color?

    init(systemIconName:String, iconSize:CGFloat, foregroundColor:Color? = nil, action:@escaping ()->Void) {
        self.action = action
        self.systemIconName = systemIconName
        self.iconSize = iconSize
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Button(action: {
            self.action()
        }) {
            Image(systemName: systemIconName)
            .resizable()
            .frame(width: iconSize, height: iconSize, alignment: .trailing)
            .foregroundColor(foregroundColor)
        }
        .frame(width: iconSize, height: iconSize, alignment: .leading)
    }
}


struct SystemIconButtonView_Previews: PreviewProvider {
    static var previews: some View {
        SystemIconButtonView(systemIconName: "backward.end.fill", iconSize: 20) {
            // nothing to do!
        }
    }
}
