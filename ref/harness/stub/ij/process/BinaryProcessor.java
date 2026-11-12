package ij.process;

/**
 * Minimal ImageJ "BinaryProcessor": a 0/255 view over a ByteProcessor.
 */
public class BinaryProcessor extends ImageProcessor {

    private final ByteProcessor processor;

    public BinaryProcessor(ByteProcessor processor) {
        super(processor.getWidth(), processor.getHeight());
        this.processor = processor;
    }

    public Object getPixels() {
        return processor.getPixels();
    }

    public int get(int x, int y) {
        return processor.get(x, y);
    }

    public void set(int x, int y, int v) {
        processor.set(x, y, v);
    }

    public int[] getHistogram() {
        return processor.getHistogram();
    }

    public BinaryProcessor copy() {
        return new BinaryProcessor(processor.copy());
    }

    /** ImageJ semantics: 0 -> 255, 255 -> 0. */
    public void invert() {
        byte[] pixels = (byte[]) processor.getPixels();
        for (int i = 0; i < pixels.length; i++) {
            int v = pixels[i] & 0xff;
            pixels[i] = (byte) (v == 0 ? 255 : (v == 255 ? 0 : 255 - v));
        }
    }
}
