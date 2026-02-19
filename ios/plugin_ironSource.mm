// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 7.9.0
// ----------------------------------------------------------------------------
// DESIGN: LevelPlayInterstitialDelegate and LevelPlayRewardedVideoDelegate share
//         method signatures (didFailToShowWithError:andAdInfo:, didOpenWithAdInfo:,
//         didCloseWithAdInfo:). We must use SEPARATE delegate objects per ad type.
// API notes:
//   IS_INTERSTITIAL / IS_REWARDED_VIDEO (not IS_AD_UNIT_* which don't exist in 7.9.0)
//   hasInterstitial (not isInterstitialReady)
//   CoronaLuaRef is void* — NULL sentinel (not LUA_NOREF)
//   Lua 5.1: lua_pushcfunction/lua_setfield (not luaL_setfuncs)
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ----------------------------------------------------------------------------
// Shared state (simple globals for plugin singleton pattern)
// ----------------------------------------------------------------------------

static lua_State    *sL           = NULL;
static CoronaLuaRef  sListenerRef = NULL;   // void* — NULL = no listener

static void DispatchEvent(const char *type, const char *phase, BOOL isError, NSString *response) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sL || !sListenerRef) return;
        CoronaLuaNewEvent(sL, "ironSource");
        lua_pushstring(sL, type);               lua_setfield(sL, -2, "type");
        lua_pushstring(sL, phase);              lua_setfield(sL, -2, "phase");
        lua_pushboolean(sL, isError ? 1 : 0);  lua_setfield(sL, -2, "isError");
        if (response) { lua_pushstring(sL, [response UTF8String]); lua_setfield(sL, -2, "response"); }
        CoronaLuaDispatchEvent(sL, sListenerRef, 0);
    });
}

// ----------------------------------------------------------------------------
// Interstitial delegate
// ----------------------------------------------------------------------------

@interface ISPluginInterstitialDelegate : NSObject <LevelPlayInterstitialDelegate>
@end

@implementation ISPluginInterstitialDelegate

- (void)didLoadWithAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("interstitial", "loaded", NO, nil);
}
- (void)didFailToLoadWithError:(NSError *)error {
    DispatchEvent("interstitial", "show", YES, error ? [error localizedDescription] : @"load failed");
}
- (void)didOpenWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didShowWithAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("interstitial", "show", NO, nil);
}
- (void)didFailToShowWithError:(NSError *)error andAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("interstitial", "show", YES, error ? [error localizedDescription] : @"show failed");
}
- (void)didClickWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didCloseWithAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("interstitial", "closed", NO, nil);
}

@end

// ----------------------------------------------------------------------------
// Rewarded video delegate
// ----------------------------------------------------------------------------

@interface ISPluginRewardedVideoDelegate : NSObject <LevelPlayRewardedVideoDelegate>
@end

@implementation ISPluginRewardedVideoDelegate

// LevelPlayRewardedVideoDelegate (adds availability)
- (void)hasAvailableAdWithAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "available", NO, nil);
}
- (void)hasNoAvailableAd {}

// LevelPlayRewardedVideoBaseDelegate (required)
- (void)didReceiveRewardForPlacement:(ISPlacementInfo *)placementInfo withAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "reward", NO, placementInfo ? placementInfo.placementName : nil);
}
- (void)didFailToShowWithError:(NSError *)error andAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "show", YES, error ? [error localizedDescription] : @"show failed");
}
- (void)didOpenWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didClick:(ISPlacementInfo *)placementInfo withAdInfo:(ISAdInfo *)adInfo {}
- (void)didCloseWithAdInfo:(ISAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "closed", NO, nil);
}

@end

// Delegate singletons
static ISPluginInterstitialDelegate  *sInterstitialDelegate  = nil;
static ISPluginRewardedVideoDelegate *sRewardedVideoDelegate  = nil;

// ----------------------------------------------------------------------------
// Lua API
// ----------------------------------------------------------------------------

