import ij.IJ;
import ij.ImagePlus;
import ij.process.ByteProcessor;
import ij.process.ColorProcessor;
import ij.process.ImageProcessor;
import ij.process.ShortProcessor;

import siox.SioxSegmentator;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.awt.Rectangle;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Reference harness for the ORIGINAL (unmodified) Java segmentation algorithms.
 *
 *   java -cp out Harness &lt;input.gray&gt; &lt;width&gt; &lt;height&gt; &lt;outdir&gt;
 *
 * &lt;input.gray&gt; holds exactly width*height bytes, one 8 bit grey level per
 * pixel, row major. The harness runs every original algorithm on that image
 * and writes the golden outputs into &lt;outdir&gt;:
 *
 *   scalars.txt            key/value pairs (see SCALAR_KEYS)
 *   otsu_image.raw         8 bit binary image of OtsuThresholding_
 *   multiotsu_region0..3   8 bit region images of Multi_OtsuThreshold (MLEVEL=4)
 *   mixture_image.raw      8 bit binary image of MixtureModeling_
 *   blob4_map.raw          int16 label map of Blob_Labeler (4 connected)
 *   blob8_map.raw          int16 label map of Blob_Labeler (8 connected)
 *   watershed.raw          8 bit binary image of Watershed_Algorithm
 *   densitometry1.rgb.raw  8 bit RGB output of Densitometry_1_Channel_
 *   densitometry3.rgb.raw  8 bit RGB output of Densitometry_3_Channel_
 *   retfm_gray.raw         8 bit grey output of RetFM_J.convertToGrayscale
 *   retfm_<subset>_gray.raw the same for every other selection of the channels
 *   retfm_otsu_image.raw   8 bit image after RetFM_J.getThreshold + threshold + invert
 *   rats_mask.raw          8 bit mask of RATS_ (swapped dimensions!)
 *   siox_cm.raw            float32 confidence matrix of SIOX (little endian)
 *   siox_mask.raw          8 bit mask of SIOX
 */
public class Harness {

