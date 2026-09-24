package com.ansca.corona;

/** Minimal stand-in for com.ansca.corona.CoronaRuntimeTask (JVM tests only). */
public interface CoronaRuntimeTask {
    void executeUsing(CoronaRuntime runtime);
}
