package ij.plugin.frame;

/**
 * Minimal ImageJ "Recorder" (macro recording).
 *
 * The original Multi_Thresholder class calls Recorder.record(...); the
 * harness never records a macro, so the flag stays false and the calls are
 * no-ops.
 */
public class Recorder {

    /** ImageJ's macro recording flag; the harness never records. */
    public static boolean record = false;

    public static void record(String option) {
    }

    public static void record(String command, String option) {
    }

    public static void record(String command, String option, String value) {
    }

    public static void record(String command, double value1, double value2) {
    }

    public static String recordOption(String command, String option, String value) {
        return value;
    }
}
