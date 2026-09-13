package com.unity3d.mediation.rewarded;

import com.unity3d.mediation.LevelPlayAdError;
import com.unity3d.mediation.LevelPlayAdInfo;

/** Minimal stand-in for com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener. */
public interface LevelPlayRewardedAdListener {
    void onAdLoaded(LevelPlayAdInfo adInfo);

    void onAdLoadFailed(LevelPlayAdError error);

    void onAdDisplayed(LevelPlayAdInfo adInfo);

    void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo);

    default void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    }

    default void onAdClicked(LevelPlayAdInfo adInfo) {
    }

    default void onAdClosed(LevelPlayAdInfo adInfo) {
    }

    default void onAdInfoChanged(LevelPlayAdInfo adInfo) {
    }
}
