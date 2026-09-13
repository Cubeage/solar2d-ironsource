package com.unity3d.mediation;

/** Minimal stand-in for com.unity3d.mediation.LevelPlayInitError. */
public final class LevelPlayInitError {
    private final int code;
    private final String message;

    public LevelPlayInitError(int code, String message) {
        this.code = code;
        this.message = message;
    }

    public int getErrorCode() {
        return code;
    }

    public String getErrorMessage() {
        return message;
    }
}
