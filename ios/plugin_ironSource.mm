// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ----------------------------------------------------------------------------
#pragma mark - Plugin class declaration
// ----------------------------------------------------------------------------

@interface IronSourcePlugin : NSObject <ISInterstitialDelegate, ISRewardedVideoDelegate>
@property (nonatomic, assign) lua_State *L;
@property (nonatomic, assign) CoronaLuaRef listenerRef;
+ (instancetype)sharedInstance;
- (void)dispatchEventType:(NSString *)type phase:(NSString *)phase isError:(BOOL)isError response:(NSString *)response;
@end

// ----------------------------------------------------------------------------
#pragma mark - Plugin singleton implementation
// ----------------------------------------------------------------------------

@implementation IronSourcePlugin

+ (instancetype)sharedInstance {
    static IronSourcePlugin *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IronSourcePlugin alloc] init];
    });
    return instance;
}

- (void)dispatchEventType:(NSString *)type phase:(NSString *)phase isError:(BOOL)isError response:(NSString *)response {
    dispatch_async(dispatch_get_main_queue(), ^{
        lua_State *L = self.L;
        if (L == NULL || self.listenerRef == LUA_NOREF) return;

        CoronaLuaNewEvent(L, "ironSource");

        lua_pushstring(L, [type UTF8String]);
        lua_setfield(L, -2, "type");

        lua_pushstring(L, [phase UTF8String]);
        lua_setfield(L, -2, "phase");

        lua_pushboolean(L, isError ? 1 : 0);
        lua_setfield(L, -2, "isError");

        if (response != nil) {
            lua_pushstring(L, [response UTF8String]);
            lua_setfield(L, -2, "response");
        }

        CoronaLuaDispatchEvent(L, self.listenerRef, 0);
    });
}

// ----------------------------------------------------------------------------
#pragma mark - ISInterstitialDelegate
// ----------------------------------------------------------------------------

- (void)interstitialDidLoad {
    [self dispatchEventType:@"interstitial" phase:@"loaded" isError:NO response:nil];
}

- (void)interstitialDidFailToLoadWithError:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"load failed";
    [self dispatchEventType:@"interstitial" phase:@"show" isError:YES response:msg];
}

- (void)interstitialDidOpen {}

- (void)interstitialDidClose {
    [self dispatchEventType:@"interstitial" phase:@"closed" isError:NO response:nil];
}

- (void)interstitialDidShow {
    [self dispatchEventType:@"interstitial" phase:@"show" isError:NO response:nil];
}

- (void)interstitialDidFailToShowWithError:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"show failed";
    [self dispatchEventType:@"interstitial" phase:@"show" isError:YES response:msg];
}

- (void)didClickInterstitial {}

// ----------------------------------------------------------------------------
#pragma mark - ISRewardedVideoDelegate
// ----------------------------------------------------------------------------

- (void)rewardedVideoHasChangedAvailability:(BOOL)available {
    if (available) {
        [self dispatchEventType:@"rewardedVideo" phase:@"available" isError:NO response:nil];
    }
}

- (void)didReceiveRewardForPlacement:(ISPlacementInfo *)placementInfo {
    NSString *name = placementInfo ? placementInfo.placementName : nil;
    [self dispatchEventType:@"rewardedVideo" phase:@"reward" isError:NO response:name];
}

- (void)rewardedVideoDidFailToShowWithError:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"show failed";
    [self dispatchEventType:@"rewardedVideo" phase:@"show" isError:YES response:msg];
}

- (void)rewardedVideoDidOpen {}

- (void)rewardedVideoDidClose {
    [self dispatchEventType:@"rewardedVideo" phase:@"closed" isError:NO response:nil];
}

- (void)rewardedVideoDidStart {}

- (void)rewardedVideoDidEnd {}

- (void)didClickRewardedVideo:(ISPlacementInfo *)placementInfo {}

@end

// ----------------------------------------------------------------------------
#pragma mark - Lua C functions
// ----------------------------------------------------------------------------

