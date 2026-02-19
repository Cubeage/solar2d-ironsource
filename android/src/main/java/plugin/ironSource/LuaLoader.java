// ----------------------------------------------------------------------------
// LuaLoader.java  –  Solar2D plugin bridge for IronSource (Unity LevelPlay) SDK
// Package: plugin.ironSource
// ----------------------------------------------------------------------------

package plugin.ironSource;

import android.app.Activity;
import android.util.Log;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ironsource.mediationsdk.IronSource;
import com.ironsource.mediationsdk.logger.IronSourceError;
import com.ironsource.mediationsdk.model.Placement;
import com.ironsource.mediationsdk.sdk.ISInterstitialListener;
import com.ironsource.mediationsdk.sdk.ISRewardedVideoListener;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.NamedJavaFunction;

/**
 * Solar2D plugin entry point for IronSource SDK 9.x
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

    // -------------------------------------------------------------------------
    // CoronaRuntimeListener
    // -------------------------------------------------------------------------

    @Override
    public void onLoaded(CoronaRuntime runtime) {}

    @Override
    public void onStarted(CoronaRuntime runtime) {}

    @Override
    public void onSuspended(CoronaRuntime runtime) {
        IronSource.onPause(CoronaEnvironment.getCoronaActivity());
    }

    @Override
    public void onResumed(CoronaRuntime runtime) {
        IronSource.onResume(CoronaEnvironment.getCoronaActivity());
    }

    @Override
    public void onExiting(CoronaRuntime runtime) {
        final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
        if (activity != null) {
            CoronaLua.deleteRef(activity.getLuaState(), listenerRef);
        }
        listenerRef = CoronaLua.REFNIL;
    }

    // -------------------------------------------------------------------------
    // JavaFunction  –  called when Lua does require("plugin.ironSource")
    // -------------------------------------------------------------------------

    @Override
    public int invoke(LuaState L) {
        // Register this as a runtime listener so we forward lifecycle events.
        CoronaEnvironment.addRuntimeListener(this);

        // Push a table of Lua-callable functions.
        NamedJavaFunction[] funcs = {
            new InitWrapper(),
            new LoadWrapper(),
            new ShowWrapper(),
            new IsAvailableWrapper(),
        };
        CoronaLua.newLibrary(L, funcs);
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
                LuaState L = CoronaEnvironment.getCoronaRuntime().getLuaState();
                if (L == null) return;

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
            // arg 1: listener function
            if (!CoronaLua.isListener(L, 1, "ironSource")) {
                Log.e(TAG, "ironSource.init() – first argument must be a listener function");
                return 0;
            }
            listenerRef = CoronaLua.newRef(L, 1);

            // arg 2: options table
            if (L.getTop() < 2 || !L.isTable(2)) {
                Log.e(TAG, "ironSource.init() – second argument must be an options table");
                return 0;
            }

            // Read options
            String appKey = null;
            L.getField(2, "key");
            if (!L.isNil(-1)) appKey = L.toString(-1);
            L.pop(1);

            String userId = null;
            L.getField(2, "userId");
            if (!L.isNil(-1)) userId = L.toString(-1);
            L.pop(1);

            boolean hasUserConsent = false;
            L.getField(2, "hasUserConsent");
            if (!L.isNil(-1)) hasUserConsent = L.toBoolean(-1);
            L.pop(1);

            boolean coppaUnderAge = false;
            L.getField(2, "coppaUnderAge");
            if (!L.isNil(-1)) coppaUnderAge = L.toBoolean(-1);
            L.pop(1);

            boolean ccpaDoNotSell = false;
            L.getField(2, "ccpaDoNotSell");
            if (!L.isNil(-1)) ccpaDoNotSell = L.toBoolean(-1);
            L.pop(1);

            boolean showDebugLog = false;
            L.getField(2, "showDebugLog");
            if (!L.isNil(-1)) showDebugLog = L.toBoolean(-1);
            L.pop(1);

            if (appKey == null || appKey.isEmpty()) {
                Log.e(TAG, "ironSource.init() – options.key (appKey) is required");
                return 0;
            }

            final String finalAppKey = appKey;
            final String finalUserId = userId;
            final boolean finalConsent = hasUserConsent;
            final boolean finalCoppa   = coppaUnderAge;
            final boolean finalCcpa    = ccpaDoNotSell;
            final boolean finalDebug   = showDebugLog;

            final CoronaActivity activity = CoronaEnvironment.getCoronaActivity();
            if (activity == null) return 0;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        if (finalDebug) {
                            IronSource.setAdaptersDebug(true);
                        }

                        // Privacy / consent
                        IronSource.setConsent(finalConsent);
                        IronSource.setMetaData("is_coppa", finalCoppa ? "true" : "false");
                        IronSource.setMetaData("do_not_sell", finalCcpa ? "true" : "false");

                        if (finalUserId != null && !finalUserId.isEmpty()) {
                            IronSource.setUserId(finalUserId);
                        }

                        // Register interstitial listener
                        IronSource.setInterstitialListener(new ISInterstitialListener() {
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
                        IronSource.setRewardedVideoListener(new ISRewardedVideoListener() {
                            @Override
                            public void onRewardedVideoAvailabilityChanged(boolean available) {
                                if (available) {
                                    dispatchEvent("rewardedVideo", "available", false, null);
                                }
                            }
                            @Override
                            public void onRewardedVideoAdRewarded(Placement placement) {
                                dispatchEvent("rewardedVideo", "reward", false,
                                        placement != null ? placement.getPlacementName() : null);
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
                        IronSource.init(activity, finalAppKey,
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
                Log.e(TAG, "ironSource.load() – first argument must be adUnitType string");
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
                        // IronSource autoloads rewarded video; explicit load not needed
                        Log.d(TAG, "rewardedVideo is auto-loaded by IronSource SDK");
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
                Log.e(TAG, "ironSource.show() – first argument must be adUnitType string");
                return 0;
            }
            final String adUnitType = L.toString(1);

            String placement = null;
            if (L.getTop() >= 2 && L.isTable(2)) {
                L.getField(2, "placementName");
                if (!L.isNil(-1)) placement = L.toString(-1);
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
