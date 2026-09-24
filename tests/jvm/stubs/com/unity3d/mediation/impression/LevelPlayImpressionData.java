package com.unity3d.mediation.impression;

import org.json.JSONObject;

/** Minimal stand-in for mediation-sdk 9.3.0 {@code LevelPlayImpressionData}. */
public class LevelPlayImpressionData {
    private final JSONObject allData;

    public LevelPlayImpressionData(JSONObject allData) {
        this.allData = allData;
    }

    public JSONObject getAllData() {
        return allData;
    }
}
