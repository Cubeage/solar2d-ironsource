package com.ansca.corona;

import com.naef.jnlua.LuaState;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Minimal stand-in for {@code com.ansca.corona.CoronaLua}.
 *
 * <p>{@link #newEvent} mirrors the shipped implementation (CoronaCards-Android 2026.3728,
 * {@code CoronaLua.newEvent} bytecode: {@code newTable}, {@code pushString(eventName)},
 * {@code setField(-2, "name")}) so that failures raised while building the event table are
 * reproduced, not hidden.
 *
 * <p>{@link #dispatchEvent} mirrors the real order of operations: it pushes
 * {@code event.name}, and pops the event table and that name only when it actually
 * reached the listener. An exception raised inside the listener call therefore leaves the
 * event table on the Lua stack, exactly like the real implementation.
 */
public class CoronaLua {
    public static final int REFNIL = -1;
    public static final int NOREF = -2;

    /** Fault injection: when set, {@link #newEvent} throws it once. */
    public static RuntimeException failNextNewEvent;
    /** Fault injection: when set, {@link #dispatchEvent} throws it once before dispatching. */
    public static Exception failNextDispatchEvent;

    /** Test hook receiving the event table the plugin built. */
    public interface EventSink {
        void onEvent(Map<String, Object> event);
    }

    public static EventSink sink;
    public static int dispatchCount;
    /** Lua VM touched while on the Android UI thread (must stay 0: the VM is not thread-safe). */
    public static int uiThreadLuaAccesses;

    private static void checkThread() {
        if (android.app.Activity.uiThreadDepth > 0) uiThreadLuaAccesses++;
    }

    public static int newRef(LuaState L, int index) {
        return 1;
    }

    public static void deleteRef(LuaState L, int ref) {
        // No registry in the stub.
    }

    public static boolean isListener(LuaState L, int index, String eventName) {
        return L.isFunction(index);
    }

    public static void newEvent(LuaState L, String eventName) {
        checkThread();
        L.newTable();
        L.pushString(eventName);
        if (failNextNewEvent != null) {
            // Thrown at the setField(-2, "name") step, exactly like the production trace,
            // leaving the half-built event table on the Lua stack.
            RuntimeException failure = failNextNewEvent;
            failNextNewEvent = null;
            throw failure;
        }
        L.setField(-2, "name");
    }

    public static void dispatchEvent(LuaState L, int listenerRef, int nresults) throws Exception {
        checkThread();
        int eventIndex = L.getTop();

        if (failNextDispatchEvent != null) {
            Exception failure = failNextDispatchEvent;
            failNextDispatchEvent = null;
            throw failure;
        }

        L.getField(eventIndex, "name"); // push event.name
        if (L.isString(-1)) {
            Map<String, Object> event = new LinkedHashMap<String, Object>();
            Object table = L.get(eventIndex);
            if (table instanceof Map) {
                for (Map.Entry<?, ?> entry : ((Map<?, ?>) table).entrySet()) {
                    event.put(String.valueOf(entry.getKey()), entry.getValue());
                }
            }
            dispatchCount++;
            if (sink != null) {
                sink.onEvent(event);
            }
            L.pop(2);
        } else {
            L.pop(2);
            throw new Exception("[Lua::DispatchEvent()] ERROR: Attempt to dispatch malformed event."
                    + " The event must have a 'name' string property.");
        }
    }
}
