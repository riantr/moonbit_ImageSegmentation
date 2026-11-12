package ij;

import ij.process.ByteProcessor;
import ij.process.ColorProcessor;

/**
 * Minimal ImageJ "NewImage" factory.
 *
 * ImageJ semantics (kept faithful so that the golden output matches):
 *  - FILL_WHITE fills the new image with white (255 for 8-bit, 0xFFFFFF for RGB);
 *  - FILL_BLACK fills the new image with black (0 for 8-bit and for RGB).
 */
public class NewImage {

    public static final int FILL_WHITE = 0;
    public static final int FILL_BLACK = 1;

    public static ImagePlus createByteImage(String title, int width, int height, int slices, int fill) {
        ByteProcessor bp = new ByteProcessor(width, height);
        byte[] pixels = (byte[]) bp.getPixels();
        byte value = (fill == FILL_BLACK) ? (byte) 0 : (byte) 255;
        java.util.Arrays.fill(pixels, value);
        return new ImagePlus(title, bp);
    }

    public static ImagePlus createRGBImage(String title, int width, int height, int slices, int fill) {
        ColorProcessor cp = new ColorProcessor(width, height);
        int[] pixels = (int[]) cp.getPixels();
        int value = (fill == FILL_BLACK) ? 0 : 0xFFFFFF;
        java.util.Arrays.fill(pixels, value);
        return new ImagePlus(title, cp);
    }
}
