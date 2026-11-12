import ij.*;
import ij.plugin.PlugIn;
import siox.*;

public class SIOX_Segmentation implements PlugIn {

	public void run(String arg) {
		if (IJ.versionLessThan("1.43m"))
			return;
		ImagePlus imp = IJ.getImage();
		if (imp.getBitDepth()!=24)
			IJ.error("SOIX", "RGB image required");
		else
			new SegmentationGUI(imp);
	}
}
