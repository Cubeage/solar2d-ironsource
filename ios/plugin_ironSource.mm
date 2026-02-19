// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 9.x
// ----------------------------------------------------------------------------
// Rewritten for SDK 9.x object-based API (LPMInterstitialAd / LPMRewardedAd).
// All old static APIs removed in SDK 9.0 have been replaced.
//
// SDK 9.x changes:
//   - Init:      [LevelPlay initWithRequest:completion:]  (LPMInitRequest)
//   - Consent:   [LevelPlay setConsent:]  (NOT [IronSource setConsent:])
//   - Interstitial: LPMInterstitialAd object + LPMInterstitialAdDelegate
//   - Rewarded:  LPMRewardedAd object + LPMRewardedAdDelegate
//
// Lua API (unchanged from 7.x):
//   ironSource.init(listener, options)          -- options: key, userId, interstitialAdUnitId,
//                                               --   rewardedVideoAdUnitId, hasUserConsent,
//                                               --   coppaUnderAge, ccpaDoNotSell, showDebugLog
//   ironSource.load(adType)                     -- "interstitial" | "rewardedVideo"
//   ironSource.show(adType [, options])         -- options: placementName
//   ironSource.isAvailable(adType) → boolean
//
// Events: { name="ironSource", type, phase, isError [, response] }
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>   // includes LPM* headers in SDK 9.x

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ---------------------------------------------------------------------------
// Shared globals (plugin singleton)
// ---------------------------------------------------------------------------

static lua_State    *sL           = NULL;
static CoronaLuaRef  sListenerRef = NULL;   // void* — NULL = no listener

static LPMInterstitialAd *sInterstitialAd = nil;
static LPMRewardedAd     *sRewardedAd     = nil;

// ---------------------------------------------------------------------------
// Event dispatch helper
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Helper: get the topmost presented view controller
// ---------------------------------------------------------------------------

static UIViewController *TopViewController(void) {
    UIWindow *window = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ---------------------------------------------------------------------------
// Interstitial delegate (LPMInterstitialAdDelegate — SDK 9.x)
// ---------------------------------------------------------------------------

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

- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {
    // no-op — click events not forwarded to Lua
}

- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "closed", NO, nil);
    // Auto-preload next interstitial (mirrors Android behavior)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sInterstitialAd) [sInterstitialAd loadAd];
    });
}

@end

// ---------------------------------------------------------------------------
// Rewarded delegate (LPMRewardedAdDelegate — SDK 9.x)
// ---------------------------------------------------------------------------

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

- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    NSString *msg = error ? [error localizedDescription] : @"show failed";
    DispatchEvent("rewardedVideo", "show", YES, msg);
}

- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {
    // no-op
}

- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "closed", NO, nil);
    // Auto-reload for next show (mirrors Android behavior)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sRewardedAd) [sRewardedAd loadAd];
    });
}

- (void)didRewardAdWithAdInfo:(LPMAdInfo *)adInfo reward:(LPMReward *)reward {
    NSString *rewardName = (reward && reward.name.length) ? reward.name
                         : (adInfo.placementName.length   ? adInfo.placementName : nil);
    DispatchEvent("rewardedVideo", "reward", NO, rewardName);
}

// Optional: fires when a higher-CPM ad replaces the loaded one
- (void)didChangeAdInfo:(LPMAdInfo *)adInfo {}

@end

// Delegate singletons
static ISPluginInterstitialDelegate *sInterstitialDelegate = nil;
static ISPluginRewardedDelegate     *sRewardedDelegate     = nil;

// ---------------------------------------------------------------------------
// Lua: init(listener, options)
// ---------------------------------------------------------------------------

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

#define GSTR(f) ({ lua_getfield(L,2,f); NSString *_v=lua_isstring(L,-1)?@(lua_tostring(L,-1)):nil; lua_pop(L,1); _v; })
#define GBOOL(f) ({ lua_getfield(L,2,f); BOOL _v=lua_isboolean(L,-1)&&(BOOL)lua_toboolean(L,-1); lua_pop(L,1); _v; })

    NSString *appKey              = GSTR("key");
    NSString *userId              = GSTR("userId");
    NSString *interstitialAdUnitId = GSTR("interstitialAdUnitId");
    NSString *rewardedAdUnitId    = GSTR("rewardedVideoAdUnitId");
    BOOL hasConsent               = GBOOL("hasUserConsent");
    BOOL coppa                    = GBOOL("coppaUnderAge");
    BOOL ccpa                     = GBOOL("ccpaDoNotSell");
    BOOL debug                    = GBOOL("showDebugLog");

