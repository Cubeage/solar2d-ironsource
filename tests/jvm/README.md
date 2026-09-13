# JVM regression tests (plugin.ironSource event dispatch)

`run.sh` compiles the real Android plugin source
(`android/src/main/java/plugin/ironSource/LuaLoader.java`) against the minimal
stand-ins in `stubs/` and runs `plugin.ironSource.LuaLoaderDispatchTest` on a plain
JVM. It needs nothing but a JDK (CI uses JDK 17), no Android SDK, no Gradle and no
network access:

```bash
tests/jvm/run.sh
```

Exit code 0 means every check passed; the command prints `N checks, M failure(s)`.

## What it covers

* The production crash path: a failure while `dispatchEvent()` builds the event table
  (`CoronaLua.newEvent` -> `LuaState.setField`) must be logged and dropped, never
  propagate out of the IronSource callback into the app process.
* Recovery: after a failed dispatch the Lua stack top is restored, so the next event
  dispatches normally.
* `type` / `phase` are never pushed as null (a null maps to `""`).
* `isError` is always emitted as a boolean.
* A null `response` omits the `response` field (Lua sees nil), matching the behaviour
  consumers already handle; a non-null `response` is passed through unchanged.
* Every event path (loaded / displayed / clicked / closed / reward / show / load-failed
  / init failed) never calls `pushString(null)`.

## Why the stand-ins look the way they do

The `com.ansca.corona` and `com.naef.jnlua` stand-ins model the shipped runtime, not an
idealised one:

* `CoronaLua.newEvent` = `newTable()` + `pushString(name)` + `setField(-2, "name")`,
  matching the bytecode of `CoronaCards-Android-2026.3728`.
* `LuaState.pushString(null)` throws instead of pushing: the JNLua JNI bridge only
  pushes when the JNI string conversion succeeds (`external/JNLua/src/main/c/jnlua.c`),
  so a null either aborts the call or silently skips the push and desynchronizes the
  Lua stack for every following `setField(-2, ...)`.
* `LuaState.setField` validates the index ("illegal index") and the target table
  ("illegal type"), as JNLua does.

The `com.unity3d.mediation` stand-ins mirror the LevelPlay 9.3.0 signatures the plugin
uses; they capture the `init` / ad listeners so the tests can fire the same callbacks
the SDK fires (`onAdLoadFailed`, `onAdRewarded`, ...).