static int lua_init(lua_State *L) {
    // arg 1: listener function
    if (!CoronaLuaIsListener(L, 1, "ironSource")) {
        luaL_error(L, "ironSource.init() – first argument must be a listener function");
        return 0;
    }

    IronSourcePlugin *plugin = [IronSourcePlugin sharedInstance];
    plugin.L = L;

    if (plugin.listenerRef != LUA_NOREF) {
        CoronaLuaDeleteRef(L, plugin.listenerRef);
    }
    plugin.listenerRef = CoronaLuaNewRef(L, 1);

    if (lua_gettop(L) < 2 || !lua_istable(L, 2)) {
        luaL_error(L, "ironSource.init() – second argument must be an options table");
        return 0;
    }

    // Read appKey
    lua_getfield(L, 2, "key");
    NSString *appKey = nil;
    if (lua_isstring(L, -1)) appKey = @(lua_tostring(L, -1));
    lua_pop(L, 1);

    if (appKey == nil || appKey.length == 0) {
        luaL_error(L, "ironSource.init() – options.key (appKey) is required");
        return 0;
    }

    // Optional fields
    lua_getfield(L, 2, "userId");
    NSString *userId = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : nil;
    lua_pop(L, 1);

    lua_getfield(L, 2, "hasUserConsent");
    BOOL hasConsent = lua_isboolean(L, -1) ? (BOOL)lua_toboolean(L, -1) : NO;
    lua_pop(L, 1);

    lua_getfield(L, 2, "coppaUnderAge");
    BOOL coppa = lua_isboolean(L, -1) ? (BOOL)lua_toboolean(L, -1) : NO;
    lua_pop(L, 1);

    lua_getfield(L, 2, "ccpaDoNotSell");
    BOOL ccpa = lua_isboolean(L, -1) ? (BOOL)lua_toboolean(L, -1) : NO;
    lua_pop(L, 1);

    lua_getfield(L, 2, "showDebugLog");
    BOOL debug = lua_isboolean(L, -1) ? (BOOL)lua_toboolean(L, -1) : NO;
    lua_pop(L, 1);

    lua_getfield(L, 2, "attStatus");
    NSString *attStatus = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : nil;
    lua_pop(L, 1);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (debug) {
            [IronSource setAdaptersDebug:YES];
        }

        [IronSource setConsent:hasConsent];
        [IronSource setMetaDataWithKey:@"is_coppa" value:coppa ? @"true" : @"false"];
        [IronSource setMetaDataWithKey:@"do_not_sell" value:ccpa ? @"true" : @"false"];

        if (attStatus && [attStatus isEqualToString:@"authorized"]) {
            [IronSource setMetaDataWithKey:@"ATTStatus" value:@"1"];
        }

        if (userId && userId.length > 0) {
            [IronSource setUserId:userId];
        }

        [IronSource setInterstitialDelegate:plugin];
        [IronSource setRewardedVideoDelegate:plugin];

        [IronSource initWithAppKey:appKey adUnits:@[IS_AD_UNIT_INTERSTITIAL, IS_AD_UNIT_REWARDED_VIDEO]];
    });

    return 0;
}

static int lua_load(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.load() – first argument must be adUnitType string");
        return 0;
    }
    NSString *adUnitType = @(lua_tostring(L, 1));

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adUnitType isEqualToString:@"interstitial"]) {
            [IronSource loadInterstitial];
        }
        // rewardedVideo is auto-loaded by IronSource SDK
    });
    return 0;
}

static int lua_show(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.show() – first argument must be adUnitType string");
        return 0;
    }
    NSString *adUnitType = @(lua_tostring(L, 1));

    NSString *placement = nil;
    if (lua_gettop(L) >= 2 && lua_istable(L, 2)) {
        lua_getfield(L, 2, "placementName");
        if (lua_isstring(L, -1)) placement = @(lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    NSString *finalPlacement = [placement copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
        if ([adUnitType isEqualToString:@"interstitial"]) {
            if ([IronSource isInterstitialReady]) {
                if (finalPlacement.length > 0) {
                    [IronSource showInterstitialWithViewController:vc placement:finalPlacement];
                } else {
                    [IronSource showInterstitialWithViewController:vc placement:nil];
                }
            } else {
                [[IronSourcePlugin sharedInstance] dispatchEventType:@"interstitial" phase:@"show" isError:YES response:@"not ready"];
            }
        } else if ([adUnitType isEqualToString:@"rewardedVideo"]) {
            if ([IronSource hasRewardedVideo]) {
                if (finalPlacement.length > 0) {
                    [IronSource showRewardedVideoWithViewController:vc placement:finalPlacement];
                } else {
                    [IronSource showRewardedVideoWithViewController:vc placement:nil];
                }
            } else {
                [[IronSourcePlugin sharedInstance] dispatchEventType:@"rewardedVideo" phase:@"show" isError:YES response:@"not available"];
            }
        }
    });
    return 0;
}

static int lua_isAvailable(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    NSString *adUnitType = @(lua_tostring(L, 1));
    BOOL available = NO;
    if ([adUnitType isEqualToString:@"interstitial"]) {
        available = [IronSource isInterstitialReady];
    } else if ([adUnitType isEqualToString:@"rewardedVideo"]) {
        available = [IronSource hasRewardedVideo];
    }
    lua_pushboolean(L, available ? 1 : 0);
    return 1;
}

// ----------------------------------------------------------------------------
#pragma mark - Plugin entry point
// ----------------------------------------------------------------------------

static const luaL_Reg kFunctions[] = {
    { "init",        lua_init        },
    { "load",        lua_load        },
    { "show",        lua_show        },
    { "isAvailable", lua_isAvailable },
    { NULL, NULL }
};

CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    // Initialise the plugin singleton
    IronSourcePlugin *plugin = [IronSourcePlugin sharedInstance];
    plugin.L            = L;
    plugin.listenerRef  = LUA_NOREF;

    // Create and return the Lua library table
    lua_newtable(L);
    luaL_setfuncs(L, kFunctions, 0);

    return 1;
}