#undef GSTR
#undef GBOOL

    if (!appKey.length) { luaL_error(L, "ironSource.init: options.key required"); return 0; }

    // Capture for async block
    NSString *appKeyC              = [appKey copy];
    NSString *userIdC              = [userId copy];
    NSString *intAdUnitIdC         = [interstitialAdUnitId copy];
    NSString *rvAdUnitIdC          = [rewardedAdUnitId copy];

    dispatch_async(dispatch_get_main_queue(), ^{

        // ---- Privacy / consent (must be set BEFORE init in SDK 9.x) ----
        [LevelPlay setConsent:hasConsent];                                  // SDK 9.x consent API
        [LevelPlay setMetaDataWithKey:@"is_coppa"    value:coppa ? @"true" : @"false"];
        [LevelPlay setMetaDataWithKey:@"do_not_sell" value:ccpa  ? @"true" : @"false"];
        if (debug) [LevelPlay setAdaptersDebug:YES];

        // ---- Build LPMInitRequest ----
        LPMInitRequestBuilder *builder =
            [[LPMInitRequestBuilder alloc] initWithAppKey:appKeyC];
        if (userIdC.length) {
            [builder withUserId:userIdC];
        }
        LPMInitRequest *initRequest = [builder build];

        // ---- Initialize LevelPlay SDK ----
        [LevelPlay initWithRequest:initRequest completion:^(LPMConfiguration * _Nullable config,
                                                            NSError * _Nullable error) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"%@ (%ld)",
                                 error.localizedDescription, (long)error.code];
                NSLog(@"[IronSourcePlugin] LevelPlay init failed: %@", msg);
                DispatchEvent("init", "failed", YES, msg);
                return;
            }

            NSLog(@"[IronSourcePlugin] LevelPlay SDK initialized successfully");
            DispatchEvent("init", "success", NO, nil);

            // ---- Create and load Interstitial ----
            if (intAdUnitIdC.length) {
                if (!sInterstitialDelegate) sInterstitialDelegate = [[ISPluginInterstitialDelegate alloc] init];
                sInterstitialAd = [[LPMInterstitialAd alloc] initWithAdUnitId:intAdUnitIdC];
                sInterstitialAd.delegate = sInterstitialDelegate;
                [sInterstitialAd loadAd];
            }

            // ---- Create and load Rewarded ----
            if (rvAdUnitIdC.length) {
                if (!sRewardedDelegate) sRewardedDelegate = [[ISPluginRewardedDelegate alloc] init];
                sRewardedAd = [[LPMRewardedAd alloc] initWithAdUnitId:rvAdUnitIdC];
                sRewardedAd.delegate = sRewardedDelegate;
                [sRewardedAd loadAd];
            }
        }];
    });

    return 0;
}

// ---------------------------------------------------------------------------
// Lua: load(adType)
// ---------------------------------------------------------------------------

static int lua_load(lua_State *L) {
    if (!lua_isstring(L, 1)) { luaL_error(L, "ironSource.load: arg 1 must be string"); return 0; }
    NSString *adType = @(lua_tostring(L, 1));

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd) [sInterstitialAd loadAd];
            else NSLog(@"[IronSourcePlugin] ironSource.load(interstitial) – ad object not ready");
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd) [sRewardedAd loadAd];
            else NSLog(@"[IronSourcePlugin] ironSource.load(rewardedVideo) – ad object not ready");
        }
    });
    return 0;
}

// ---------------------------------------------------------------------------
// Lua: show(adType [, options])
// ---------------------------------------------------------------------------

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
        UIViewController *vc = TopViewController();

        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd && [sInterstitialAd isAdReady]) {
                [sInterstitialAd showAdWithViewController:vc placementName:(fp.length ? fp : nil)];
            } else {
                DispatchEvent("interstitial", "show", YES, @"not ready");
            }

        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd && [sRewardedAd isAdReady]) {
                [sRewardedAd showAdWithViewController:vc placementName:(fp.length ? fp : nil)];
            } else {
                DispatchEvent("rewardedVideo", "show", YES, @"not available");
            }
        }
    });
    return 0;
}

// ---------------------------------------------------------------------------
// Lua: isAvailable(adType) → boolean
// ---------------------------------------------------------------------------

static int lua_isAvailable(lua_State *L) {
    if (!lua_isstring(L, 1)) { lua_pushboolean(L, 0); return 1; }
    NSString *adType = @(lua_tostring(L, 1));
    BOOL available = NO;
    if ([adType isEqualToString:@"interstitial"])  available = (sInterstitialAd && [sInterstitialAd isAdReady]);
    if ([adType isEqualToString:@"rewardedVideo"]) available = (sRewardedAd     && [sRewardedAd     isAdReady]);
    lua_pushboolean(L, available ? 1 : 0);
    return 1;
}

// ---------------------------------------------------------------------------
// Plugin entry point
// ---------------------------------------------------------------------------

CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    sL           = L;
    sListenerRef = NULL;   // CoronaLuaRef = void* — NULL means no listener

    // Lua 5.1: manual table construction
    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
