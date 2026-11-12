package ij.gui;

/** Minimal ImageJ "ShapeRoi" (a ROI described by a java.awt shape). */
public class ShapeRoi extends Roi {

    public ShapeRoi(Roi roi) {
        super(roi.getX(), roi.getY(), roi.getWidth(), roi.getHeight());
    }

    /** Symmetric difference; the harness never relies on its geometry. */
    public Roi xor(ShapeRoi other) {
        return new Roi(getX(), getY(), getWidth(), getHeight());
    }
}
