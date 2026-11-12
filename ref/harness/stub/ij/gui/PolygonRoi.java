package ij.gui;

import java.awt.Polygon;

/** Minimal ImageJ "PolygonRoi". */
public class PolygonRoi extends Roi {

    private final Polygon polygon;

    public PolygonRoi(Polygon polygon, int type) {
        super(0, 0, polygon == null ? 0 : polygon.npoints, 0);
        this.polygon = polygon;
    }

    public Polygon getPolygon() {
        return polygon;
    }
}
