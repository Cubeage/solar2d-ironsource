package com.ansca.corona;

import com.naef.jnlua.LuaState;

/** Minimal stand-in for com.ansca.corona.CoronaRuntime (JVM tests only). */
public class CoronaRuntime {
    private final LuaState luaState;

    public CoronaRuntime(LuaState luaState) {
        this.luaState = luaState;
    }

    public LuaState getLuaState() {
        return luaState;
    }
}
