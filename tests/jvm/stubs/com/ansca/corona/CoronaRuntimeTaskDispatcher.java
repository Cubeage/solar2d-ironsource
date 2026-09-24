package com.ansca.corona;

import android.app.Activity;
import com.naef.jnlua.LuaState;

/**
 * Minimal stand-in for com.ansca.corona.CoronaRuntimeTaskDispatcher (JVM tests only).
 *
 * <p>The real dispatcher queues the task onto the Corona runtime (Lua) thread. The stub
 * runs it synchronously, but outside any {@link Activity#runOnUiThread} scope, which is
 * what the runtime thread means for the UI-thread access checks in {@link CoronaLua}.
 */
public class CoronaRuntimeTaskDispatcher {
    public static int sent;
    /** Fault injection: when set, the next send() throws it. */
    public static RuntimeException failNextSend;

    private final CoronaRuntime runtime;

    public CoronaRuntimeTaskDispatcher(LuaState L) {
        this.runtime = new CoronaRuntime(L);
    }

    public boolean send(CoronaRuntimeTask task) {
        if (failNextSend != null) {
            RuntimeException failure = failNextSend;
            failNextSend = null;
            throw failure;
        }
        sent++;
        int saved = Activity.uiThreadDepth;
        Activity.uiThreadDepth = 0;
        try {
            task.executeUsing(runtime);
        } finally {
            Activity.uiThreadDepth = saved;
        }
        return true;
    }
}
