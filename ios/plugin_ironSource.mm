// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 7.9.0
// ----------------------------------------------------------------------------
// API notes (IronSource 7.9.0):
//   - IS_INTERSTITIAL / IS_REWARDED_VIDEO (not IS_AD_UNIT_*)
//   - hasInterstitial (not isInterstitialReady)
//   - LevelPlayInterstitialDelegate (ISInterstitialDelegate deprecated since 7.3.0)
//   - LevelPlayRewardedVideoDelegate (ISRewardedVideoDelegate deprecated since 7.3.0)
// Corona:
//   - CoronaLuaRef is void* — use NULL as sentinel (not LUA_NOREF)
//   - Solar2D uses Lua 5.1 — use lua_pushcfunction/lua_setfield not luaL_setfuncs
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ----------------------------------------------------------------------------
#pragma mark - Plugin class
// ----------------------------------------------------------------------------

@interface IronSourcePlugin : NSObject <LevelPlayInterstitialDelegate, LevelPlayRewardedVideoDelegate>
@property (nonatomic, assign) lua_State    *L;
@property (nonatomic, assign) CoronaLuaRef  listenerRef;  // void* — NULL = no listener
+ (instancetype)sharedInstance;
- (void)dispatchType:(NSString *)type phase:(NSString *)phase isError:(BOOL)isError response:(NSString *)response;
@end

@implementation IronSourcePlugin

+ (instancetype)sharedInstance {
    static IronSourcePlugin *s = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ s = [[IronSourcePlugin alloc] init]; s.listenerRef = NULL; });
    return s;
}

- (void)dispatchType:(NSString *)type phase:(NSString *)phase isError:(BOOL)isError response:(NSString *)response {
    dispatch_async(dispatch_get_main_queue(), ^{
        lua_State *L = self.L;
        if (!L || !self.listenerRef) return;

        CoronaLuaNewEvent(L, "ironSource");
        lua_pushstring(L, [type UTF8String]);  lua_setfield(L, -2, "type");
        lua_pushstring(L, [phase UTF8String]); lua_setfield(L, -2, "phase");
        lua_pushboolean(L, isError ? 1 : 0);   lua_setfield(L, -2, "isError");
        if (response) { lua_pushstring(L, [response UTF8String]); lua_setfield(L, -2, "response"); }
        CoronaLuaDispatchEvent(L, self.listenerRef, 0);
    });
}

// ---- LevelPlayInterstitialDelegate ----

- (void)didLoadWithAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"interstitial" phase:@"loaded" isError:NO response:nil];
}
- (void)didFailToLoadWithError:(NSError *)error {
    [self dispatchType:@"interstitial" phase:@"show" isError:YES
              response:error ? [error localizedDescription] : @"load failed"];
}
- (void)didOpenWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didShowWithAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"interstitial" phase:@"show" isError:NO response:nil];
}
- (void)didFailToShowWithError:(NSError *)error andAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"interstitial" phase:@"show" isError:YES
              response:error ? [error localizedDescription] : @"show failed"];
}
- (void)didClickWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didCloseWithAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"interstitial" phase:@"closed" isError:NO response:nil];
}

// ---- LevelPlayRewardedVideoDelegate (extends LevelPlayRewardedVideoBaseDelegate) ----

- (void)hasAvailableAdWithAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"rewardedVideo" phase:@"available" isError:NO response:nil];
}
- (void)hasNoAvailableAd {}

- (void)didReceiveRewardForPlacement:(ISPlacementInfo *)placementInfo withAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"rewardedVideo" phase:@"reward" isError:NO
              response:placementInfo ? placementInfo.placementName : nil];
}
- (void)didFailToShowWithError:(NSError *)error andAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"rewardedVideo" phase:@"show" isError:YES
              response:error ? [error localizedDescription] : @"show failed"];
}
- (void)didOpenWithAdInfo:(ISAdInfo *)adInfo {}
- (void)didClick:(ISPlacementInfo *)placementInfo withAdInfo:(ISAdInfo *)adInfo {}
- (void)didCloseWithAdInfo:(ISAdInfo *)adInfo {
    [self dispatchType:@"rewardedVideo" phase:@"closed" isError:NO response:nil];
}

@end

// ----------------------------------------------------------------------------
#pragma mark - Lua API
// ----------------------------------------------------------------------------

