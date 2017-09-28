//
//  ActionRequestHandler.m
//  NovelSpeakerURLDownloadExtension
//
//  Created by 飯村卓司 on 2016/09/27.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "ActionRequestHandler.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface ActionRequestHandler ()

@property (nonatomic, strong) NSExtensionContext *extensionContext;

@end

@implementation ActionRequestHandler

#define APP_GROUP_USER_DEFAULTS_SUITE_NAME @"group.com.limuraproducts.novelspeaker"
#define APP_GROUP_USER_DEFAULTS_URL_DOWNLOAD_QUEUE @"URLDownloadQueue"
#define APP_GROUP_USER_DEFAULTS_ADD_TEXT_QUEUE @"AddTextQueue"

- (NSUserDefaults*)getNovelSpeakerAppGroupUserDefaults
{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_USER_DEFAULTS_SUITE_NAME];
    return defaults;
}

- (void)addStringQueueToNovelSpeakerAppGroupUserDefaults:(NSString*)key text:(NSString*)text {
    NSUserDefaults* userDefaults = [self getNovelSpeakerAppGroupUserDefaults];
    NSArray* currentArray = [userDefaults stringArrayForKey:key];
    NSMutableArray* newArray = nil;
    if (currentArray == nil) {
        newArray = [NSMutableArray new];
    }else{
        newArray = [[NSMutableArray alloc] initWithArray:currentArray];
    }
    [newArray addObject:text];
    [userDefaults setObject:newArray forKey:key];
    [userDefaults synchronize];
}

- (void)addURLDownloadQueue:(NSURL*)url {
    [self addStringQueueToNovelSpeakerAppGroupUserDefaults:APP_GROUP_USER_DEFAULTS_URL_DOWNLOAD_QUEUE text:[url absoluteString]];
}

- (void)addTextQueue:(NSString*)text {
    [self addStringQueueToNovelSpeakerAppGroupUserDefaults:APP_GROUP_USER_DEFAULTS_ADD_TEXT_QUEUE text:text];
}

- (BOOL)checkAndRunItemProvider_for_PropertyListType:(NSItemProvider *)itemProvider context:(NSExtensionContext*)context{
    if (! [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypePropertyList]) {
        return NO;
    }
    [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypePropertyList options:nil completionHandler:^(NSDictionary *dictionary, NSError *error) {
        NSLog(@"PropertyList: %@", dictionary);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSDictionary *resultsDictionary = @{ NSExtensionJavaScriptFinalizeArgumentKey: @{ @"type" : @"PropertyList" } };
            NSItemProvider *resultsProvider = [[NSItemProvider alloc] initWithItem:resultsDictionary typeIdentifier:(NSString *)kUTTypePropertyList];
            
            NSExtensionItem *resultsItem = [[NSExtensionItem alloc] init];
            resultsItem.attachments = @[ resultsProvider ];
            
            [context completeRequestReturningItems:@[ resultsItem ] completionHandler:nil];
        }];
    }];
    return YES;
}

- (BOOL)checkAndRunItemProvider_for_PlainTextType:(NSItemProvider *)itemProvider context:(NSExtensionContext*)context{
    if (! [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypePlainText]) {
        return NO;
    }
    [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypePlainText options:nil completionHandler:^(NSString *item, NSError *error) {
        NSLog(@"isPlainText: %@", item);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            //[self addTextQueue:item];
            NSDictionary *resultsDictionary = @{ NSExtensionJavaScriptFinalizeArgumentKey: @{ @"type" : @"PlainText", @"data": item } };
            NSItemProvider *resultsProvider = [[NSItemProvider alloc] initWithItem:resultsDictionary typeIdentifier:(NSString *)kUTTypePropertyList];
            
            NSExtensionItem *resultsItem = [[NSExtensionItem alloc] init];
            resultsItem.attachments = @[ resultsProvider ];
            
            [context completeRequestReturningItems:@[ resultsItem ] completionHandler:nil];
        }];
    }];
    return YES;
}

