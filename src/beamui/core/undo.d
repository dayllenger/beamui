/**
Simple class that encapsulates Undo/Redo functionality.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.undo;

import beamui.core.collections : Collection;

/// Interface for operations, that can be undone
interface UndoOperation {
    /// Try to merge two operations, return true if succeded
    bool merge(UndoOperation);
    void modified();
}

/// Undo/Redo buffer
class UndoBuffer {
    private Collection!UndoOperation _undoStack;
    private Collection!UndoOperation _redoStack;
    private UndoOperation _savedState;

    /// Returns true if the buffer contains any undo items
    @property bool hasUndo() const {
        return _undoStack.count > 0;
    }
    /// Returns true if the buffer contains any redo items
    @property bool hasRedo() const {
        return _redoStack.count > 0;
    }

    /// Add an operation for undo, clearing the redo stack
    void push(UndoOperation op) {
        _redoStack.clear();
        if (_undoStack.count > 0) {
            if (_undoStack.back.merge(op)) {
                //_undoStack.back.modified();
                return; // merged - no need to add new operation
            }
        }
        _undoStack.pushBack(op);
    }

    /// Returns operation to be undone (put into redo), `null` if no undo ops available
    UndoOperation undo() {
        if (hasUndo) {
            UndoOperation result = _undoStack.popBack();
            _redoStack.pushBack(result);
            return result;
        } else
            return null;
    }

    /// Returns operation to be redone (put into undo), `null` if no redo ops available
    UndoOperation redo() {
        if (hasRedo) {
            UndoOperation result = _redoStack.popBack();
            _undoStack.pushBack(result);
            return result;
        } else
            return null;
    }

    /// Clear both undo and redo stacks
    void clear() {
        _undoStack.clear();
        _redoStack.clear();
        _savedState = null;
    }

    /// The current state is saved
    void saved() {
        _savedState = _undoStack.back;
        foreach (op; _undoStack) {
            op.modified();
        }
        foreach (op; _redoStack) {
            op.modified();
        }
    }

    /// True if the content has been changed since last `saved()` or `clear()` call
    @property bool modified() const {
        return _savedState !is _undoStack.back;
    }

    /// True if saved state is in redo stack
    @property bool savedInRedo() const {
        return _savedState && _savedState in _redoStack;
    }
}
