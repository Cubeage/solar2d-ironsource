// ----------------------------------------------------------------------------
// LuaLoader.java  –  Solar2D plugin bridge for IronSource/LevelPlay SDK 9.x
// Package: plugin.ironSource
// API verified by bytecode inspection of mediation-sdk-9.2.0.aar
// ----------------------------------------------------------------------------

package plugin.ironSource;

import android.util.Log;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;

import com.unity3d.mediation.LevelPlay;
import com.unity3d.mediation.LevelPlayAdError;
import com.unity3d.mediation.LevelPlayAdInfo;
import com.unity3d.mediation.LevelPlayConfiguration;
import com.unity3d.mediation.LevelPlayInitError;
import com.unity3d.mediation.LevelPlayInitListener;
import com.unity3d.mediation.LevelPlayInitRequest;
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd;
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener;
import com.unity3d.mediation.rewarded.LevelPlayReward;
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd;
import com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener;

import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.NamedJavaFunction;

/**
 * Solar2D plugin entry point for IronSource/LevelPlay SDK 9.x
 *
 * Lua API:
 *   ironSource.init(listener, options)
 *   ironSource.load(adUnitType)
 *   ironSource.show(adUnitType [, options])
 *   ironSource.isAvailable(adUnitType)  → boolean
 *
 * options table for init():
 *   key                  = "appKey"           (required)
 *   interstitialAdUnitId = "..."              (required for interstitial)
 *   rewardedVideoAdUnitId = "..."             (required for rewarded)
 *   userId               = "..."             (optional)
 *   hasUserConsent       = true/false        (GDPR)
 *   coppaUnderAge        = true/false        (COPPA)
 *   ccpaDoNotSell        = true/false        (CCPA)
 *   showDebugLog         = true/false
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {

    private static final String TAG = "IronSourcePlugin";

    /** Lua registry reference to the Lua listener function. */
    private int listenerRef = CoronaLua.REFNIL;

    /** Store the CoronaRuntime so we can access LuaState from callbacks. */
    private CoronaRuntime fRuntime;

    /** LevelPlay ad unit objects – created after SDK init succeeds. */
    private LevelPlayInterstitialAd interstitialAd;
    private LevelPlayRewardedAd rewardedAd;

    // -------------------------------------------------------------------------
    // CoronaRuntimeListener
    // -------------------------------------------------------------------------

    @Override
    public void onLoaded(CoronaRuntime runtime) {
        fRuntime = runtime;
    }

    @Override
    public void onStarted(CoronaRuntime runtime) {}

    @Override
    public void onSuspended(CoronaRuntime runtime) {
        // SDK 9.x removed IronSource.onPause() — no-op
    }

    @Override
    public void onResumed(CoronaRuntime runtime) {
        // SDK 9.x removed IronSource.onResume() — no-op
    }

    @Override
    public void onExiting(CoronaRuntime runtime) {
        if (runtime != null && listenerRef != CoronaLua.REFNIL) {
            LuaState L = runtime.getLuaState();
            if (L != null) {
                CoronaLua.deleteRef(L, listenerRef);
            }
        }
        listenerRef  = CoronaLua.REFNIL;
        fRuntime     = null;
        interstitialAd = null;
        rewardedAd     = null;
    }

    // -------------------------------------------------------------------------
    // JavaFunction  –  called when Lua does require("plugin.ironSource")
    // -------------------------------------------------------------------------

    @Override
    public int invoke(LuaState L) {
        CoronaEnvironment.addRuntimeListener(this);

        // Create and return a Lua table of functions
        L.newTable();

        L.pushJavaFunction(new InitWrapper());
        L.setField(-2, "init");

        L.pushJavaFunction(new LoadWrapper());
        L.setField(-2, "load");

        L.pushJavaFunction(new ShowWrapper());
        L.setField(-2, "show");

        L.pushJavaFunction(new IsAvailableWrapper());
        L.setField(-2, "isAvailable");

        return 1;
    }

    // -------------------------------------------------------------------------
    // Helper: dispatch an event table to the Lua listener
    // -------------------------------------------------------------------------

    private void dispatchEvent(final String type, final String phase,
                               final boolean isError, final String response) {
        final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
        if (activity == null) return;

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (fRuntime == null) return;
                LuaState L = fRuntime.getLuaState();
                if (L == null) return;
                if (listenerRef == CoronaLua.REFNIL) return;

                CoronaLua.newEvent(L, "ironSource");

                L.pushString(type);
                L.setField(-2, "type");

                L.pushString(phase);
                L.setField(-2, "phase");

                L.pushBoolean(isError);
                L.setField(-2, "isError");

                if (response != null) {
                    L.pushString(response);
                    L.setField(-2, "response");
                }

                try {
                    CoronaLua.dispatchEvent(L, listenerRef, 0);
                } catch (Exception e) {
                    Log.e(TAG, "Error dispatching ironSource event: " + e.getMessage());
                }
            }
        });
    }

    // -------------------------------------------------------------------------
    // init(listener, options)
    // -------------------------------------------------------------------------

    private class InitWrapper implements NamedJavaFunction {
        @Override
        public String getName() { return "init"; }

        @Override
        public int invoke(LuaState L) {
            if (!CoronaLua.isListener(L, 1, "ironSource")) {
                Log.e(TAG, "ironSource.init() – arg 1 must be a listener function");
                return 0;
            }
            listenerRef = CoronaLua.newRef(L, 1);

            if (L.getTop() < 2 || !L.isTable(2)) {
                Log.e(TAG, "ironSource.init() – arg 2 must be an options table");
                return 0;
            }

            // --- Read options from Lua table ---

            L.getField(2, "key");
            final String appKey = L.isString(-1) ? L.toString(-1) : null;
            L.pop(1);

            if (appKey == null || appKey.isEmpty()) {
                Log.e(TAG, "ironSource.init() – options.key (appKey) is required");
                return 0;
            }

            L.getField(2, "interstitialAdUnitId");
            final String interstitialAdUnitId = L.isString(-1) ? L.toString(-1) : null;
            L.pop(1);

            L.getField(2, "rewardedVideoAdUnitId");
            final String rewardedVideoAdUnitId = L.isString(-1) ? L.toString(-1) : null;
            L.pop(1);

            L.getField(2, "userId");
            final String userId = L.isString(-1) ? L.toString(-1) : null;
            L.pop(1);

            L.getField(2, "hasUserConsent");
            final boolean hasConsent = L.isBoolean(-1) && L.toBoolean(-1);
            L.pop(1);

            L.getField(2, "coppaUnderAge");
            final boolean coppa = L.isBoolean(-1) && L.toBoolean(-1);
            L.pop(1);

            L.getField(2, "ccpaDoNotSell");
            final boolean ccpa = L.isBoolean(-1) && L.toBoolean(-1);
            L.pop(1);

            L.getField(2, "showDebugLog");
            final boolean debug = L.isBoolean(-1) && L.toBoolean(-1);
            L.pop(1);

            // --- Run init on UI thread ---

            final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
            if (activity == null) return 0;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        // Set privacy/consent flags BEFORE SDK init
                        LevelPlay.setConsent(hasConsent);
                        LevelPlay.setMetaData("is_coppa", coppa ? "true" : "false");
                        LevelPlay.setMetaData("do_not_sell", ccpa ? "true" : "false");

                        if (debug) {
                            LevelPlay.setAdaptersDebug(true);
                        }

                        if (userId != null && !userId.isEmpty()) {
                            LevelPlay.setDynamicUserId(userId);
                        }

                        // Build LevelPlayInitRequest
                        LevelPlayInitRequest.Builder builder =
                                new LevelPlayInitRequest.Builder(appKey);
                        if (userId != null && !userId.isEmpty()) {
                            builder = builder.withUserId(userId);
                        }
                        final LevelPlayInitRequest initRequest = builder.build();

                        // Initialise LevelPlay SDK
                        LevelPlay.init(activity, initRequest, new LevelPlayInitListener() {

                            @Override
                            public void onInitSuccess(LevelPlayConfiguration configuration) {
                                Log.d(TAG, "LevelPlay SDK initialized successfully");
                                dispatchEvent("init", "success", false, null);

                                // ---- Interstitial ----
                                if (interstitialAdUnitId != null && !interstitialAdUnitId.isEmpty()) {
                                    interstitialAd = new LevelPlayInterstitialAd(interstitialAdUnitId);
                                    interstitialAd.setListener(new LevelPlayInterstitialAdListener() {

                                        @Override
                                        public void onAdLoaded(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("interstitial", "loaded", false, null);
                                        }

                                        @Override
                                        public void onAdLoadFailed(LevelPlayAdError error) {
                                            dispatchEvent("interstitial", "show", true,
                                                    error != null ? error.getErrorMessage() : "load failed");
                                        }

                                        @Override
                                        public void onAdDisplayed(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("interstitial", "show", false, null);
                                        }

                                        @Override
                                        public void onAdDisplayFailed(LevelPlayAdError error,
                                                                      LevelPlayAdInfo adInfo) {
                                            dispatchEvent("interstitial", "show", true,
                                                    error != null ? error.getErrorMessage() : "show failed");
                                        }

                                        @Override
                                        public void onAdClicked(LevelPlayAdInfo adInfo) {}

                                        @Override
                                        public void onAdClosed(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("interstitial", "closed", false, null);
                                            // Auto-preload next interstitial
                                            if (interstitialAd != null) {
                                                interstitialAd.loadAd();
                                            }
                                        }

                                        @Override
                                        public void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
                                    });
                                    // Start pre-loading immediately after init
                                    interstitialAd.loadAd();
                                }

                                // ---- Rewarded ----
                                if (rewardedVideoAdUnitId != null && !rewardedVideoAdUnitId.isEmpty()) {
                                    rewardedAd = new LevelPlayRewardedAd(rewardedVideoAdUnitId);
                                    rewardedAd.setListener(new LevelPlayRewardedAdListener() {

                                        @Override
                                        public void onAdLoaded(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("rewardedVideo", "available", false, null);
                                        }

                                        @Override
                                        public void onAdLoadFailed(LevelPlayAdError error) {
                                            dispatchEvent("rewardedVideo", "show", true,
                                                    error != null ? error.getErrorMessage() : "load failed");
                                        }

                                        @Override
                                        public void onAdDisplayed(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("rewardedVideo", "show", false, null);
                                        }

                                        @Override
                                        public void onAdDisplayFailed(LevelPlayAdError error,
                                                                      LevelPlayAdInfo adInfo) {
                                            dispatchEvent("rewardedVideo", "show", true,
                                                    error != null ? error.getErrorMessage() : "show failed");
                                        }

                                        @Override
                                        public void onAdRewarded(LevelPlayReward reward,
                                                                 LevelPlayAdInfo adInfo) {
                                            String rewardName = (reward != null) ? reward.getName() : null;
                                            dispatchEvent("rewardedVideo", "reward", false, rewardName);
                                        }

                                        @Override
                                        public void onAdClicked(LevelPlayAdInfo adInfo) {}

                                        @Override
                                        public void onAdClosed(LevelPlayAdInfo adInfo) {
                                            dispatchEvent("rewardedVideo", "closed", false, null);
                                            // Auto-reload for next show
                                            if (rewardedAd != null) {
                                                rewardedAd.loadAd();
                                            }
                                        }

                                        @Override
                                        public void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
                                    });
                                    // SDK 9.x: rewarded is NO LONGER auto-loaded; must call manually
                                    rewardedAd.loadAd();
                                }
                            }

                            @Override
                            public void onInitFailed(LevelPlayInitError error) {
                                String msg = (error != null)
                                        ? (error.getErrorMessage() + " - " + error.getErrorCode())
                                        : "unknown";
                                Log.e(TAG, "LevelPlay SDK init failed: " + msg);
                                dispatchEvent("init", "failed", true, msg);
                            }
                        });

                    } catch (Exception e) {
                        Log.e(TAG, "ironSource.init() error: " + e.getMessage());
                    }
                }
            });

            return 0;
        }
    }

    // -------------------------------------------------------------------------
    // load(adUnitType)
    // -------------------------------------------------------------------------

    private class LoadWrapper implements NamedJavaFunction {
        @Override
        public String getName() { return "load"; }

        @Override
        public int invoke(LuaState L) {
            if (!L.isString(1)) {
                Log.e(TAG, "ironSource.load() – arg 1 must be adUnitType string");
                return 0;
            }
            final String adUnitType = L.toString(1);
            final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
            if (activity == null) return 0;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if ("interstitial".equals(adUnitType)) {
                        if (interstitialAd != null) {
                            interstitialAd.loadAd();
                        } else {
                            Log.w(TAG, "ironSource.load(interstitial) – ad object not ready yet");
                        }
                    } else if ("rewardedVideo".equals(adUnitType)) {
                        if (rewardedAd != null) {
                            rewardedAd.loadAd();
                        } else {
                            Log.w(TAG, "ironSource.load(rewardedVideo) – ad object not ready yet");
                        }
                    } else {
                        Log.e(TAG, "ironSource.load() – unknown adUnitType: " + adUnitType);
                    }
                }
            });
            return 0;
        }
    }

    // -------------------------------------------------------------------------
    // show(adUnitType [, options])
    // -------------------------------------------------------------------------

    private class ShowWrapper implements NamedJavaFunction {
        @Override
        public String getName() { return "show"; }

        @Override
        public int invoke(LuaState L) {
            if (!L.isString(1)) {
                Log.e(TAG, "ironSource.show() – arg 1 must be adUnitType string");
                return 0;
            }
            final String adUnitType = L.toString(1);

            String placement = null;
            if (L.getTop() >= 2 && L.isTable(2)) {
                L.getField(2, "placementName");
                if (L.isString(-1)) placement = L.toString(-1);
                L.pop(1);
            }
            final String finalPlacement = placement;

            final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
            if (activity == null) return 0;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if ("interstitial".equals(adUnitType)) {
                        if (interstitialAd != null && interstitialAd.isAdReady()) {
                            if (finalPlacement != null && !finalPlacement.isEmpty()) {
                                interstitialAd.showAd(activity, finalPlacement);
                            } else {
                                interstitialAd.showAd(activity);
                            }
                        } else {
                            dispatchEvent("interstitial", "show", true, "not ready");
                        }
                    } else if ("rewardedVideo".equals(adUnitType)) {
                        if (rewardedAd != null && rewardedAd.isAdReady()) {
                            if (finalPlacement != null && !finalPlacement.isEmpty()) {
                                rewardedAd.showAd(activity, finalPlacement);
                            } else {
                                rewardedAd.showAd(activity);
                            }
                        } else {
                            dispatchEvent("rewardedVideo", "show", true, "not available");
                        }
                    } else {
                        Log.e(TAG, "ironSource.show() – unknown adUnitType: " + adUnitType);
                    }
                }
            });
            return 0;
        }
    }

    // -------------------------------------------------------------------------
    // isAvailable(adUnitType)  →  boolean
    // -------------------------------------------------------------------------

    private class IsAvailableWrapper implements NamedJavaFunction {
        @Override
        public String getName() { return "isAvailable"; }

        @Override
        public int invoke(LuaState L) {
            if (!L.isString(1)) {
                L.pushBoolean(false);
                return 1;
            }
            final String adUnitType = L.toString(1);
            boolean available = false;
            if ("interstitial".equals(adUnitType)) {
                available = interstitialAd != null && interstitialAd.isAdReady();
            } else if ("rewardedVideo".equals(adUnitType)) {
                available = rewardedAd != null && rewardedAd.isAdReady();
            }
            L.pushBoolean(available);
            return 1;
        }
    }
}
