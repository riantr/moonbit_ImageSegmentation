package ij;

import ij.gui.Overlay;
import ij.gui.Roi;
import ij.measure.Calibration;
import ij.measure.ImageStatistics;
import ij.process.ImageProcessor;

import java.util.ArrayList;
import java.util.List;

/**
 * Minimal ImageJ "ImagePlus".
 *
 * Every instance that is constructed is appended to ImagePlus.CREATED
 * (construction order), which is how the harness finds the images that the
 * original algorithms produce inside their run() methods.
 */
public class ImagePlus {

    /** All constructed ImagePlus instances, in construction order. */
    public static final List<ImagePlus> CREATED = new ArrayList<ImagePlus>();

    private String title;
    private ImageProcessor processor;
    private Roi roi;
    private Overlay overlay;
    private Calibration calibration;

    public ImagePlus(ImageProcessor processor) {
        this.processor = processor;
        this.title = (processor == null) ? "Image" : ("Image " + processor.getWidth() + "x" + processor.getHeight());
        CREATED.add(this);
    }

    public ImagePlus(String title, ImageProcessor processor) {
        this.title = title;
        this.processor = processor;
        CREATED.add(this);
    }

    public ImagePlus(String title) {
        this.title = title;
        CREATED.add(this);
    }

    public ImageProcessor getProcessor() {
        return processor;
    }

    public void setProcessor(ImageProcessor processor) {
        this.processor = processor;
    }

    public int getWidth() {
        return processor == null ? 0 : processor.getWidth();
    }

    public int getHeight() {
        return processor == null ? 0 : processor.getHeight();
    }

    public String getTitle() {
        return title;
    }

    /**
     * ImageJ semantics: the title without a trailing ".tif" (RATS_ uses it
     * to name its result image).
     */
    public String getShortTitle() {
        String shortTitle = getTitle();
        int index = shortTitle.indexOf(".tif");
        if (index > 0) {
            shortTitle = shortTitle.substring(0, index);
        }
        return shortTitle;
    }

    public boolean isLocked() {
        return false;
    }

    public void lock() {
    }

    public void unlock() {
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public Roi getRoi() {
        return roi;
    }

    public void setRoi(Roi roi) {
        this.roi = roi;
    }

    public Overlay getOverlay() {
        return overlay;
    }

    public void setOverlay(Overlay overlay) {
        this.overlay = overlay;
    }

    public void show() {
    }

    /**
     * ImageJ redraws the window after a change; the harness has no window,
     * so the call only exists to satisfy the original plugins.
     */
    public void updateAndDraw() {
    }

    public void close() {
    }

    public ImageStack getStack() {
        return null;
    }

    public void setCalibration(Object calibration) {
        this.calibration = (Calibration) calibration;
    }

    public Calibration getCalibration() {
        return calibration;
    }

    public Object getWindow() {
        return null;
    }

    public ImageStatistics getStatistics() {
        return processor == null ? new ImageStatistics() : processor.getStatistics();
    }
}
