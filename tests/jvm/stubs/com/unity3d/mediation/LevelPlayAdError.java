package com.unity3d.mediation;

/** Minimal stand-in for com.unity3d.mediation.LevelPlayAdError. */
public final class LevelPlayAdError {
    private final String message;
    private final int code;

    public LevelPlayAdError(String message) {
        this(message, 0);
    }

    public LevelPlayAdError(String message, int code) {
        this.message = message;
        this.code = code;
    }

    public int getErrorCode() {
        return code;
    }

    /**
     * The real SDK (9.3.0, bytecode-verified) coalesces an absent message to {@code ""};
     * this stub additionally accepts null so the tests can pin the plugin's own defensive
     * null policy on the dispatch path.
     */
    public String getErrorMessage() {
        return message;
    }
}
