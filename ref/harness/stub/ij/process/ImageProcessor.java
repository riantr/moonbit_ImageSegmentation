package ij.process;

import ij.measure.ImageStatistics;

import java.awt.Rectangle;

/**
 * Minimal ImageJ "ImageProcessor" base class.
 *
 * The concrete subclasses (Byte/Short/Float/Color) own the pixel array; this
 * base class only owns the geometry, the ROI and the shared conversions.
 *
 * ROI semantics (as in ImageJ): the ROI defaults to the whole image
 * (0,0,width,height) and threshold()/invert() only touch the ROI.
 */
public abstract class ImageProcessor {

    protected int width;
    protected int height;
    protected Rectangle roi;

    /**
     * The value range of the processor. ImageJ initialises it with the full
     * range of the pixel type; the concrete processors adjust it.
     */
    protected double min = 0.0;
    protected double max = 255.0;

    /** The threshold range; NO_THRESHOLD means "no threshold is set". */
    protected double minThreshold = NO_THRESHOLD;
    protected double maxThreshold = NO_THRESHOLD;

    /**
     * ImageJ's "no threshold" marker.
     *
     * The value is the one of the ImageJ version the Multi_Thresholder
     * plugin was built against: the sentinel is baked into the bytecode of
     * the shipped class, so the stub has to use the very same value for
     * the plugin to behave as it does in ImageJ.
     */
    public static final double NO_THRESHOLD = -808080.0;

    /** The red LUT; the harness only ever uses this one. */
    public static final int RED_LUT = 0;

    public ImageProcessor(int width, int height) {
        this.width = width;
        this.height = height;
        this.roi = new Rectangle(0, 0, width, height);
    }

    /**
     * The smallest pixel value of the processor.
     *
     * ImageJ keeps this in a field that is only refreshed by findMinAndMax();
     * for the byte and short processors it is the full range of the type.
     */
    public double getMin() {
        return min;
    }

    /** The largest pixel value of the processor. */
    public double getMax() {
        return max;
    }

    /** Sets the threshold range; the LUT is ignored by the harness. */
    public void setThreshold(double lower, double upper, int lut) {
        this.minThreshold = lower;
        this.maxThreshold = upper;
    }

    /** The lower bound of the threshold range. */
    public double getMinThreshold() {
        return minThreshold;
    }

    /** The upper bound of the threshold range. */
    public double getMaxThreshold() {
        return maxThreshold;
    }

    /** Removes the threshold. */
    public void resetThreshold() {
        this.minThreshold = NO_THRESHOLD;
        this.maxThreshold = NO_THRESHOLD;
    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }

    /** Raw pixel array of the concrete type (byte[], short[], float[], int[]). */
    public abstract Object getPixels();

    /** Pixel value at (x,y) in the native range of the processor. */
    public abstract int get(int x, int y);

    /** Writes a pixel value at (x,y) in the native range of the processor. */
    public abstract void set(int x, int y, int v);

    public void putPixel(int x, int y, int v) {
        set(x, y, v);
    }

    public int getPixel(int x, int y) {
        return get(x, y);
    }

    /**
     * ImageJ semantics: the pixel value in the native range of the processor
     * (an unsigned value for 8 bit images, the float value for 32 bit float
     * images). The concrete processors override this where the two differ.
     */
    public float getPixelValue(int x, int y) {
        return get(x, y);
    }

    /** 256 bin histogram of the pixel values. */
    public abstract int[] getHistogram();

    public abstract ImageProcessor copy();

    public Rectangle getRoi() {
        return roi;
    }

    public void setRoi(Rectangle r) {
        this.roi = (r == null) ? new Rectangle(0, 0, width, height) : r;
    }

    /**
     * ImageJ also accepts an ij.gui.Roi; only its bounding box is honoured
     * (the harness never uses a non rectangular ROI).
     */
    public void setRoi(ij.gui.Roi roi) {
        if (roi == null) {
            this.roi = new Rectangle(0, 0, width, height);
        } else {
            this.roi = new Rectangle(roi.getX(), roi.getY(), roi.getWidth(), roi.getHeight());
        }
    }

    /** ImageJ keeps the color model on the processor; the harness ignores it. */
    public void setColorModel(java.awt.image.IndexColorModel colorModel) {
    }

    public void fill() {
    }

    /**
     * ImageJ threshold(): pixels strictly greater than the level become 255,
     * every other pixel becomes 0. Only the ROI is touched.
     */
    public void threshold(int level) {
        Rectangle r = getRoi();
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                if (get(x, y) > level) {
                    set(x, y, 255);
                } else {
                    set(x, y, 0);
                }
            }
        }
    }

    /**
     * ImageJ invert(): v -> 255 - v, restricted to the ROI. On the binary
     * images produced by this harness this is exactly the 0 <-> 255 swap.
     */
    public void invert() {
        Rectangle r = getRoi();
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                set(x, y, 255 - get(x, y));
            }
        }
    }

    /** Converts to 8 bit; when scaling is true the value range is stretched. */
    public ByteProcessor convertToByte(boolean scaling) {
        ByteProcessor out = new ByteProcessor(width, height);
        int min = 255;
        int max = 0;
        if (scaling) {
            Rectangle r = getRoi();
            for (int y = r.y; y < r.y + r.height; y++) {
                for (int x = r.x; x < r.x + r.width; x++) {
                    int v = get(x, y);
                    if (v < min) min = v;
                    if (v > max) max = v;
                }
            }
        }
        Rectangle r = getRoi();
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                int v = get(x, y);
                if (v < 0) v = 0;
                if (v > 255) v = 255;
                if (scaling) {
                    if (max > min) {
                        v = (int) ((v - min) * 255.0 / (max - min) + 0.5);
                    } else {
                        v = 0;
                    }
                }
                out.set(x, y, v);
            }
        }
        return out;
    }

    /** Converts to 32 bit float (values are kept as they are). */
    public FloatProcessor convertToFloatProcessor() {
        FloatProcessor out = new FloatProcessor(width, height);
        Rectangle r = getRoi();
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                out.setf(y * width + x, get(x, y));
            }
        }
        return out;
    }

    /** Converts to an RGB processor (gray images are expanded to R=G=B). */
    public ColorProcessor convertToColorProcessor() {
        ColorProcessor out = new ColorProcessor(width, height);
        Rectangle r = getRoi();
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                int v = get(x, y);
                if (v < 0) v = 0;
                if (v > 255) v = 255;
                out.putPixel(x, y, (v << 16) | (v << 8) | v);
            }
        }
        return out;
    }

    /**
     * Statistics over the ROI. pixelCount is the number of pixels of the ROI
     * (this is what RetFM_J.getThreshold uses); area counts the non zero
     * pixels of the ROI.
     */
    public ImageStatistics getStatistics() {
        ImageStatistics stats = new ImageStatistics();
        Rectangle r = getRoi();
        stats.pixelCount = r.width * r.height;
        long sum = 0;
        long nonZero = 0;
        for (int y = r.y; y < r.y + r.height; y++) {
            for (int x = r.x; x < r.x + r.width; x++) {
                int v = get(x, y);
                sum += v;
                if (v != 0) nonZero++;
            }
        }
        stats.area = nonZero;
        stats.mean = stats.pixelCount == 0 ? 0.0 : (double) sum / stats.pixelCount;
        return stats;
    }
}
