/**
CSS head module.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.css.css;

public import beamui.css.parser;
public import beamui.css.tokenizer;

StyleSheet createStyleSheet(string source)
{
    return parseCSS(tokenizeCSS(source));
}
