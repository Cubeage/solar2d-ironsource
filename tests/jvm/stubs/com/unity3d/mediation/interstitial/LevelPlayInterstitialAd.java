package com.unity3d.mediation.interstitial;

import android.app.Activity;

/** Minimal stand-in for com.unity3d.mediation.interstitial.LevelPlayInterstitialAd. */
public final class LevelPlayInterstitialAd {
    /** Test hook: the listener the plugin registered. */
    public static LevelPlayInterstitialAdListener lastListener;
    public static int loadCount;
    public static boolean adReady;
    public static int showCount;

    private final String adUnitId;

    public LevelPlayInterstitialAd(String adUnitId) {
        this.adUnitId = adUnitId;
    }

    public String getAdUnitId() {
        return adUnitId;
    }

    public void setListener(LevelPlayInterstitialAdListener listener) {
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
}
