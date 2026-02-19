// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 9.x
// ----------------------------------------------------------------------------
// SDK 9.x uses object-based LPMInterstitialAd / LPMRewardedAd APIs.
// The old static IronSource APIs (loadInterstitial, hasInterstitial,
// showInterstitialWithViewController:placement:, hasRewardedVideo,
// showRewardedVideoWithViewController:placement:, setLevelPlayInterstitialDelegate:,
// setLevelPlayRewardedVideoDelegate:, setConsent:) were removed in SDK 9.0.
//
// Init flow:
//   LPMInitRequest → [LevelPlay initWithRequest:completion:]
// Interstitial:
//   LPMInterstitialAd (LPMInterstitialAdDelegate) — loadAd / showAdWithViewController:placementName:
// Rewarded:
//   LPMRewardedAd (LPMRewardedAdDelegate) — loadAd / showAdWithViewController:placementName:
// Consent:
//   [LevelPlay setConsent:BOOL]  (NOT [IronSource setConsent:])
//
// CoronaLuaRef is void* — NULL sentinel (not LUA_NOREF)
// Lua 5.1: lua_pushcfunction/lua_setfield (not luaL_setfuncs)
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ----------------------------------------------------------------------------
// Shared state (plugin singleton)
// ----------------------------------------------------------------------------

static lua_State    *sL           = NULL;
static CoronaLuaRef  sListenerRef = NULL;   // void* — NULL = no listener

static LPMInterstitialAd *sInterstitialAd = nil;
static LPMRewardedAd     *sRewardedAd     = nil;

// Forward-declare delegate objects (defined below)
@class ISPluginInterstitialDelegate;
@class ISPluginRewardedDelegate;

static ISPluginInterstitialDelegate *sInterstitialDelegate = nil;
static ISPluginRewardedDelegate     *sRewardedDelegate     = nil;

// ----------------------------------------------------------------------------
// Event dispatcher — always dispatches on main thread
// ----------------------------------------------------------------------------

static void DispatchEvent(const char *type, const char *phase, BOOL isError, NSString *response) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sL || !sListenerRef) return;
        CoronaLuaNewEvent(sL, "ironSource");
        lua_pushstring(sL, type);              lua_setfield(sL, -2, "type");
        lua_pushstring(sL, phase);             lua_setfield(sL, -2, "phase");
        lua_pushboolean(sL, isError ? 1 : 0); lua_setfield(sL, -2, "isError");
        if (response) {
            lua_pushstring(sL, [response UTF8String]);
            lua_setfield(sL, -2, "response");
        }
        CoronaLuaDispatchEvent(sL, sListenerRef, 0);
    });
}

// ----------------------------------------------------------------------------
// Interstitial delegate  (LPMInterstitialAdDelegate)
// Required: didLoadAdWithAdInfo:, didFailToLoadAdWithAdUnitId:error:, didDisplayAdWithAdInfo:
// Optional: didFailToDisplayAdWithAdInfo:error:, didClickAdWithAdInfo:, didCloseAdWithAdInfo:
// ----------------------------------------------------------------------------

@interface ISPluginInterstitialDelegate : NSObject <LPMInterstitialAdDelegate>
@end

@implementation ISPluginInterstitialDelegate

- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "loaded", NO, nil);
}

- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"load failed";
    DispatchEvent("interstitial", "show", YES, msg);
}

- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "show", NO, nil);
}

- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"show failed";
    DispatchEvent("interstitial", "show", YES, msg);
}

- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {}

- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "closed", NO, nil);
}

@end

// ----------------------------------------------------------------------------
// Rewarded delegate  (LPMRewardedAdDelegate)
// Required: didLoadAdWithAdInfo:, didFailToLoadAdWithAdUnitId:error:,
//           didDisplayAdWithAdInfo:, didRewardAdWithAdInfo:reward:
// Optional: didFailToDisplayAdWithAdInfo:error:, didClickAdWithAdInfo:, didCloseAdWithAdInfo:
// ----------------------------------------------------------------------------

@interface ISPluginRewardedDelegate : NSObject <LPMRewardedAdDelegate>
@end

@implementation ISPluginRewardedDelegate

- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "available", NO, nil);
}

- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"load failed";
    DispatchEvent("rewardedVideo", "show", YES, msg);
}

- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "show", NO, nil);
}

- (void)didRewardAdWithAdInfo:(LPMAdInfo *)adInfo reward:(LPMReward *)reward {
    // Pass reward name (or placement name from adInfo if available) as response
    NSString *rewardName = (reward && reward.name.length) ? reward.name
                         : (adInfo.placementName.length   ? adInfo.placementName : nil);
    DispatchEvent("rewardedVideo", "reward", NO, rewardName);
}

- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"show failed";
    DispatchEvent("rewardedVideo", "show", YES, msg);
}

- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {}

- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "closed", NO, nil);
}

@end

// ----------------------------------------------------------------------------
// Lua API implementation
// ----------------------------------------------------------------------------

