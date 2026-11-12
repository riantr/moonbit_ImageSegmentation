package ij;

import ij.process.ImageProcessor;

import java.util.ArrayList;
import java.util.List;

/** Minimal ImageJ image stack. */
public class ImageStack {

    private final List<ImageProcessor> slices = new ArrayList<ImageProcessor>();

    public int getSize() {
        return slices.size();
    }

    public int getWidth() {
        return slices.isEmpty() ? 0 : slices.get(0).getWidth();
    }

    public int getHeight() {
        return slices.isEmpty() ? 0 : slices.get(0).getHeight();
    }

    public ImageProcessor getProcessor(int n) {
        return slices.get(n);
    }

    public void addSlice(String label, ImageProcessor ip) {
        slices.add(ip);
    }
}
