package ij.measure;

/** Minimal ImageJ "Calibration". */
public class Calibration {

    public double pixelWidth = 1.0;
    public double pixelHeight = 1.0;
    public String pixelWidthUnit = "pixel";
    public String pixelHeightUnit = "pixel";

    public String getPixelWidthUnit() {
        return pixelWidthUnit;
    }

    public String getPixelHeightUnit() {
        return pixelHeightUnit;
    }
}