- (BOOL)checkAndRunItemProvider_for_URLType:(NSItemProvider *)itemProvider context:(NSExtensionContext*)context{
    if (! [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeURL]) {
        return NO;
    }
    [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeURL options:nil completionHandler:^(NSURL *url, NSError *error) {
        NSLog(@"isURL: %@", [url absoluteString]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            //[self addURLDownloadQueue:url];
            NSDictionary *resultsDictionary = @{ NSExtensionJavaScriptFinalizeArgumentKey: @{ @"type" : @"URL", @"data": [url absoluteString] } };
            NSItemProvider *resultsProvider = [[NSItemProvider alloc] initWithItem:resultsDictionary typeIdentifier:(NSString *)kUTTypePropertyList];
            
            NSExtensionItem *resultsItem = [[NSExtensionItem alloc] init];
            resultsItem.attachments = @[ resultsProvider ];
            
            [context completeRequestReturningItems:@[ resultsItem ] completionHandler:nil];
        }];
    }];
    return YES;
}

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    // Do not call super in an Action extension with no user interface
    self.extensionContext = context;

    BOOL found = NO;
    
    // PropertyListType, URLType, PlainTextType の順で試す
    for (NSExtensionItem *item in context.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            NSLog(@"%@", itemProvider.registeredTypeIdentifiers);
            if ([self checkAndRunItemProvider_for_PropertyListType:itemProvider context:context] == YES) {
                found = YES;
                break;
            }
        }
        if (found) {
            break;
        }
    }
    if (!found) {
        for (NSExtensionItem *item in context.inputItems) {
            for (NSItemProvider *itemProvider in item.attachments) {
                if ([self checkAndRunItemProvider_for_URLType:itemProvider context:context] == YES) {
                    found = YES;
                    break;
                }
            }
            if (found) {
                break;
            }
        }
    }
    if (!found) {
        for (NSExtensionItem *item in context.inputItems) {
            for (NSItemProvider *itemProvider in item.attachments) {
                if ([self checkAndRunItemProvider_for_PlainTextType:itemProvider context:context] == YES) {
                    found = YES;
                    break;
                }
            }
            if (found) {
                break;
            }
        }
    }
    
    if (!found) {
        NSError* err = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"ActionRequestHandler_CanNotUseThisInformation", @"ことせかい で利用可能な情報ではありませんでした。")}];
        [context cancelRequestWithError:err];
    }
    
    /*
    BOOL found = NO;
    
    // Find the item containing the results from the JavaScript preprocessing.
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypePropertyList]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypePropertyList options:nil completionHandler:^(NSDictionary *dictionary, NSError *error) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [self itemLoadCompletedWithPreprocessingResults:dictionary[NSExtensionJavaScriptPreprocessingResultsKey]];
                    }];
                }];
                found = YES;
            }
            break;
        }
        if (found) {
            break;
        }
    }
    
    if (!found) {
        // We did not find anything
        [self doneWithResults:nil];
    }
     */
}

- (void)itemLoadCompletedWithPreprocessingResults:(NSDictionary *)javaScriptPreprocessingResults {
    // Here, do something, potentially asynchronously, with the preprocessing
    // results.
    
    // In this very simple example, the JavaScript will have passed us the
    // current background color style, if there is one. We will construct a
    // dictionary to send back with a desired new background color style.
    if ([javaScriptPreprocessingResults[@"currentBackgroundColor"] length] == 0) {
        // No specific background color? Request setting the background to red.
        [self doneWithResults:@{ @"newBackgroundColor": @"red" }];
    } else {
        // Specific background color is set? Request replacing it with green.
        [self doneWithResults:@{ @"newBackgroundColor": @"green" }];
    }
}

- (void)doneWithResults:(NSDictionary *)resultsForJavaScriptFinalize {
    if (resultsForJavaScriptFinalize) {
        // Construct an NSExtensionItem of the appropriate type to return our
        // results dictionary in.
        
        // These will be used as the arguments to the JavaScript finalize()
        // method.
        
        NSDictionary *resultsDictionary = @{ NSExtensionJavaScriptFinalizeArgumentKey: resultsForJavaScriptFinalize };
        
        NSItemProvider *resultsProvider = [[NSItemProvider alloc] initWithItem:resultsDictionary typeIdentifier:(NSString *)kUTTypePropertyList];
        
        NSExtensionItem *resultsItem = [[NSExtensionItem alloc] init];
        resultsItem.attachments = @[resultsProvider];
        
        // Signal that we're complete, returning our results.
        [self.extensionContext completeRequestReturningItems:@[resultsItem] completionHandler:nil];
    } else {
        // We still need to signal that we're done even if we have nothing to
        // pass back.
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }
    
    // Don't hold on to this after we finished with it.
    self.extensionContext = nil;
}

@end
