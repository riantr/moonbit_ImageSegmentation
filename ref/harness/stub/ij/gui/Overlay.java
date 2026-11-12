package ij.gui;

import java.util.ArrayList;
import java.util.List;

/** Minimal ImageJ "Overlay" (a list of ROIs drawn on top of an image). */
public class Overlay {

    private final List<Roi> rois = new ArrayList<Roi>();

    public void add(Roi roi) {
        rois.add(roi);
    }

    public int size() {
        return rois.size();
    }

    public Roi get(int index) {
        return rois.get(index);
    }
}
