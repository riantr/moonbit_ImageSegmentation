package ij.measure;

/**
 * Minimal ImageJ "ImageStatistics".
 *
 * pixelCount is the number of pixels of the ROI (this is what
 * RetFM_J.getThreshold uses); area counts the non zero pixels of the ROI.
 */
public class ImageStatistics {

    public int pixelCount;
    public double area;
    public double mean;
    public double min;
    public double max;
    public double stdDev;

    /**
     * An empty set of statistics.
     */
    public ImageStatistics() {
    }

    /**
     * ImageJ computes the statistics of an image; the harness only needs
     * the type to exist (the original MultiThresholderPlot class extends
     * StackStatistics, which extends this class).
     */
    public ImageStatistics(ij.ImagePlus imp) {
    }
}
