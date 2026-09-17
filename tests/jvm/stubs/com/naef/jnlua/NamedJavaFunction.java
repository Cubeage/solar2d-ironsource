package com.naef.jnlua;

/** Minimal stand-in for com.naef.jnlua.NamedJavaFunction (JVM tests only). */
public interface NamedJavaFunction extends JavaFunction {
    String getName();
}