// ironSource.init(listener, options)
// options: { key, userId, hasUserConsent, coppaUnderAge, ccpaDoNotSell,
//            showDebugLog, interstitialAdUnitId, rewardedVideoAdUnitId }
static int lua_init(lua_State *L) {
    if (!CoronaLuaIsListener(L, 1, "ironSource")) {
        luaL_error(L, "ironSource.init: arg 1 must be a listener");
        return 0;
    }
    sL = L;
    if (sListenerRef) { CoronaLuaDeleteRef(L, sListenerRef); }
    sListenerRef = CoronaLuaNewRef(L, 1);

    if (lua_gettop(L) < 2 || !lua_istable(L, 2)) {
        luaL_error(L, "ironSource.init: arg 2 must be an options table");
        return 0;
    }

#define GSTR(f)  ({ lua_getfield(L,2,(f)); NSString *_v = lua_isstring(L,-1) ? @(lua_tostring(L,-1)) : nil; lua_pop(L,1); _v; })
#define GBOOL(f) ({ lua_getfield(L,2,(f)); BOOL _v = lua_isboolean(L,-1) && (BOOL)lua_toboolean(L,-1); lua_pop(L,1); _v; })

    NSString *appKey              = GSTR("key");
    NSString *userId              = GSTR("userId");
    NSString *interstitialAdUnit  = GSTR("interstitialAdUnitId");
    NSString *rewardedAdUnit      = GSTR("rewardedVideoAdUnitId");
    BOOL hasConsent               = GBOOL("hasUserConsent");
    BOOL coppa                    = GBOOL("coppaUnderAge");
    BOOL ccpa                     = GBOOL("ccpaDoNotSell");
    BOOL debug                    = GBOOL("showDebugLog");

#undef GSTR
#undef GBOOL

    if (!appKey.length) {
        luaL_error(L, "ironSource.init: options.key is required");
        return 0;
    }

    // Capture all values for async block
    NSString *appKeyC           = [appKey copy];
    NSString *userIdC           = [userId copy];
    NSString *interstitialIdC   = [interstitialAdUnit copy];
    NSString *rewardedIdC       = [rewardedAdUnit copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        // Consent and privacy (must be called before init)
        [LevelPlay setConsent:hasConsent];
        [LevelPlay setMetaDataWithKey:@"is_coppa"    value:coppa ? @"true" : @"false"];
        [LevelPlay setMetaDataWithKey:@"do_not_sell" value:ccpa  ? @"true" : @"false"];

        if (debug) {
            [LevelPlay setAdaptersDebug:YES];
        }

        // Create delegate objects
        sInterstitialDelegate = [[ISPluginInterstitialDelegate alloc] init];
        sRewardedDelegate     = [[ISPluginRewardedDelegate alloc] init];

        // Create ad objects (requires ad unit IDs from LevelPlay dashboard)
        if (interstitialIdC.length) {
            sInterstitialAd = [[LPMInterstitialAd alloc] initWithAdUnitId:interstitialIdC];
            [sInterstitialAd setDelegate:sInterstitialDelegate];
        }
        if (rewardedIdC.length) {
            sRewardedAd = [[LPMRewardedAd alloc] initWithAdUnitId:rewardedIdC];
            [sRewardedAd setDelegate:sRewardedDelegate];
        }

        // Build init request
        LPMInitRequest *initRequest = [[LPMInitRequest alloc]
                                       initWithAppKey:appKeyC
                                       userId:(userIdC.length ? userIdC : nil)];

        // Initialize SDK
        [LevelPlay initWithRequest:initRequest
                        completion:^(LPMConfiguration * _Nullable config, NSError * _Nullable error) {
            if (error) {
                DispatchEvent("init", "failed", YES, [error localizedDescription]);
            } else {
                DispatchEvent("init", "success", NO, nil);
            }
        }];
    });
    return 0;
}

// ironSource.load(adType)   adType = "interstitial" | "rewardedVideo"
static int lua_load(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.load: arg 1 must be adType string");
        return 0;
    }
    NSString *adType = @(lua_tostring(L, 1));

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd) {
                [sInterstitialAd loadAd];
            } else {
                DispatchEvent("interstitial", "show", YES, @"interstitialAdUnitId not set");
            }
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd) {
                [sRewardedAd loadAd];
            } else {
                DispatchEvent("rewardedVideo", "show", YES, @"rewardedVideoAdUnitId not set");
            }
        }
    });
    return 0;
}

// ironSource.show(adType [, options])   options: { placementName }
static int lua_show(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.show: arg 1 must be adType string");
        return 0;
    }
    NSString *adType = @(lua_tostring(L, 1));

    NSString *placement = nil;
    if (lua_gettop(L) >= 2 && lua_istable(L, 2)) {
        lua_getfield(L, 2, "placementName");
        if (lua_isstring(L, -1)) placement = @(lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    NSString *fp = [placement copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;

        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd && [sInterstitialAd isAdReady]) {
                [sInterstitialAd showAdWithViewController:vc
                                           placementName:(fp.length ? fp : nil)];
            } else {
                DispatchEvent("interstitial", "show", YES, @"not ready");
            }
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd && [sRewardedAd isAdReady]) {
                [sRewardedAd showAdWithViewController:vc
                                       placementName:(fp.length ? fp : nil)];
            } else {
                DispatchEvent("rewardedVideo", "show", YES, @"not available");
            }
        }
    });
    return 0;
}

// ironSource.isAvailable(adType)  → boolean
// Corona/Solar2D calls Lua from the main thread, so direct access is safe.
static int lua_isAvailable(lua_State *L) {
    if (!lua_isstring(L, 1)) { lua_pushboolean(L, 0); return 1; }
    NSString *adType = @(lua_tostring(L, 1));
    BOOL v = NO;
    if ([adType isEqualToString:@"interstitial"])  v = sInterstitialAd ? [sInterstitialAd isAdReady] : NO;
    if ([adType isEqualToString:@"rewardedVideo"]) v = sRewardedAd     ? [sRewardedAd     isAdReady] : NO;
    lua_pushboolean(L, v ? 1 : 0);
    return 1;
}

// ----------------------------------------------------------------------------
// Entry point — called when Lua does require("plugin.ironSource")
// ----------------------------------------------------------------------------

CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    sL           = L;
    sListenerRef = NULL;  // CoronaLuaRef = void* — NULL means no listener

    // Lua 5.1 table construction
    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
