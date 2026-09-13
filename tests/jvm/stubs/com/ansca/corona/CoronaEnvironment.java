package com.ansca.corona;

/** Minimal stand-in for com.ansca.corona.CoronaEnvironment (JVM tests only). */
public class CoronaEnvironment {
    private static CoronaActivity activity;

    public static CoronaActivity getCoronaActivity() {
        return activity;
    }

    public static void setCoronaActivity(CoronaActivity value) {
        activity = value;
    }

    public static void addRuntimeListener(CoronaRuntimeListener listener) {
        // No runtime to attach to in JVM tests; the test calls LuaLoader.onLoaded() directly.
    }
}
