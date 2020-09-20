//
//  ScrollableVStack.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/03/09.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

class ScrollableVStackData<Content:Hashable>:ObservableObject {
    @Published var dataArray:[Content]
    @Published var contentSizeMap:[Int:CGSize] = [:]
    @Published var scrollOffset:CGFloat = .zero {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var dragHeight:CGFloat = .zero
    @Published var toplevelSize:CGSize = .zero
    
    init(dataArray:[Content]) {
        self.dataArray = dataArray
    }
}

struct ScrollableVStackInnerView<Content:Hashable>: View {
    @ObservedObject var data:ScrollableVStackData<Content>
    let converter:((Content, ScrollableVStack<Content>)->AnyView)
    let parent:ScrollableVStack<Content>

    init(data:ScrollableVStackData<Content>, converter:@escaping ((Content, ScrollableVStack<Content>)->AnyView), parent: ScrollableVStack<Content>) {
        self.data = data
        self.converter = converter
        self.parent = parent
        //print("ScrollableVStackData data.dataArray.count: \(data.dataArray.count)")
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(self.data.dataArray, id: \.self, content: { content -> AnyView in
                return AnyView(
                    self.converter(content, self.parent)
                    .onDisappear(perform: {
                        print("onDisappear(\(content.hashValue))")
                        self.data.contentSizeMap.removeValue(forKey: content.hashValue)
                    })
                    .background(
                        GeometryReader { innerViewGeometry in
                            Text("")
                            .onAppear {
                                print("onAppear(\(content.hashValue))")
                                self.data.contentSizeMap[content.hashValue] = innerViewGeometry.size
                            }
                        }
                    )
                )
            })
        }
    }
}

struct ScrollableVStack<Content:Hashable>: View {
    let converter:((Content, ScrollableVStack<Content>)->AnyView)

    @ObservedObject var data:ScrollableVStackData<Content>
    @State var scrollAmount:Float = 0.0 {
        didSet {
            print("scrollAmount changed: \(self.scrollAmount)")
        }
    }

    init(data:[Content], converter:@escaping ((Content, ScrollableVStack<Content>)->AnyView)) {
        self.data = ScrollableVStackData<Content>(dataArray: data)
        self.converter = converter
        print("ScrollableVStack.init() called.")
    }
    
    func UpdateData(data:[Content]) {
        print("ScrollableVStack.UpdateData() data.count: \(data.count)")
        self.data.dataArray = data
    }

    func ScrollToIndex(at:Int, isAnimationEnable:Bool = false){
        var yOffset:CGFloat = 0.0
        for (i,content) in data.dataArray.enumerated() {
            if i == at {
                break
            }
            if let size = data.contentSizeMap[content.hashValue] {
                yOffset += size.height
            }
        }
        scrollTo(height: -yOffset, isAnimationEnable: isAnimationEnable)
    }
    func GetCurrentDisplayedIndex() -> Int? {
        var yOffset:CGFloat = 0.0
        for (i,content) in data.dataArray.enumerated() {
            guard let size = data.contentSizeMap[content.hashValue] else { continue }
            yOffset += size.height
            if yOffset > data.scrollOffset {
                return i
            }
        }
        return nil
    }
    func GetCurrentDisplayedContent() -> Content? {
        guard let index = GetCurrentDisplayedIndex() else { return nil }
        guard data.dataArray.count > index else { return nil }
        return data.dataArray[index]
    }
    
    func CalcTotalContentHeight() -> CGFloat {
        var height:CGFloat = .zero
        for content in data.dataArray {
            guard let size = data.contentSizeMap[content.hashValue] else { continue }
            height += size.height
        }
        return height
    }

    func scrollTo(height:CGFloat, isAnimationEnable:Bool = false) {
        let displayHeight = self.data.toplevelSize.height
        let contentHeight = CalcTotalContentHeight()
        let scrollPositionMin = -(contentHeight - (contentHeight < displayHeight ? 0 : displayHeight))
        print("scrollTo(): height: \(height), displayHeight: \(displayHeight), scrollOffset: \(data.scrollOffset), dragHeight: \(data.dragHeight), contentHeight: \(contentHeight), scrollPositionMin: \(scrollPositionMin)")
        let newScrollOffset:CGFloat
        if height < scrollPositionMin {
            newScrollOffset = scrollPositionMin
        }else if height > 0 {
            newScrollOffset = .zero
        }else{
            newScrollOffset = height
        }

        if isAnimationEnable {
            withAnimation {
                self.data.dragHeight = .zero
                self.data.scrollOffset = newScrollOffset
            }
        }else{
            self.data.dragHeight = .zero
            self.data.scrollOffset = newScrollOffset
        }
    }
    
    func onDragEnded(value:DragGesture.Value) {
        //print("onDragEnded: value: \(value), outerGeometry: \(outerGeometry)")
        scrollTo(height: self.data.scrollOffset + value.predictedEndTranslation.height, isAnimationEnable: true)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ScrollableVStackInnerView<Content>(data: self.data, converter: self.converter, parent: self)
            }
            .content.offset(x: 0, y: self.data.scrollOffset + self.data.dragHeight + self.CalcTotalContentHeight() / 2 - geometry.size.height / 2)
            .onAppear(perform: {
                self.data.toplevelSize = geometry.size
            })
            .gesture(DragGesture()
                .onChanged({ self.data.dragHeight = $0.translation.height })
                .onEnded({ self.onDragEnded(value: $0) })
            )
            .focusable(true)
            .digitalCrownRotation(self.$scrollAmount, from: 0.0, through: 1.0, by: 0.01, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: false)
        }
    }
}

struct ScrollableVStack_Previews: PreviewProvider {
    static var previews: some View {
        let data:[String] = ["あいうえお", "かきくけこ", "さしすせそ"]
        let view = ScrollableVStack<String>(data: data, converter: { content, _ -> AnyView in
            AnyView(Text(content))
        })
        return view
    }
}
