package android.app;

import android.content.Context;

/** Minimal stand-in for android.app.Activity (JVM tests only). */
public class Activity extends Context {
    /** Runs the action on the UI thread. Mirrors Activity.runOnUiThread: immediate when called on the UI thread. */
    public void runOnUiThread(Runnable action) {
        uiThreadDepth++;
        try {
            action.run();
        } finally {
            uiThreadDepth--;
        }
    }

    /** > 0 while code runs inside runOnUiThread, i.e. on the Android UI thread. */
    public static int uiThreadDepth;
}
