package com.unity3d.mediation.rewarded;

import android.app.Activity;

/** Minimal stand-in for com.unity3d.mediation.rewarded.LevelPlayRewardedAd. */
public final class LevelPlayRewardedAd {
    /** Test hook: the listener the plugin registered. */
    public static LevelPlayRewardedAdListener lastListener;
    public static int loadCount;
    public static boolean adReady;
    public static int showCount;

    private final String adUnitId;

    public LevelPlayRewardedAd(String adUnitId) {
        this.adUnitId = adUnitId;
    }

    public String getAdUnitId() {
        return adUnitId;
    }

    public void setListener(LevelPlayRewardedAdListener listener) {
        lastListener = listener;
    }

    public void loadAd() {
        loadCount++;
    }

    public boolean isAdReady() {
        return adReady;
    }

    public void showAd(Activity activity) {
        showCount++;
    }

    public void showAd(Activity activity, String placementName) {
        showCount++;
    }

    public LevelPlayReward getReward() {
        return null;
    }
}
