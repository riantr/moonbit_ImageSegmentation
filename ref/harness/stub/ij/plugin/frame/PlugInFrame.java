package ij.plugin.frame;

/**
 * Minimal ImageJ "PlugInFrame".
 *
 * The real class extends java.awt.Frame, and so does this one: the original
 * Multi_Thresholder class is verified against it with reflection, and the
 * JVM verifier needs the frame hierarchy to resolve the AWT calls of that
 * class.
 *
 * The harness never instantiates a frame (it allocates the plugin without
 * running its constructor), so the headless environment is not a problem.
 */
public class PlugInFrame extends java.awt.Frame {

    public PlugInFrame(String title) {
        super(title);
    }

    /** ImageJ closes the frame and releases its resources; a no-op here. */
    public void close() {
    }
}
