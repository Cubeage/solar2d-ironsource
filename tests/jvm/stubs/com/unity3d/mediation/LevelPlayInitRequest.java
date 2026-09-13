package com.unity3d.mediation;

/** Minimal stand-in for com.unity3d.mediation.LevelPlayInitRequest. */
public final class LevelPlayInitRequest {
    private final String appKey;
    private final String userId;

    private LevelPlayInitRequest(String appKey, String userId) {
        this.appKey = appKey;
        this.userId = userId;
    }

    public String getAppKey() {
        return appKey;
    }

    public String getUserId() {
        return userId;
    }

    /** Minimal stand-in for LevelPlayInitRequest.Builder. */
    public static final class Builder {
        private final String appKey;
        private String userId;

        public Builder(String appKey) {
            this.appKey = appKey;
        }

        public Builder withUserId(String userId) {
            this.userId = userId;
            return this;
        }

        public LevelPlayInitRequest build() {
            return new LevelPlayInitRequest(appKey, userId);
        }
    }
}
