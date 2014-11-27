/**
 * Copyright 2014 GameThrive
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "GameThrivePush.h"
#import "GameThrive.h"

GameThrive* gameThrive;

NSString* notficationOpenedCallbackId;
NSString* getTagsCallbackId;
NSString* getIdsCallbackId;

NSMutableDictionary* launchDict;

id <CDVCommandDelegate> pluginCommandDelegate;

void successCallback(NSString* callbackId, NSDictionary* data) {
    CDVPluginResult* commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:data];
    commandResult.keepCallback = @1;
    [pluginCommandDelegate sendPluginResult:commandResult callbackId:callbackId];
}

void processNotificationOpened(NSDictionary* launchOptions) {
    successCallback(notficationOpenedCallbackId, launchOptions);
}

void initGameThriveObject(NSDictionary* launchOptions, const char* appId, BOOL autoRegister) {
    if (gameThrive == nil) {
        NSString* appIdStr = (appId ? [NSString stringWithUTF8String: appId] : nil);
        
        gameThrive = [[GameThrive alloc] initWithLaunchOptions:launchOptions appId:appIdStr handleNotification:^(NSString* message, NSDictionary* additionalData, BOOL isActive) {
            launchDict = [NSMutableDictionary new];
            launchDict[@"message"] = message;
            if (additionalData)
                launchDict[@"additionalData"] = additionalData;
            launchDict[@"isActive"] = [NSNumber numberWithBool:isActive];
            
            if (pluginCommandDelegate)
                processNotificationOpened(launchDict);
        } autoRegister:autoRegister];
    }
}

@implementation UIApplication(GameThriveCordovaPush)

static void injectSelector(Class newClass, SEL newSel, Class addToClass, SEL makeLikeSel) {
    Method newMeth = class_getInstanceMethod(newClass, newSel);
    IMP imp = method_getImplementation(newMeth);
    const char* methodTypeEncoding = method_getTypeEncoding(newMeth);
    
    BOOL successful = class_addMethod(addToClass, makeLikeSel, imp, methodTypeEncoding);
    if (!successful) {
        class_addMethod(addToClass, newSel, imp, methodTypeEncoding);
        newMeth = class_getInstanceMethod(addToClass, newSel);
        
        Method orgMeth = class_getInstanceMethod(addToClass, makeLikeSel);
        
        method_exchangeImplementations(orgMeth, newMeth);
    }
}

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(setDelegate:)), class_getInstanceMethod(self, @selector(setGameThriveCordovaDelegate:)));
}

static Class delegateClass = nil;

- (void) setGameThriveCordovaDelegate:(id<UIApplicationDelegate>)delegate {
    if(delegateClass != nil)
        return;
    delegateClass = [delegate class];
    
    injectSelector(self.class, @selector(gameThriveApplication:didFinishLaunchingWithOptions:),
                   delegateClass, @selector(application:didFinishLaunchingWithOptions:));
    [self setGameThriveCordovaDelegate:delegate];
}

- (BOOL)gameThriveApplication:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    if ([launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey] != nil)
        initGameThriveObject(launchOptions, nil, true);
    
    if ([self respondsToSelector:@selector(gameThriveApplication:didFinishLaunchingWithOptions:)])
        return [self gameThriveApplication:application didFinishLaunchingWithOptions:launchOptions];
    return YES;
}

@end

@implementation GameThrivePush

- (void)init:(CDVInvokedUrlCommand*)command {
    pluginCommandDelegate = self.commandDelegate;
    notficationOpenedCallbackId = command.callbackId;

    NSDictionary* options = command.arguments[0];
    
    BOOL autoRegister = true;
    if ([options objectForKey:@"autoRegister"] == @NO)
        autoRegister = false;

    initGameThriveObject(nil, [options[@"appId"] UTF8String], autoRegister);
    
    if (launchDict)
        processNotificationOpened(launchDict);
}

- (void)getTags:(CDVInvokedUrlCommand*)command {
    getTagsCallbackId = command.callbackId;
    [gameThrive getTags:^(NSDictionary* result) {
        successCallback(getTagsCallbackId, result);
    }];
}

- (void)getIds:(CDVInvokedUrlCommand*)command {
    getIdsCallbackId = command.callbackId;
    [gameThrive IdsAvailable:^(NSString* playerId, NSString* pushToken) {
        if(pushToken == nil)
            pushToken = @"";
        
        successCallback(getIdsCallbackId, @{@"playerId" : playerId, @"pushToken" : pushToken});
    }];
}

- (void)sendTags:(CDVInvokedUrlCommand*)command {
    [gameThrive sendTags:command.arguments[0]];
}

- (void)deleteTags:(CDVInvokedUrlCommand*)command {
    [gameThrive deleteTags:command.arguments];
}

- (void)registerForPushNotifications:(CDVInvokedUrlCommand*)command {
    [gameThrive registerForPushNotifications];
}

@end
