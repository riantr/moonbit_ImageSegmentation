package ij;

/** Minimal ImageJ window manager; no image is ever open. */
public class WindowManager {

    private static ImagePlus current;

    public static int[] getIDList() {
        return new int[0];
    }

    public static ImagePlus getImage(int id) {
        return current;
    }

    public static void setCurrentWindow(Object window) {
    }

    public static void toFront(Object window) {
    }

    public static ImagePlus getCurrentImage() {
        return current;
    }

    public static void setTempCurrentImage(ImagePlus imp) {
        current = imp;
    }
}