static int lua_init(lua_State *L) {
    if (!CoronaLuaIsListener(L, 1, "ironSource")) {
        luaL_error(L, "ironSource.init: arg 1 must be a listener"); return 0;
    }
    sL = L;
    if (sListenerRef) { CoronaLuaDeleteRef(L, sListenerRef); }
    sListenerRef = CoronaLuaNewRef(L, 1);

    if (lua_gettop(L) < 2 || !lua_istable(L, 2)) {
        luaL_error(L, "ironSource.init: arg 2 must be options table"); return 0;
    }

#define GSTR(f) ({ lua_getfield(L,2,f); NSString *v=lua_isstring(L,-1)?@(lua_tostring(L,-1)):nil; lua_pop(L,1); v; })
#define GBOOL(f) ({ lua_getfield(L,2,f); BOOL v=lua_isboolean(L,-1)&&(BOOL)lua_toboolean(L,-1); lua_pop(L,1); v; })

    NSString *appKey    = GSTR("key");
    NSString *userId    = GSTR("userId");
    NSString *attStatus = GSTR("attStatus");
    BOOL hasConsent     = GBOOL("hasUserConsent");
    BOOL coppa          = GBOOL("coppaUnderAge");
    BOOL ccpa           = GBOOL("ccpaDoNotSell");
    BOOL debug          = GBOOL("showDebugLog");

#undef GSTR
#undef GBOOL

    if (!appKey.length) { luaL_error(L, "ironSource.init: options.key required"); return 0; }

    NSString *appKeyC = [appKey copy], *userIdC = [userId copy], *attC = [attStatus copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (debug) [IronSource setAdaptersDebug:YES];
        [IronSource setConsent:hasConsent];
        [IronSource setMetaDataWithKey:@"is_coppa"    value:coppa ? @"true" : @"false"];
        [IronSource setMetaDataWithKey:@"do_not_sell" value:ccpa  ? @"true" : @"false"];
        if ([attC isEqualToString:@"authorized"]) [IronSource setMetaDataWithKey:@"ATTStatus" value:@"1"];
        if (userIdC.length) [IronSource setUserId:userIdC];

        // Create separate delegate objects (avoids duplicate method signature issues)
        if (!sInterstitialDelegate)  sInterstitialDelegate  = [[ISPluginInterstitialDelegate  alloc] init];
        if (!sRewardedVideoDelegate) sRewardedVideoDelegate = [[ISPluginRewardedVideoDelegate alloc] init];

        [IronSource setLevelPlayInterstitialDelegate:sInterstitialDelegate];
        [IronSource setLevelPlayRewardedVideoDelegate:sRewardedVideoDelegate];

        [IronSource initWithAppKey:appKeyC adUnits:@[IS_INTERSTITIAL, IS_REWARDED_VIDEO]];
    });
    return 0;
}

static int lua_load(lua_State *L) {
    if (!lua_isstring(L, 1)) { luaL_error(L, "ironSource.load: arg 1 must be string"); return 0; }
    NSString *adType = @(lua_tostring(L, 1));
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adType isEqualToString:@"interstitial"]) [IronSource loadInterstitial];
    });
    return 0;
}

static int lua_show(lua_State *L) {
    if (!lua_isstring(L, 1)) { luaL_error(L, "ironSource.show: arg 1 must be string"); return 0; }
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
            if ([IronSource hasInterstitial])
                [IronSource showInterstitialWithViewController:vc placement:fp.length ? fp : nil];
            else
                DispatchEvent("interstitial", "show", YES, @"not ready");
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if ([IronSource hasRewardedVideo])
                [IronSource showRewardedVideoWithViewController:vc placement:fp.length ? fp : nil];
            else
                DispatchEvent("rewardedVideo", "show", YES, @"not available");
        }
    });
    return 0;
}

static int lua_isAvailable(lua_State *L) {
    if (!lua_isstring(L, 1)) { lua_pushboolean(L, 0); return 1; }
    NSString *adType = @(lua_tostring(L, 1));
    BOOL v = NO;
    if ([adType isEqualToString:@"interstitial"])  v = [IronSource hasInterstitial];
    if ([adType isEqualToString:@"rewardedVideo"]) v = [IronSource hasRewardedVideo];
    lua_pushboolean(L, v ? 1 : 0);
    return 1;
}

// ----------------------------------------------------------------------------
// Entry point
// ----------------------------------------------------------------------------

CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    sL           = L;
    sListenerRef = NULL;  // CoronaLuaRef = void* — NULL means no listener

    // Lua 5.1: manual table construction
    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
