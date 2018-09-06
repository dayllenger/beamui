/**


Copyright: Vadim Lopatin 2015-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.metadata;

import std.string : join;
import std.traits;
import beamui.widgets.widget;

version = GENERATE_PROPERTY_METADATA;

interface WidgetMetadataDef
{
    Widget create();
    /// Short class name, e.g. "EditLine"
    string className();
    /// Module name, e.g. "beamui.widgets.editors"
    string moduleName();
    /// Full class name, e.g. "beamui.widgets.editors.EditLine"
    string fullName();
    /// Property list, e.g. [{uint, "backgroundColor"}]
    WidgetPropertyMetadata[] properties();
}

struct WidgetSignalMetadata
{
    string name;
    string typeString;
    //TypeTuple
    TypeInfo returnType;
    TypeInfo paramsType;
}

/// Stores information about property
struct WidgetPropertyMetadata
{
    TypeInfo type;
    string name;
}

private __gshared WidgetMetadataDef[string] _registeredWidgets;

WidgetMetadataDef findWidgetMetadata(string name)
{
    return _registeredWidgets.get(name, null);
}

/// Returns true if passed name is identifier of registered widget class
bool isWidgetClassName(string name)
{
    return (name in _registeredWidgets) !is null;
}

string[] getRegisteredWidgetsList()
{
    return _registeredWidgets.keys;
}

void registerWidgetMetadata(string name, WidgetMetadataDef metadata)
{
    _registeredWidgets[name] = metadata;
}

WidgetSignalMetadata[] getSignalList(T)()
{
    WidgetSignalMetadata[] res;
    foreach (m; __traits(allMembers, T))
    {
        static if (__traits(compiles, (typeof(__traits(getMember, T, m)))))
        {
            // skip non-public members
            static if (__traits(getProtection, __traits(getMember, T, m)) == "public")
            {
                static if (__traits(compiles, __traits(getMember, T, m).params_t) &&
                        __traits(compiles, __traits(getMember, T, m).return_t))
                {
                    alias ti = typeof(__traits(getMember, T, m));
                    res ~= WidgetSignalMetadata(m, __traits(getMember, T, m)
                            .return_t.stringof ~ __traits(getMember, T, m).params_t.stringof,
                            typeid(__traits(getMember, T, m).return_t), typeid(__traits(getMember, T, m).params_t));
                }
            }
        }
    }
    return res;
}

enum isMarkupType(T) = is(T == int) || is(T == float) || is(T == double) || is(T == bool) ||
        is(T == Rect) || is(T == string) || is(T == dstring) || is(T == StringListValue[]);

enum isPublicPropertyFunction(alias overload) =
    __traits(getProtection, overload) == "public" && functionAttributes!overload & FunctionAttribute.property;

private template markupPropertyType(alias overload)
{
    alias ret = ReturnType!overload;
    alias params = ParameterTypeTuple!overload;
    static if (params.length == 0 && isMarkupType!ret /* && !isTemplate!ret*/ )
    {
        enum markupPropertyType = ret.stringof;
    }
    else static if (params.length == 1 && isMarkupType!(params[0]) /* && !isTemplate!(params[0])*/ )
    {
        enum markupPropertyType = params[0].stringof;
    }
    else
    {
        enum markupPropertyType = null;
    }
}

string registerWidgetMetadataClass(T)() if (is(T : Widget))
{
    enum classDef = generateMetadataClass!T;
    enum registerDef = generateRegisterMetadataClass!T;
    return classDef ~ registerDef;
}

private string generateMetadataClass(T)() if (is(T : Widget))
{
    //pragma(msg, getSignalList!t);
    return format(`
        static final class %1$sMetadata : WidgetMetadataDef
        {
            Widget create()
            {
                return new %2$s.%1$s;
            }
            string className()
            {
                return "%1$s";
            }
            string moduleName()
            {
                return "%2$s";
            }
            string fullName()
            {
                return "%2$s.%1$s";
            }
            WidgetPropertyMetadata[] properties()
            {
                return %3$s;
            }
        }
    `, T.stringof, moduleName!T, generatePropertiesMetadata!T);
}

private string generatePropertiesMetadata(T)() if (is(T : Widget))
{
    version (GENERATE_PROPERTY_METADATA)
    {
        auto properties = generatePropertyTypeList!T;
        return join(properties);
    }
    else
    {
        return "[]";
    }
}

private string[] generatePropertyTypeList(T)()
{
    import std.meta;

    string[] properties;
    properties ~= "[";
    foreach (m; __traits(allMembers, T))
    {
        static if (__traits(compiles, (typeof(__traits(getMember, T, m)))))
        {
            //static if (is (typeof(__traits(getMember, T, m)) == function)) {
            static if (__traits(isVirtualFunction, __traits(getMember, T, m)))
            {
                alias overloads = typeof(__traits(getVirtualFunctions, T, m));
                static if (overloads.length == 2)
                {
                    static if (isPublicPropertyFunction!(__traits(getVirtualFunctions, T, m)[0]) &&
                            isPublicPropertyFunction!(__traits(getVirtualFunctions, T, m)[1]))
                    {
                        //pragma(msg, m ~ " isPublicPropertyFunction0=" ~ isPublicPropertyFunction!(__traits(getVirtualFunctions, T, m)[0]).stringof);
                        //pragma(msg, m ~ " isPublicPropertyFunction1=" ~ isPublicPropertyFunction!(__traits(getVirtualFunctions, T, m)[1]).stringof);
                        immutable getterType = markupPropertyType!(__traits(getVirtualFunctions, T, m)[0]);
                        immutable setterType = markupPropertyType!(__traits(getVirtualFunctions, T, m)[1]);
                        static if (getterType && setterType && getterType == setterType)
                        {
                            //pragma(msg, "markup property found: " ~ getterType ~ " " ~ m.stringof);
                            properties ~= "WidgetPropertyMetadata( typeid(" ~ getterType ~ "), " ~ m.stringof ~ " ), ";
                        }
                    }
                }
            }
        }
    }
    properties ~= "]";
    return properties;
}

private string generateRegisterMetadataClass(T)() if (is(T : Widget))
{
    return format(`registerWidgetMetadata("%1$s", new %1$sMetadata);`, T.stringof);
}
