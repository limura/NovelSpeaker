//
//  NiftyUtility.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/19.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "NiftyUtility.h"
#import "NSDataZlibExtension.h"
#import <CommonCrypto/CommonHMAC.h>
#import <UserNotifications/UserNotifications.h>
#import "UIViewControllerExtension.h"

@implementation NiftyUtility

/// UIButton に表示される文字列を変更します
+ (void)setUIButtonText:(UIButton*)button text:(NSString*)text {
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitle:text forState:UIControlStateFocused];
    [button setTitle:text forState:UIControlStateDisabled];
    [button setTitle:text forState:UIControlStateReserved];
    [button setTitle:text forState:UIControlStateSelected];
    [button setTitle:text forState:UIControlStateApplication];
    [button setTitle:text forState:UIControlStateHighlighted];
}

// a を b で xor します。b が a より短い場合はループして適用します
+ (NSData*)xorData:(NSData*)aData b:(NSData*)bData {
    NSMutableData* result = [NSMutableData new];
    if (aData == nil || bData == nil) {
        return result;
    }
    const char* a = [aData bytes];
    const char* b = [bData bytes];
    for (int i = 0; i < aData.length; i++) {
        const char xorByte = a[i] ^ b[i % bData.length];
        [result appendBytes:&xorByte length:sizeof(xorByte)];
    }
    return result;
}

+ (NSData*)sha256:(NSData*)keyData {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH]={0};
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

/// ダサい暗号化
+ (NSString*)stringEncrypt:(NSString*)string key:(NSString*)key{
    if (string == nil || key == nil || [string length] <= 0 || [key length] <= 0) {
        return nil;
    }
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSData* keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    keyData = [NiftyUtility sha256:keyData];
    NSData* zipedData = [data deflate:9];
    NSData* encryptedData = [NiftyUtility xorData:zipedData b:keyData];
    return [encryptedData base64EncodedStringWithOptions:0];
}
/// ダサい暗号化の戻し
+ (NSString*)stringDecrypt:(NSString*)string key:(NSString*)key{
    if (string == nil || key == nil || [string length] <= 0 || [key length] <= 0) {
        return nil;
    }
    NSData* data = [[NSData alloc] initWithBase64EncodedString:string options:0];
    NSData* keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    keyData = [NiftyUtility sha256:keyData];
    NSData* decryptedData = [NiftyUtility xorData:data b:keyData];
    if (decryptedData == nil) {
        return nil;
    }
    NSData* unzipedData = [decryptedData inflate];
    if (unzipedData == nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
}

/// dictionary の key に入っているデータが正しく NSString であることを確認した上で取り出します
+ (NSString*)validateNSDictionaryForString:(NSDictionary*)dictionary key:(id)key{
    id obj = [dictionary objectForKey:key];
    if (obj != nil && [obj isKindOfClass:[NSString class]]) {
        return obj;
    }
    return nil;
}
/// dictionary の key に入っているデータが正しく NSArray であることを確認した上で取り出します
+ (NSArray*)validateNSDictionaryForArray:(NSDictionary*)dictionary key:(id)key{
    id obj = [dictionary objectForKey:key];
    if (obj != nil && [obj isKindOfClass:[NSArray class]]) {
        return obj;
    }
    return nil;
}
/// dictionary の key に入っているデータが正しく NSDictionary であることを確認した上で取り出します
+ (NSDictionary*)validateNSDictionaryForDictionary:(NSDictionary*)dictionary key:(id)key{
    id obj = [dictionary objectForKey:key];
    if (obj != nil && [obj isKindOfClass:[NSDictionary class]]) {
        return obj;
    }
    return nil;
}

/// dictionary の key に入っているデータが正しく NSNumber であることを確認した上で取り出します
+ (NSNumber*)validateNSDictionaryForNumber:(NSDictionary*)dictionary key:(id)key{
    id obj = [dictionary objectForKey:key];
    if (obj != nil && [obj isKindOfClass:[NSNumber class]]) {
        return obj;
    }
    return nil;
}

/// NSNumber で BOOL が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addBoolValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number{
    if (number == nil) {
        return;
    }
    [dictionary setObject:number forKey:key];
}
/// NSNumber で intValue が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addIntValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number{
    if (number == nil) {
        return;
    }
    [dictionary setObject:number forKey:key];
}
/// NSNumber で floatValue が表現されているものを、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addFloatValueForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key number:(NSNumber*)number{
    if (number == nil) {
        return;
    }
    [dictionary setObject:number forKey:key];
}
/// NSString を、JSON に変換される予定の NSMutableDictionary に入れます。number が nil であった場合など、エラーがある場合は NSDictionary には追加されません。
+ (void)addStringForJSONNSDictionary:(NSMutableDictionary*)dictionary key:(id)key string:(NSString*)string{
    if (string == nil) {
        return;
    }
    [dictionary setObject:string forKey:key];
}


/// HTML のエスケープ文字を元に戻します。(TODO: &#... 形式に対応する必要があります)
+ (NSString*)decodeHtmlEscape:(NSString*)htmlString {
    if (htmlString == nil) {
        return nil;
    }
    htmlString = [htmlString stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    htmlString = [htmlString stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    htmlString = [htmlString stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    htmlString = [htmlString stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    
    // これは最後にやらないと駄目
    htmlString = [htmlString stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    
    return htmlString;
}

/// 最上位の UIViewController を取得します。nil が返る可能性があります
+ (UIViewController*)findToplevelViewController
{
    return [UIViewController toplevelViewController];
}

/// 空白や改行など表示されない文字を全て排除した文字列を生成する
+ (NSString*)removeWhiteSpace:(NSString*)str{
    NSRegularExpression* regexp = [[NSRegularExpression alloc] initWithPattern:@"\\s+" options:0 error:nil];
    return [regexp stringByReplacingMatchesInString:str options:0 range:NSMakeRange(0, [str length]) withTemplate:@""];
}

/// 通知を表示させます
+ (void)InvokeNotificationNow:(NSString*)title message:(NSString*)message badgeNumber:(NSInteger)badgeNumber{
    UNMutableNotificationContent* notificationContent = [UNMutableNotificationContent new];
    notificationContent.title = title;
    notificationContent.body = message;
    notificationContent.badge = [[NSNumber alloc] initWithLong:badgeNumber];
    // Identifirer が同じ通知がある場合はその通知が消されて新しい通知に上書きされるので、個々の通知毎にユニークなIDをつけることにします
    NSDate* date = [NSDate date];
    NSDateFormatter* dateFormatter = [NSDateFormatter new];
    [dateFormatter setDateFormat:@"YYYYMMDDhhmmss"];
    NSString* uniqueIdentifier = [[NSString alloc] initWithFormat:@"NovelSpeaker_Notification_%@", [dateFormatter stringFromDate:date]];
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:uniqueIdentifier
                                                                          content:notificationContent
                                                                          trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        ;
    }];
}

/// NSString を zlib で圧縮して NSData にして返します
+ (NSData*)stringDeflate:(NSString*)string level:(int)level{
    if (string == nil) {
        string = @"";
    }
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [data deflate:9];
}

/// NSString が圧縮された NSData を NSString に戻します
+ (NSString*)stringInflate:(NSData*)data{
    NSData* unzipedData = nil;
    if (data == nil) {
        return @"";
    }
    unzipedData = [data inflate];
    return [[NSString alloc] initWithData:unzipedData encoding:NSUTF8StringEncoding];
}


@end
