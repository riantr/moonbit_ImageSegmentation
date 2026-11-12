package ij.gui;

import java.awt.Color;

/**
 * Minimal ImageJ "Toolbar".
 *
 * The foreground/background colours are the ones the densitometry plugins
 * compare the pixels against: foreground = white (255,255,255),
 * background = black (0,0,0).
 */
public class Toolbar {

    /** Tool id of the point tool (RATSQuadtree.drawCenter uses it). */
    public static final int POINT = 0;

    public static Color getForegroundColor() {
        return new Color(255, 255, 255);
    }

    public static Color getBackgroundColor() {
        return new Color(0, 0, 0);
    }
}
