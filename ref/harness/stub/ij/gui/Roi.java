package ij.gui;

/** Minimal ImageJ "Roi" (region of interest). */
public class Roi {

    public static final int RECTANGLE = 1;
    public static final int POLYGON = 2;
    public static final int OVAL = 3;
    public static final int LINE = 4;

    protected int x;
    protected int y;
    protected int width;
    protected int height;

    public Roi(int x, int y, int width, int height) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    public int getX() {
        return x;
    }

    public int getY() {
        return y;
    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }
}
