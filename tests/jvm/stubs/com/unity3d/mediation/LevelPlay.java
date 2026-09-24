package com.unity3d.mediation;

import android.content.Context;

/**
 * Minimal stand-in for the LevelPlay 9.3.0 API surface used by LuaLoader.
 * Signatures mirror com.unity3d.ads-mediation:mediation-sdk:9.3.0.
 */
public final class LevelPlay {
    /** Test hook: the init listener the plugin registered. */
    public static LevelPlayInitListener lastInitListener;
    public static int initCount;

    private LevelPlay() {
    }

    public static void init(Context context, LevelPlayInitRequest request, LevelPlayInitListener listener) {
        initCount++;
        lastInitListener = listener;
    }

    public static void setConsent(boolean consent) {
    }

    public static void setMetaData(String key, String value) {
    }

    public static void setAdaptersDebug(boolean enabled) {
    }

    /** Test hook: impression listeners the plugin registered. */
    public static final java.util.List<com.unity3d.mediation.impression.LevelPlayImpressionDataListener> impressionListeners =
            new java.util.ArrayList<>();

    public static void addImpressionDataListener(com.unity3d.mediation.impression.LevelPlayImpressionDataListener listener) {
        impressionListeners.add(listener);
    }

    public static boolean setDynamicUserId(String userId) {
        return true;
    }
}
