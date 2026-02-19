// ----------------------------------------------------------------------------
// LuaLoader.java  –  Solar2D plugin bridge for IronSource SDK 7.9.0
// Package: plugin.ironSource
// API verified by bytecode inspection of CoronaCards-Android-2026.3728 and mediationsdk-7.9.0
// ----------------------------------------------------------------------------

package plugin.ironSource;

import android.util.Log;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;

import com.ironsource.mediationsdk.IronSource;
import com.ironsource.mediationsdk.logger.IronSourceError;
import com.ironsource.mediationsdk.model.Placement;
import com.ironsource.mediationsdk.sdk.InitializationListener;
import com.ironsource.mediationsdk.sdk.InterstitialListener;
import com.ironsource.mediationsdk.sdk.RewardedVideoListener;

import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.NamedJavaFunction;

/**
 * Solar2D plugin entry point for IronSource SDK 7.9.0
 *
 * Lua API:
 *   ironSource.init(listener, options)
 *   ironSource.load(adUnitType)
 *   ironSource.show(adUnitType [, options])
 *   ironSource.isAvailable(adUnitType)  → boolean
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {

    private static final String TAG = "IronSourcePlugin";

    /** Lua registry reference to the Lua listener function. */
    private int listenerRef = CoronaLua.REFNIL;

    /** Store the CoronaRuntime so we can access LuaState from callbacks. */
    private CoronaRuntime fRuntime;

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
        final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
        if (activity != null) {
            IronSource.onPause(activity);
        }
    }

    @Override
    public void onResumed(CoronaRuntime runtime) {
        final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
        if (activity != null) {
            IronSource.onResume(activity);
        }
    }

    @Override
    public void onExiting(CoronaRuntime runtime) {
        if (runtime != null && listenerRef != CoronaLua.REFNIL) {
            LuaState L = runtime.getLuaState();
            if (L != null) {
                CoronaLua.deleteRef(L, listenerRef);
            }
        }
        listenerRef = CoronaLua.REFNIL;
        fRuntime = null;
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

            // Read options
            L.getField(2, "key");
            final String appKey = L.isString(-1) ? L.toString(-1) : null;
            L.pop(1);

            if (appKey == null || appKey.isEmpty()) {
                Log.e(TAG, "ironSource.init() – options.key (appKey) is required");
                return 0;
            }

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

            final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
            if (activity == null) return 0;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        if (debug) {
                            IronSource.setAdaptersDebug(true);
                        }

                        IronSource.setConsent(hasConsent);
                        IronSource.setMetaData("is_coppa", coppa ? "true" : "false");
                        IronSource.setMetaData("do_not_sell", ccpa ? "true" : "false");

                        if (userId != null && !userId.isEmpty()) {
                            IronSource.setUserId(userId);
                        }

                        // Register interstitial listener
                        IronSource.setInterstitialListener(new InterstitialListener() {
                            @Override
                            public void onInterstitialAdReady() {
                                dispatchEvent("interstitial", "loaded", false, null);
                            }

                            @Override
                            public void onInterstitialAdLoadFailed(IronSourceError error) {
                                dispatchEvent("interstitial", "show", true,
                                        error != null ? error.getErrorMessage() : "load failed");
                            }

                            @Override
                            public void onInterstitialAdOpened() {}

                            @Override
                            public void onInterstitialAdClosed() {
                                dispatchEvent("interstitial", "closed", false, null);
                            }

                            @Override
                            public void onInterstitialAdShowSucceeded() {
                                dispatchEvent("interstitial", "show", false, null);
                            }

                            @Override
                            public void onInterstitialAdShowFailed(IronSourceError error) {
                                dispatchEvent("interstitial", "show", true,
                                        error != null ? error.getErrorMessage() : "show failed");
                            }

                            @Override
                            public void onInterstitialAdClicked() {}
                        });

                        // Register rewarded video listener
                        IronSource.setRewardedVideoListener(new RewardedVideoListener() {
                            @Override
                            public void onRewardedVideoAvailabilityChanged(boolean available) {
                                if (available) {
                                    dispatchEvent("rewardedVideo", "available", false, null);
                                }
                            }

                            @Override
                            public void onRewardedVideoAdRewarded(Placement placement) {
                                String name = placement != null ? placement.getPlacementName() : null;
                                dispatchEvent("rewardedVideo", "reward", false, name);
                            }

                            @Override
                            public void onRewardedVideoAdShowFailed(IronSourceError error) {
                                dispatchEvent("rewardedVideo", "show", true,
                                        error != null ? error.getErrorMessage() : "show failed");
                            }

                            @Override
                            public void onRewardedVideoAdOpened() {}

                            @Override
                            public void onRewardedVideoAdClosed() {
                                dispatchEvent("rewardedVideo", "closed", false, null);
                            }

                            @Override
                            public void onRewardedVideoAdStarted() {}

                            @Override
                            public void onRewardedVideoAdEnded() {}

                            @Override
                            public void onRewardedVideoAdClicked(Placement placement) {}
                        });

                        // Initialise IronSource SDK
                        IronSource.init(activity, appKey,
                                new InitializationListener() {
                                    @Override
                                    public void onInitializationComplete() {
                                        Log.d(TAG, "IronSource SDK initialized successfully");
                                    }
                                },
                                IronSource.AD_UNIT.INTERSTITIAL,
                                IronSource.AD_UNIT.REWARDED_VIDEO);

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
                        IronSource.loadInterstitial();
                    } else if ("rewardedVideo".equals(adUnitType)) {
                        Log.d(TAG, "rewardedVideo is auto-loaded by IronSource SDK after init");
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
                        if (IronSource.isInterstitialReady()) {
                            if (finalPlacement != null && !finalPlacement.isEmpty()) {
                                IronSource.showInterstitial(finalPlacement);
                            } else {
                                IronSource.showInterstitial();
                            }
                        } else {
                            dispatchEvent("interstitial", "show", true, "not ready");
                        }
                    } else if ("rewardedVideo".equals(adUnitType)) {
                        if (IronSource.isRewardedVideoAvailable()) {
                            if (finalPlacement != null && !finalPlacement.isEmpty()) {
                                IronSource.showRewardedVideo(finalPlacement);
                            } else {
                                IronSource.showRewardedVideo();
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
            String adUnitType = L.toString(1);
            boolean available = false;
            if ("interstitial".equals(adUnitType)) {
                available = IronSource.isInterstitialReady();
            } else if ("rewardedVideo".equals(adUnitType)) {
                available = IronSource.isRewardedVideoAvailable();
            }
            L.pushBoolean(available);
            return 1;
        }
    }
}
