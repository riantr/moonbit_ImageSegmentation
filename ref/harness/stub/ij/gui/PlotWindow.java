package ij.gui;

/**
 * Minimal ImageJ "PlotWindow" in the ij.gui package.
 *
 * ImageJ 1.x kept the plot window in ij.gui and the original sources import
 * ij.gui.* (not ij.plot.*), so the class has to be reachable from ij.gui for
 * Multi_OtsuThreshold to compile verbatim. It extends ij.plot.PlotWindow,
 * the location required by the harness contract; both are headless no-ops.
 */
public class PlotWindow extends ij.plot.PlotWindow {

    public PlotWindow(String title, String xLabel, String yLabel, float[] xValues, float[] yValues) {
        super(title, xLabel, yLabel, xValues, yValues);
    }
}
