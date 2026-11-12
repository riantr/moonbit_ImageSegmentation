package ij.util;

/**
 * Minimal ImageJ "Tools".
 *
 * Only the helpers that the compiled plugins call are provided. RATS_ uses
 * Tools.parseDouble() to read the parameters of a macro run; the harness
 * never runs a macro, so this method is never reached.
 */
public class Tools {

    /** Parses a decimal number, tolerating surrounding whitespace. */
    public static double parseDouble(String s) {
        return Double.parseDouble(s.trim());
    }
}
