package ij.gui;

import ij.plugin.filter.PlugInFilterRunner;

import java.awt.Component;
import java.util.ArrayList;
import java.util.List;
import java.util.Vector;

/**
 * Minimal ImageJ "GenericDialog".
 *
 * Default behaviour (headless harness):
 *  - showDialog() does nothing and wasCanceled() returns false, so every
 *    algorithm runs with its DEFAULT parameter values;
 *  - wasOKed() returns true;
 *  - getNextNumber()/getNextBoolean()/getNextChoiceIndex() return the default
 *    value that was registered for the corresponding widget, in registration
 *    order.
 *
 * Choice index: the index of the item that was passed as the default item.
 * Multi_OtsuThreshold registers {"2","3","4","5"} with default "4", i.e. index
 * 2, and computes MLEVEL = getNextChoiceIndex() + 2 = 4.
 *
 * The class extends java.awt.Component because RetFM_J hands the dialog to
 * javax.swing.JFileChooser.showOpenDialog(Component); no window is ever shown.
 */
public class GenericDialog extends Component {

    private final String title;

    private final List<Double> numbers = new ArrayList<Double>();
    private final List<Boolean> booleans = new ArrayList<Boolean>();
    private final List<Integer> choices = new ArrayList<Integer>();

    private final Vector numericFields = new Vector();

    private int numberIndex = 0;
    private int booleanIndex = 0;
    private int choiceIndex = 0;

    private boolean canceled = false;
    private boolean oked = true;

    public GenericDialog(String title) {
        this.title = title;
    }

    public String getTitle() {
        return title;
    }

    public void addNumericField(String label, double value) {
        addNumericField(label, value, 2);
    }

    public void addNumericField(String label, double value, int digits) {
        numbers.add(Double.valueOf(value));
        numericFields.add(label);
    }

    public void addSlider(String label, double min, double max, double value) {
        numbers.add(Double.valueOf(value));
        numericFields.add(label);
    }

    public void addCheckbox(String label, boolean value) {
        booleans.add(Boolean.valueOf(value));
    }

    public void addChoice(String label, String[] items, String defaultItem) {
        int index = 2;
        if (items != null) {
            for (int i = 0; i < items.length; i++) {
                if (items[i] != null && items[i].equals(defaultItem)) {
                    index = i;
                    break;
                }
            }
        }
        choices.add(Integer.valueOf(index));
    }

    public void addMessage(String message) {
    }

    public void addPreviewCheckbox(PlugInFilterRunner runner) {
    }

    public void addDialogListener(DialogListener listener) {
    }

    public void showDialog() {
    }

    public boolean wasCanceled() {
        return canceled;
    }

    public boolean wasOKed() {
        return oked;
    }

    public double getNextNumber() {
        if (numberIndex < numbers.size()) {
            return numbers.get(numberIndex++).doubleValue();
        }
        return 0.0;
    }

    public boolean getNextBoolean() {
        if (booleanIndex < booleans.size()) {
            return booleans.get(booleanIndex++).booleanValue();
        }
        return false;
    }

    public int getNextChoiceIndex() {
        if (choiceIndex < choices.size()) {
            return choices.get(choiceIndex++).intValue();
        }
        return 2;
    }

    public Vector getNumericFields() {
        return numericFields;
    }
}
