import ij.process.ByteProcessor;
import ij.process.FloatProcessor;

import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

/**
 * Diagnostic (NOT part of the harness): compares the quadtree leaf layout of
 * the ORIGINAL RATS_ plugin with the layout that the MoonBit port uses.
 *
 * The original orders the leaflets of a level quadrant wise
 * (RATSQuadtree.getLevel: NW | NE / SW | SE), while the MoonBit port builds
 * its levels in "push order" (for every parent: nw, ne, sw, se) but indexes
 * the flat array row major. This probe computes the resulting mask both ways
 * and compares it with a reference mask file.
 *
 * usage: RatsLayoutProbe <input.gray> <width> <height> <referenceMask.raw>
 */
public class RatsLayoutProbe {

    private static final double SIGMA = 25.0;
    private static final double LAMBDA = 3.0;

    public static void main(String[] args) throws Exception {
        byte[] source = Files.readAllBytes(new File(args[0]).toPath());
        int width = Integer.parseInt(args[1]);
        int height = Integer.parseInt(args[2]);
        byte[] reference = Files.readAllBytes(new File(args[3]).toPath());

        ByteProcessor ip = new ByteProcessor(width, height, source.clone());

        // ---- fillArrays + gradientMHFW (copied from RATS_) ----
        float[][] p = new float[width][height];
        float[][] top = new float[width][height];
        float[][] bot = new float[width][height];
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                p[x][y] = ip.getPixelValue(x, y);
            }
        }
        float scale = 1.0f / 16.0f;
        float lambdasigma = (float) (LAMBDA * SIGMA * LAMBDA * SIGMA);
        float two = 2.0f;
        int wm1 = width - 1;
        int hm1 = height - 1;
        for (int y = 0; y < height; y++) {
            int yU, yD;
            if ((y % hm1) == 0) {
                yU = y - ((y == 0) ? 0 : 1);
                yD = y + ((y == hm1) ? 0 : 1);
            } else {
                yU = y - 1;
                yD = y + 1;
            }
            for (int x = 0; x < width; x++) {
                int xL, xR;
                if ((x % wm1) == 0) {
                    xL = x - ((x == 0) ? 0 : 1);
                    xR = x + ((x == wm1) ? 0 : 1);
                } else {
                    xL = x - 1;
                    xR = x + 1;
                }
                float wx = p[xL][yU] - p[xL][yD] + two * (p[x][yU] - p[x][yD]) + p[xR][yU] - p[xR][yD];
                float wy = p[xL][yU] - p[xR][yU] + two * (p[xL][y] - p[xR][y]) + p[xL][yD] - p[xR][yD];
                float tempG = (wx * wx + wy * wy) * scale;
                if (tempG > lambdasigma) {
                    bot[x][y] = tempG;
                    top[x][y] = p[x][y] * tempG;
                }
            }
        }

        int[] dim = {width, height};
        double[] minSzPx = {(double) ((int) dim[0] / 5.0), (double) ((int) dim[1] / 5.0)};
        if (minSzPx[0] < minSzPx[1]) {
            minSzPx[1] = minSzPx[0];
        } else {
            minSzPx[0] = minSzPx[1];
        }
        RATSQuadtree qtTop = new RATSQuadtree(dim, minSzPx);
        RATSQuadtree qtBot = new RATSQuadtree(dim, minSzPx);
        FloatProcessor topIp = new FloatProcessor(top);
        qtTop.fillWithSums(topIp);
        FloatProcessor botIp = new FloatProcessor(bot);
        qtBot.fillWithSums(botIp);

        int depth = qtTop.countLevels();
        float test = (float) (3.0 * LAMBDA * SIGMA * LAMBDA * SIGMA);

        // ---- layout A: the original (quadrant wise) ----
        RATSQuadtree[][] qTop = qtTop.getLevel(depth - 1);
        RATSQuadtree[][] qBot = qtBot.getLevel(depth - 1);
        int n = qTop.length;
        float[][] gridA = new float[n][n];
        for (int v = 0; v < n; v++) {
            for (int u = 0; u < n; u++) {
                gridA[v][u] = ratsThresh(qTop[v][u], qBot[v][u], test);
            }
        }

        // ---- layout B: push order, indexed row major (the MoonBit port) ----
        List<List<RATSQuadtree>> levelsTop = pushOrderLevels(qtTop);
        List<List<RATSQuadtree>> levelsBot = pushOrderLevels(qtBot);
        int leafCols = (int) Math.sqrt(levelsTop.get(levelsTop.size() - 1).size());
        float[][] gridB = new float[leafCols][leafCols];
        for (int row = 0; row < leafCols; row++) {
            for (int col = 0; col < leafCols; col++) {
                gridB[row][col] = moonbitThresh(levelsTop, levelsBot, row, col, test);
            }
        }

        byte[] maskA = resize(gridA, p, width, height);
        byte[] maskB = resize(gridB, p, width, height);

        System.out.println("levels(depth)=" + depth + " leaf grid=" + leafCols + "x" + leafCols);
        System.out.println("original layout  vs reference : " + diff(maskA, reference));
        System.out.println("moonbit  layout  vs reference : " + diff(maskB, reference));
        System.out.println("original layout  vs moonbit   : " + diff(maskA, maskB));
        System.out.println("grid A (original):");
        print(gridA);
        System.out.println("grid B (moonbit) :");
        print(gridB);
    }

    /** The level arrays in push order (nw, ne, sw, se per parent). */
    private static List<List<RATSQuadtree>> pushOrderLevels(RATSQuadtree root) {
        List<List<RATSQuadtree>> levels = new ArrayList<List<RATSQuadtree>>();
        List<RATSQuadtree> current = new ArrayList<RATSQuadtree>();
        current.add(root);
        levels.add(current);
        while (true) {
            List<RATSQuadtree> next = new ArrayList<RATSQuadtree>();
            boolean anySplit = false;
            for (int i = 0; i < current.size(); i++) {
                RATSQuadtree node = current.get(i);
                RATSQuadtree[][] children = node.getChildren();
                if (children[0][0] != null) {
                    anySplit = true;
                    next.add(children[0][0]);
                    next.add(children[0][1]);
                    next.add(children[1][0]);
                    next.add(children[1][1]);
                } else {
                    next.add(node);
                }
            }
            levels.add(next);
            current = next;
            if (!anySplit) {
                break;
            }
        }
        return levels;
    }

    /** The MoonBit port's walk up the tree: the parent is (row/2, col/2). */
    private static float moonbitThresh(List<List<RATSQuadtree>> levelsTop, List<List<RATSQuadtree>> levelsBot,
                                        int row, int col, float test) {
        int level = levelsTop.size() - 1;
        int r = row;
        int c = col;
        float result = -1.0f;
        boolean running = true;
        while (running) {
            int cols = (int) Math.sqrt(levelsTop.get(level).size());
            RATSQuadtree nodeTop = levelsTop.get(level).get(r * cols + c);
            RATSQuadtree nodeBot = levelsBot.get(level).get(r * cols + c);
            float topV = nodeTop.getSumFloat();
            float botV = nodeBot.getSumFloat();
            if (botV > test) {
                result = topV / botV;
                running = false;
            } else if (level == 0) {
                result = -1.0f;
                running = false;
            } else {
                level = level - 1;
                r = r / 2;
                c = c / 2;
            }
        }
        return result;
    }

    /** The original RATS_.ratsThresh. */
    private static float ratsThresh(RATSQuadtree qTop, RATSQuadtree qBot, float test) {
        float topV = qTop.getSumFloat();
        float botV = qBot.getSumFloat();
        if (botV > test) {
            return topV / botV;
        } else if (qTop.getLevel() == 0) {
            return -1.0f;
        } else {
            return ratsThresh(qTop.getParent(), qBot.getParent(), test);
        }
    }

    /** The original RATS_.resize, with the FloatProcessor(float[][]) semantics. */
    private static byte[] resize(float[][] in, float[][] p, int width, int height) {
        int oh = height;
        int ow = width;
        int iw = in.length;
        int ih = in[0].length;
        float[][] out = new float[ow][oh];
        float[] sx = new float[ow];
        float[] sy = new float[oh];
        int[] ix = new int[ow];
        int[] iy = new int[oh];
        for (int x = 0; x < ow; x++) {
            sx[x] = ((float) x) / ((float) (ow - 1)) * (iw - 1);
            ix[x] = (int) sx[x];
        }
        sx[ow - 1] = sx[ow - 2] + 0.99f * (sx[ow - 1] - sx[ow - 2]);
        ix[ow - 1] = (int) sx[ow - 1];
        for (int y = 0; y < oh; y++) {
            sy[y] = ((float) y) / ((float) (oh - 1)) * (ih - 1);
            iy[y] = (int) sy[y];
        }
        sy[oh - 1] = sy[oh - 2] + 0.99f * (sy[oh - 1] - sy[oh - 2]);
        iy[oh - 1] = (int) sy[oh - 1];
        for (int x = 0; x < ow; x++) {
            for (int y = 0; y < oh; y++) {
                float dx = (ix[x] + 1 - sx[x]) * in[ix[x]][iy[y]] + (sx[x] - ix[x]) * in[ix[x] + 1][iy[y]];
                float gx = (ix[x] + 1 - sx[x]) * in[ix[x]][iy[y] + 1] + (sx[x] - ix[x]) * in[ix[x] + 1][iy[y] + 1];
                float r = (iy[y] + 1 - sy[y]) * dx + (sy[y] - iy[y]) * gx;
                if (r < p[x][y]) {
                    out[x][y] = 255.0f;
                }
            }
        }
        // FloatProcessor(out): width = out[0].length, height = out.length
        int fpWidth = out[0].length;
        int fpHeight = out.length;
        byte[] mask = new byte[fpWidth * fpHeight];
        for (int row = 0; row < fpHeight; row++) {
            for (int col = 0; col < fpWidth; col++) {
                float v = out[row][col];
                mask[row * fpWidth + col] = (byte) (v > 127.0f ? 255 : 0);
            }
        }
        return mask;
    }

    private static String diff(byte[] a, byte[] b) {
        int n = 0;
        int first = -1;
        for (int i = 0; i < Math.min(a.length, b.length); i++) {
            if (a[i] != b[i]) {
                n++;
                if (first < 0) {
                    first = i;
                }
            }
        }
        return n + " differing byte(s), first at " + first + " (len " + a.length + " vs " + b.length + ")";
    }

    private static void print(float[][] grid) {
        for (int i = 0; i < grid.length; i++) {
            StringBuilder sb = new StringBuilder("  ");
            for (int j = 0; j < grid[i].length; j++) {
                sb.append(String.format("%9.3f", grid[i][j]));
            }
            System.out.println(sb.toString());
        }
    }
}
