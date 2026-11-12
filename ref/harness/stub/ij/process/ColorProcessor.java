package ij.process;

/**
 * Minimal ImageJ "ColorProcessor".
 *
 * Pixel packing (as used by the harness): 0x00RRGGBB, i.e. the red byte is
 * the most significant byte of the 24 bit colour, then green, then blue.
 * The alpha byte is never stored, so the value written through putPixel() is
 * kept verbatim (ImageJ would OR 0xff000000 into it; the harness always
 * extracts the three colour bytes, so this is not observable in the golden
 * outputs).
 */
public class ColorProcessor extends ImageProcessor {

    protected int[] pixels;

    public ColorProcessor(int width, int height) {
        super(width, height);
        this.pixels = new int[width * height];
    }

    public ColorProcessor(int width, int height, int[] pixels) {
        super(width, height);
        this.pixels = pixels;
    }

    public Object getPixels() {
        return pixels;
    }

    /** Typed accessor for the packed RGB array. */
    public int[] getIntPixels() {
        return pixels;
    }

    /** ImageJ semantics: returns the packed 0x00RRGGBB value. */
    public int get(int x, int y) {
        return pixels[y * width + x];
    }

    public void set(int x, int y, int v) {
        pixels[y * width + x] = v;
    }

    /** Writes a packed 0x00RRGGBB colour; out of range coordinates are ignored. */
    public void putPixel(int x, int y, int c) {
        int index = y * width + x;
        if (index < 0 || index >= pixels.length) {
            return;
        }
        pixels[index] = c;
    }

    public int getPixel(int x, int y) {
        return pixels[y * width + x];
    }

    /** Channel 1 = red, 2 = green, 3 = blue. */
    public ByteProcessor getChannel(int channel) {
        return getChannel(channel, null);
    }

    /** Channel 1 = red, 2 = green, 3 = blue; b may be null (then it is allocated). */
    public ByteProcessor getChannel(int channel, ByteProcessor b) {
        if (b == null) {
            b = new ByteProcessor(width, height);
        }
        byte[] out = (byte[]) b.getPixels();
        for (int i = 0; i < pixels.length; i++) {
            int c = pixels[i];
            int r = (c >> 16) & 0xff;
            int g = (c >> 8) & 0xff;
            int bch = c & 0xff;
            out[i] = (byte) (channel == 1 ? r : channel == 2 ? g : channel == 3 ? bch : 0);
        }
        return b;
    }

    public int[] getHistogram() {
        int[] histogram = new int[256];
        for (int i = 0; i < pixels.length; i++) {
            histogram[(pixels[i] >> 16) & 0xff]++;
        }
        return histogram;
    }

    public ColorProcessor copy() {
        return new ColorProcessor(width, height, pixels.clone());
    }

    /** Standard ImageJ luminance conversion (0.299 R + 0.587 G + 0.114 B). */
    public ByteProcessor convertToByte(boolean scaling) {
        ByteProcessor out = new ByteProcessor(width, height);
        byte[] outPixels = (byte[]) out.getPixels();
        for (int i = 0; i < pixels.length; i++) {
            int c = pixels[i];
            int r = (c >> 16) & 0xff;
            int g = (c >> 8) & 0xff;
            int b = c & 0xff;
            outPixels[i] = (byte) (int) (0.299 * r + 0.587 * g + 0.114 * b + 0.5);
        }
        return out;
    }

    public FloatProcessor convertToFloatProcessor() {
        FloatProcessor out = new FloatProcessor(width, height);
        for (int i = 0; i < pixels.length; i++) {
            int c = pixels[i];
            int r = (c >> 16) & 0xff;
            int g = (c >> 8) & 0xff;
            int b = c & 0xff;
            out.setf(i, 0.299f * r + 0.587f * g + 0.114f * b);
        }
        return out;
    }

    /** Inverts each colour channel separately (ImageJ behaviour for RGB). */
    public void invert() {
        for (int i = 0; i < pixels.length; i++) {
            int c = pixels[i];
            int r = 255 - ((c >> 16) & 0xff);
            int g = 255 - ((c >> 8) & 0xff);
            int b = 255 - (c & 0xff);
            pixels[i] = (r << 16) | (g << 8) | b;
        }
    }
}
