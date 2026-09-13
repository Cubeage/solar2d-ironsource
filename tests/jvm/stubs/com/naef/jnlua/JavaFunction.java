package com.naef.jnlua;

/** Minimal stand-in for com.naef.jnlua.JavaFunction (JVM tests only). */
public interface JavaFunction {
    int invoke(LuaState luaState);
}
