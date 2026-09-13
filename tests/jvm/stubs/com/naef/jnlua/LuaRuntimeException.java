package com.naef.jnlua;

/** Minimal stand-in for com.naef.jnlua.LuaRuntimeException (JVM tests only). */
public class LuaRuntimeException extends RuntimeException {
    public LuaRuntimeException(String message) {
        super(message);
    }
}
