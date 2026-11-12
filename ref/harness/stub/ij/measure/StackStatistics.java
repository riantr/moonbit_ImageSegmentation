package ij.measure;

/**
 * Minimal ImageJ "StackStatistics".
 *
 * The original MultiThresholderPlot class extends it; the harness only needs
 * the type to exist so that the class links.
 */
public class StackStatistics extends ImageStatistics {

    public StackStatistics(ij.ImagePlus imp) {
        super(imp);
    }
}
