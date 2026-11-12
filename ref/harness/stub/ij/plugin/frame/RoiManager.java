package ij.plugin.frame;

import ij.gui.Roi;

import java.util.ArrayList;
import java.util.List;

/** Minimal ImageJ "RoiManager". */
public class RoiManager {

    private static RoiManager instance;

    private final List<Roi> rois = new ArrayList<Roi>();
    private boolean visible = true;

    public RoiManager() {
    }

    public RoiManager(boolean hideWindow) {
        this.visible = !hideWindow;
    }

    public static RoiManager getInstance() {
        if (instance == null) {
            instance = new RoiManager();
        }
        return instance;
    }

    public boolean isVisible() {
        return visible;
    }

    public void setVisible(boolean visible) {
        this.visible = visible;
    }

    public void addRoi(Roi roi) {
        rois.add(roi);
    }

    public int getRoiCount() {
        return rois.size();
    }

    public void runCommand(String command) {
    }
}
