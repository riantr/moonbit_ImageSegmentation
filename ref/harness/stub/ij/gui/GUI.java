package ij.gui;

/**
 * Minimal ImageJ "GUI" helper.
 *
 * The original Multi_Thresholder class calls GUI.center(this); the harness
 * runs headless and has no window to centre, so the call is a no-op.
 */
public class GUI {

    /** Centres a component in the screen; a no-op in the harness. */
    public static void center(java.awt.Component component) {
    }

    /** The ImageJ icon; never used by the harness. */
    public static java.awt.Image getImage() {
        return null;
    }
}
