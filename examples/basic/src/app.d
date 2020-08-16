module app;

import beamui;

mixin RegisterPlatforms;

int main()
{
    // initialize library
    GuiApp app;
    if (!app.initialize())
        return -1;

    // view the hardcoded CSS string as an embedded resource
    resourceList.embedFromMemory("_styles_.css", css);
    // setup a better theme and our stylesheet
    platform.stylesheets = [StyleResource("light"), StyleResource("_styles_")];

    // create a window with 1x1 size and expand it to the size of content
    Window window = platform.createWindow("Converter", null, WindowOptions.expanded, 1, 1);
    // show it with the temperature converter as its main widget
    window.show(() => render!TemperatureConverter);
    // run application event loop
    return platform.runEventLoop();
}

const css = `
TemperatureConverter {
    display: grid;
    grid-template-columns: 80px 80px;
    grid-template-rows: auto auto;
    padding: 12px;
}
.error { border-color: red }
`;

class TemperatureConverter : Panel
{
    import std.exception : ifThrown;
    import std.math : isFinite;

    static class State : WidgetState
    {
        float value = 0; // in Celsius
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
        TextField ed1 = render!TextField;
        TextField ed2 = render!TextField;
        // we may either control the text fields,
        // so their text will always be in sync with the value,
        // or, on bad input, allow the user to type that input right
        if (isFinite(st.value))
        {
            ed1.text = to!dstring(st.value);
            ed2.text = to!dstring(toF(st.value));
        }
        else
        {
            // attributes without values are just CSS classes
            ed1.attributes["error"];
            ed2.attributes["error"];
        }
        // update the value on typing in one of the input fields.
        // use `setState` to set the state, so the library will know
        // that the view might have changed
        ed1.onChange = (str) {
            setState(st.value, ifThrown(to!float(str), float.nan));
        };
        ed2.onChange = (str) {
            setState(st.value, ifThrown(toC(to!float(str)), float.nan));
        };
        // organize sub-widgets in a flat grid
        wrap(
            render((Label lb) { lb.text = "Celsius"; }),
            render((Label lb) { lb.text = "Fahrenheit"; }),
            ed1,
            ed2,
        );
    }
}

float toF(float c) { return c * 9 / 5 + 32; }
float toC(float f) { return (f - 32) * 5 / 9; }
