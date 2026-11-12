package ij;

/**
 * Minimal ImageJ "Macro".
 *
 * The harness never runs inside a macro, so getOptions() returns null. A
 * plugin that would read its parameters from a macro (RATS_ does) then falls
 * back to its own dialog, and the harness' GenericDialog stub answers with
 * the default values of that dialog.
 */
public class Macro {

    /** null: no macro is running. */
    public static String getOptions() {
        return null;
    }
}
