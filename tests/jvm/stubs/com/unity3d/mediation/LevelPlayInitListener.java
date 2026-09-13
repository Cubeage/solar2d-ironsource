package com.unity3d.mediation;

/** Minimal stand-in for com.unity3d.mediation.LevelPlayInitListener. */
public interface LevelPlayInitListener {
    void onInitSuccess(LevelPlayConfiguration configuration);

    void onInitFailed(LevelPlayInitError error);
}
