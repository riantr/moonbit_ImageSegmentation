package ij.gui;

import ij.process.ImageProcessor;

/**
 * Minimal ImageJ "Wand".
 *
 * Only needed so that Blob_Labeler compiles: the harness disables the
 * optional vectorization step (private static field "segment") so the wand is
 * never actually used to trace a contour.
 */
public class Wand {

    public int[] xpoints = new int[0];
    public int[] ypoints = new int[0];
    public int npoints = 0;

    public Wand() {
    }

    public Wand(ImageProcessor ip) {
    }

    public void autoOutline(int x, int y, int lower, int upper) {
    }
}
