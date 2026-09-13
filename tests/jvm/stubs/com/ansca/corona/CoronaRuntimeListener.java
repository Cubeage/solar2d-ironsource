package com.ansca.corona;

/** Minimal stand-in for com.ansca.corona.CoronaRuntimeListener (JVM tests only). */
public interface CoronaRuntimeListener {
    void onLoaded(CoronaRuntime runtime);

    void onStarted(CoronaRuntime runtime);

    void onSuspended(CoronaRuntime runtime);

    void onResumed(CoronaRuntime runtime);

    void onExiting(CoronaRuntime runtime);
}
