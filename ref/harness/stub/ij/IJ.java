package ij;

import java.util.ArrayList;
import java.util.List;

/**
 * Minimal ImageJ "IJ" facade used by the reference harness.
 *
 * Semantics:
 *  - every method is a no-op except where noted;
 *  - IJ.write(String) and IJ.showMessage(...) RECORD their text into
 *    IJ.MESSAGES (in call order) so the harness can scrape the numbers that
 *    the original algorithms print;
 *  - IJ.log(String) records into IJ.LOGS (call order) and is otherwise a no-op.
 */
public class IJ {

    /** Original code reads this flag (Blob_Labeler.debug). */
    public static boolean debugMode = false;

    /** Messages emitted through IJ.write / IJ.showMessage, in call order. */
    public static final List<String> MESSAGES = new ArrayList<String>();

    /** Messages emitted through IJ.log, in call order. */
    public static final List<String> LOGS = new ArrayList<String>();

    public static void log(String msg) {
        LOGS.add(msg);
    }

    public static void write(String msg) {
        MESSAGES.add(msg);
    }

    public static void showMessage(String msg) {
        MESSAGES.add(msg);
    }

    public static void showMessage(String title, String msg) {
        MESSAGES.add(msg);
    }

    public static void showProgress(double progress) {
    }

    public static void showStatus(String status) {
    }

    public static void error(String title, String msg) {
        MESSAGES.add(title + ": " + msg);
    }

    public static void run(String command, String args) {
    }

    public static void run(String command) {
    }

    public static void setTool(int tool) {
    }

    public static void makePoint(int x, int y) {
    }

    /** Always false: the harness pretends to run a modern ImageJ. */
    public static boolean versionLessThan(String version) {
        return false;
    }

    public static int setupDialog(ImagePlus imp, int flags) {
        return flags;
    }

    public static void noImage() {
    }

    public static void register(Class<?> c) {
    }

    public static String getVersion() {
        return "1.53";
    }
}
