package ij.gui;

/**
 * Minimal ImageJ "TrimmedButton" (an AWT button whose label is trimmed).
 *
 * The original Multi_Thresholder class creates four of them in its
 * constructor; the harness never runs that constructor, but the class has to
 * link.
 */
public class TrimmedButton extends java.awt.Button {

    public TrimmedButton(String label) {
        super(label);
    }

    public TrimmedButton(String label, int trim) {
        super(label);
    }
}
