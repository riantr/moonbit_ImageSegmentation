import ij.*;
import ij.process.*;
import ij.gui.*;
import ij.util.*;
import ij.plugin.filter.*;
import java.awt.*;


public class Quadtree_Demo implements PlugInFilter {
 
 ImagePlus imp;
 
 public int setup(String arg, ImagePlus theImp) {
    if (IJ.versionLessThan("1.41k")) {return DONE;}
    this.imp = theImp;
     return DOES_8G + DOES_16 + DOES_32;
 } 
  
 public void run(ImageProcessor ip){
  
  int[] dim = {imp.getWidth(), imp.getHeight()};
  int minSzPx = (int) dim[0]/16;
  RATSQuadtree qt = new RATSQuadtree(dim, minSzPx);
  int nLevels = qt.countLevels();
  RATSQuadtree[][] q = qt.getLevel(1);
  IJ.log("");
  IJ.log("This first part of the demo draws level 1");
  IJ.log("  which has the 4 children that cover the entire image");
  IJ.log("  In all there are " + nLevels + " levels of quadtrees");
  int wait = 500;
  q[0][0].drawBounds(imp);IJ.wait(wait); 
  q[0][1].drawBounds(imp);IJ.wait(wait); 
  q[1][0].drawBounds(imp);IJ.wait(wait); 
  q[1][1].drawBounds(imp);IJ.wait(wait); 
  
  IJ.log("");
  IJ.log("This second part of the demo shows levels 2 through " + (nLevels-1));
  IJ.log("  with basic info about each leaflet (or child) shown");
  IJ.log("  in the NW (upper left) quadrants");
  for (int i = 2; i<nLevels; i++){
    RATSQuadtree[][] qc = qt.getLevel(i);     
    qc[0][0].drawBounds(imp);printInfo(qc[0][0]);IJ.wait(wait);
    qc[0][1].drawBounds(imp);printInfo(qc[0][1]);IJ.wait(wait);
    qc[1][0].drawBounds(imp);printInfo(qc[1][0]);IJ.wait(wait);
    qc[1][1].drawBounds(imp);printInfo(qc[1][1]);IJ.wait(wait);
  }  
 }// run 
  
 private void printInfo(RATSQuadtree q){
  double[] c = q.getCenter();
  double[] dim = q.getDimDouble();
  double area = dim[0] * dim[1];
  IJ.log("Leaflet belongs to level " + q.getLevel() + " in quadrant " + q.getName());
  IJ.log("  Leaflet centered at [" + c[0] + ", " + c[1] + "]");
  IJ.log("  Mean of pixels = " + IJ.d2s(q.getSumFloat(imp)/area,1));
 }
  
}