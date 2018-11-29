/**
Standard actions commonly used in dialogs and controls.

Synopsis:
---
import beamui.core.stdaction;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.stdaction;

import beamui.core.actions;
import beamui.core.i18n;

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
    ACTION_CANCEL = new Action(tr("Cancel"), "dialog-cancel", KeyCode.escape);
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

    ACTION_LINE_BEGIN = new Action(null, KeyCode.home);
    ACTION_LINE_END = new Action(null, KeyCode.end);
    ACTION_PAGE_UP = new Action(null, KeyCode.pageUp);
    ACTION_PAGE_DOWN = new Action(null, KeyCode.pageDown);
    ACTION_PAGE_BEGIN = new Action(null, KeyCode.pageUp, KeyFlag.control);
    ACTION_PAGE_END = new Action(null, KeyCode.pageDown, KeyFlag.control);
    ACTION_DOCUMENT_BEGIN = new Action(null, KeyCode.home, KeyFlag.control);
    ACTION_DOCUMENT_END = new Action(null, KeyCode.end, KeyFlag.control);

    ACTION_SELECT_LINE_BEGIN = new Action(null, KeyCode.home, KeyFlag.shift);
    ACTION_SELECT_LINE_END = new Action(null, KeyCode.end, KeyFlag.shift);
    ACTION_SELECT_PAGE_UP = new Action(null, KeyCode.pageUp, KeyFlag.shift);
    ACTION_SELECT_PAGE_DOWN = new Action(null, KeyCode.pageDown, KeyFlag.shift);
    ACTION_SELECT_PAGE_BEGIN = new Action(null, KeyCode.pageUp, KeyFlag.control | KeyFlag.shift);
    ACTION_SELECT_PAGE_END = new Action(null, KeyCode.pageDown, KeyFlag.control | KeyFlag.shift);
    ACTION_SELECT_DOCUMENT_BEGIN = new Action(null, KeyCode.home, KeyFlag.control | KeyFlag.shift);
    ACTION_SELECT_DOCUMENT_END = new Action(null, KeyCode.end, KeyFlag.control | KeyFlag.shift);

    ACTION_ENTER = new Action(tr("Enter"), KeyCode.enter);
    ACTION_BACKSPACE = new Action(tr("Backspace"), KeyCode.backspace);
    ACTION_DELETE = new Action(tr("Delete"), KeyCode.del);

    ACTION_SELECT_ALL = new Action(tr("Select all"), KeyCode.A, KeyFlag.control);

    ACTION_ZOOM_IN = new Action(tr("Zoom In"), KeyCode.numAdd, KeyFlag.control); // BUG: such combinations do not work
    ACTION_ZOOM_OUT = new Action(tr("Zoom Out"), KeyCode.numSub, KeyFlag.control);

    ACTION_UNDO = new Action(tr("&Undo"), KeyCode.Z, KeyFlag.control).setEnabled(false);
    ACTION_REDO = new Action(tr("&Redo"), KeyCode.Y, KeyFlag.control).setEnabled(false)
        .addShortcut(KeyCode.Z, KeyFlag.control | KeyFlag.shift);
    ACTION_CUT = new Action(tr("Cu&t"), KeyCode.X, KeyFlag.control).setEnabled(false)
        .addShortcut(KeyCode.del, KeyFlag.shift);
    ACTION_COPY = new Action(tr("&Copy"), KeyCode.C, KeyFlag.control).setEnabled(false)
        .addShortcut(KeyCode.ins, KeyFlag.control);
    ACTION_PASTE = new Action(tr("&Paste"), KeyCode.V, KeyFlag.control)
        .addShortcut(KeyCode.ins, KeyFlag.shift);

    import beamui.core.functions : bunch;

    bunch(
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
    ).context(ActionContext.widgetTree);
}
