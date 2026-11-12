package ij.process;

/**
 * Minimal ImageJ "ShortProcessor" (16 bit, signed).
 *
 * Blob_Labeler uses both the (x,y) accessors and the linear (index) accessors
 * on the label map, so both are provided.
 */
public class ShortProcessor extends ImageProcessor {

    protected short[] pixels;

    public ShortProcessor(int width, int height) {
        super(width, height);
        this.pixels = new short[width * height];
        this.max = 65535.0;
    }

    public ShortProcessor(int width, int height, short[] pixels) {
        super(width, height);
        this.pixels = pixels;
        this.max = 65535.0;
    }

    public Object getPixels() {
        return pixels;
    }

    /** Typed accessor for the signed short array. */
    public short[] getShortPixels() {
        return pixels;
    }

    public int get(int x, int y) {
        return pixels[y * width + x] & 0xffff;
    }

    /** Linear (row major) access, as used by Blob_Labeler. */
    public int get(int index) {
        return pixels[index] & 0xffff;
    }

    public void set(int x, int y, int v) {
        pixels[y * width + x] = (short) v;
    }

    /** Linear (row major) access, as used by Blob_Labeler. */
    public void set(int index, int v) {
        pixels[index] = (short) v;
    }

    public int[] getHistogram() {
        int[] histogram = new int[256];
        for (int i = 0; i < pixels.length; i++) {
            histogram[pixels[i] & 0xff]++;
        }
        return histogram;
    }

    public ShortProcessor copy() {
        return new ShortProcessor(width, height, pixels.clone());
    }
}
