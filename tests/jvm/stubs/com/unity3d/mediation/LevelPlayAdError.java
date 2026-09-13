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

    /** May return null, like the SDK: "No fill" / error-text-less failures report no message. */
    public String getErrorMessage() {
        return message;
    }
}
