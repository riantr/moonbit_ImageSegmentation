package ij.process;

/**
 * Minimal ImageJ "FloatProcessor" (32 bit float).
 *
 * ImageJ semantics that the harness depends on:
 *  - getPixelValue(x,y) returns the *float* value of the pixel; it is NOT
 *    truncated to an int (RATSQuadtree sums the gradient energies with it);
 *  - the FloatProcessor(float[][]) constructor reads a 2D array as
 *    [row][column]: the image width is the length of the inner arrays and the
 *    image height is the number of rows (see README.md);
 *  - convertToByte(clip) clips the values into 0..255 (clip == true) or
 *    rounds them without clipping (clip == false).
 */
public class FloatProcessor extends ImageProcessor {

    protected float[] pixels;

    public FloatProcessor(int width, int height) {
        super(width, height);
        this.pixels = new float[width * height];
    }

    public FloatProcessor(int width, int height, float[] pixels) {
        super(width, height);
        this.pixels = pixels;
    }

    /**
     * Builds a float image from a 2D array that is read as [row][column]:
     * the width is the length of the inner arrays, the height is the number of
     * rows and the pixel (column, row) holds array[row][column].
     */
    public FloatProcessor(float[][] pixels) {
        this(pixels[0].length, pixels.length);
        for (int y = 0; y < pixels.length; y++) {
            int rowoffset = y * width;
            for (int x = 0; x < pixels[0].length; x++) {
                setf(rowoffset + x, pixels[y][x]);
            }
        }
    }

    public Object getPixels() {
        return pixels;
    }

    /** Typed accessor for the float array. */
    public float[] getFloatPixels() {
        return pixels;
    }

    public int get(int x, int y) {
        return (int) pixels[y * width + x];
    }

    public void set(int x, int y, int v) {
        pixels[y * width + x] = v;
    }

    public float getf(int index) {
        return pixels[index];
    }

    public void setf(int index, float v) {
        pixels[index] = v;
    }

    /**
     * The value of the pixel at (x,y) as a float.
     *
     * NOTE: this is *not* upstream ImageJ's behaviour. Upstream ImageJ
     * returns NaN for coordinates outside the image; here the flat index
     * `y * width + x` is used directly (a true out of range index throws
     * ArrayIndexOutOfBoundsException). The RATS quadtree sums the
     * *transposed* float image (its width is the image height), so it
     * addresses the image with x in [0,width-1] of the *original* image and
     * therefore leaves the image for every non square input. The MoonBit
     * port (FloatImage::get) reads the same flat index without a bounds
     * check, and the golden outputs have to match it byte for byte.
     */
    public float getPixelValue(int x, int y) {
        return pixels[y * width + x];
    }

    /** ImageJ semantics: pixels[i] *= value, evaluated in double precision. */
    public void multiply(double value) {
        for (int i = 0; i < pixels.length; i++) {
            pixels[i] = (float) (pixels[i] * value);
        }
    }

    public int[] getHistogram() {
        int[] histogram = new int[256];
        for (int i = 0; i < pixels.length; i++) {
            int v = (int) pixels[i];
            if (v < 0) v = 0;
            if (v > 255) v = 255;
            histogram[v]++;
        }
        return histogram;
    }

    public FloatProcessor copy() {
        return new FloatProcessor(width, height, pixels.clone());
    }

    /**
     * ImageJ semantics: with clip == true the values are clipped into
     * 0..255, otherwise they are rounded (and may wrap around).
     */
    public ByteProcessor convertToByte(boolean clip) {
        ByteProcessor out = new ByteProcessor(width, height);
        byte[] bp = (byte[]) out.getPixels();
        for (int i = 0; i < pixels.length; i++) {
            if (clip) {
                if (pixels[i] > 255) {
                    bp[i] = (byte) 255;
                } else if (pixels[i] < 0) {
                    bp[i] = 0;
                } else {
                    bp[i] = (byte) pixels[i];
                }
            } else {
                bp[i] = (byte) (pixels[i] + 0.5);
            }
        }
        return out;
    }
}
