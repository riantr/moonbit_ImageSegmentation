package ij.io;

import ij.ImagePlus;

/** Minimal ImageJ "FileSaver" (imported by RetFM_J, never executed). */
public class FileSaver {

    private final ImagePlus imp;

    public FileSaver(ImagePlus imp) {
        this.imp = imp;
    }

    public boolean saveAsTiff(String path) {
        return true;
    }

    public ImagePlus getImagePlus() {
        return imp;
    }
}
