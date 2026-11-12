package ij.measure;

import ij.text.TextWindow;

/** Minimal ImageJ "ResultsTable" (imported by RetFM_J, never executed). */
public class ResultsTable {

    private static ResultsTable current;

    public static ResultsTable getResultsTable() {
        if (current == null) {
            current = new ResultsTable();
        }
        return current;
    }

    public static TextWindow getResultsWindow() {
        return new TextWindow("Results", "", 100, 100);
    }

    public int getCounter() {
        return 0;
    }

    public String getColumnHeadings() {
        return "\tArea";
    }

    public String getRowAsString(int row) {
        return "";
    }
}
