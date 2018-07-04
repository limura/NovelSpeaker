//
//  NiftyUtility.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/19.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NiftyUtility : NSObject

/// UIButton に表示される文字列を変更します。
/// 全ての State を同じ文字列で上書きします。
+ (void)setUIButtonText:(UIButton*)button text:(NSString*)text;

/// ダサい暗号化
+ (NSString*)stringEncrypt:(NSString*)string key:(NSString*)key;
/// ダサい暗号化の戻し
+ (NSString*)stringDecrypt:(NSString*)string key:(NSString*)key;

/// dictionary の key に入っているデータが正しく NSString であることを確認した上で取り出します
+ (NSString*)validateNSDictionaryForString:(NSDictionary*)dictionary key:(id)key;
/// dictionary の key に入っているデータが正しく NSArray であることを確認した上で取り出します
+ (NSArray*)validateNSDictionaryForArray:(NSDictionary*)dictionary key:(id)key;
/// dictionary の key に入っているデータが正しく NSDictionary であることを確認した上で取り出します
+ (NSDictionary*)validateNSDictionaryForDictionary:(NSDictionary*)dictionary key:(id)key;
/// dictionary の key に入っているデータが正しく NSNumber であることを確認した上で取り出します
+ (NSNumber*)validateNSDictionaryForNumber:(NSDictionary*)dictionary key:(id)key;

/// NSNumber で BOOL が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addBoolValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number;
/// NSNumber で intValue が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addIntValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number;
/// NSNumber で floatValue が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addFloatValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number;
/// NSString を、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addStringForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key string:(NSString*)string;

/// HTML のエスケープ文字を元に戻します。
+ (NSString*)decodeHtmlEscape:(NSString*)htmlString;

@end
