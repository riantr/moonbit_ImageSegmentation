/**
 * A differential cross check of `Math.pow` (Java) against `@math.pow`
 * (MoonBit).
 *
 * The QA report of the first round listed as a residual risk that the two
 * are "not required to be bit identical". That is a property of the platform,
 * so it cannot be argued away - it can only be *measured*. This tool measures
 * it on the arguments the port actually uses:
 *
 *   * the exponent 2.0 with a base in [-256, 256] - the mixture model
 *     (`Math.pow(i - mu, 2)`) and the Otsu plugin,
 *   * the exponent 2.4 with a base in [0, 1] - the sRGB gamma of SIOX,
 *   * the exponent 1/3 with a base in [0, 1] - the CIELAB cube root of SIOX.
 *
 * The arguments are built by a linear congruential generator, so the MoonBit
 * test `the pow of the port matches the Java Math.pow` builds exactly the
 * same ones without exchanging a file.
 *
 * The result of the measurement (see QA_REPORT.md):
 *
 *   * the exponent 2.0: the two sides are **bit identical** (0 of the 20 000
 *     arguments differ). Both compute the correctly rounded square: MoonBit's
 *     `@math.pow` is the fdlibm port of OpenJDK's, which returns `x * x` for
 *     the exponent 2, and a single IEEE multiplication is the correctly
 *     rounded square. The tool checks that property on the Java side, the
 *     MoonBit test checks it on the MoonBit side.
 *   * the exponents 2.4 and 1/3: the two sides differ in about 0.1 % of the
 *     arguments, always by exactly **one** unit in the last place of the
 *     double. The result is narrowed to a float right afterwards, which
 *     absorbs such a difference unless it falls on a float rounding
 *     boundary.
 *
 * Every family is pinned to its own checksum, so a change of either platform
 * is reported instead of silently changing the result of the port.
 *
 * The Java side is a gate of `verify_all.ps1`.
 *
 * Usage:
 *     javac -encoding UTF-8 -cp out -d tools\out tools\PowCrossCheck.java
 *     java -cp "out;tools\out" PowCrossCheck
 */
public class PowCrossCheck {
    /** The checksum of the bit patterns of the results with the exponent 2.0. */
    public static final long EXPECTED_TWO = 546001597L;

    /** The checksum of the bit patterns of the results with the exponent 2.4. */
    public static final long EXPECTED_GAMMA = 299101583L;

    /** The checksum of the bit patterns of the results with the exponent 1/3. */
    public static final long EXPECTED_CUBE = 656082642L;

    /** The number of arguments per family. */
    public static final int ROUNDS = 20000;

    /** The seed of the linear congruential generator. */
    public static final int SEED = 20261030;

    /** The modulus of the checksum. */
    private static final long MODULUS = 1000000007L;

    /** The state of the generator. */
    private static int state = SEED;

    /** The next value of the generator (the same arithmetic as in Java). */
    private static int next() {
        state = (1103515245 * state + 12345) & 0x7FFFFFFF;
        return state;
    }

    /** Fold the raw bit pattern of a result into the checksum. */
    private static long fold(long checksum, double value) {
        long bits = Double.doubleToRawLongBits(value);
        long m = ((bits % MODULUS) + MODULUS) % MODULUS;
        return (checksum * 31 + m) % MODULUS;
    }

    public static void main(String[] args) {
        long familyTwo = 0;
        long familyGamma = 0;
        long familyCube = 0;
        int notTheSquare = 0;

        // the exponent 2.0: the mixture model and the Otsu plugin
        for (int i = 0; i < ROUNDS; i++) {
            state = next();
            double x = (double) (state % 2000001) / 1000000.0 - 256.0;
            double squared = Math.pow(x, 2.0);
            familyTwo = fold(familyTwo, squared);
            if (Double.doubleToRawLongBits(squared) != Double.doubleToRawLongBits(x * x)) {
                notTheSquare++;
            }
        }

        // the exponent 2.4: the sRGB gamma of SIOX
        for (int i = 0; i < ROUNDS; i++) {
            state = next();
            double x = (double) (state % 1000001) / 1000000.0;
            familyGamma = fold(familyGamma, Math.pow(x, 2.4));
        }

        // the exponent 1/3: the CIELAB cube root of SIOX
        for (int i = 0; i < ROUNDS; i++) {
            state = next();
            double x = (double) (state % 1000001) / 1000000.0;
            familyCube = fold(familyCube, Math.pow(x, 1.0 / 3.0));
        }

        System.out.println("family 2.0   : " + familyTwo);
        System.out.println("family 2.4   : " + familyGamma);
        System.out.println("family 1/3   : " + familyCube);

        boolean failed = false;
        if (familyTwo != EXPECTED_TWO) {
            System.out.println("FAIL: the exponent 2.0 computes " + familyTwo
                    + ", " + EXPECTED_TWO + " is expected");
            failed = true;
        }
        if (familyGamma != EXPECTED_GAMMA) {
            System.out.println("FAIL: the exponent 2.4 computes " + familyGamma
                    + ", " + EXPECTED_GAMMA + " is expected");
            failed = true;
        }
        if (familyCube != EXPECTED_CUBE) {
            System.out.println("FAIL: the exponent 1/3 computes " + familyCube
                    + ", " + EXPECTED_CUBE + " is expected");
            failed = true;
        }
        if (notTheSquare != 0) {
            System.out.println("FAIL: " + notTheSquare + " of the " + ROUNDS
                    + " squares are not the exactly rounded x * x");
            failed = true;
        }
        if (failed) {
            System.exit(1);
        }
        System.out.println("ALL-PASS: Math.pow behaves as the reference of the port does");
    }
}
