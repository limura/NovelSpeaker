//
//  NarouLoader.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

/// 小説家になろう の API 個を使って小説情報を読み出すclass。
/// SettingDataModel の NarouContent に追加するなどします。
@interface NarouLoader : NSObject

/// NarouContent のリストを更新します。
/// 怪しく検索条件を内部で勝手に作ります。
- (BOOL)UpdateContentList;

@end
