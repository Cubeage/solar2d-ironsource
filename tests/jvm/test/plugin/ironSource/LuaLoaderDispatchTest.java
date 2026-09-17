package plugin.ironSource;

import android.util.Log;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaRuntimeException;
import com.naef.jnlua.LuaState;
import com.unity3d.mediation.LevelPlay;
import com.unity3d.mediation.LevelPlayAdError;
import com.unity3d.mediation.LevelPlayAdInfo;
import com.unity3d.mediation.LevelPlayConfiguration;
import com.unity3d.mediation.LevelPlayInitError;
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd;
import com.unity3d.mediation.rewarded.LevelPlayReward;
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * JVM regression tests for the plugin.ironSource event dispatch path.
 *
 * <p>Covers the production crash where a failing dispatch killed the app process:
 * {@code LuaRuntimeException: nil} raised while {@code LuaLoader.dispatchEvent} built the
 * event table (CoronaLua.newEvent -> LuaState.setField), plus the null-handling rules for
 * every field. The plugin source under test is the real
 * {@code android/src/main/java/plugin/ironSource/LuaLoader.java}; the SDK/Corona/JNLua
 * classes are the minimal stand-ins under {@code tests/jvm/stubs}.
 *
 * <p>Run with {@code tests/jvm/run.sh} (or the "JVM Tests" workflow).
 */
public final class LuaLoaderDispatchTest {

    private static final List<Map<String, Object>> events = new ArrayList<Map<String, Object>>();

    private static int checks;
    private static int failures;

    private LuaState luaState;
    private CoronaActivity activity;
    private LuaLoader plugin;

