package ij.gui;

import java.awt.AWTEvent;

/** Minimal ImageJ "DialogListener". */
public interface DialogListener {
    boolean dialogItemChanged(GenericDialog gd, AWTEvent e);
}