    /** The exact key list and order of scalars.txt. */
    private static final String[] SCALAR_KEYS = {
            "otsu.threshold",
            "multiotsu.level",
            "multiotsu.t1",
            "multiotsu.t2",
            "multiotsu.t3",
            "multiotsu.t4",
            "multiotsu.level2.t1",
            "multiotsu.level2.t2",
            "multiotsu.level3.t1",
            "multiotsu.level3.t2",
            "multiotsu.level3.t3",
            "multiotsu.level5.t1",
            "multiotsu.level5.t2",
            "multiotsu.level5.t3",
            "multiotsu.level5.t4",
            "multiotsu.level5.t5",
            "autothreshold.Huang",
            "autothreshold.Intermodes",
            "autothreshold.IsoData",
            "autothreshold.Li",
            "autothreshold.MaxEntropy",
            "autothreshold.Mean",
            "autothreshold.MinError(I)",
            "autothreshold.Minimum",
            "autothreshold.Moments",
            "autothreshold.Otsu",
            "autothreshold.Percentile",
            "autothreshold.RenyiEntropy",
            "autothreshold.Shanbhag",
            "autothreshold.Triangle",
            "autothreshold.Yen",
            "mixture.threshold",
            "mixture.mu1",
            "mixture.variance1",
            "mixture.mu2",
            "mixture.variance2",
            "mixture.errorMin",
            "mixture.diffMu",
            "mixture.directThreshold",
            "mixture.realThreshold",
            "mixture.bits.mu1",
            "mixture.bits.variance1",
            "mixture.bits.mu2",
            "mixture.bits.variance2",
            "mixture.bits.errorMin",
            "mixture.bits.diffMu",
            "mixture.bits.realThreshold",
            "blob4.numberOfLabels",
            "blob4.failed",
            "blob8.numberOfLabels",
            "blob8.failed",
            "blob4.noedge.numberOfLabels",
            "blob4.noedge.failed",
            "blob8.noedge.numberOfLabels",
            "blob8.noedge.failed",
            "blob4.bgcol.numberOfLabels",
            "blob4.bgcol.failed",
            "blob8.bgcol.numberOfLabels",
            "blob8.bgcol.failed",
            "retfm.otsuThreshold",
            "retfm.red.otsuThreshold",
            "retfm.green.otsuThreshold",
            "retfm.blue.otsuThreshold",
            "retfm.rg.otsuThreshold",
            "retfm.rb.otsuThreshold",
            "retfm.gb.otsuThreshold",
            "retfm.none.otsuThreshold",
            "rats.mask.width",
            "rats.mask.height",
            "rats.failed",
            "siox.success",
            "siox.failed"
    };

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("usage: Harness <input.gray> <width> <height> <outdir>");
            System.exit(2);
        }

        File inputFile = new File(args[0]);
        int width = Integer.parseInt(args[1]);
        int height = Integer.parseInt(args[2]);
        File outDir = new File(args[3]);
        if (!outDir.isDirectory() && !outDir.mkdirs()) {
            throw new IOException("cannot create output directory " + outDir);
        }

        byte[] source = readAllBytes(inputFile);
        if (source.length != width * height) {
            throw new IllegalArgumentException("expected " + (width * height) + " bytes in "
                    + inputFile + " but got " + source.length);
        }

        Map<String, String> scalars = new LinkedHashMap<String, String>();

        // ------------------------------------------------------------------
        // OtsuThresholding_ : binary image + threshold from the IJ message
        // ------------------------------------------------------------------
        IJ.MESSAGES.clear();
        ImagePlus.CREATED.clear();
        OtsuThresholding_ otsu = new OtsuThresholding_();
        otsu.run(gray(source, width, height));
        ImagePlus otsuImage = created(width, height, "OtsuThresholding_");
        writeBytes(new File(outDir, "otsu_image.raw"), (byte[]) otsuImage.getProcessor().getPixels());
        String otsuMessage = findMessage("Found threshold : ");
        scalars.put("otsu.threshold", Integer.toString(Integer.parseInt(otsuMessage.substring("Found threshold : ".length()).trim())));

        // ------------------------------------------------------------------
        // Multi_OtsuThreshold : MLEVEL = 4 region images + thresholds
        // ------------------------------------------------------------------
        ImagePlus.CREATED.clear();
        Multi_OtsuThreshold multiOtsu = new Multi_OtsuThreshold();
        multiOtsu.run(gray(source, width, height));
        List<ImagePlus> regions = created(4, width, height, "Multi_OtsuThreshold");
        for (int k = 0; k < 4; k++) {
            writeBytes(new File(outDir, "multiotsu_region" + k + ".raw"),
                    (byte[]) regions.get(k).getProcessor().getPixels());
        }
        // Same code path as the original run(): buildHistogram -> buildLookupTables -> findMaxSigma.
        float[] histogram = new float[256];
        multiOtsu.buildHistogram(histogram, source.clone(), width, height);
        float[][] p = new float[256][256];
        float[][] s = new float[256][256];
        float[][] h = new float[256][256];
        multiOtsu.buildLookupTables(p, s, h, histogram);
        int[] multiThresholds = new int[4];
        multiOtsu.findMaxSigma(4, h, multiThresholds);
        scalars.put("multiotsu.level", "4");
        scalars.put("multiotsu.t1", Integer.toString(multiThresholds[0]));
        scalars.put("multiotsu.t2", Integer.toString(multiThresholds[1]));
        scalars.put("multiotsu.t3", Integer.toString(multiThresholds[2]));
        scalars.put("multiotsu.t4", Integer.toString(multiThresholds[3]));

        // The plugin hard codes MLEVEL = 4, but `findMaxSigma` implements the
        // levels 2, 3 and 5 as well. The port supports them, so the reference
        // has to cover them too - otherwise those branches of the port would
        // never be checked against anything.
        for (int mlevel : new int[]{2, 3, 5}) {
            int[] levelThresholds = new int[mlevel];
            multiOtsu.findMaxSigma(mlevel, h, levelThresholds);
            for (int k = 0; k < mlevel; k++) {
                scalars.put("multiotsu.level" + mlevel + ".t" + (k + 1),
                        Integer.toString(levelThresholds[k]));
            }
        }

        // ------------------------------------------------------------------
        // MixtureModeling_ : binary image + the statistics it prints
        // ------------------------------------------------------------------
        IJ.MESSAGES.clear();
        ImagePlus.CREATED.clear();
        MixtureModeling_ mixture = new MixtureModeling_();
        mixture.run(gray(source, width, height));
        ImagePlus mixtureImage = created(width, height, "MixtureModeling_");
        writeBytes(new File(outDir, "mixture_image.raw"), (byte[]) mixtureImage.getProcessor().getPixels());

        String mu1Message = findMessage("Mu1 : ");
        String mu2Message = findMessage("Mu2 : ");
        String errorMinMessage = findMessage("ErrorMin : ");
        String diffMuMessage = findMessage("Diff Mu : ");
        String directMessage = findMessage("Direct threshold : ");
        String realMessage = findMessage("Real threshold : ");

        String mu1 = between(mu1Message, "Mu1 : ", ", variance1 : ");
        String variance1 = between(mu1Message, ", variance1 : ", null);
        String mu2 = between(mu2Message, "Mu2 : ", ", variance2 : ");
        String variance2 = between(mu2Message, ", variance2 : ", null);
        String errorMin = between(errorMinMessage, "ErrorMin : ", null);
        String diffMu = between(diffMuMessage, "Diff Mu : ", null);
        String directThreshold = between(directMessage, "Direct threshold : ", null);
        String realThreshold = between(realMessage, "Real threshold : ", null);

        // The printed numbers are Float.toString() of the plugin's float fields;
        // parsing them back yields exactly the same float (toString/parseFloat
        // round trip), so the raw bit patterns below are the plugin's bits.
        float mu1Value = Float.parseFloat(mu1);
        float variance1Value = Float.parseFloat(variance1);
        float mu2Value = Float.parseFloat(mu2);
        float variance2Value = Float.parseFloat(variance2);
        float errorMinValue = Float.parseFloat(errorMin);

        scalars.put("mixture.threshold", Integer.toString((int) Float.parseFloat(realThreshold)));
        scalars.put("mixture.mu1", mu1);
        scalars.put("mixture.variance1", variance1);
        scalars.put("mixture.mu2", mu2);
        scalars.put("mixture.variance2", variance2);
        scalars.put("mixture.errorMin", errorMin);
        scalars.put("mixture.diffMu", diffMu);
        scalars.put("mixture.directThreshold", directThreshold);
        scalars.put("mixture.realThreshold", realThreshold);
        scalars.put("mixture.bits.mu1", Integer.toString(Float.floatToRawIntBits(mu1Value)));
        scalars.put("mixture.bits.variance1", Integer.toString(Float.floatToRawIntBits(variance1Value)));
        scalars.put("mixture.bits.mu2", Integer.toString(Float.floatToRawIntBits(mu2Value)));
        scalars.put("mixture.bits.variance2", Integer.toString(Float.floatToRawIntBits(variance2Value)));
        scalars.put("mixture.bits.errorMin", Integer.toString(Float.floatToRawIntBits(errorMinValue)));
        // `Diff Mu` is `mu2 - mu1` in float precision, `Real threshold` is the
        // float that holds the integer the plugin found. Both are floats, so
        // they get a bit pattern of their own - a decimal comparison with a
        // tolerance would hide a difference in the last bit.
        scalars.put("mixture.bits.diffMu",
                Integer.toString(Float.floatToRawIntBits(Float.parseFloat(diffMu))));
        scalars.put("mixture.bits.realThreshold",
                Integer.toString(Float.floatToRawIntBits(Float.parseFloat(realThreshold))));

        // ------------------------------------------------------------------
        // Blob_Labeler : label maps for the 4 and 8 connected neighbourhoods
        // (the optional vectorization step is disabled, the labeling is not)
        //
        // The plugin allocates `int[] labels = new int[size/2]` and reads
        // `labels[i]` for `i` in `0 .. labelColour`. For an image with more
        // labels than `size/2` the read leaves the array and the plugin
        // raises an ArrayIndexOutOfBoundsException (a 1x1 image is the
        // smallest case). The harness catches it and reports the failure
        // the same way it reports a plugin that found no labels: an empty
        // label map and zero labels.
        // ------------------------------------------------------------------
        Field segmentField = Blob_Labeler.class.getDeclaredField("segment");
        segmentField.setAccessible(true);
        segmentField.setBoolean(null, false);
        Field neighb8Field = Blob_Labeler.class.getDeclaredField("neighb8");
        neighb8Field.setAccessible(true);
        Field bgcolField = Blob_Labeler.class.getDeclaredField("bgcol");
        bgcolField.setAccessible(true);
        Field edgeField = Blob_Labeler.class.getDeclaredField("edge");
        edgeField.setAccessible(true);

        // The default configuration of the plugin: background 0 and the edge
        // correction on.
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                false, 0, true, "blob4_map.raw", "blob4.numberOfLabels", "blob4.failed");
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                true, 0, true, "blob8_map.raw", "blob8.numberOfLabels", "blob8.failed");

        // The same plugin without the edge correction: the first row and the
        // first column are not overwritten with the background colour, so the
        // labeling sees the border of the image and finds more labels.
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                false, 0, false, "blob4_noedge_map.raw",
                "blob4.noedge.numberOfLabels", "blob4.noedge.failed");
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                true, 0, false, "blob8_noedge_map.raw",
                "blob8.noedge.numberOfLabels", "blob8.noedge.failed");

        // The same plugin with a background colour of 1: the pixels with the
        // grey level 1 are the background now.
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                false, 1, true, "blob4_bgcol_map.raw",
                "blob4.bgcol.numberOfLabels", "blob4.bgcol.failed");
        runBlob(source, width, height, outDir, scalars, neighb8Field, bgcolField, edgeField,
                true, 1, true, "blob8_bgcol_map.raw",
                "blob8.bgcol.numberOfLabels", "blob8.bgcol.failed");

        // ------------------------------------------------------------------
        // Watershed_Algorithm : binary image
        // ------------------------------------------------------------------
        ImagePlus.CREATED.clear();
        Watershed_Algorithm watershed = new Watershed_Algorithm();
        watershed.run(gray(source, width, height));
        ImagePlus watershedImage = created(width, height, "Watershed_Algorithm");
        writeBytes(new File(outDir, "watershed.raw"),
                (byte[]) watershedImage.getProcessor().getPixels());

        // ------------------------------------------------------------------
        // Densitometry_1_Channel_ / Densitometry_3_Channel_ : RGB output
        //
        // The plugins have three settings that the default run does not use:
        // the binarisation (`blnFill`), the inversion (`blnInvr`), the
        // tolerance (`intTol` and `intRtol` / `intGtol` / `intBtol`) and the
        // region of interest of the image. Every one of them is a parameter of
        // the plugins, so the harness runs them as well.
        // ------------------------------------------------------------------
        Field blnFillField1 = Densitometry_1_Channel_.class.getDeclaredField("blnFill");
        blnFillField1.setAccessible(true);
        Field blnInvrField1 = Densitometry_1_Channel_.class.getDeclaredField("blnInvr");
        blnInvrField1.setAccessible(true);
        Field intTolField1 = Densitometry_1_Channel_.class.getDeclaredField("intTol");
        intTolField1.setAccessible(true);
        Field blnFillField3 = Densitometry_3_Channel_.class.getDeclaredField("blnFill");
        blnFillField3.setAccessible(true);
        Field blnInvrField3 = Densitometry_3_Channel_.class.getDeclaredField("blnInvr");
        blnInvrField3.setAccessible(true);
        Field intRtolField3 = Densitometry_3_Channel_.class.getDeclaredField("intRtol");
        intRtolField3.setAccessible(true);
        Field intGtolField3 = Densitometry_3_Channel_.class.getDeclaredField("intGtol");
        intGtolField3.setAccessible(true);
        Field intBtolField3 = Densitometry_3_Channel_.class.getDeclaredField("intBtol");
        intBtolField3.setAccessible(true);

        ColorProcessor color1 = color(source, width, height);
        new Densitometry_1_Channel_().run(color1);
        writeRgb((int[]) color1.getPixels(), new File(outDir, "densitometry1.rgb.raw"));

        ColorProcessor color3 = color(source, width, height);
        new Densitometry_3_Channel_().run(color3);
        writeRgb((int[]) color3.getPixels(), new File(outDir, "densitometry3.rgb.raw"));

        // the binarised variant: the pixels that do not match are replaced with
        // the inverted background colour
        configure1(blnFillField1, blnInvrField1, intTolField1, true, false, 127);
        configure3(blnFillField3, blnInvrField3, intRtolField3, intGtolField3, intBtolField3,
                true, false, 127, 127, 127);
        ColorProcessor color1Bin = color(source, width, height);
        new Densitometry_1_Channel_().run(color1Bin);
        writeRgb((int[]) color1Bin.getPixels(), new File(outDir, "densitometry1_binary.rgb.raw"));

        ColorProcessor color3Bin = color(source, width, height);
        new Densitometry_3_Channel_().run(color3Bin);
        writeRgb((int[]) color3Bin.getPixels(), new File(outDir, "densitometry3_binary.rgb.raw"));

        // the inverted variant: the decision is the other way round
        configure1(blnFillField1, blnInvrField1, intTolField1, true, true, 127);
        configure3(blnFillField3, blnInvrField3, intRtolField3, intGtolField3, intBtolField3,
                true, true, 127, 127, 127);
        ColorProcessor color1Inv = color(source, width, height);
        new Densitometry_1_Channel_().run(color1Inv);
        writeRgb((int[]) color1Inv.getPixels(), new File(outDir, "densitometry1_inverse.rgb.raw"));

        ColorProcessor color3Inv = color(source, width, height);
        new Densitometry_3_Channel_().run(color3Inv);
        writeRgb((int[]) color3Inv.getPixels(), new File(outDir, "densitometry3_inverse.rgb.raw"));

        // the variant that only works on a part of the image: the plugins
        // iterate the ROI, so a run on the whole image never reaches that
        // branch
        configure1(blnFillField1, blnInvrField1, intTolField1, false, false, 127);
        ColorProcessor color1Roi = color(source, width, height);
        color1Roi.setRoi(densitometryRoi(width, height));
        new Densitometry_1_Channel_().run(color1Roi);
        writeRgb((int[]) color1Roi.getPixels(), new File(outDir, "densitometry1_roi.rgb.raw"));

        // the variant with a different tolerance: the tolerance is a parameter
        // of the plugins, and the three channel tolerances are different from
        // each other so that a mix-up of the channels would show up
        configure1(blnFillField1, blnInvrField1, intTolField1, false, false, 64);
        configure3(blnFillField3, blnInvrField3, intRtolField3, intGtolField3, intBtolField3,
                false, false, 64, 32, 16);
        ColorProcessor color1Tol = color(source, width, height);
        new Densitometry_1_Channel_().run(color1Tol);
        writeRgb((int[]) color1Tol.getPixels(), new File(outDir, "densitometry1_tol.rgb.raw"));

        ColorProcessor color3Tol = color(source, width, height);
        new Densitometry_3_Channel_().run(color3Tol);
        writeRgb((int[]) color3Tol.getPixels(), new File(outDir, "densitometry3_tol.rgb.raw"));

        // ------------------------------------------------------------------
        // RetFM_J : grayscale conversion + Otsu threshold
        //
        // The plugin converts the colour image to grayscale, computes the Otsu
        // threshold of THAT image and thresholds it (RetFM_J.java:190-196).
        // The threshold therefore belongs to the converted grayscale image
        // and not to the grey source: with a neutral colour image the two are
        // the same, with the non-neutral colours of `color()` they are not.
        // ------------------------------------------------------------------
        RetFM_J retfm = new RetFM_J();
        Field useChannelsField = RetFM_J.class.getDeclaredField("useChannels");
        useChannelsField.setAccessible(true);
        useChannelsField.set(retfm, new boolean[]{true, true, true});

        ImageProcessor retfmGray = retfm.convertToGrayscale(color(source, width, height));
        writeBytes(new File(outDir, "retfm_gray.raw"), (byte[]) retfmGray.getPixels());

        int retfmThreshold = retfm.getThreshold(retfmGray);
        scalars.put("retfm.otsuThreshold", Integer.toString(retfmThreshold));

        ImageProcessor retfmOtsu = new ByteProcessor(width, height,
                ((byte[]) retfmGray.getPixels()).clone());
        retfmOtsu.threshold(retfmThreshold);
        retfmOtsu.invert();
        writeBytes(new File(outDir, "retfm_otsu_image.raw"), (byte[]) retfmOtsu.getPixels());

        // The same helpers with another selection of the channels: the channel
        // selection is a branch of `convertToGrayscale` (the divisor is the
        // number of the selected channels and every selected channel
        // contributes its own plane), and the threshold of a different
        // grayscale image is a different one. The empty selection divides by
        // zero: the product becomes NaN and the original returns an all zero
        // image.
        String[][] retfmVariants = {
                {"red", "1,0,0"},
                {"green", "0,1,0"},
                {"blue", "0,0,1"},
                {"rg", "1,1,0"},
                {"rb", "1,0,1"},
                {"gb", "0,1,1"},
                {"none", "0,0,0"},
        };
        for (String[] variant : retfmVariants) {
            String[] flags = variant[1].split(",");
            useChannelsField.set(retfm, new boolean[]{
                    "1".equals(flags[0]), "1".equals(flags[1]), "1".equals(flags[2])});
            ImageProcessor gray = retfm.convertToGrayscale(color(source, width, height));
            writeBytes(new File(outDir, "retfm_" + variant[0] + "_gray.raw"),
                    (byte[]) gray.getPixels());
            scalars.put("retfm." + variant[0] + ".otsuThreshold",
                    Integer.toString(retfm.getThreshold(gray)));
        }

        // ------------------------------------------------------------------
        // AutoThresholder : the 15 methods of AutoThresholder.getMethods()
        // ------------------------------------------------------------------
        ByteProcessor grayImage = gray(source, width, height);
        int[] imageHistogram = grayImage.getHistogram();
        AutoThresholder autoThresholder = new AutoThresholder();
        for (String method : AutoThresholder.getMethods()) {
            scalars.put("autothreshold." + method,
                    Integer.toString(autoThresholder.getThreshold(method, imageHistogram)));
        }

        // ------------------------------------------------------------------
        // RATS_ : regionalised automatic threshold selection (Wilkinson 2000)
        //
        // The plugin is driven with its own defaults: sigma = 25.0,
        // lambda = 3.0 and the minimum leaf size min(floor(w/5), floor(h/5))
        // that RATS_ derives from the image dimensions. The mask image has
        // the dimensions of the input swapped (its width is the input
        // height); that is the behaviour of the plugin and is preserved.
        // ------------------------------------------------------------------
        int ratsWidth = 0;
        int ratsHeight = 0;
        byte[] ratsMask = new byte[0];
        int ratsFailed = 0;
        try {
            ImagePlus.CREATED.clear();
            ByteProcessor ratsInput = gray(source, width, height);
            ImagePlus ratsSource = new ImagePlus("rats-input", ratsInput);
            int createdBefore = ImagePlus.CREATED.size();
            RATS_ rats = new RATS_();
            rats.setup("", ratsSource);
            rats.run(ratsInput);
            if (ImagePlus.CREATED.size() <= createdBefore) {
                throw new IllegalStateException("RATS_ did not create a result image");
            }
            ImageProcessor ratsResult = created(height, width, "RATS_").getProcessor();
            ratsWidth = ratsResult.getWidth();
            ratsHeight = ratsResult.getHeight();
            ratsMask = (byte[]) ratsResult.getPixels();
        } catch (Throwable failure) {
            System.err.println("harness: RATS_ failed: " + failure.getClass().getName()
                    + ": " + failure.getMessage());
            failure.printStackTrace();
            ratsWidth = 0;
            ratsHeight = 0;
            ratsMask = new byte[0];
            ratsFailed = 1;
        }
        writeBytes(new File(outDir, "rats_mask.raw"), ratsMask);
        scalars.put("rats.mask.width", Integer.toString(ratsWidth));
        scalars.put("rats.mask.height", Integer.toString(ratsHeight));
        scalars.put("rats.failed", Integer.toString(ratsFailed));

        // ------------------------------------------------------------------
        // SIOX : Simple Interactive Object Extraction
        //
        // The confidence matrix is built deterministically from the grey
        // levels: v <= 63 is a known background pixel (0.0), v >= 192 a
        // known foreground pixel (1.0) and everything in between is unknown
        // (0.5). segmentate() overwrites the matrix with its result.
        // ------------------------------------------------------------------
        int[] argb = new int[width * height];
        float[] cm = new float[width * height];
        for (int i = 0; i < argb.length; i++) {
            int v = source[i] & 0xff;
            argb[i] = packColor(v);
            cm[i] = (v <= 63) ? 0.0f : ((v >= 192) ? 1.0f : 0.5f);
        }
        int sioxSuccess = 0;
        int sioxFailed = 0;
        try {
            SioxSegmentator siox = new SioxSegmentator(width, height,
                    new float[]{0.64f, 1.28f, 2.56f});
            sioxSuccess = siox.segmentate(argb, cm, 1, 4.0) ? 1 : 0;
        } catch (Throwable failure) {
            System.err.println("harness: SIOX failed: " + failure.getClass().getName()
                    + ": " + failure.getMessage());
            failure.printStackTrace();
            sioxSuccess = 0;
            sioxFailed = 1;
        }
        writeBytes(new File(outDir, "siox_cm.raw"), floatArrayToLeBytes(cm));
        writeBytes(new File(outDir, "siox_mask.raw"), confidenceMask(cm));
        scalars.put("siox.success", Integer.toString(sioxSuccess));
        scalars.put("siox.failed", Integer.toString(sioxFailed));

        // ------------------------------------------------------------------
        // Multi_Thresholder : the level mapping helpers of the plugin
        // ------------------------------------------------------------------
        writeMultiThresholder(new File(outDir, "multithresholder.txt"));

        // ------------------------------------------------------------------
        // scalars.txt
        // ------------------------------------------------------------------
        StringBuilder sb = new StringBuilder();
        for (String key : SCALAR_KEYS) {
            String value = scalars.get(key);
            if (value == null) {
                throw new IllegalStateException("missing scalar " + key);
            }
            sb.append(key).append(' ').append(value).append('\n');
        }
        writeBytes(new File(outDir, "scalars.txt"), sb.toString().getBytes("UTF-8"));

        System.out.println("harness: wrote " + outDir.getAbsolutePath());
    }

    // ----------------------------------------------------------------------
    // helpers
    // ----------------------------------------------------------------------

    private static byte[] readAllBytes(File file) throws IOException {
        return Files.readAllBytes(file.toPath());
    }

    /**
     * The ARGB value of the colour that renders the grey level `v`.
     *
     * R = v, G = 3v/4, B = 255 - v: the channels are distinguishable, so a
     * plugin that uses the wrong channel cannot go unnoticed.
     */
    private static int packColor(int v) {
        int r = v;
        int g = (v * 3) / 4;
        int b = 255 - v;
        return 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    /** A fresh 8 bit copy of the source image (the algorithms mutate their input). */
    private static ByteProcessor gray(byte[] source, int width, int height) {
        return new ByteProcessor(width, height, source.clone());
    }

    /**
     * A fresh RGB copy of the source image.
     *
     * The colour channels are deliberately NOT neutral: the grey level `v` is
     * rendered as `R = v`, `G = 3v/4` and `B = 255 - v`. A neutral copy
     * (R = G = B) would let a plugin that mixes up the channels pass the
     * verification, because every channel would carry the same value. The
     * MoonBit CLI builds its RGB image the same way (see `gray_to_rgb` in
     * cmd/seg/main.mbt), so both sides see exactly the same colours.
     */
    private static ColorProcessor color(byte[] source, int width, int height) {
        int[] pixels = new int[width * height];
        for (int i = 0; i < pixels.length; i++) {
            pixels[i] = packColor(source[i] & 0xff);
        }
        return new ColorProcessor(width, height, pixels);
    }

    private static ImagePlus lastCreated() {
        return lastCreated(1).get(0);
    }

    /**
     * The image a plugin created, checked against the expected size.
     *
     * The harness takes the last image a plugin created. Without this check a
     * plugin that creates an image of the wrong size - or an image before it
     * fills it - would silently contribute the wrong pixels to the golden
     * output.
     */
    private static ImagePlus created(int width, int height, String what) {
        ImagePlus image = lastCreated();
        ImageProcessor processor = image.getProcessor();
        if (processor.getWidth() != width || processor.getHeight() != height) {
            throw new IllegalStateException(what + " produced an image of "
                    + processor.getWidth() + "x" + processor.getHeight()
                    + " instead of " + width + "x" + height);
        }
        return image;
    }

    /**
     * The `count` images a plugin created, each checked against the expected
     * size.
     */
    private static List<ImagePlus> created(int count, int width, int height, String what) {
        List<ImagePlus> images = lastCreated(count);
        for (int k = 0; k < count; k++) {
            ImageProcessor processor = images.get(k).getProcessor();
            if (processor.getWidth() != width || processor.getHeight() != height) {
                throw new IllegalStateException(what + " produced the image " + k
                        + " with the size " + processor.getWidth() + "x"
                        + processor.getHeight() + " instead of " + width + "x" + height);
            }
        }
        return images;
    }

    /**
     * Runs `Blob_Labeler` with the given background colour and edge
     * correction and writes the label map, the label count and the failure
     * flag.
     *
     * The plugin reads its background colour and its edge correction from
     * static fields, so they are set before the run. A run that raises an
     * exception is reported the same way the harness reports the default
     * configuration: an empty label map, no labels and `failed = 1`.
     */
    private static void runBlob(
            byte[] source, int width, int height, File outDir,
            Map<String, String> scalars,
            Field neighb8Field, Field bgcolField, Field edgeField,
            boolean eightConnected, int bgcol, boolean edgeCorrection,
            String fileName, String labelKey, String failedKey) throws IOException {
        try {
            neighb8Field.setBoolean(null, eightConnected);
            bgcolField.setInt(null, bgcol);
            edgeField.setBoolean(null, edgeCorrection);
            Blob_Labeler blob = new Blob_Labeler();
            ImagePlus image = null;
            int failed = 0;
            try {
                blob.run(gray(source, width, height));
                image = blob.getResult();
            } catch (Throwable failure) {
                System.err.println("harness: Blob_Labeler failed: "
                        + failure.getClass().getName() + ": " + failure.getMessage());
                image = null;
                failed = 1;
            }
            scalars.put(failedKey, Integer.toString(failed));
            if (image == null) {
                writeShortMap(new short[width * height], new File(outDir, fileName));
                scalars.put(labelKey, "0");
            } else {
                writeShortMap((short[]) image.getProcessor().getPixels(),
                        new File(outDir, fileName));
                scalars.put(labelKey, Integer.toString(labelCount(image.getTitle())));
            }
        } catch (IllegalAccessException e) {
            throw new IllegalStateException("cannot configure Blob_Labeler", e);
        }
    }

    /**
     * Sets the static fields of the 1-channel densitometry plugin.
     *
     * The plugin reads its settings from static fields, so a field that is
     * left over from an earlier run would silently change the next one.
     * Every run therefore sets **all** of them explicitly.
     */
    private static void configure1(
            Field blnFill, Field blnInvr, Field intTol,
            boolean fill, boolean inverse, int tolerance) throws IllegalAccessException {
        blnFill.setBoolean(null, fill);
        blnInvr.setBoolean(null, inverse);
        intTol.setInt(null, tolerance);
    }

    /**
     * Sets the static fields of the 3-channel densitometry plugin.
     *
     * See `configure1`: every run sets all of the fields explicitly.
     */
    private static void configure3(
            Field blnFill, Field blnInvr,
            Field intRtol, Field intGtol, Field intBtol,
            boolean fill, boolean inverse,
            int redTolerance, int greenTolerance, int blueTolerance)
            throws IllegalAccessException {
        blnFill.setBoolean(null, fill);
        blnInvr.setBoolean(null, inverse);
        intRtol.setInt(null, redTolerance);
        intGtol.setInt(null, greenTolerance);
        intBtol.setInt(null, blueTolerance);
    }

    /**
     * The region of interest the densitometry variant works on: the middle
     * half of the image (at least one pixel).
     *
     * The plugins only iterate the ROI of the image, so a run on the whole
     * image never reaches that branch. The MoonBit CLI computes the same
     * rectangle (see `densitometry_roi` in cmd/seg/main.mbt).
     */
    private static Rectangle densitometryRoi(int width, int height) {        int x = width / 4;
        int y = height / 4;
        int w = Math.max(1, width / 2);
        int h = Math.max(1, height / 2);
        if (x + w > width) {
            w = width - x;
        }
        if (y + h > height) {
            h = height - y;
        }
        return new Rectangle(x, y, w, h);
    }

    private static List<ImagePlus> lastCreated(int count) {
        List<ImagePlus> created = ImagePlus.CREATED;
        if (created.size() < count) {
            throw new IllegalStateException("expected " + count
                    + " created images but got " + created.size());
        }
        return new ArrayList<ImagePlus>(created.subList(created.size() - count, created.size()));
    }

    /** The first recorded IJ message that starts with the given prefix. */
    private static String findMessage(String prefix) {
        for (String message : IJ.MESSAGES) {
            if (message.startsWith(prefix)) {
                return message;
            }
        }
        throw new IllegalStateException("no IJ message starting with '" + prefix + "' in " + IJ.MESSAGES);
    }

    /** The substring between two markers, trimmed. */
    private static String between(String message, String start, String end) {
        int from = message.indexOf(start);
        if (from < 0) {
            throw new IllegalStateException("missing '" + start + "' in: " + message);
        }
        from += start.length();
        int to = (end == null) ? -1 : message.indexOf(end, from);
        String value = (to < 0) ? message.substring(from) : message.substring(from, to);
        return value.trim();
    }

    /** Blob_Labeler names its result image "blobs 4c <n>" / "blobs 8c <n>". */
    private static int labelCount(String title) {
        int index = title.lastIndexOf(' ');
        return Integer.parseInt(title.substring(index + 1).trim());
    }

    private static void writeBytes(File file, byte[] bytes) throws IOException {
        FileOutputStream out = new FileOutputStream(file);
        try {
            out.write(bytes);
            out.flush();
        } finally {
            out.close();
        }
    }

    /** Little endian int16 label map. */
    private static void writeShortMap(short[] pixels, File file) throws IOException {
        byte[] bytes = new byte[pixels.length * 2];
        for (int i = 0; i < pixels.length; i++) {
            int value = pixels[i] & 0xffff;
            bytes[2 * i] = (byte) (value & 0xff);
            bytes[2 * i + 1] = (byte) ((value >> 8) & 0xff);
        }
        writeBytes(file, bytes);
    }

    /** Packed 0x00RRGGBB pixels dumped as R,G,B bytes. */
    private static void writeRgb(int[] pixels, File file) throws IOException {
        byte[] bytes = new byte[pixels.length * 3];
        for (int i = 0; i < pixels.length; i++) {
            int c = pixels[i];
            bytes[3 * i] = (byte) ((c >> 16) & 0xff);
            bytes[3 * i + 1] = (byte) ((c >> 8) & 0xff);
            bytes[3 * i + 2] = (byte) (c & 0xff);
        }
        writeBytes(file, bytes);
    }

    /** The float values as little endian float32 (Float.floatToRawIntBits). */
    private static byte[] floatArrayToLeBytes(float[] values) {
        byte[] bytes = new byte[values.length * 4];
        for (int i = 0; i < values.length; i++) {
            int bits = Float.floatToRawIntBits(values[i]);
            bytes[4 * i] = (byte) (bits & 0xff);
            bytes[4 * i + 1] = (byte) ((bits >> 8) & 0xff);
            bytes[4 * i + 2] = (byte) ((bits >> 16) & 0xff);
            bytes[4 * i + 3] = (byte) ((bits >> 24) & 0xff);
        }
        return bytes;
    }

    /** 255 for every confidence of at least 0.5, 0 for every other one. */
    private static byte[] confidenceMask(float[] values) {
        byte[] bytes = new byte[values.length];
        for (int i = 0; i < values.length; i++) {
            bytes[i] = (values[i] >= 0.5f) ? (byte) 255 : (byte) 0;
        }
        return bytes;
    }

    // ----------------------------------------------------------------------
    // Multi_Thresholder
    // ----------------------------------------------------------------------

    /** The processor kinds of the Multi_Thresholder test matrix. */
    private static final String[] MT_KINDS = { "byte", "short" };

    /** The value range of the two processor kinds. */
    private static final double[] MT_MINS = { 0.0, 0.0 };
    private static final double[] MT_MAXS = { 255.0, 65535.0 };

    /** The thresholds the test matrix runs through. */
    private static final double[] MT_THRESHOLDS = { 0.0, 73.0, 128.0, 255.0 };

    /**
     * Drives the level mapping helpers of the original Multi_Thresholder
     * plugin and writes their results.
     *
     * The plugin is a GUI frame whose constructor builds a window. The
     * harness allocates the instance WITHOUT running that constructor, so
     * that only the four helper methods are exercised; the class itself is
     * the *original* compiled one, taken from the plugin jar.
     *
     * The two fields the methods read are set for every case: the "dark
     * background" check box and the "inverted LUT" flag.
     *
     * Every result is written as the raw IEEE-754 bits of the double, so
     * that the MoonBit port can be compared byte for byte.
     */
    private static void writeMultiThresholder(File file) throws Exception {
        Class<?> pluginClass = Class.forName("Multi_Thresholder");
        Object plugin = allocateWithoutConstructor(pluginClass);

        Field darkField = pluginClass.getDeclaredField("darkBackground");
        darkField.setAccessible(true);
        Field invertedField = pluginClass.getDeclaredField("invertedLut");
        invertedField.setAccessible(true);

        Method scaleUp = pluginClass.getDeclaredMethod("scaleUp", ImageProcessor.class, double.class);
        Method scaleDown = pluginClass.getDeclaredMethod("scaleDown", ImageProcessor.class, double.class);
        Method scaleUpAndSet = pluginClass.getDeclaredMethod("scaleUpAndSet", ImageProcessor.class, double.class, double.class);
        Method setThreshold = pluginClass.getDeclaredMethod("setThreshold", double.class, ImagePlus.class);
        scaleUp.setAccessible(true);
        scaleDown.setAccessible(true);
        scaleUpAndSet.setAccessible(true);
        setThreshold.setAccessible(true);

        StringBuilder sb = new StringBuilder();
        for (int kind = 0; kind < MT_KINDS.length; kind++) {
            String name = MT_KINDS[kind];
            boolean isByte = (kind == 0);
            double max = MT_MAXS[kind];
            for (int t = 0; t < MT_THRESHOLDS.length; t++) {
                double threshold = MT_THRESHOLDS[t];
                String head = name + " t=" + (int) threshold;

                ImageProcessor ip = newProcessor(isByte);
                sb.append(head).append(" scaleUp(0,").append((int) max).append(") => ")
                        .append(bits((Double) scaleUp.invoke(plugin, ip, threshold))).append('\n');

                ip = newProcessor(isByte);
                sb.append(head).append(" scaleDown(0,").append((int) max).append(") => ")
                        .append(bits((Double) scaleDown.invoke(plugin, ip, threshold))).append('\n');

                ip = newProcessor(isByte);
                scaleUpAndSet.invoke(plugin, ip, 0.0, threshold);
                sb.append(head).append(" scaleUpAndSet(0,").append((int) threshold).append(") => ")
                        .append(bits(ip.getMinThreshold())).append(' ')
                        .append(bits(ip.getMaxThreshold())).append('\n');

                ip = newProcessor(isByte);
                scaleUpAndSet.invoke(plugin, ip, threshold, max);
                sb.append(head).append(" scaleUpAndSet(").append((int) threshold).append(",")
                        .append((int) max).append(") => ")
                        .append(bits(ip.getMinThreshold())).append(' ')
                        .append(bits(ip.getMaxThreshold())).append('\n');

                ip = newProcessor(isByte);
                scaleUpAndSet.invoke(plugin, ip, ImageProcessor.NO_THRESHOLD, max);
                sb.append(head).append(" scaleUpAndSet(NO_THRESHOLD,").append((int) max).append(") => ")
                        .append(bits(ip.getMinThreshold())).append(' ')
                        .append(bits(ip.getMaxThreshold())).append('\n');

                for (int dark = 0; dark < 2; dark++) {
                    for (int inverted = 0; inverted < 2; inverted++) {
                        java.awt.Checkbox box = new java.awt.Checkbox("Dark Background");
                        box.setState(dark != 0);
                        darkField.set(plugin, box);
                        invertedField.setBoolean(plugin, inverted != 0);
                        ImageProcessor target = newProcessor(isByte);
                        ImagePlus imp = new ImagePlus("multithresholder", target);
                        setThreshold.invoke(plugin, threshold, imp);
                        sb.append(head).append(" setThreshold(dark=").append(dark)
                                .append(",inverted=").append(inverted).append(") => ")
                                .append(bits(target.getMinThreshold())).append(' ')
                                .append(bits(target.getMaxThreshold())).append('\n');
                    }
                }
            }
        }
        writeBytes(file, sb.toString().getBytes("UTF-8"));
    }

    /** A fresh processor of the requested kind. */
    private static ImageProcessor newProcessor(boolean isByte) {
        return isByte ? new ByteProcessor(1, 1) : new ShortProcessor(1, 1);
    }

    /**
     * Allocates an instance of the class without running any constructor.
     *
     * The Multi_Thresholder plugin is a GUI frame; the harness only needs
     * its four helper methods, so the window building constructor is
     * skipped.
     */
    private static Object allocateWithoutConstructor(Class<?> cls) throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field theUnsafe = unsafeClass.getDeclaredField("theUnsafe");
        theUnsafe.setAccessible(true);
        Object unsafe = theUnsafe.get(null);
        Method allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        return allocate.invoke(unsafe, cls);
    }

    /** The raw IEEE-754 bits of a double, as 16 hex digits. */
    private static String bits(double value) {
        String hex = Long.toHexString(Double.doubleToRawLongBits(value));
        StringBuilder sb = new StringBuilder();
        for (int i = hex.length(); i < 16; i++) {
            sb.append('0');
        }
        return sb.append(hex).toString();
    }
}
