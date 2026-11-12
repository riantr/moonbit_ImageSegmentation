package ij;

import java.util.Hashtable;

/** Minimal ImageJ menu registry; no command is ever available. */
public class Menus {
    public static Hashtable getCommands() {
        return new Hashtable();
    }
}
