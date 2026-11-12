package ij.plugin.filter;

import ij.ImagePlus;

/** Minimal ImageJ "ExtendedPlugInFilter". */
public interface ExtendedPlugInFilter extends PlugInFilter {

    int showDialog(ImagePlus imp, String command, PlugInFilterRunner pfr);

    void setNPasses(int nPasses);
}
