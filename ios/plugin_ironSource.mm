// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 9.x
// ----------------------------------------------------------------------------
// v9.3.5 — Definitive static-linking fix:
//
// ROOT CAUSE (all v9.3.1–v9.3.4 failures):
//   IronSource.framework/IronSource is a STATIC LIBRARY (ar archive), not a
//   dynamic Mach-O dylib. You cannot dlopen() a static library. All previous
//   dlopen() attempts silently returned NULL, gSDKLoaded = NO, and init()
//   dispatched "failed" immediately — causing the black screen.
//
// FIX:
//   The CI build uses `libtool -static` to merge IronSource's static library
//   into libplugin_ironSource.a. All symbols are linked directly into the app
//   binary at CoronaBuilder time. No dynamic loading needed.
//   metadata.lua no longer declares `frameworks = {"IronSource"}` (there is no
//   dynamic framework to embed).
//
// Lua API (unchanged):
//   ironSource.init(listener, options)   -- options: key, userId,
//                                        --   interstitialAdUnitId,
//                                        --   rewardedVideoAdUnitId,
//                                        --   hasUserConsent, coppaUnderAge,
//                                        --   ccpaDoNotSell, showDebugLog
//   ironSource.load(adType)             -- "interstitial" | "rewardedVideo"
//   ironSource.show(adType [, opts])    -- opts: placementName
//   ironSource.isAvailable(adType)      -- returns boolean
//
// Events: { name="ironSource", type, phase, isError [, response] }
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// IronSource is statically merged into libplugin_ironSource.a at build time.
// Import headers normally — class refs are resolved at link time.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#import <IronSource/IronSource.h>
#pragma clang diagnostic pop

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ---------------------------------------------------------------------------
// Shared plugin globals
// ---------------------------------------------------------------------------
static lua_State    *sL           = NULL;
static CoronaLuaRef  sListenerRef = NULL;

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
        if (response) {
            lua_pushstring(sL, [response UTF8String]);
            lua_setfield(sL, -2, "response");
        }
        CoronaLuaDispatchEvent(sL, sListenerRef, 0);
    });
}

// ---------------------------------------------------------------------------
// Helper: topmost view controller
// ---------------------------------------------------------------------------
static UIViewController *TopViewController(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
                if (window) break;
            }
        }
    }
    if (!window) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ---------------------------------------------------------------------------
// Interstitial delegate
// ---------------------------------------------------------------------------
@interface ISPluginInterstitialDelegate : NSObject <LPMInterstitialAdDelegate>
@end
@implementation ISPluginInterstitialDelegate

- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "loaded", NO, nil);
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    DispatchEvent("interstitial", "show", YES,
                  error ? [error localizedDescription] : @"load failed");
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "show", NO, nil);
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    DispatchEvent("interstitial", "show", YES,
                  error ? [error localizedDescription] : @"show failed");
}
- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("interstitial", "closed", NO, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sInterstitialAd) [sInterstitialAd loadAd];
    });
}
@end

// ---------------------------------------------------------------------------
// Rewarded delegate
// ---------------------------------------------------------------------------
@interface ISPluginRewardedDelegate : NSObject <LPMRewardedAdDelegate>
@end
@implementation ISPluginRewardedDelegate

- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "available", NO, nil);
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    DispatchEvent("rewardedVideo", "show", YES,
                  error ? [error localizedDescription] : @"load failed");
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "show", NO, nil);
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    DispatchEvent("rewardedVideo", "show", YES,
                  error ? [error localizedDescription] : @"show failed");
}
- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    DispatchEvent("rewardedVideo", "closed", NO, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sRewardedAd) [sRewardedAd loadAd];
    });
}
- (void)didRewardAdWithAdInfo:(LPMAdInfo *)adInfo reward:(LPMReward *)reward {
    NSString *name = reward.name.length ? reward.name : adInfo.placementName;
    DispatchEvent("rewardedVideo", "reward", NO, name);
}
- (void)didChangeAdInfo:(LPMAdInfo *)adInfo {}
@end

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
    if (sListenerRef) CoronaLuaDeleteRef(L, sListenerRef);
    sListenerRef = CoronaLuaNewRef(L, 1);

    if (lua_gettop(L) < 2 || !lua_istable(L, 2)) {
        luaL_error(L, "ironSource.init: arg 2 must be options table"); return 0;
    }

