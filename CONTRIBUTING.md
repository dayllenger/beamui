# Contribution guidelines

## Coding style

Basically, coding style inherits the [Phobos style](https://dlang.org/dstyle.html).
There are little differences, like no space after `cast(...)` operator.

Tune your editor as described in `.editorconfig` file in the root folder, if your editor cannot recognize it.

### Structure

Organize your code into meaningful blocks. Most of classes in the library use such layout:
```D
class A
{
    @property
    {
        // properties
    }

    // public fields

    private
    {
        // private or protected fields
    }

    // constructors
    this();
    // destructor
    ~this();

    // and then methods
    // public first
    // protected then
    // overriden last
}
```

Write trivial getters in one line, for example:
```D
@property
{
    /// Documentation comment
    long time() const { return _time; }
    /// ditto
    void time(long value)
    {
        _time = value;
        requestUniverseUpdate();
    }
}
private long _time;
```

Try to place functions *below* of their first call. Humans prefer to read text in up-down direction.

If you write a lot of code, split parts with the following line:

```
    //===============================================================
    // Stuff processing
```

### Attributes

The lefthand attributes and qualifiers should have such order:
```D
abstract/final/override public/protected/package/private static @property
```
The righthand:
```D
const/inout pure nothrow @nogc @trusted/@safe
```

If you want to add some attributes, don't spam with them. Try to use a colon mark e.g. `@nogc:`

### Documentation

Use one general documentation comment and `ditto` in getter/setter pairs.
Don't split them in two senseless "Get the ..." and "Set the ...".

Don't duplicate documentation from the base method to the overriden one. Documentation engine will do it by itself.

Start doc comments with an uppercase and simple comments with a lowercase letter.

## Debugging constants

This section keeps all debug constants of the project.
They add more logging in certain places of code.

You can enable them in two ways:

* into `dub.json` file in `debugVersions` property.
This will force to rebuild the whole library, including dependencies.
* on top of the module you debug with `debug = ...;` statement.
This will activate debug constant only in that module and won't rebuild everything.

[More info](https://dlang.org/spec/version.html#debug_specification)

### Common
```
resalloc
FileFormats
FontResources
drawables
actions
focus
```

### Platforms
```
sdl
x11
mouse
keys
redraw
resizing
state
timers
tooltips
```

### Widgets
```
editors
lists
menus
scrollbars
styles
trees
```