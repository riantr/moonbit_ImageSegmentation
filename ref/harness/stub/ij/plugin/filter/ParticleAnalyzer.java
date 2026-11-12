package ij.plugin.filter;

import ij.ImagePlus;
import ij.measure.ResultsTable;
import ij.plugin.frame.RoiManager;

/** Minimal ImageJ "ParticleAnalyzer" (imported by RetFM_J, never executed). */
public class ParticleAnalyzer {

    public static final int EXCLUDE_EDGE_PARTICLES = 1;
    public static final int SHOW_NONE = 0;
    public static final int SHOW_OUTLINES = 2;
    public static final int SHOW_MEASUREMENTS = 4;
    public static final int SHOW_LABELS = 16;
    public static final int SHOW_CENTROIDS = 32;
    public static final int SHOW_SUMMARIES = 64;

    public ParticleAnalyzer(int options, int measure, RoiManager roiManager,
                            double minSize, double maxSize,
                            double minCircularity, double maxCircularity) {
    }

    public void analyze(ImagePlus imp) {
    }

    public static void setResultsTable(ResultsTable rt) {
    }

    public static void setRoiManager(RoiManager rm) {
    }
}