#define GSTR(f)  ({ lua_getfield(L,2,f); NSString *_v=lua_isstring(L,-1)?@(lua_tostring(L,-1)):nil; lua_pop(L,1); _v; })
#define GBOOL(f) ({ lua_getfield(L,2,f); BOOL _v=lua_isboolean(L,-1)&&(BOOL)lua_toboolean(L,-1); lua_pop(L,1); _v; })

    NSString *appKey = GSTR("key");
    NSString *userId = GSTR("userId");
    NSString *intId  = GSTR("interstitialAdUnitId");
    NSString *rvId   = GSTR("rewardedVideoAdUnitId");
    BOOL consent     = GBOOL("hasUserConsent");
    BOOL coppa       = GBOOL("coppaUnderAge");
    BOOL ccpa        = GBOOL("ccpaDoNotSell");
    BOOL debug       = GBOOL("showDebugLog");

#undef GSTR
#undef GBOOL

    if (!appKey.length) { luaL_error(L, "ironSource.init: options.key required"); return 0; }

    appKey = [appKey copy]; userId = [userId copy];
    intId  = [intId copy];  rvId   = [rvId copy];

    dispatch_async(dispatch_get_main_queue(), ^{

        // Privacy / consent
        [LevelPlay setConsent:consent];
        [LevelPlay setMetaDataWithKey:@"is_coppa" value:coppa ? @"true" : @"false"];
        [LevelPlay setMetaDataWithKey:@"do_not_sell" value:ccpa ? @"true" : @"false"];
        if (debug) {
            [LevelPlay setAdaptersDebug:YES];
        }

        // Build LPMInitRequest
        LPMInitRequestBuilder *builder =
            [[LPMInitRequestBuilder alloc] initWithAppKey:appKey];
        if (userId.length) {
            [builder withUserId:userId];
        }
        LPMInitRequest *initRequest = [builder build];

        if (!initRequest) {
            NSLog(@"[IronSourcePlugin] ERROR: LPMInitRequest build returned nil");
            DispatchEvent("init", "failed", YES, @"LPMInitRequest.build() returned nil");
            return;
        }

        // Init LevelPlay SDK
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

            // Create + load interstitial
            if (intId.length) {
                if (!sInterstitialDelegate)
                    sInterstitialDelegate = [[ISPluginInterstitialDelegate alloc] init];
                sInterstitialAd = [[LPMInterstitialAd alloc] initWithAdUnitId:intId];
                [sInterstitialAd setDelegate:sInterstitialDelegate];
                [sInterstitialAd loadAd];
            }

            // Create + load rewarded
            if (rvId.length) {
                if (!sRewardedDelegate)
                    sRewardedDelegate = [[ISPluginRewardedDelegate alloc] init];
                sRewardedAd = [[LPMRewardedAd alloc] initWithAdUnitId:rvId];
                [sRewardedAd setDelegate:sRewardedDelegate];
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
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.load: arg 1 must be string"); return 0;
    }
    NSString *adType = @(lua_tostring(L, 1));
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd) [sInterstitialAd loadAd];
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd) [sRewardedAd loadAd];
        }
    });
    return 0;
}

// ---------------------------------------------------------------------------
// Lua: show(adType [, options])
// ---------------------------------------------------------------------------
static int lua_show(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        luaL_error(L, "ironSource.show: arg 1 must be string"); return 0;
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
        UIViewController *vc = TopViewController();

        if ([adType isEqualToString:@"interstitial"]) {
            if (sInterstitialAd && [sInterstitialAd isAdReady]) {
                [sInterstitialAd showAdWithViewController:vc
                                            placementName:fp.length ? fp : nil];
            } else {
                DispatchEvent("interstitial", "show", YES, @"not ready");
            }
        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            if (sRewardedAd && [sRewardedAd isAdReady]) {
                [sRewardedAd showAdWithViewController:vc
                                        placementName:fp.length ? fp : nil];
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
    if ([adType isEqualToString:@"interstitial"] && sInterstitialAd)
        available = [sInterstitialAd isAdReady];
    if ([adType isEqualToString:@"rewardedVideo"] && sRewardedAd)
        available = [sRewardedAd isAdReady];
    lua_pushboolean(L, available ? 1 : 0);
    return 1;
}

// ---------------------------------------------------------------------------
// Plugin entry point
// ---------------------------------------------------------------------------
CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {
    NSLog(@"[IronSourcePlugin] v9.3.5 — IronSource statically linked, no dlopen needed");

    sL           = L;
    sListenerRef = NULL;

    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