static int lua_init(lua_State *L) {
    if (!CoronaLuaIsListener(L, 1, "ironSource")) {
        luaL_error(L, "ironSource.init: arg 1 must be a listener function");
        return 0;
    }
    IronSourcePlugin *p = [IronSourcePlugin sharedInstance];
    p.L = L;
    if (p.listenerRef) { CoronaLuaDeleteRef(L, p.listenerRef); }
    p.listenerRef = CoronaLuaNewRef(L, 1);

    if (lua_gettop(L) < 2 || !lua_istable(L, 2)) {
        luaL_error(L, "ironSource.init: arg 2 must be options table"); return 0;
    }

#define GET_STRING(field) ({ lua_getfield(L,2,#field); NSString *v = lua_isstring(L,-1) ? @(lua_tostring(L,-1)) : nil; lua_pop(L,1); v; })
#define GET_BOOL(field)   ({ lua_getfield(L,2,#field); BOOL   v = lua_isboolean(L,-1) && lua_toboolean(L,-1); lua_pop(L,1); v; })

    NSString *appKey    = GET_STRING(key);
    NSString *userId    = GET_STRING(userId);
    NSString *attStatus = GET_STRING(attStatus);
    BOOL hasConsent     = GET_BOOL(hasUserConsent);
    BOOL coppa          = GET_BOOL(coppaUnderAge);
    BOOL ccpa           = GET_BOOL(ccpaDoNotSell);
    BOOL debug          = GET_BOOL(showDebugLog);

#undef GET_STRING
#undef GET_BOOL

    if (!appKey.length) { luaL_error(L, "ironSource.init: options.key required"); return 0; }

    NSString *appKeyC    = [appKey copy];
    NSString *userIdC    = [userId copy];
    NSString *attStatusC = [attStatus copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (debug)        [IronSource setAdaptersDebug:YES];
        [IronSource setConsent:hasConsent];
        [IronSource setMetaDataWithKey:@"is_coppa"    value:coppa ? @"true" : @"false"];
        [IronSource setMetaDataWithKey:@"do_not_sell" value:ccpa  ? @"true" : @"false"];
        if ([attStatusC isEqualToString:@"authorized"]) {
            [IronSource setMetaDataWithKey:@"ATTStatus" value:@"1"];
        }
        if (userIdC.length) [IronSource setUserId:userIdC];

        IronSourcePlugin *plugin = [IronSourcePlugin sharedInstance];
        [IronSource setLevelPlayInterstitialDelegate:plugin];
        [IronSource setLevelPlayRewardedVideoDelegate:plugin];

        [IronSource initWithAppKey:appKeyC
                          adUnits:@[IS_INTERSTITIAL, IS_REWARDED_VIDEO]];
    });
    return 0;
}

static int lua_load(lua_State *L) {
    if (!lua_isstring(L, 1)) { luaL_error(L, "ironSource.load: arg 1 must be string"); return 0; }
    NSString *adType = @(lua_tostring(L, 1));
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adType isEqualToString:@"interstitial"]) [IronSource loadInterstitial];
        // rewardedVideo auto-loaded by IronSource SDK after init
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
    NSString *finalPlacement = [placement copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
        if ([adType isEqualToString:@"interstitial"]) {
            if ([IronSource hasInterstitial]) {
                [IronSource showInterstitialWithViewController:vc
                             placement:finalPlacement.length ? finalPlacement : nil];
            } else {
                [[IronSourcePlugin sharedInstance] dispatchType:@"interstitial"
                    phase:@"show" isError:YES response:@"not ready"];
            }
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if ([IronSource hasRewardedVideo]) {
                [IronSource showRewardedVideoWithViewController:vc
                              placement:finalPlacement.length ? finalPlacement : nil];
            } else {
                [[IronSourcePlugin sharedInstance] dispatchType:@"rewardedVideo"
                    phase:@"show" isError:YES response:@"not available"];
            }
        }
    });
    return 0;
}

static int lua_isAvailable(lua_State *L) {
    if (!lua_isstring(L, 1)) { lua_pushboolean(L, 0); return 1; }
    NSString *adType = @(lua_tostring(L, 1));
    BOOL available = NO;
    if ([adType isEqualToString:@"interstitial"])  available = [IronSource hasInterstitial];
    if ([adType isEqualToString:@"rewardedVideo"]) available = [IronSource hasRewardedVideo];
    lua_pushboolean(L, available ? 1 : 0);
    return 1;
}

// ----------------------------------------------------------------------------
#pragma mark - Entry point
// ----------------------------------------------------------------------------

CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    IronSourcePlugin *p = [IronSourcePlugin sharedInstance];
    p.L           = L;
    p.listenerRef = NULL;  // CoronaLuaRef = void* — NULL not LUA_NOREF

    // Lua 5.1: manual table construction (luaL_setfuncs is Lua 5.2+)
    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
