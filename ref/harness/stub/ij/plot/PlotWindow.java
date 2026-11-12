package ij.plot;

/**
 * Minimal ImageJ "PlotWindow": a headless no-op, the harness never draws.
 */
public class PlotWindow {

    public PlotWindow(String title, String xLabel, String yLabel, float[] xValues, float[] yValues) {
    }

    public void setLimits(float x1, float x2, float y1, float y2) {
    }

    public void draw() {
    }
}
