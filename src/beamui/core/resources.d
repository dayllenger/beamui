/**
Resource management.

Synopsis:
---
// embed non-standard resources listed in resources.list into executable
resourceList.embed!"resources.list";
...
// get the file path by resource ID
string filename = resourceList.getPathByID("file");
// load file
immutable(ubyte[]) data = loadResourceBytes(filename);
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.resources;

import std.file;
import std.path;
import std.string;
import beamui.core.logger;
import beamui.core.types;

// TODO: platform-specific dir separator or UNIX slash?

/// Global resource list object
__gshared ResourceList resourceList;

/// Filename prefix for embedded resources
immutable string EMBEDDED_RESOURCE_PREFIX = "@embedded@" ~ dirSeparator;

/// Resource list contains embedded resources and paths to external resource directories
struct ResourceList
{
    private EmbeddedResource[] embedded;
    private string[] _resourceDirs;
    private string[string] idToPath;

    /// Embed all resources from list
    void embed(string listFilename)()
    {
        embedded ~= embedResources!(splitLines(import(listFilename)))();
    }
    /// Embed one particular file by its filename
    void embedOne(string filename)()
    {
        embedded ~= embedResource!(filename)();
    }

    /// Get resource directory paths
    @property const(string[]) resourceDirs() const
    {
        return _resourceDirs;
    }
    /// Set resource directory paths as variable number of parameters
    void setResourceDirs(string[] paths...)
    {
        resourceDirs(paths);
    }
    /// Set resource directory paths array (only existing dirs will be added)
    @property void resourceDirs(string[] paths)
    {
        string[] existingPaths;
        foreach (path; paths)
        {
            if (exists(path) && isDir(path))
            {
                existingPaths ~= path;
                Log.d("ResourceList: adding path ", path);
            }
            else
            {
                Log.d("ResourceList: path ", path, " does not exist.");
            }
        }
        _resourceDirs = existingPaths;
        clear();
    }

    void clear()
    {
        destroy(idToPath);
    }

    /** Get resource full path.

        It searches the file by exact base name or by tail of the full path,
        in both cases matching twice with and without extension.
        Returns `null` if not found.

        Example:
        ---
        // Suppose there is a resource at "./themes/light/frame.9.png".
        // This file can be found with the following IDs:
        [
            "frame.9",
            "frame.9.png",
            "light/frame.9.png",
            "themes/light/frame.9.png",
            "./themes/light/frame.9.png",
            "themes/../themes/light/frame.9.png", // such paths work too
        ]
        ---

        Note: If ID matches several files, path of the last file is returned.
    */
    string getPathByID(string id)
    {
        if (id.startsWith("#") || id.startsWith("{"))
            return null; // it's not a file name
        if (auto p = id in idToPath)
            return *p;

        string normID = buildNormalizedPath(id);

        // search in embedded
        // search backwards to allow overriding standard resources (which are added first)
        foreach_reverse (ref r; embedded)
        {
            if (matchPathWithID(r.filename, normID))
            {
                string fn = EMBEDDED_RESOURCE_PREFIX ~ r.filename;
                idToPath[id] = fn;
                return fn;
            }
        }
        // search in external
        foreach (path; _resourceDirs)
        {
            foreach (string fn; dirEntries(path, SpanMode.breadth))
            {
                if (matchPathWithID(fn, normID))
                {
                    idToPath[id] = fn;
                    return fn;
                }
            }
        }
        Log.w("Resource ", id, " is not found");
        return null;
    }

    private bool matchPathWithID(string path, string id)
    {
        if (pathSplitter(stripExtension(path)).endsWith(pathSplitter(id)))
            return true;
        if (pathSplitter(path).endsWith(pathSplitter(id)))
            return true;
        return false;
    }

    /**
    Get embedded resource by its full filename (without prefix).

    Null if not found.
    See `getPathByID` to get full filename.
    */
    EmbeddedResource* getEmbedded(string filename)
    {
        foreach_reverse (ref r; embedded)
        {
            if (filename == r.filename)
                return &r;
        }
        return null;
    }

    /// Print resource list stats
    debug void printStats()
    {
        foreach (r; embedded)
        {
            Log.d("EmbeddedResource: ", r.filename);
        }
        Log.d("Resource dirs: ", _resourceDirs);
    }
}

/**
    Load embedded resource or arbitrary file as a byte array.

    Name of embedded resource should start with `@embedded@/` prefix.
    Name of external file is a usual path.
*/
immutable(ubyte[]) loadResourceBytes(string filename)
{
    if (filename.startsWith(EMBEDDED_RESOURCE_PREFIX))
    {
        auto embedded = resourceList.getEmbedded(filename[EMBEDDED_RESOURCE_PREFIX.length .. $]);
        return embedded ? embedded.data : null;
    }
    else
    {
        try
        {
            return cast(immutable ubyte[])std.file.read(filename);
        }
        catch (Exception e)
        {
            Log.e("Exception while loading resource file ", filename);
            return null;
        }
    }
}

struct EmbeddedResource
{
    immutable string filename;
    immutable ubyte[] data;
}

/// Embed all resources from list
private EmbeddedResource[] embedResources(string[] resourceNames)()
{
    EmbeddedResource[] list;
    static foreach (r; resourceNames)
        list ~= embedResource!r;
    return list;
}

private EmbeddedResource[] embedResource(string resourceName)()
{
    static if (resourceName.startsWith("#"))
    {
        // skip commented
        return null;
    }
    else
    {
        // WARNING: some compilers may disallow import file by full path.
        // in this case `getPathByID` will not adress embedded resources by path
        version (USE_BASE_PATH_FOR_RESOURCES)
        {
            immutable string name = baseName(resourceName);
        }
        else
        {
            immutable string name = resourceName;
        }
        static if (name.length > 0)
        {
            auto data = cast(immutable ubyte[])import(name);
            return [EmbeddedResource(buildNormalizedPath(name), data)];
        }
        else
            return [];
    }
}

//===============================================================
// Tests

unittest
{
    const filename = buildNormalizedPath("./themes/light/frame.9.png");
    const result = EMBEDDED_RESOURCE_PREFIX ~ filename;

    ResourceList list;
    list.embedded = [EmbeddedResource(filename, null)];
    assert(list.getPathByID("frame") is null);
    assert(list.getPathByID("/frame.9.png") is null);
    assert(list.getPathByID("ght/frame.9") is null);
    assert(list.getPathByID("frame.9") == result);
    assert(list.getPathByID("frame.9.png") == result);
    assert(list.getPathByID("light/frame.9.png") == result);
    assert(list.getPathByID("themes/light/frame.9.png") == result);
    assert(list.getPathByID("themes/../themes/light/frame.9.png") == result);
    assert(list.getPathByID("./themes/light/frame.9.png") == result);
}
