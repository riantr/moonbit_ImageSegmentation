package ij.process;

/**
 * Minimal ImageJ "ImageStatistics" of the ij.process package.
 *
 * The original Multi_Thresholder plugin (and its MultiThresholderPlot
 * class) use the old location of the class; the modern one lives in
 * ij.measure. The harness needs the type to exist so that the plugin
 * class links; the statistics themselves are never computed.
 */
public class ImageStatistics {

    public int pixelCount;
    public double area;
    public double mean;
    public double min;
    public double max;
    public double stdDev;

    /** An empty set of statistics. */
    public ImageStatistics() {
    }

    /** ImageJ computes the statistics of an image. */
    public ImageStatistics(ij.ImagePlus imp) {
    }
}
