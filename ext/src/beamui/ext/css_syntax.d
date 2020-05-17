/**
CSS syntax support for source editors.

Copyright: Vadim Lopatin 2015, dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.ext.css_syntax;

import beamui.core.editable;

final class CssSyntaxSupport : SyntaxSupport
{
    @property
    {
        inout(EditableContent) content() inout { return _content; }
        void content(EditableContent c)
        {
            _content = c;
        }

        bool supportsToggleLineComment() const { return true; }
        bool supportsToggleBlockComment() const { return true; }
        bool supportsSmartIndents() const { return true; }
    }

    private EditableContent _content;

    void updateHighlight(const dstring[] lines, TokenPropString[] props, int startLine, int endLine)
    {
    }

    TextPosition findPairedBracket(TextPosition p)
    {
        assert(_content);

        return p;
    }

    bool canToggleLineComment(TextRange range) const
    {
        assert(_content);

        return false;
    }

    void toggleLineComment(TextRange range, Object source)
    {
        assert(_content);

    }

    bool canToggleBlockComment(TextRange range) const
    {
        assert(_content);

        return false;
    }

    void toggleBlockComment(TextRange range, Object source)
    {
        assert(_content);

    }

    void applySmartIndent(EditOperation op, Object source)
    {
        assert(_content);

    }
}
