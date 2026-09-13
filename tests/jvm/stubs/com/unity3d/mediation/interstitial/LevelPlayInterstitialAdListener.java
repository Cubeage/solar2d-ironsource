package com.unity3d.mediation.interstitial;

import com.unity3d.mediation.LevelPlayAdError;
import com.unity3d.mediation.LevelPlayAdInfo;

/** Minimal stand-in for com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener. */
public interface LevelPlayInterstitialAdListener {
    void onAdLoaded(LevelPlayAdInfo adInfo);

    void onAdLoadFailed(LevelPlayAdError error);

    void onAdDisplayed(LevelPlayAdInfo adInfo);

    default void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    }

    default void onAdClicked(LevelPlayAdInfo adInfo) {
    }

    default void onAdClosed(LevelPlayAdInfo adInfo) {
    }

    default void onAdInfoChanged(LevelPlayAdInfo adInfo) {
    }
}
