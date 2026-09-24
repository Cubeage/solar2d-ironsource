package org.json;

/** Minimal stand-in for Android's org.json.JSONObject: holds its serialized form. */
public class JSONObject {
    private final String json;

    public JSONObject(String json) {
        this.json = json;
    }

    @Override
    public String toString() {
        return json;
    }
}
