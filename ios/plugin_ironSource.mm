// plugin_ironSource.mm
// Solar2D iOS plugin bridge for IronSource (Unity LevelPlay) SDK 9.x
// ----------------------------------------------------------------------------
// v9.3.4 — Root-cause fix for "black screen" on iOS:
//
// PROBLEM: CoronaBuilder links with -undefined dynamic_lookup. All ObjC class
// refs compiled into libplugin_ironSource.a (LevelPlay, LPMInterstitialAd, etc.)
// become BIND-AT-LOAD symbols. At dyld load time — BEFORE main() — these refs
// are bound to NULL because IronSource.framework is not in LC_LOAD_DYLIB.
// dlopen() in luaopen_ loads the framework, but the already-bound NULL slots in
// __DATA.__objc_classrefs are NOT updated by dyld after the fact.
// Result: [LevelPlay initWithRequest:...] = objc_msgSend(NULL, ...) = no-op.
// Init callback never fires. Ads never load. Black screen if game waits for init.
//
// FIX: Do NOT import IronSource headers at compile time. Do NOT write [ClassName ...]
// with literal class names. After dlopen(), use objc_getClass() to get live class
// pointers, then use objc_msgSend() / performSelector: for all calls. These go
// through the ObjC runtime (NOT the pre-bound classref slots) and work correctly.
//
// Lua API (unchanged):
//   ironSource.init(listener, options)   -- options: key, userId, interstitialAdUnitId,
//                                        --   rewardedVideoAdUnitId, hasUserConsent,
//                                        --   coppaUnderAge, ccpaDoNotSell, showDebugLog
//   ironSource.load(adType)             -- "interstitial" | "rewardedVideo"
//   ironSource.show(adType [, opts])    -- opts: placementName
//   ironSource.isAvailable(adType)      -- returns boolean
//
// Events: { name="ironSource", type, phase, isError [, response] }
// ----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

// Import IronSource headers for method signature / selector declarations ONLY.
// This does NOT generate ObjC class refs as long as we avoid literal [ClassName ...]
// syntax for class-level calls. Instance method calls ([instance method]) are safe
// because they use the object's isa pointer, not the static class ref slot.
// The -F flag points the compiler to the SDK; the framework is NOT linked into the
// binary here — dlopen() handles runtime loading.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#import <IronSource/IronSource.h>
#pragma clang diagnostic pop

#import "CoronaRuntime.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"

// ---------------------------------------------------------------------------
// Runtime class pointers — populated in luaopen_ AFTER dlopen()
// Use these instead of compile-time class refs (which are NULL at launch)
// ---------------------------------------------------------------------------
static Class kLevelPlay              = Nil;
static Class kLPMInterstitialAd      = Nil;
static Class kLPMRewardedAd          = Nil;
static Class kLPMInitRequestBuilder  = Nil;

static BOOL gSDKLoaded = NO;   // set YES when dlopen + objc_getClass succeed

// ---------------------------------------------------------------------------
// Shared plugin globals
// ---------------------------------------------------------------------------
static lua_State    *sL           = NULL;
static CoronaLuaRef  sListenerRef = NULL;

static id sInterstitialAd = nil;   // LPMInterstitialAd* (id to avoid compile-time classref)
static id sRewardedAd     = nil;   // LPMRewardedAd*

// ---------------------------------------------------------------------------
// objc_msgSend helper typedefs (self + SEL + explicit args)
// ---------------------------------------------------------------------------
typedef void (*VoidBoolIMP)(id, SEL, BOOL);       // (self, SEL, BOOL)
typedef void (*VoidIdIMP)(id, SEL, id);            // (self, SEL, id) — 1 object arg
typedef void (*VoidIdIdIMP)(id, SEL, id, id);      // (self, SEL, id, id) — 2 object args
typedef id   (*IdIdIMP)(id, SEL, id);              // (self, SEL, id) → id
typedef id   (*AllocIMP)(id, SEL);                 // (self, SEL) → id

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
// Helper: topmost view controller (iOS 13+ scene API + legacy fallback)
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
// Interstitial delegate — informal protocol (no compile-time IronSource refs)
// Selectors match LPMInterstitialAdDelegate. IronSource calls via
// respondsToSelector: + objc_msgSend, so formal protocol conformance is optional.
// ---------------------------------------------------------------------------
@interface ISPluginInterstitialDelegate : NSObject
@end
@implementation ISPluginInterstitialDelegate

