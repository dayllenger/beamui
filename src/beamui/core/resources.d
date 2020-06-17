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
import beamui.core.config;
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
        static if (BACKEND_CONSOLE)
        {
            embedded ~= embedResources!(splitLines(import("console_" ~ listFilename)))();
        }
        else
        {
            embedded ~= embedResources!(splitLines(import(listFilename)))();
        }
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

    /**
    Get resource full path.

    $(UL
        $(LI if provided path - by path relative to embedded files location or resource dirs)
        $(LI if path is provided partially - match the tail)
        $(LI if provided extension - with extension)
        $(LI if nothing of those - by base name)
    )
    Null if not found.

    Note: If ID matches several files, path of the last file is returned.
    */
    string getPathByID(string id)
    {
        if (id.startsWith("#") || id.startsWith("{"))
            return null; // it's not a file name
        if (auto p = id in idToPath)
            return *p;

        import std.algorithm : any;

        bool searchWithDir = any!isDirSeparator(id);
        bool searchWithExt = extension(id) !is null;

        string tmp;
        string normID = buildNormalizedPath(id);

        // search in embedded
        // search backwards to allow overriding standard resources (which are added first)
        // double strip is needed for .9.png (is there a better solution?)
        foreach_reverse (ref r; embedded)
        {
            tmp = r.filename;
            if (!searchWithDir)
                tmp = baseName(tmp);
            if (!searchWithExt)
                tmp = stripExtension(stripExtension(tmp));
            if (tmp.endsWith(normID) &&
                (tmp.length == normID.length || isDirSeparator(tmp[$ - normID.length - 1])))
            {
                // found
                string fn = EMBEDDED_RESOURCE_PREFIX ~ r.filename;
                idToPath[id] = fn;
                return fn;
            }
        }
        // search in external
        foreach (path; _resourceDirs)
        {
            foreach (fn; dirEntries(path, SpanMode.breadth))
            {
                tmp = fn;
                if (!searchWithDir)
                    tmp = baseName(tmp);
                if (!searchWithExt)
                    tmp = stripExtension(stripExtension(tmp));
                if (tmp.endsWith(normID) &&
                    (tmp.length == normID.length || isDirSeparator(tmp[$ - normID.length - 1])))
                {
                    // found
                    idToPath[id] = fn;
                    return fn;
                }
            }
        }
        Log.w("Resource ", id, " is not found");
        return null;
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
    static if (resourceName.startsWith("#")) // comment
    {
        return [];
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
            static if (data.length > 0)
                return [EmbeddedResource(buildNormalizedPath(name), data)];
            else
                return [];
        }
        else
            return [];
    }
}
