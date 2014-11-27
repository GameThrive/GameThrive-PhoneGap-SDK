/**
 * Copyright 2014 GameThrive
 * Portions Copyright 2014 StackMob
 *
 * This file includes portions from the StackMob iOS SDK and distributed under an Apache 2.0 license.
 * StackMob was acquired by PayPal and ceased operation on May 22, 2014.
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

#import "GameThrive.h"
#import "GTHTTPClient.h"
#import "GTTrackPlayerPurchase.h"
#import "HGTJailbreakDetection.h"

#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define DEFAULT_PUSH_HOST @"https://gamethrive.com/api/v1/"

#define NOTIFICATION_TYPE_BADGE 1
#define NOTIFICATION_TYPE_SOUND 2
#define NOTIFICATION_TYPE_ALERT 4
#define NOTIFICATION_TYPE_ALL 7

static GameThrive* defaultClient = nil;

@interface GameThrive ()

@property(nonatomic, readwrite, copy) NSString *app_id;
@property(nonatomic, readwrite, copy) NSDictionary *lastMessageReceived;
@property(nonatomic, readwrite, copy) NSString *deviceModel;
@property(nonatomic, readwrite, copy) NSString *systemVersion;
@property(nonatomic, retain) GTHTTPClient *httpClient;

@end

@implementation GameThrive

@synthesize app_id = _GT_publicKey;
@synthesize httpClient = _GT_httpRequest;
@synthesize lastMessageReceived;

NSMutableDictionary* tagsToSend;

NSString* mDeviceToken;
GTResultSuccessBlock tokenUpdateSuccessBlock;
GTFailureBlock tokenUpdateFailureBlock;
NSString* mPlayerId;

GTIdsAvailableBlock idsAvailableBlockWhenReady;
GTHandleNotificationBlock handleNotification;

UIBackgroundTaskIdentifier focusBackgroundTask;

GTTrackPlayerPurchase* trackPlayerPurchase;


bool registeredWithApple = false; // Has attempted to register for push notifications with Apple.
bool gameThriveReg = false;
NSNumber* lastTrackedTime;
int mNotificationTypes = -1;

- (id)initWithLaunchOptions:(NSDictionary*)launchOptions {
    return [self initWithLaunchOptions:launchOptions appId:nil handleNotification:nil autoRegister:true];
}

- (id)initWithLaunchOptions:(NSDictionary*)launchOptions autoRegister:(BOOL)autoRegister {
    return [self initWithLaunchOptions:launchOptions appId:nil handleNotification:nil autoRegister:autoRegister];
}

- (id)initWithLaunchOptions:(NSDictionary*)launchOptions handleNotification:(GTHandleNotificationBlock)callback {
    return [self initWithLaunchOptions:launchOptions appId:nil handleNotification:callback autoRegister:true];
}

- (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId handleNotification:(GTHandleNotificationBlock)callback {
    return [self initWithLaunchOptions:launchOptions appId:appId handleNotification:callback autoRegister:true];
}

- (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId handleNotification:(GTHandleNotificationBlock)callback autoRegister:(BOOL)autoRegister {
    self = [super init];
    
    if (self) {
        handleNotification = callback;
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        
        if (appId)
            self.app_id = appId;
        else
            self.app_id = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GameThrive_APPID"];
        
        NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@", DEFAULT_PUSH_HOST]];
        self.httpClient = [[GTHTTPClient alloc] initWithBaseURL:url];
        
        struct utsname systemInfo;
        uname(&systemInfo);
        self.deviceModel   = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        self.systemVersion = [[UIDevice currentDevice] systemVersion];
        
        if ([GameThrive defaultClient] == nil)
            [GameThrive setDefaultClient:self];
        
        // Handle changes to the app id. This might happen on a developer's device when testing.
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        if (self.app_id == nil)
            self.app_id = [defaults stringForKey:@"GT_APP_ID"];
        else if (![self.app_id isEqualToString:[defaults stringForKey:@"GT_APP_ID"]]) {
            [defaults setObject:self.app_id forKey:@"GT_APP_ID"];
            [defaults setObject:nil forKey:@"GT_PLAYER_ID"];
            [defaults synchronize];
        }
        
        mPlayerId = [defaults stringForKey:@"GT_PLAYER_ID"];
        mDeviceToken = [defaults stringForKey:@"GT_DEVICE_TOKEN"];
        registeredWithApple = mDeviceToken != nil || [defaults boolForKey:@"GT_REGISTERED_WITH_APPLE"];
        mNotificationTypes = getNotificationTypes();
        
        // Register this device with Apple's APNS server.
        if (autoRegister || registeredWithApple)
            [self registerForPushNotifications];
        // iOS 8 - Register for remote notifications to get a token now since registerUserNotificationSettings is what shows the prompt.
        else if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerForRemoteNotifications)])
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        
        if (mPlayerId != nil)
            [self registerPlayer];
        else // Fall back incase Apple does not responsed in time.
            [self performSelector:@selector(registerPlayer) withObject:nil afterDelay:30.0f];
    }
    
    NSDictionary* userInfo = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (userInfo && NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_7_0) {
        // Only call for iOS 6.
        // In iOS 7 & 8 the fetchCompletionHandler gets called inaddition to userInfo being filled here.
        [self notificationOpened:userInfo isActive:false];
    }
    
    clearBadgeCount();
    
    if ([GTTrackPlayerPurchase canTrack])
        trackPlayerPurchase = [[GTTrackPlayerPurchase alloc] init];
    
    return self;
}

// "registerForRemoteNotifications*" calls didRegisterForRemoteNotificationsWithDeviceToken
// in the implementation UIApplication(GameThrivePush) below after contacting Apple's server.
- (void)registerForPushNotifications {
    // For iOS 8 devices
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        // ClassFromString to work around pre Xcode 6 link errors when building an app using the GameThrive framework.
        Class uiUserNotificationSettings = NSClassFromString(@"UIUserNotificationSettings");
        NSUInteger notificationTypes = NOTIFICATION_TYPE_ALL;
        
        [[UIApplication sharedApplication] registerUserNotificationSettings:[uiUserNotificationSettings settingsForTypes:notificationTypes categories:nil]];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    else { // For iOS 6 & 7 devices
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert];
        if (!registeredWithApple) {
            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:@YES forKey:@"GT_REGISTERED_WITH_APPLE"];
            [defaults synchronize];
        }
    }
}

- (void)registerDeviceToken:(id)inDeviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSString* deviceToken = [[inDeviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    
    [self updateDeviceToken:[[deviceToken componentsSeparatedByString:@" "] componentsJoinedByString:@""] onSuccess:successBlock onFailure:failureBlock];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:mDeviceToken forKey:@"GT_DEVICE_TOKEN"];
    [defaults synchronize];
}

- (void)updateDeviceToken:(NSString*)deviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    
    if (mPlayerId == nil) {
        mDeviceToken = deviceToken;
        tokenUpdateSuccessBlock = successBlock;
        tokenUpdateFailureBlock = failureBlock;
        
        // iOS 8 - We get a token right away but give the user 30 sec to responsed to the system prompt.
        // The goal is to only have 1 server call.
        if (isCapableOfGettingNotificationTypes()) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(registerPlayer) object:nil];
            [self performSelector:@selector(registerPlayer) withObject:nil afterDelay:30.0f];
        }
        else
            [self registerPlayer];
        return;
    }
    
    if ([deviceToken isEqualToString:mDeviceToken]) {
        if (successBlock)
            successBlock(nil);
        return;
    }
    
    mDeviceToken = deviceToken;
    
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             deviceToken, @"identifier",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock];
    
    if (idsAvailableBlockWhenReady) {
        mNotificationTypes = getNotificationTypes();
        if (getUsableDeviceToken())
            idsAvailableBlockWhenReady(mPlayerId, getUsableDeviceToken());
        idsAvailableBlockWhenReady = nil;
    }
}


- (NSArray*)getSoundFiles {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* error = nil;
    
    NSArray* allFiles = [fm contentsOfDirectoryAtPath:[[NSBundle mainBundle] resourcePath] error:&error];
    NSMutableArray* soundFiles = [NSMutableArray new];
    if (error == nil) {
        for(id file in allFiles) {
            if ([file hasSuffix:@".wav"] || [file hasSuffix:@".mp3"])
                [soundFiles addObject:file];
        }
    }
    
    return soundFiles;
}

- (void)registerPlayer {
    // Make sure we only call create or on_session once per run of the app.
    if (gameThriveReg)
        return;
    
    gameThriveReg = true;
    
    NSMutableURLRequest* request;
    if (mPlayerId == nil)
        request = [self.httpClient requestWithMethod:@"POST" path:@"players"];
    else
        request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_session", mPlayerId]];
    
    NSDictionary* infoDictionary = [[NSBundle mainBundle]infoDictionary];
    NSString* build = infoDictionary[(NSString*)kCFBundleVersionKey];
    
    NSMutableDictionary* dataDic = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             self.deviceModel, @"device_model",
                             self.systemVersion, @"device_os",
                             [[NSLocale preferredLanguages] objectAtIndex:0], @"language",
                             [NSNumber numberWithInt:(int)[[NSTimeZone localTimeZone] secondsFromGMT]], @"timezone",
                             build, @"game_version",
                             [NSNumber numberWithInt:0], @"device_type",
                             [[[UIDevice currentDevice] identifierForVendor] UUIDString], @"ad_id",
                             [self getSoundFiles], @"sounds",
                             @"010603", @"sdk",
                             mDeviceToken, @"identifier", // identifier MUST be at the end as it could be nil.
                             nil];
    
    mNotificationTypes = getNotificationTypes();
    
    if ([HGTJailbreakDetection isJailbroken])
        dataDic[@"rooted"] = @YES;
    
    if (mNotificationTypes != -1 && isCapableOfGettingNotificationTypes())
        dataDic[@"notification_types"] = [NSNumber numberWithInt:mNotificationTypes];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:^(NSDictionary* results) {
        if ([results objectForKey:@"id"] != nil) {
            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            mPlayerId = [results objectForKey:@"id"];
            [defaults setObject:mPlayerId forKey:@"GT_PLAYER_ID"];
            [defaults synchronize];
            
            if (mDeviceToken)
                [self updateDeviceToken:mDeviceToken onSuccess:tokenUpdateSuccessBlock onFailure:tokenUpdateFailureBlock];
            
            if (tagsToSend != nil) {
                [self sendTags:tagsToSend];
                tagsToSend = nil;
            }
            
            if (idsAvailableBlockWhenReady) {
                idsAvailableBlockWhenReady(mPlayerId, getUsableDeviceToken());
                if (getUsableDeviceToken())
                    idsAvailableBlockWhenReady = nil;
            }
        }
    } onFailure:^(NSError* error) {
        NSLog(@"Error registering with GameThrive: %@", error);
    }];
}

- (void)IdsAvailable:(GTIdsAvailableBlock)idsAvailableBlock {
    if (mPlayerId)
        idsAvailableBlock(mPlayerId, getUsableDeviceToken());
    
    if (mPlayerId == nil || getUsableDeviceToken() == nil)
        idsAvailableBlockWhenReady = idsAvailableBlock;
}

- (NSString*)getPlayerId {
    return mPlayerId;
}

NSString* getUsableDeviceToken() {
    if (mNotificationTypes > 0)
        return mDeviceToken;
    return nil;
}

- (void)sendTags:(NSDictionary*)keyValuePair {
    [self sendTags:keyValuePair onSuccess:nil onFailure:nil];
}

- (void)sendTags:(NSDictionary*)keyValuePair onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    if (mPlayerId == nil) {
        if (tagsToSend == nil)
            tagsToSend = [keyValuePair mutableCopy];
        else
            [tagsToSend addEntriesFromDictionary:keyValuePair];
        return;
    }
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             keyValuePair, @"tags",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request
               onSuccess:successBlock
               onFailure:failureBlock];
}

- (void)sendTag:(NSString*)key value:(NSString*)value {
    [self sendTag:key value:value onSuccess:nil onFailure:nil];
}

- (void)sendTag:(NSString*)key value:(NSString*)value onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self sendTags:[NSDictionary dictionaryWithObjectsAndKeys: value, key, nil] onSuccess:successBlock onFailure:failureBlock];
}

- (void)getTags:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"GET" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    [self enqueueRequest:request onSuccess:^(NSDictionary* results) {
        if ([results objectForKey:@"tags"] != nil)
            successBlock([results objectForKey:@"tags"]);
    } onFailure:failureBlock];
}

- (void)getTags:(GTResultSuccessBlock)successBlock {
    [self getTags:successBlock onFailure:nil];
}


- (void)deleteTag:(NSString*)key onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self deleteTags:@[key] onSuccess:successBlock onFailure:failureBlock];
}

- (void)deleteTag:(NSString*)key {
    [self deleteTags:@[key] onSuccess:nil onFailure:nil];
}

- (void)deleteTags:(NSArray*)keys onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    if (mPlayerId == nil)
        return;
    
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSMutableDictionary* deleteTagsDict = [NSMutableDictionary dictionary];
    for(id key in keys)
        [deleteTagsDict setObject:@"" forKey:key];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             deleteTagsDict, @"tags",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock];
}

- (void)deleteTags:(NSArray*)keys {
    [self deleteTags:keys onSuccess:nil onFailure:nil];
}

- (void) sendNotificationTypesUpdateIsConfirmed:(BOOL)isConfirm {
    // iOS 8 - User changed notification settings for the app.
    if (mPlayerId && isCapableOfGettingNotificationTypes() && (isConfirm || mNotificationTypes != getNotificationTypes()) ) {
        mNotificationTypes = getNotificationTypes();
        NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
        
        NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                 self.app_id, @"app_id",
                                 [NSNumber numberWithInt:mNotificationTypes], @"notification_types",
                                 nil];
        
        NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
        [request setHTTPBody:postData];
        
        [self enqueueRequest:request onSuccess:nil onFailure:nil];
        
        if (getUsableDeviceToken() && idsAvailableBlockWhenReady) {
            idsAvailableBlockWhenReady(mPlayerId, getUsableDeviceToken());
            idsAvailableBlockWhenReady = nil;
        }
    }

}


- (void) beginBackgroundFocusTask {
    focusBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self endBackgroundFocusTask];
    }];
}

- (void) endBackgroundFocusTask {
    [[UIApplication sharedApplication] endBackgroundTask: focusBackgroundTask];
    focusBackgroundTask = UIBackgroundTaskInvalid;
}

- (void)onFocus:(NSString*)state {
    bool wasBadgeSet = false;
    
    if ([state isEqualToString:@"resume"]) {
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        
        [self sendNotificationTypesUpdateIsConfirmed:false];
        wasBadgeSet = clearBadgeCount();
    }
    
    if (mPlayerId == nil)
        return;
    
    // If resuming and badge was set, clear it on the server as well.
    if (wasBadgeSet && [state isEqualToString:@"resume"]) {
        NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
        
        NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                 self.app_id, @"app_id",
                                 @0, @"badge_count",
                                 nil];
        
        NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
        [request setHTTPBody:postData];
        
        [self enqueueRequest:request onSuccess:nil onFailure:nil];
        return;
    }
    
    // Update the playtime on the server when the app put into the background or the device goes to sleep mode.
    if ([state isEqualToString:@"suspend"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self beginBackgroundFocusTask];
        
            NSNumber* timeElapsed = @(([[NSDate date] timeIntervalSince1970] - [lastTrackedTime longLongValue]) + 0.5);
            timeElapsed = [NSNumber numberWithLongLong: [timeElapsed longLongValue]];
            lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
            
            NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_focus", mPlayerId]];
            NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                     self.app_id, @"app_id",
                                     @"ping", @"state",
                                     timeElapsed, @"active_time",
                                     nil];
            
            NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
            [request setHTTPBody:postData];
        
            // We are already running in a thread so send the request synchronous to keep the thread alive.
            [self enqueueRequest:request
                       onSuccess:nil
                       onFailure:nil
                   isSynchronous:true];
            [self endBackgroundFocusTask];
        });
    }
}

- (void)sendPurchases:(NSArray*)purchases {
    if (mPlayerId == nil)
        return;
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_purchase", mPlayerId]];
    
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             purchases, @"purchases",
                             nil];
    
    NSData *postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request
               onSuccess:nil
               onFailure:nil];
}

- (void)sendPurchase:(NSNumber*)amount onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSLog(@"sendPurchase is deprecated as this is now automatic for Apple IAP purchases. The method does nothing!");
}

- (void)sendPurchase:(NSNumber*)amount {
    NSLog(@"sendPurchase is deprecated as this is now automatic for Apple IAP purchases. The method does nothing!");
}

- (void)notificationOpened:(NSDictionary*)messageDict isActive:(BOOL)isActive {
    NSDictionary* customDict = [messageDict objectForKey:@"custom"];
    NSString* messageId = [customDict objectForKey:@"i"];
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"notifications/%@", messageId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             mPlayerId, @"player_id",
                             @(YES), @"opened",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:nil onFailure:nil];
    
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive && [customDict objectForKey:@"u"] != nil) {
        NSURL *url = [NSURL URLWithString:[customDict objectForKey:@"u"]];
        [[UIApplication sharedApplication] openURL:url];
    }
    
    self.lastMessageReceived = messageDict;
    
    // Clear bages and nofiications from this app. Setting to 1 then 0 was needed to clear the notifications.
    clearBadgeCount();
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    
    if (handleNotification)
        handleNotification([self getMessageString], [self getAdditionalData], isActive);
}

bool clearBadgeCount() {
    if (mNotificationTypes == -1 || (mNotificationTypes & NOTIFICATION_TYPE_BADGE) == 0)
        return false;
    
    bool wasBadgeSet = false;
    
    if ([UIApplication sharedApplication].applicationIconBadgeNumber > 0)
        wasBadgeSet = true;
    
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    
    return wasBadgeSet;
}

bool isCapableOfGettingNotificationTypes() {
    return [[UIApplication sharedApplication] respondsToSelector:@selector(currentUserNotificationSettings)];
}

int getNotificationTypes() {
    if (mDeviceToken) {
        if (isCapableOfGettingNotificationTypes())
            return [[UIApplication sharedApplication] currentUserNotificationSettings].types;
        else
            return NOTIFICATION_TYPE_ALL;
    }
    
    return -1;
}

- (void) updateNotificationTypes:(int)notificationTypes {
    BOOL changed = (mNotificationTypes != notificationTypes);
    
    mNotificationTypes = notificationTypes;
    
    if (mPlayerId == nil)
        [self registerPlayer];
    else if (mDeviceToken)
        [self sendNotificationTypesUpdateIsConfirmed:changed];
    
    if (idsAvailableBlockWhenReady && mPlayerId && getUsableDeviceToken())
        idsAvailableBlockWhenReady(mPlayerId, getUsableDeviceToken());
}

- (NSDictionary*)getAdditionalData {
    return [[self.lastMessageReceived objectForKey:@"custom"] objectForKey:@"a"];
}

- (NSString*)getMessageString {
    return self.lastMessageReceived[@"aps"][@"alert"];
}

- (void)enqueueRequest:(NSURLRequest*)request onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock isSynchronous:false];
}

- (void)enqueueRequest:(NSURLRequest*)request onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock isSynchronous:(BOOL)isSynchronous {
    if (isSynchronous) {
        NSURLResponse* response = nil;
        NSError* error = nil;
        
        [NSURLConnection sendSynchronousRequest:request
            returningResponse:&response
            error:&error];
        
        [self handleJSONNSURLResponse:response data:nil error:error onSuccess:successBlock onFailure:failureBlock];
    }
    else {
		[NSURLConnection
            sendAsynchronousRequest:request
            queue:[[NSOperationQueue alloc] init]
            completionHandler:^(NSURLResponse* response,
                                NSData* data,
                                NSError* error) {
                [self handleJSONNSURLResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock];
            }];
    }
}

- (void)handleJSONNSURLResponse:(NSURLResponse*) response data:(NSData*) data error:(NSError*) error onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [HTTPResponse statusCode];
    NSError* jsonError;
    NSMutableDictionary* innerJson;
    
    if (data != nil && [data length] > 0) {
        innerJson = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
        if (jsonError != nil) {
            if (failureBlock != nil)
                failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"returned" : jsonError}]);
            return;
        }
    }
    
    if (error == nil && statusCode == 200) {
        if (successBlock != nil) {
            if (innerJson != nil)
                successBlock(innerJson);
            else
                successBlock(nil);
        }
    }
    else if (failureBlock != nil) {
        if (innerJson != nil && error == nil)
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"returned" : innerJson}]);
        else if (error != nil)
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"error" : error}]);
        else
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:nil]);
    }
}


+ (void)setDefaultClient:(GameThrive *)client {
    defaultClient = client;
}

+ (GameThrive *)defaultClient {
    return defaultClient;
}

@end


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


@implementation UIApplication(GameThrivePush)

- (void)gameThriveDidRegisterForRemoteNotifications:(UIApplication*)app deviceToken:(NSData*)deviceToken {
    NSLog(@"Device Registered with Apple.");
    [[GameThrive defaultClient] registerDeviceToken:deviceToken onSuccess:^(NSDictionary* results) {
        NSLog(@"Device Registered with GameThrive.");
    } onFailure:^(NSError* error) {
        NSLog(@"Error in GameThrive Registration: %@", error);
    }];
    
    if ([self respondsToSelector:@selector(gameThriveDidRegisterForRemoteNotifications:deviceToken:)])
        [self gameThriveDidRegisterForRemoteNotifications:app deviceToken:deviceToken];
}

- (void)gameThriveDidFailRegisterForRemoteNotification:(UIApplication*)app error:(NSError*)err {
    NSLog(@"Error registering for Apple push notifications. Error: %@", err);
    
    if ([self respondsToSelector:@selector(gameThriveDidFailRegisterForRemoteNotification:error:)])
        [self gameThriveDidFailRegisterForRemoteNotification:app error:err];
}

- (void)gameThriveDidRegisterUserNotifications:(UIApplication*)application settings:(UIUserNotificationSettings*)notificationSettings {
    if ([GameThrive defaultClient])
        [[GameThrive defaultClient] updateNotificationTypes:notificationSettings.types];
    
    if ([self respondsToSelector:@selector(gameThriveDidRegisterUserNotifications:settings:)])
        [self gameThriveDidRegisterUserNotifications:application settings:notificationSettings];
}


// Notification opened! iOS 6 ONLY!
//     gameThriveRemoteSilentNotification gets called on iOS 7 & 8
- (void)gameThriveReceivedRemoteNotification:(UIApplication*)application userInfo:(NSDictionary*)userInfo {
    [[GameThrive defaultClient] notificationOpened:userInfo isActive:[application applicationState] == UIApplicationStateActive];
    
    if ([self respondsToSelector:@selector(gameThriveReceivedRemoteNotification:userInfo:)])
        [self gameThriveReceivedRemoteNotification:application userInfo:userInfo];
}

// Notification opened or silent one received on iOS 7 & 8
- (void) gameThriveRemoteSilentNotification:(UIApplication*)application UserInfo:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult)) completionHandler {
    
    if (userInfo[@"m"]) {
        NSDictionary* data = userInfo;
        
        id category = [[NSClassFromString(@"UIMutableUserNotificationCategory") alloc] init];
        [category setIdentifier:@"dynamic"];
        
        Class UIMutableUserNotificationActionClass = NSClassFromString(@"UIMutableUserNotificationAction");
        NSMutableArray* actionArray = [[NSMutableArray alloc] init];
        for (NSDictionary* button in data[@"o"]) {
            id action = [[UIMutableUserNotificationActionClass alloc] init];
            [action setTitle:button[@"n"]];
            [action setIdentifier:button[@"i"] ? button[@"i"] : [action title]];
            [action setActivationMode:UIUserNotificationActivationModeForeground];
            [action setDestructive:NO];
            [action setAuthenticationRequired:NO];
            
            [actionArray addObject:action];
            // iOS 8 shows notification buttons in reverse in all cases but alerts. This flips it so the frist button is on the left.
            if (actionArray.count == 2)
                [category setActions:@[actionArray[1], actionArray[0]] forContext:UIUserNotificationActionContextMinimal];
        }
        
        [category setActions:actionArray forContext:UIUserNotificationActionContextDefault];
        
        Class uiUserNotificationSettings = NSClassFromString(@"UIUserNotificationSettings");
        NSUInteger notificationTypes = NOTIFICATION_TYPE_ALL;
        
        [[UIApplication sharedApplication] registerUserNotificationSettings:[uiUserNotificationSettings settingsForTypes:notificationTypes categories:[NSSet setWithObject:category]]];
        
        UILocalNotification* notification = [[UILocalNotification alloc] init];
        notification.category = [category identifier];
        notification.alertBody = data[@"m"];
        notification.userInfo = userInfo;
        notification.soundName = data[@"s"];
        if (notification.soundName == nil)
            notification.soundName = UILocalNotificationDefaultSoundName;
        if (data[@"b"])
            notification.applicationIconBadgeNumber = [data[@"b"] intValue];
        
        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    }
    else
        [[GameThrive defaultClient] notificationOpened:userInfo isActive:[application applicationState] == UIApplicationStateActive];
    
    if ([self respondsToSelector:@selector(gameThriveRemoteSilentNotification:UserInfo:fetchCompletionHandler:)])
        [self gameThriveRemoteSilentNotification:application UserInfo:userInfo fetchCompletionHandler:completionHandler];
    else
        completionHandler(UIBackgroundFetchResultNewData);
}

+ (void)processLocalActionBasedNotification:(UILocalNotification*) notification identifier:(NSString*)identifier {
    if (notification.userInfo && notification.userInfo[@"custom"]) {
        NSMutableDictionary* userInfo = [notification.userInfo mutableCopy];
        NSMutableDictionary* customDict = [userInfo[@"custom"] mutableCopy];
        NSMutableDictionary* additionalData = [[NSMutableDictionary alloc] initWithDictionary:customDict[@"a"]];
        
        NSMutableArray* buttonArray = [[NSMutableArray alloc] init];
        for (NSDictionary* button in userInfo[@"o"]) {
            [buttonArray addObject: @{@"text" : button[@"n"],
                                      @"id" : (button[@"i"] ? button[@"i"] : button[@"n"])}];
        }
        
        additionalData[@"actionSelected"] = identifier;
        additionalData[@"actionButtons"] = buttonArray;
        
        customDict[@"a"] = additionalData;
        userInfo[@"custom"] = customDict;
        
        userInfo[@"aps"] = @{@"alert" : userInfo[@"m"]};
    
        [[GameThrive defaultClient] notificationOpened:userInfo isActive:[[UIApplication sharedApplication] applicationState] == UIApplicationStateActive];
    }
}

- (void) gameThriveLocalNotificationOpened:(UIApplication*)application handleActionWithIdentifier:(NSString*)identifier forLocalNotification:(UILocalNotification*)notification completionHandler:(void(^)()) completionHandler {
    
    [UIApplication processLocalActionBasedNotification:notification identifier:identifier];
    
    if ([self respondsToSelector:@selector(gameThriveLocalNotificationOpened:handleActionWithIdentifier:forLocalNotification:completionHandler:)])
        [self gameThriveLocalNotificationOpened:application handleActionWithIdentifier:identifier forLocalNotification:notification completionHandler:completionHandler];
    else
        completionHandler();
}

- (void)gameThriveLocalNotificaionOpened:(UIApplication*)application notification:(UILocalNotification*)notification {
    [UIApplication processLocalActionBasedNotification:notification identifier:@"__DEFAULT__"];
    
    if ([self respondsToSelector:@selector(gameThriveLocalNotificaionOpened:notification:)])
        [self gameThriveLocalNotificaionOpened:application notification:notification];
}

- (void)gameThriveApplicationWillResignActive:(UIApplication*)application {
    if ([GameThrive defaultClient])
        [[GameThrive defaultClient] onFocus:@"suspend"];
    
    if ([self respondsToSelector:@selector(gameThriveApplicationWillResignActive:)])
        [self gameThriveApplicationWillResignActive:application];
}
- (void)gameThriveApplicationDidBecomeActive:(UIApplication*)application {
    if ([GameThrive defaultClient])
        [[GameThrive defaultClient] onFocus:@"resume"];
    
    if ([self respondsToSelector:@selector(gameThriveApplicationDidBecomeActive:)])
        [self gameThriveApplicationDidBecomeActive:application];
}

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(setDelegate:)), class_getInstanceMethod(self, @selector(setGameThriveDelegate:)));
}



static Class delegateClass = nil;

- (void) setGameThriveDelegate:(id<UIApplicationDelegate>)delegate {
    
	if(delegateClass != nil)
		return;
    
	delegateClass = [delegate class];
    
    injectSelector(self.class, @selector(gameThriveReceivedRemoteNotification:userInfo:),
                   delegateClass, @selector(application:didReceiveRemoteNotification:));
    
    injectSelector(self.class, @selector(gameThriveRemoteSilentNotification:UserInfo:fetchCompletionHandler:),
                    delegateClass, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:));
    
    injectSelector(self.class, @selector(gameThriveDidRegisterUserNotifications:settings:),
                   delegateClass, @selector(application:didRegisterUserNotificationSettings:));
    
    injectSelector(self.class, @selector(gameThriveLocalNotificationOpened:handleActionWithIdentifier:forLocalNotification:completionHandler:),
                    delegateClass, @selector(application:handleActionWithIdentifier:forLocalNotification:completionHandler:));
    
    injectSelector(self.class, @selector(gameThriveDidRegisterForRemoteNotifications:deviceToken:),
                    delegateClass, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:));
    
    injectSelector(self.class, @selector(gameThriveDidFailRegisterForRemoteNotification:error:),
                    delegateClass, @selector(application:didFailToRegisterForRemoteNotificationsWithError:));
    
    injectSelector(self.class, @selector(gameThriveLocalNotificaionOpened:notification:),
                    delegateClass, @selector(application:didReceiveLocalNotification:));
    
    injectSelector(self.class, @selector(gameThriveApplicationWillResignActive:),
                    delegateClass, @selector(applicationWillResignActive:));
    
    injectSelector(self.class, @selector(gameThriveApplicationDidBecomeActive:),
                    delegateClass, @selector(applicationDidBecomeActive:));
    
    
    [self setGameThriveDelegate:delegate];
}

@end

