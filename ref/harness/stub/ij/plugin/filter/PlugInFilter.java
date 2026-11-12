package ij.plugin.filter;

import ij.ImagePlus;
import ij.process.ImageProcessor;

/**
 * Minimal ImageJ "PlugInFilter".
 *
 * The flag values are the ones of ImageJ 1.x; the harness never relies on
 * them (the algorithms are driven through run() directly, so only the names
 * have to exist).
 */
public interface PlugInFilter {

    int DOES_8G = 1;
    int DOES_8C = 2;
    int DOES_16 = 4;
    int DOES_32 = 8;
    int DOES_RGB = 16;
    int DOES_ALL = DOES_8G + DOES_8C + DOES_16 + DOES_32 + DOES_RGB;
    int DOES_STACKS = 32;
    int SUPPORTS_MASKING = 64;
    int NO_CHANGES = 128;
    int NO_UNDO = 256;
    int NO_IMAGE_REQUIRED = 512;
    int ROI_REQUIRED = 1024;
    int STACK_REQUIRED = 2048;
    int DONE = 4096;
    int CONVERT_TO_FLOAT = 8192;
    int SNAPSHOT = 16384;
    int PARALLELIZE_STACKS = 32768;
    int FINAL_PROCESSING = 65536;
    int KEEP_THRESHOLD = 131072;
    int PARALLELIZE_IMAGES = 262144;
    int NO_UNDO_RESET = 524288;

    int setup(String arg, ImagePlus imp);

    void run(ImageProcessor ip);
}
