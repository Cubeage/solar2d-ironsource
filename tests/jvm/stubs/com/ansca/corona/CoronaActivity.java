package com.ansca.corona;

import android.app.Activity;

/** Minimal stand-in for com.ansca.corona.CoronaActivity (JVM tests only). */
public class CoronaActivity extends Activity {
    /** When set, the next runOnUiThread() call throws it (fault injection for tests). */
    public RuntimeException failNextRunOnUiThread;

    @Override
    public void runOnUiThread(Runnable action) {
        if (failNextRunOnUiThread != null) {
            RuntimeException failure = failNextRunOnUiThread;
            failNextRunOnUiThread = null;
            throw failure;
        }
        super.runOnUiThread(action);
    }
}
