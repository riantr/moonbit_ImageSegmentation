package ij.process;

/**
 * Minimal ImageJ "ByteProcessor".
 *
 * ImageJ semantics:
 *  - the pixel array is a SIGNED byte[] (values 128..255 are negative);
 *  - get(x,y) returns the unsigned value (pixels[..] & 0xff);
 *  - set(x,y,v) stores (byte) v;
 *  - getHistogram() counts the unsigned values.
 */
public class ByteProcessor extends ImageProcessor {

    protected byte[] pixels;

    public ByteProcessor(int width, int height) {
        super(width, height);
        this.pixels = new byte[width * height];
    }

    public ByteProcessor(int width, int height, byte[] pixels) {
        super(width, height);
        this.pixels = pixels;
    }

    /**
     * Copy constructor over another 8 bit processor. Needed by RetFM_J, which
     * builds a ByteProcessor from ColorProcessor.getChannel(int); the pixels
     * of the source processor are copied verbatim.
     */
    public ByteProcessor(int width, int height, ByteProcessor processor) {
        super(width, height);
        byte[] source = (byte[]) processor.getPixels();
        this.pixels = new byte[width * height];
        System.arraycopy(source, 0, this.pixels, 0, Math.min(source.length, this.pixels.length));
    }

    public Object getPixels() {
        return pixels;
    }

    /** Typed accessor for the signed byte array. */
    public byte[] getBytePixels() {
        return pixels;
    }

    public int get(int x, int y) {
        return pixels[y * width + x] & 0xff;
    }

    /**
     * ImageJ semantics: the unsigned byte value of the pixel. Out of bounds
     * coordinates give NaN.
     */
    public float getPixelValue(int x, int y) {
        if (x < 0 || x >= width || y < 0 || y >= height) {
            return Float.NaN;
        }
        return pixels[y * width + x] & 0xff;
    }

    public void set(int x, int y, int v) {
        pixels[y * width + x] = (byte) v;
    }

    public int[] getHistogram() {
        int[] histogram = new int[256];
        for (int i = 0; i < pixels.length; i++) {
            histogram[pixels[i] & 0xff]++;
        }
        return histogram;
    }

    public ByteProcessor copy() {
        return new ByteProcessor(width, height, pixels.clone());
    }

    public ByteProcessor convertToByte(boolean scaling) {
        return copy();
    }

    public FloatProcessor convertToFloatProcessor() {
        FloatProcessor out = new FloatProcessor(width, height);
        for (int i = 0; i < pixels.length; i++) {
            out.setf(i, pixels[i] & 0xff);
        }
        return out;
    }
}