- (void)didLoadAdWithAdInfo:(id)adInfo {
    DispatchEvent("interstitial", "loaded", NO, nil);
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    DispatchEvent("interstitial", "show", YES,
                  error ? [error localizedDescription] : @"load failed");
}
- (void)didDisplayAdWithAdInfo:(id)adInfo {
    DispatchEvent("interstitial", "show", NO, nil);
}
- (void)didFailToDisplayAdWithAdInfo:(id)adInfo error:(NSError *)error {
    DispatchEvent("interstitial", "show", YES,
                  error ? [error localizedDescription] : @"show failed");
}
- (void)didClickAdWithAdInfo:(id)adInfo {}
- (void)didCloseAdWithAdInfo:(id)adInfo {
    DispatchEvent("interstitial", "closed", NO, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sInterstitialAd) [sInterstitialAd loadAd];
    });
}
@end

// ---------------------------------------------------------------------------
// Rewarded delegate — informal protocol
// ---------------------------------------------------------------------------
@interface ISPluginRewardedDelegate : NSObject
@end
@implementation ISPluginRewardedDelegate

- (void)didLoadAdWithAdInfo:(id)adInfo {
    DispatchEvent("rewardedVideo", "available", NO, nil);
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    DispatchEvent("rewardedVideo", "show", YES,
                  error ? [error localizedDescription] : @"load failed");
}
- (void)didDisplayAdWithAdInfo:(id)adInfo {
    DispatchEvent("rewardedVideo", "show", NO, nil);
}
- (void)didFailToDisplayAdWithAdInfo:(id)adInfo error:(NSError *)error {
    DispatchEvent("rewardedVideo", "show", YES,
                  error ? [error localizedDescription] : @"show failed");
}
- (void)didClickAdWithAdInfo:(id)adInfo {}
- (void)didCloseAdWithAdInfo:(id)adInfo {
    DispatchEvent("rewardedVideo", "closed", NO, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sRewardedAd) [sRewardedAd loadAd];
    });
}
- (void)didRewardAdWithAdInfo:(id)adInfo reward:(id)reward {
    NSString *name = nil;
    @try {
        name = [reward valueForKey:@"name"];
        if (!name.length) name = [adInfo valueForKey:@"placementName"];
    } @catch (...) {}
    DispatchEvent("rewardedVideo", "reward", NO, name);
}
- (void)didChangeAdInfo:(id)adInfo {}
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

    NSString *appKey    = GSTR("key");
    NSString *userId    = GSTR("userId");
    NSString *intId     = GSTR("interstitialAdUnitId");
    NSString *rvId      = GSTR("rewardedVideoAdUnitId");
    BOOL consent        = GBOOL("hasUserConsent");
    BOOL coppa          = GBOOL("coppaUnderAge");
    BOOL ccpa           = GBOOL("ccpaDoNotSell");
    BOOL debug          = GBOOL("showDebugLog");

