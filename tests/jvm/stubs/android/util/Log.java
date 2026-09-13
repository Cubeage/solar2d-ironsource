package android.util;

import java.util.ArrayList;
import java.util.List;

/** Minimal stand-in for android.util.Log that records what the plugin logged (JVM tests only). */
public class Log {
    public static final List<String> errors = new ArrayList<String>();
    public static final List<String> warnings = new ArrayList<String>();

    public static int e(String tag, String msg) {
        errors.add(tag + ": " + msg);
        return 0;
    }

    public static int e(String tag, String msg, Throwable tr) {
        errors.add(tag + ": " + msg + " [" + (tr == null ? "null" : tr.getClass().getName()) + "]");
        return 0;
    }

    public static int w(String tag, String msg) {
        warnings.add(tag + ": " + msg);
        return 0;
    }

    public static int d(String tag, String msg) {
        return 0;
    }

    public static void reset() {
        errors.clear();
        warnings.clear();
    }
}
