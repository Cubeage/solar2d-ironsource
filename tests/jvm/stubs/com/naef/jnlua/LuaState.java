package com.naef.jnlua;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Minimal JVM-only stand-in for JNLua's {@code LuaState}.
 *
 * <p>It models only the stack contract the plugin depends on, following the JNLua 1.x
 * sources vendored by Solar2D (coronalabs/corona, external/JNLua/src/main/c/jnlua.c):
 *
 * <ul>
 *   <li>{@code pushString(null)}: the JNI bridge rejects the null through
 *       {@code getstringchars} -> {@code checknotnull} ({@code NullPointerException},
 *       message "null", jnlua.c:1852-1863) and therefore pushes nothing at all
 *       (jnlua.c:589-604), leaving the Lua stack one element shorter than the caller
 *       assumes. This stub does the same and records the attempt in
 *       {@link #nullPushes}.</li>
 *   <li>{@code setField}: the index is validated ("illegal index") and the target must be a
 *       table ("illegal type") before the value is popped (jnlua.c:1339-1363).</li>
 *   <li>{@code pop(n)} goes through {@code setTop(-n-1)} and validates the count
 *       ("illegal count").</li>
 * </ul>
 *
 * <p>Values are plain Java objects: String, Boolean, {@link JavaFunction}, a
 * {@code Map<String,Object>} for Lua tables and {@code null} for nil.
 */
public class LuaState {
    /** Number of pushString(null) attempts. Must stay 0: it is the crash trigger. */
    public static int nullPushes;

    public final List<Object> stack = new ArrayList<Object>();

    public int getTop() {
        return stack.size();
    }

    public void setTop(int index) {
        if (index < 0) {
            int target = stack.size() + index + 1;
            if (target < 0) {
                throw new IllegalArgumentException("illegal index");
            }
            setTop(target);
            return;
        }
        while (stack.size() < index) {
            stack.add(null);
        }
        while (stack.size() > index) {
            stack.remove(stack.size() - 1);
        }
    }

    public void pop(int count) {
        if (count < 0 || count > stack.size()) {
            throw new IllegalArgumentException("illegal count");
        }
        setTop(stack.size() - count);
    }

    public void newTable() {
        stack.add(new LinkedHashMap<String, Object>());
    }

    public void pushNil() {
        stack.add(null);
    }

    public void pushString(String s) {
        if (s == null) {
            nullPushes++;
            throw new NullPointerException("null");
        }
        stack.add(s);
    }

    public void pushBoolean(boolean b) {
        stack.add(Boolean.valueOf(b));
    }

    public void pushJavaFunction(JavaFunction function) {
        stack.add(function);
    }

    public void getField(int index, String key) {
        Object table = value(index);
        if (!(table instanceof Map)) {
            throw new IllegalArgumentException("illegal type");
        }
        stack.add(((Map<?, ?>) table).get(key));
    }

    public void setField(int index, String key) {
        int absolute = absolute(index);
        if (absolute < 1 || absolute > stack.size()) {
            throw new IllegalArgumentException("illegal index");
        }
        Object table = stack.get(absolute - 1);
        if (!(table instanceof Map)) {
            throw new IllegalArgumentException("illegal type");
        }
        Object newValue = stack.remove(stack.size() - 1);
        ((Map<String, Object>) table).put(key, newValue);
    }

    public boolean isString(int index) {
        return valueOrNull(index) instanceof String;
    }

    public boolean isTable(int index) {
        return valueOrNull(index) instanceof Map;
    }

    public boolean isBoolean(int index) {
        return valueOrNull(index) instanceof Boolean;
    }

    public boolean isFunction(int index) {
        return valueOrNull(index) instanceof JavaFunction;
    }

    public boolean isNoneOrNil(int index) {
        return valueOrNull(index) == null;
    }

    public boolean toBoolean(int index) {
        Object value = value(index);
        return value instanceof Boolean && ((Boolean) value).booleanValue();
    }

    public String toString(int index) {
        Object value = value(index);
        return (value == null) ? "nil" : String.valueOf(value);
    }

    // --- Test affordances (not part of the JNLua API surface used by the plugin) ---

    /** Raw stack slot, 1-based / negative from the top. */
    public Object get(int index) {
        return valueOrNull(index);
    }

    /** Pushes a new Lua table and returns it so a test can populate it. */
    public Map<String, Object> pushTable() {
        Map<String, Object> table = new LinkedHashMap<String, Object>();
        stack.add(table);
        return table;
    }

    private int absolute(int index) {
        return (index > 0) ? index : stack.size() + index + 1;
    }

    private Object value(int index) {
        int absolute = absolute(index);
        if (absolute < 1 || absolute > stack.size()) {
            throw new IllegalArgumentException("illegal index");
        }
        return stack.get(absolute - 1);
    }

    private Object valueOrNull(int index) {
        int absolute = absolute(index);
        if (absolute < 1 || absolute > stack.size()) {
            return null;
        }
        return stack.get(absolute - 1);
    }
}