#undef GSTR
#undef GBOOL

    if (!appKey.length) { luaL_error(L, "ironSource.init: options.key required"); return 0; }

    if (!gSDKLoaded) {
        NSLog(@"[IronSourcePlugin] init() skipped — SDK not loaded (dlopen failed)");
        DispatchEvent("init", "failed", YES, @"IronSource.framework not loaded");
        return 0;
    }

    // Capture copies for async block
    appKey = [appKey copy]; userId = [userId copy];
    intId  = [intId copy];  rvId   = [rvId copy];

    dispatch_async(dispatch_get_main_queue(), ^{

        // ---- Privacy / consent: use kLevelPlay (runtime pointer, valid after dlopen) ----
        ((VoidBoolIMP)objc_msgSend)((id)kLevelPlay,
                                    @selector(setConsent:), consent);
        ((VoidIdIdIMP)objc_msgSend)((id)kLevelPlay,
                                    @selector(setMetaDataWithKey:value:),
                                    @"is_coppa", coppa ? @"true" : @"false");
        ((VoidIdIdIMP)objc_msgSend)((id)kLevelPlay,
                                    @selector(setMetaDataWithKey:value:),
                                    @"do_not_sell", ccpa ? @"true" : @"false");
        if (debug) {
            ((VoidBoolIMP)objc_msgSend)((id)kLevelPlay,
                                        @selector(setAdaptersDebug:), YES);
        }

        // ---- Build LPMInitRequest ----
        // alloc
        id builder = ((AllocIMP)objc_msgSend)((id)kLPMInitRequestBuilder, @selector(alloc));
        // initWithAppKey:
        builder = ((IdIdIMP)objc_msgSend)(builder, @selector(initWithAppKey:), appKey);
        // withUserId: (optional, returns self for chaining)
        if (userId.length) {
            builder = ((IdIdIMP)objc_msgSend)(builder, @selector(withUserId:), userId);
        }
        // build → LPMInitRequest
        id initRequest = ((AllocIMP)objc_msgSend)(builder, @selector(build));

        if (!initRequest) {
            NSLog(@"[IronSourcePlugin] ERROR: LPMInitRequest build returned nil");
            DispatchEvent("init", "failed", YES, @"LPMInitRequest.build() returned nil");
            return;
        }

        // ---- Init LevelPlay SDK ----
        // initWithRequest:completion: (request:id, completion:block)
        void (^completion)(id, NSError *) = ^(id config, NSError *error) {
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
            if (intId.length && kLPMInterstitialAd) {
                if (!sInterstitialDelegate)
                    sInterstitialDelegate = [[ISPluginInterstitialDelegate alloc] init];
                id ad = ((AllocIMP)objc_msgSend)((id)kLPMInterstitialAd, @selector(alloc));
                ad = ((IdIdIMP)objc_msgSend)(ad, @selector(initWithAdUnitId:), intId);
                sInterstitialAd = ad;
                ((VoidIdIMP)objc_msgSend)(sInterstitialAd, @selector(setDelegate:), sInterstitialDelegate);
                [sInterstitialAd loadAd];
            }

            // Create + load rewarded
            if (rvId.length && kLPMRewardedAd) {
                if (!sRewardedDelegate)
                    sRewardedDelegate = [[ISPluginRewardedDelegate alloc] init];
                id ad = ((AllocIMP)objc_msgSend)((id)kLPMRewardedAd, @selector(alloc));
                ad = ((IdIdIMP)objc_msgSend)(ad, @selector(initWithAdUnitId:), rvId);
                sRewardedAd = ad;
                ((VoidIdIMP)objc_msgSend)(sRewardedAd, @selector(setDelegate:), sRewardedDelegate);
                [sRewardedAd loadAd];
            }
        };

        // objc_msgSend for initWithRequest:completion: (request + block args)
        ((VoidIdIdIMP)objc_msgSend)((id)kLevelPlay,
                                    @selector(initWithRequest:completion:),
                                    initRequest, completion);
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
        typedef void (*ShowIMP)(id, SEL, UIViewController *, NSString *);

        if ([adType isEqualToString:@"interstitial"]) {
            BOOL ready = NO;
            if (sInterstitialAd)
                ready = [sInterstitialAd respondsToSelector:@selector(isAdReady)] &&
                        ((BOOL (*)(id,SEL))objc_msgSend)(sInterstitialAd, @selector(isAdReady));
            if (ready) {
                ((ShowIMP)objc_msgSend)(sInterstitialAd,
                                        @selector(showAdWithViewController:placementName:),
                                        vc, fp.length ? fp : nil);
            } else {
                DispatchEvent("interstitial", "show", YES, @"not ready");
            }

        } else if ([adType isEqualToString:@"rewardedVideo"]) {
            BOOL ready = NO;
            if (sRewardedAd)
                ready = [sRewardedAd respondsToSelector:@selector(isAdReady)] &&
                        ((BOOL (*)(id,SEL))objc_msgSend)(sRewardedAd, @selector(isAdReady));
            if (ready) {
                ((ShowIMP)objc_msgSend)(sRewardedAd,
                                        @selector(showAdWithViewController:placementName:),
                                        vc, fp.length ? fp : nil);
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
        available = ((BOOL (*)(id,SEL))objc_msgSend)(sInterstitialAd, @selector(isAdReady));
    if ([adType isEqualToString:@"rewardedVideo"] && sRewardedAd)
        available = ((BOOL (*)(id,SEL))objc_msgSend)(sRewardedAd, @selector(isAdReady));
    lua_pushboolean(L, available ? 1 : 0);
    return 1;
}

// ---------------------------------------------------------------------------
// Plugin entry point — called by CoronaBuilder when require("plugin.ironSource")
// ---------------------------------------------------------------------------
CORONA_EXPORT
int luaopen_plugin_ironSource(lua_State *L) {

    // ---- Step 1: dlopen IronSource.framework ----
    // The framework is injected into <AppBundle>/Frameworks/ by build-ios.sh.
    // It is NOT in LC_LOAD_DYLIB, so dyld does NOT load it at app launch.
    // We must dlopen it before any ObjC class access. Use RTLD_NOW so all
    // symbols are resolved immediately (not lazily) in case of symbol deps.

    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *fwPath = [bundlePath stringByAppendingPathComponent:
                        @"Frameworks/IronSource.framework/IronSource"];
    void *handle = dlopen([fwPath UTF8String], RTLD_NOW | RTLD_GLOBAL);

    if (!handle) {
        NSLog(@"[IronSourcePlugin] WARNING: dlopen(%@) failed: %s", fwPath, dlerror());
        // Secondary search path (privateFrameworksPath)
        NSString *alt = [[[NSBundle mainBundle] privateFrameworksPath]
                         stringByAppendingPathComponent:@"IronSource.framework/IronSource"];
        handle = dlopen([alt UTF8String], RTLD_NOW | RTLD_GLOBAL);
        if (!handle) {
            NSLog(@"[IronSourcePlugin] ERROR: IronSource.framework not found at primary or secondary path. Ads disabled.");
        } else {
            NSLog(@"[IronSourcePlugin] IronSource.framework loaded (secondary path)");
        }
    } else {
        NSLog(@"[IronSourcePlugin] IronSource.framework loaded: %@", fwPath);
    }

    // ---- Step 2: Obtain class pointers via ObjC runtime ----
    // These look up classes by STRING NAME in the ObjC runtime — they find the
    // classes registered by dlopen above. This completely bypasses the NULL
    // classref slots in __DATA.__objc_classrefs that dyld bound at launch.
    if (handle) {
        kLevelPlay             = objc_getClass("LevelPlay");
        kLPMInterstitialAd     = objc_getClass("LPMInterstitialAd");
        kLPMRewardedAd         = objc_getClass("LPMRewardedAd");
        kLPMInitRequestBuilder = objc_getClass("LPMInitRequestBuilder");

        NSLog(@"[IronSourcePlugin] Runtime classes — LevelPlay:%@ IntAd:%@ RvAd:%@ Builder:%@",
              kLevelPlay, kLPMInterstitialAd, kLPMRewardedAd, kLPMInitRequestBuilder);

        gSDKLoaded = (kLevelPlay != Nil);
        if (!gSDKLoaded) {
            NSLog(@"[IronSourcePlugin] WARNING: dlopen succeeded but LevelPlay class not found");
        }
    }

    sL           = L;
    sListenerRef = NULL;

    lua_newtable(L);
    lua_pushcfunction(L, lua_init);        lua_setfield(L, -2, "init");
    lua_pushcfunction(L, lua_load);        lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_show);        lua_setfield(L, -2, "show");
    lua_pushcfunction(L, lua_isAvailable); lua_setfield(L, -2, "isAvailable");

    return 1;
}
