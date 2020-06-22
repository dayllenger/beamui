/**
Standard actions commonly used in dialogs and controls.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.events.stdactions;

import beamui.core.i18n;
import beamui.events.action;

// Elementary actions, no reason to use them in menus and toolbars

/// Move cursor to the beginning of line
Action ACTION_LINE_BEGIN;
/// Move cursor to the end of line
Action ACTION_LINE_END;
/// Move cursor one page up
Action ACTION_PAGE_UP;
/// Move cursor one page down
Action ACTION_PAGE_DOWN;
/// Move cursor to the beginning of page
Action ACTION_PAGE_BEGIN;
/// Move cursor to the end of page
Action ACTION_PAGE_END;
/// Move cursor to the beginning of document
Action ACTION_DOCUMENT_BEGIN;
/// Move cursor to the end of document
Action ACTION_DOCUMENT_END;

/// Move cursor to the beginning of line with selection
Action ACTION_SELECT_LINE_BEGIN;
/// Move cursor to the end of line with selection
Action ACTION_SELECT_LINE_END;
/// Move cursor one page up with selection
Action ACTION_SELECT_PAGE_UP;
/// Move cursor one page down with selection
Action ACTION_SELECT_PAGE_DOWN;
/// Move cursor to the beginning of page with selection
Action ACTION_SELECT_PAGE_BEGIN;
/// Move cursor to the end of page with selection
Action ACTION_SELECT_PAGE_END;
/// Move cursor to the beginning of document with selection
Action ACTION_SELECT_DOCUMENT_BEGIN;
/// Move cursor to the end of document with selection
Action ACTION_SELECT_DOCUMENT_END;

/// Insert new line (Enter)
Action ACTION_ENTER;
/// Delete char before cursor (backspace)
Action ACTION_BACKSPACE;
/// Delete char after cursor (del key)
Action ACTION_DELETE;

/// Select whole content (usually, Ctrl+A)
Action ACTION_SELECT_ALL;

/// Zoom in
Action ACTION_ZOOM_IN;
/// Zoom out
Action ACTION_ZOOM_OUT;

// Normal actions

Action ACTION_OK;
Action ACTION_CANCEL;
Action ACTION_APPLY;
Action ACTION_YES;
Action ACTION_NO;
Action ACTION_CLOSE;
Action ACTION_ABORT;
Action ACTION_RETRY;
Action ACTION_IGNORE;
Action ACTION_OPEN;
Action ACTION_OPEN_DIRECTORY;
Action ACTION_CREATE_DIRECTORY;
Action ACTION_SAVE;
Action ACTION_SAVE_ALL;
Action ACTION_DISCARD_CHANGES;
Action ACTION_DISCARD_ALL;
Action ACTION_OPEN_URL;

/// Undo last change
Action ACTION_UNDO;
/// Redo last undid change
Action ACTION_REDO;
/// Cut selection to clipboard
Action ACTION_CUT;
/// Copy selection to clipboard
Action ACTION_COPY;
/// Paste selection from clipboard
Action ACTION_PASTE;

void initStandardActions()
{
    ACTION_OK = new Action(tr("Ok"), "dialog-ok");
    ACTION_CANCEL = new Action(tr("Cancel"), "dialog-cancel", Key.escape);
    ACTION_APPLY = new Action(tr("Apply"));
    ACTION_YES = new Action(tr("Yes"), "dialog-ok");
    ACTION_NO = new Action(tr("No"), "dialog-cancel");
    ACTION_CLOSE = new Action(tr("Close"), "dialog-close");
    ACTION_ABORT = new Action(tr("Abort"));
    ACTION_RETRY = new Action(tr("Retry"));
    ACTION_IGNORE = new Action(tr("Ignore"));
    ACTION_OPEN = new Action(tr("Open"));
    ACTION_OPEN_DIRECTORY = new Action(tr("Select directory"));
    ACTION_CREATE_DIRECTORY = new Action(tr("New folder"));
    ACTION_SAVE = new Action(tr("Save"));
    ACTION_SAVE_ALL = new Action(tr("Save all"));
    ACTION_DISCARD_CHANGES = new Action(tr("Discard"));
    ACTION_DISCARD_ALL = new Action(tr("Discard all"));
    ACTION_OPEN_URL = new Action("applications-internet");

    ACTION_LINE_BEGIN = new Action(null, Key.home);
    ACTION_LINE_END = new Action(null, Key.end);
    ACTION_PAGE_UP = new Action(null, Key.pageUp);
    ACTION_PAGE_DOWN = new Action(null, Key.pageDown);
    ACTION_PAGE_BEGIN = new Action(null, Key.pageUp, KeyMods.control);
    ACTION_PAGE_END = new Action(null, Key.pageDown, KeyMods.control);
    ACTION_DOCUMENT_BEGIN = new Action(null, Key.home, KeyMods.control);
    ACTION_DOCUMENT_END = new Action(null, Key.end, KeyMods.control);

    ACTION_SELECT_LINE_BEGIN = new Action(null, Key.home, KeyMods.shift);
    ACTION_SELECT_LINE_END = new Action(null, Key.end, KeyMods.shift);
    ACTION_SELECT_PAGE_UP = new Action(null, Key.pageUp, KeyMods.shift);
    ACTION_SELECT_PAGE_DOWN = new Action(null, Key.pageDown, KeyMods.shift);
    ACTION_SELECT_PAGE_BEGIN = new Action(null, Key.pageUp, KeyMods.control | KeyMods.shift);
    ACTION_SELECT_PAGE_END = new Action(null, Key.pageDown, KeyMods.control | KeyMods.shift);
    ACTION_SELECT_DOCUMENT_BEGIN = new Action(null, Key.home, KeyMods.control | KeyMods.shift);
    ACTION_SELECT_DOCUMENT_END = new Action(null, Key.end, KeyMods.control | KeyMods.shift);

    ACTION_ENTER = new Action(tr("Enter"), Key.enter);
    ACTION_BACKSPACE = new Action(tr("Backspace"), Key.backspace);
    ACTION_DELETE = new Action(tr("Delete"), Key.del);

    ACTION_SELECT_ALL = new Action(tr("Select all"), Key.A, KeyMods.control);

    ACTION_ZOOM_IN = new Action(tr("Zoom In"), Key.equal, KeyMods.control);
    ACTION_ZOOM_OUT = new Action(tr("Zoom Out"), Key.subtract, KeyMods.control);

    ACTION_UNDO = new Action(tr("&Undo"), Key.Z, KeyMods.control).setEnabled(false);
    ACTION_REDO = new Action(tr("&Redo"), Key.Z, KeyMods.control | KeyMods.shift).setEnabled(false);
    ACTION_CUT = new Action(tr("Cu&t"), Key.X, KeyMods.control).setEnabled(false);
    ACTION_COPY = new Action(tr("&Copy"), Key.C, KeyMods.control).setEnabled(false);
    ACTION_PASTE = new Action(tr("&Paste"), Key.V, KeyMods.control).setEnabled(false);

    import beamui.core.types : tup;

    // dfmt off
    foreach (Action a; tup(
        ACTION_LINE_BEGIN,
        ACTION_LINE_END,
        ACTION_PAGE_UP,
        ACTION_PAGE_DOWN,
        ACTION_PAGE_BEGIN,
        ACTION_PAGE_END,
        ACTION_DOCUMENT_BEGIN,
        ACTION_DOCUMENT_END,
        ACTION_SELECT_LINE_BEGIN,
        ACTION_SELECT_LINE_END,
        ACTION_SELECT_PAGE_UP,
        ACTION_SELECT_PAGE_DOWN,
        ACTION_SELECT_PAGE_BEGIN,
        ACTION_SELECT_PAGE_END,
        ACTION_SELECT_DOCUMENT_BEGIN,
        ACTION_SELECT_DOCUMENT_END,
        ACTION_ENTER,
        ACTION_BACKSPACE,
        ACTION_DELETE,
        ACTION_ZOOM_IN,
        ACTION_ZOOM_OUT,

        ACTION_SELECT_ALL,
        ACTION_UNDO,
        ACTION_REDO,
        ACTION_CUT,
        ACTION_COPY,
        ACTION_PASTE,
    ))
    {
        a.context = ActionContext.widgetTree;
    }
    // dfmt on
}