    public static void main(String[] args) {
        LuaLoaderDispatchTest test = new LuaLoaderDispatchTest();

        test.caseTest("loadFailedWithNullResponse_emitsEventWithoutResponse", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.rewarded().onAdLoadFailed(new LevelPlayAdError(null));

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectFields(event, "name", "type", "phase", "isError");
                test.expectEquals("ironSource", event.get("name"), "event.name");
                test.expectEquals("rewardedVideo", event.get("type"), "event.type");
                test.expectEquals("show", event.get("phase"), "event.phase");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectStackClean();
            }
        });

        test.caseTest("loadFailedWithMessage_carriesResponse", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.rewarded().onAdLoadFailed(new LevelPlayAdError("No fill"));

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectFields(event, "name", "type", "phase", "isError", "response");
                test.expectEquals("No fill", event.get("response"), "event.response");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectStackClean();
            }
        });

        test.caseTest("nullTypeAndPhase_neverReachJnlua", new Case() {
            public void run() throws Exception {
                test.boot();
                events.clear();

                test.callDispatchEvent(null, null, true, "x");

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectFields(event, "name", "type", "phase", "isError", "response");
                test.expectEquals("", event.get("type"), "event.type for a null type");
                test.expectEquals("", event.get("phase"), "event.phase for a null phase");
                test.expectEquals("x", event.get("response"), "event.response");
                test.expectStackClean();
            }
        });

        test.caseTest("newEventFailure_isContainedAndRecovers", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                // The production failure: a nil Lua error raised inside CoronaLua.newEvent.
                CoronaLua.failNextNewEvent = new LuaRuntimeException("nil");

                test.rewarded().onAdLoadFailed(new LevelPlayAdError("No fill"));

                test.expectEventCount(0);
                test.expectLoggedError("Error dispatching ironSource event");
                test.expectStackClean();

                // The Lua stack must still be usable for the next dispatch.
                test.rewarded().onAdLoaded(new LevelPlayAdInfo());
                test.expectEventCount(1);
                test.expectEquals("available", events.get(0).get("phase"), "event.phase after recovery");
                test.expectStackClean();
            }
        });

        test.caseTest("dispatchEventFailure_isContainedAndRecovers", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                CoronaLua.failNextDispatchEvent = new Exception("listener raised");

                test.rewarded().onAdLoadFailed(new LevelPlayAdError("No fill"));

                test.expectEventCount(0);
                test.expectLoggedError("Error dispatching ironSource event");
                test.expectStackClean();

                test.rewarded().onAdClosed(new LevelPlayAdInfo());
                test.expectEventCount(1);
                test.expectEquals("closed", events.get(0).get("phase"), "event.phase after recovery");
                test.expectStackClean();
            }
        });

        test.caseTest("runOnUiThreadFailure_isContained", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.activity.failNextRunOnUiThread = new RuntimeException("ui thread gone");

                test.rewarded().onAdLoadFailed(new LevelPlayAdError("No fill"));

                test.expectEventCount(0);
                test.expectLoggedError("Error scheduling ironSource event dispatch");
                test.expectStackClean();
            }
        });

        test.caseTest("reentrantDispatch_keepsStackBalanced", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                // A listener that dispatches the next event from inside the current dispatch.
                CoronaLua.sink = new CoronaLua.EventSink() {
                    private boolean reentered;

                    public void onEvent(Map<String, Object> event) {
                        events.add(event);
                        if (!reentered) {
                            reentered = true;
                            LevelPlayRewardedAd.lastListener.onAdClosed(new LevelPlayAdInfo());
                        }
                    }
                };

                test.rewarded().onAdLoaded(new LevelPlayAdInfo());

                test.expectEventCount(2);
                test.expectEquals("available", events.get(0).get("phase"), "outer event phase");
                test.expectEquals("closed", events.get(1).get("phase"), "nested event phase");
                test.expectStackClean();
            }
        });

        test.caseTest("reentrantDispatchFailure_isContained", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                CoronaLua.sink = new CoronaLua.EventSink() {
                    private boolean reentered;

                    public void onEvent(Map<String, Object> event) {
                        events.add(event);
                        if (!reentered) {
                            reentered = true;
                            CoronaLua.failNextNewEvent = new LuaRuntimeException("nil");
                            LevelPlayRewardedAd.lastListener.onAdClosed(new LevelPlayAdInfo());
                        }
                    }
                };

                test.rewarded().onAdLoaded(new LevelPlayAdInfo());

                test.expectEventCount(1); // the nested event is dropped, the outer one is delivered
                test.expectEquals("available", events.get(0).get("phase"), "outer event phase");
                test.expectLoggedError("Error dispatching ironSource event");
                test.expectStackClean();
            }
        });

        test.caseTest("allEventPaths_neverPushNull", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.rewarded().onAdLoaded(new LevelPlayAdInfo());
                test.rewarded().onAdDisplayed(new LevelPlayAdInfo());
                test.rewarded().onAdClicked(new LevelPlayAdInfo());
                test.rewarded().onAdRewarded(new LevelPlayReward(null, 1), new LevelPlayAdInfo());
                test.rewarded().onAdLoadFailed(new LevelPlayAdError(null));
                test.rewarded().onAdDisplayFailed(new LevelPlayAdError(null), new LevelPlayAdInfo());
                test.rewarded().onAdClosed(new LevelPlayAdInfo());
                LevelPlayInterstitialAd.lastListener.onAdLoaded(new LevelPlayAdInfo());
                LevelPlayInterstitialAd.lastListener.onAdDisplayed(new LevelPlayAdInfo());
                LevelPlayInterstitialAd.lastListener.onAdLoadFailed(new LevelPlayAdError(null));
                LevelPlayInterstitialAd.lastListener.onAdClosed(new LevelPlayAdInfo());
                test.showAd("interstitial");
                test.showAd("rewardedVideo");
                LevelPlay.lastInitListener.onInitFailed(new LevelPlayInitError(0, "no config"));

                test.expectEquals(0, LuaState.nullPushes, "pushString(null) attempts");
                for (Map<String, Object> event : events) {
                    test.expectEquals("ironSource", event.get("name"), "event.name");
                    test.expectTrue(event.get("type") instanceof String, "event.type must be a string");
                    test.expectTrue(event.get("phase") instanceof String, "event.phase must be a string");
                    test.expectTrue(event.get("isError") instanceof Boolean, "event.isError must be a boolean");
                }
                test.expectStackClean();
            }
        });

        test.caseTest("rewardWithoutName_omitsResponse", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.rewarded().onAdRewarded(new LevelPlayReward(null, 1), new LevelPlayAdInfo());

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectFields(event, "name", "type", "phase", "isError");
                test.expectEquals("reward", event.get("phase"), "event.phase");
                test.expectStackClean();
            }
        });

        test.caseTest("initFailed_carriesResponse", new Case() {
            public void run() throws Exception {
                test.boot();
                events.clear();

                LevelPlay.lastInitListener.onInitFailed(new LevelPlayInitError(42, "no config"));

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectFields(event, "name", "type", "phase", "isError", "response");
                test.expectEquals("init", event.get("type"), "event.type");
                test.expectEquals("failed", event.get("phase"), "event.phase");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectEquals("no config - 42", event.get("response"), "event.response");
                test.expectStackClean();
            }
        });

        test.caseTest("notReadyShowPath_emitsErrorEvent", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.showAd("rewardedVideo");

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectEquals("rewardedVideo", event.get("type"), "event.type");
                test.expectEquals("show", event.get("phase"), "event.phase");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectEquals("not available", event.get("response"), "event.response");
                test.expectStackClean();
            }
        });

        test.caseTest("unknownShowAdUnitType_emitsErrorEvent", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.showAd("banner");

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectEquals("show", event.get("type"), "event.type");
                test.expectEquals("failed", event.get("phase"), "event.phase");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectEquals("unknown adUnitType: banner", event.get("response"), "event.response");
                test.expectStackClean();
            }
        });

        test.caseTest("unknownLoadAdUnitType_emitsErrorEvent", new Case() {
            public void run() throws Exception {
                test.boot();
                test.initSuccess();
                events.clear();

                test.loadAd("banner");

                test.expectEventCount(1);
                Map<String, Object> event = events.get(0);
                test.expectEquals("load", event.get("type"), "event.type");
                test.expectEquals("failed", event.get("phase"), "event.phase");
                test.expectEquals(Boolean.TRUE, event.get("isError"), "event.isError");
                test.expectEquals("unknown adUnitType: banner", event.get("response"), "event.response");
                test.expectStackClean();
            }
        });

        System.out.println();
        System.out.println(checks + " checks, " + failures + " failure(s)");
        if (failures > 0) {
            System.exit(1);
        }
    }

    // --- Fixture -------------------------------------------------------------

    private void boot() {
        events.clear();
        activity = new CoronaActivity();
        CoronaEnvironment.setCoronaActivity(activity);
        CoronaLua.sink = new CoronaLua.EventSink() {
            public void onEvent(Map<String, Object> event) {
                events.add(event);
            }
        };
        CoronaLua.failNextNewEvent = null;
        CoronaLua.failNextDispatchEvent = null;
        LevelPlay.lastInitListener = null;
        LevelPlayInterstitialAd.lastListener = null;
        LevelPlayRewardedAd.lastListener = null;
        LuaState.nullPushes = 0;

        luaState = new LuaState();
        plugin = new LuaLoader();
        plugin.onLoaded(new CoronaRuntime(luaState));

        plugin.invoke(luaState); // pushes the module table
        final Map<?, ?> module = (Map<?, ?>) luaState.get(-1);
        luaState.pop(1);

        luaState.pushJavaFunction(new JavaFunction() { // listener argument (index 1)
            public int invoke(LuaState L) {
                return 0;
            }
        });
        Map<String, Object> options = luaState.pushTable(); // options argument (index 2)
        options.put("key", "test-app-key");
        options.put("interstitialAdUnitId", "test-interstitial-unit");
        options.put("rewardedVideoAdUnitId", "test-rewarded-unit");

        ((JavaFunction) module.get("init")).invoke(luaState);
        luaState.setTop(0);
    }

    private void initSuccess() {
        LevelPlay.lastInitListener.onInitSuccess(new LevelPlayConfiguration());
    }

    private com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener rewarded() {
        return LevelPlayRewardedAd.lastListener;
    }

    private void showAd(String adUnitType) {
        final Map<?, ?> module = pluginModule();
        luaState.pushString(adUnitType);
        ((JavaFunction) module.get("show")).invoke(luaState);
        luaState.setTop(0);
    }

    private void loadAd(String adUnitType) {
        final Map<?, ?> module = pluginModule();
        luaState.pushString(adUnitType);
        ((JavaFunction) module.get("load")).invoke(luaState);
        luaState.setTop(0);
    }

    private Map<?, ?> pluginModule() {
        LuaState fresh = luaState;
        int before = fresh.getTop();
        plugin.invoke(fresh);
        Map<?, ?> module = (Map<?, ?>) fresh.get(-1);
        fresh.setTop(before);
        return module;
    }

    /** White-box: dispatchEvent is reached through real SDK callbacks everywhere else. */
    private void callDispatchEvent(String type, String phase, boolean isError, String response)
            throws Exception {
        Method dispatch = LuaLoader.class.getDeclaredMethod(
                "dispatchEvent", String.class, String.class, boolean.class, String.class);
        dispatch.setAccessible(true);
        try {
            dispatch.invoke(plugin, type, phase, Boolean.valueOf(isError), response);
        } catch (InvocationTargetException e) {
            Throwable cause = e.getCause();
            if (cause instanceof Exception) {
                throw (Exception) cause;
            }
            throw (Error) cause;
        }
    }

    // --- Assertions ----------------------------------------------------------

    private void expectEventCount(int expected) {
        expectEquals(expected, events.size(), "dispatched event count");
    }

    private void expectFields(Map<String, Object> event, String... expected) {
        Set<String> actual = new HashSet<String>(event.keySet());
        Set<String> want = new HashSet<String>(Arrays.asList(expected));
        expectTrue(actual.equals(want), "field set " + actual + " != expected " + want);
    }

    private void expectStackClean() {
        expectEquals(0, luaState.getTop(), "Lua stack top after dispatch");
    }

    private void expectLoggedError(String fragment) {
        for (String message : Log.errors) {
            if (message.contains(fragment)) {
                expectTrue(true, "logged: " + fragment);
                return;
            }
        }
        expectTrue(false, "expected a logged error containing \"" + fragment + "\" but got " + Log.errors);
    }

    private void expectEquals(Object expected, Object actual, String what) {
        if (expected == null ? actual == null : expected.equals(actual)) {
            expectTrue(true, what);
        } else {
            expectTrue(false, what + ": expected <" + expected + "> but was <" + actual + ">");
        }
    }

    private void expectTrue(boolean condition, String what) {
        checks++;
        if (!condition) {
            failures++;
            System.out.println("FAIL " + what);
        }
    }

    private void caseTest(String name, Case body) {
        Log.reset();
        System.out.println("--- " + name);
        try {
            body.run();
            System.out.println("    ok");
        } catch (Throwable t) {
            failures++;
            System.out.println("FAIL " + name + " threw " + t.getClass().getName() + ": " + t.getMessage());
        }
    }

    private interface Case {
        void run() throws Exception;
    }
}
