/**
Cross-platform file access utilities.

Copyright: Vadim Lopatin 2014-2017, Roman Chistokhodov 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.files;

import std.algorithm : equal, findSplit, sort;
import std.exception : collectException, enforce;
import std.file;
import std.path;
import std.process;
import std.string;
import std.utf;
import beamui.core.logger;

/// Path delimiter (\ for windows, / for others)
enum char PATH_DELIMITER = dirSeparator[0];

/// Filesystem root entry / bookmark types
enum RootEntryType
{
    /// Filesystem root
    root,
    /// Current user home
    home,
    /// Removable drive
    removable,
    /// Fixed drive
    fixed,
    /// Network
    network,
    /// Cd rom
    cdrom,
    /// Sd card
    sdcard,
    /// Custom bookmark
    bookmark,
}

/// Filesystem root entry item
struct RootEntry
{
    private RootEntryType _type;
    private string _path;
    private dstring _display;

    this(RootEntryType type, string path, dstring display = null)
    {
        _type = type;
        _path = path;
        _display = display ? display : toUTF32(baseName(path));
    }
    // dfmt off
    /// Returns type
    @property RootEntryType type() const { return _type; }
    /// Returns path
    @property string path() const { return _path; }
    /// Returns display label
    @property dstring label() const { return _display; }
    /// Returns icon resource id
    @property string icon() const
    {
        switch (type) with (RootEntryType)
        {
            case network:   return "folder-network";
            case bookmark:  return "folder-bookmark";
            case cdrom:     return "drive-optical";
            case fixed:     return "drive-harddisk";
            case home:      return "user-home";
            case root:      return "computer";
            case sdcard:    return "media-flash-sd-mmc";
            case removable: return "device-removable-media";
            default:        return "folder-blue";
        }
    }
    // dfmt on
}

/// Returns user's home directory entry
RootEntry homeEntry()
{
    return RootEntry(RootEntryType.home, homePath);
}

/// Returns user's home directory
string homePath()
{
    string path;
    version (Windows)
    {
        path = environment.get("USERPROFILE");
        if (path is null)
            path = environment.get("HOME");
    }
    else
    {
        path = environment.get("HOME");
    }
    if (path is null)
        path = "."; // fallback to current directory
    return path;
}

version (OSX)
{
}
else version (Posix)
{
    private bool isSpecialFileSystem(const char[] dir, const char[] type)
    {
        if (dir.startsWith("/dev"))
            return true;
        if (dir.startsWith("/proc"))
            return true;
        if (dir.startsWith("/sys"))
            return true;
        if (dir.startsWith("/var/run"))
            return true;
        if (dir.startsWith("/var/lock"))
            return true;
        if (type == "tmpfs" || type == "rootfs" || type == "rpc_pipefs")
            return true;
        return false;
    }

    private string getDeviceLabelFallback(const char[] type, const char[] fsName, const char[] mountDir)
    {
        if (type == "vboxsf")
        {
            return "VirtualBox shared folder";
        }
        if (type == "fuse.gvfsd-fuse")
        {
            return "GNOME Virtual file system";
        }
        return format("%s (%s)", baseName(mountDir), type);
    }

    private RootEntryType getDeviceRootEntryType(const char[] type)
    {
        switch (type)
        {
        case "iso9660":
            return RootEntryType.cdrom;
        case "vfat":
            return RootEntryType.removable;
        case "cifs":
        case "davfs":
        case "fuse.sshfs":
        case "nfs":
        case "nfs4":
            return RootEntryType.network;
        default:
            return RootEntryType.fixed;
        }
    }
}

version (FreeBSD)
{
private:
    import core.sys.posix.sys.types;

    enum MFSNAMELEN = 16; /* length of type name including null */
    enum MNAMELEN = 88; /* size of on/from name bufs */
    enum STATFS_VERSION = 0x20030518; /* current version number */

    struct fsid_t
    {
        int[2] val;
    }

    struct statfs
    {
        uint f_version; /* structure version number */
        uint f_type; /* type of filesystem */
        ulong f_flags; /* copy of mount exported flags */
        ulong f_bsize; /* filesystem fragment size */
        ulong f_iosize; /* optimal transfer block size */
        ulong f_blocks; /* total data blocks in filesystem */
        ulong f_bfree; /* free blocks in filesystem */
        long f_bavail; /* free blocks avail to non-superuser */
        ulong f_files; /* total file nodes in filesystem */
        long f_ffree; /* free nodes avail to non-superuser */
        ulong f_syncwrites; /* count of sync writes since mount */
        ulong f_asyncwrites; /* count of async writes since mount */
        ulong f_syncreads; /* count of sync reads since mount */
        ulong f_asyncreads; /* count of async reads since mount */
        ulong[10] f_spare; /* unused spare */
        uint f_namemax; /* maximum filename length */
        uid_t f_owner; /* user that mounted the filesystem */
        fsid_t f_fsid; /* filesystem id */
        char[80] f_charspare; /* spare string space */
        char[MFSNAMELEN] f_fstypename; /* filesystem type name */
        char[MNAMELEN] f_mntfromname; /* mounted filesystem */
        char[MNAMELEN] f_mntonname; /* directory on which mounted */
    }

    extern (C) nothrow @nogc
    {
        int getmntinfo(statfs** mntbufp, int flags);
    }
}

version (linux)
{
private:
    import core.stdc.stdio : FILE;

    struct mntent
    {
        char* mnt_fsname; /* Device or server for filesystem.  */
        char* mnt_dir; /* Directory mounted on.  */
        char* mnt_type; /* Type of filesystem: ufs, nfs, etc.  */
        char* mnt_opts; /* Comma-separated options for fs.  */
        int mnt_freq; /* Dump frequency (in days).  */
        int mnt_passno; /* Pass number for `fsck'.  */
    }

    extern (C) nothrow @nogc
    {
        FILE* setmntent(const char* file, const char* mode);
        mntent* getmntent(FILE* stream);
        mntent* getmntent_r(FILE* stream, mntent* result, char* buffer, int bufsize);
        int addmntent(FILE* stream, const mntent* mnt);
        int endmntent(FILE* stream);
        char* hasmntopt(const mntent* mnt, const char* opt);
    }

    string unescapeLabel(string label)
    {
        return label.replace("\\x20", " ").replace("\\x9", " ") //actually tab
        .replace("\\x5c", "\\").replace("\\xA", " "); //actually newline
    }
}

/// Returns array of system root entries
RootEntry[] getRootPaths()
{
    RootEntry[] res;
    res ~= RootEntry(RootEntryType.home, homePath);
    version (Posix)
    {
        res ~= RootEntry(RootEntryType.root, "/", "File System"d);
    }
    version (Android)
    {
        // do nothing
    }
    else version (linux)
    {
        mntent ent;
        char[1024] buf;
        FILE* f = setmntent("/etc/mtab", "r");

        if (f)
        {
            scope (exit)
                endmntent(f);
            while (getmntent_r(f, &ent, buf.ptr, cast(int)buf.length) !is null)
            {
                auto fsName = fromStringz(ent.mnt_fsname);
                auto mountDir = fromStringz(ent.mnt_dir);
                auto type = fromStringz(ent.mnt_type);

                if (mountDir == "/") // root is already added
                    continue;
                if (isSpecialFileSystem(mountDir, type)) // don't list special file systems
                    continue;

                string label;
                enum byLabel = "/dev/disk/by-label";
                if (isAbsolute(fsName))
                {
                    try
                    {
                        foreach (entry; dirEntries(byLabel, SpanMode.shallow))
                        {
                            string name = entry.name;
                            string resolvedLink;
                            if (isSymlink(name) && collectException(readLink(name), resolvedLink) is null)
                            {
                                const normalized = buildNormalizedPath(byLabel, resolvedLink);
                                if (normalized == fsName)
                                {
                                    label = unescapeLabel(baseName(name));
                                }
                            }
                        }
                    }
                    catch (Exception e)
                    {
                    }
                }

                if (!label.length)
                {
                    label = getDeviceLabelFallback(type, fsName, mountDir);
                }
                auto entryType = getDeviceRootEntryType(type);
                res ~= RootEntry(entryType, mountDir.idup, toUTF32(label));
            }
        }
    }

    version (FreeBSD)
    {
        statfs* mntbufsPtr;
        int mntbufsLen = getmntinfo(&mntbufsPtr, 0);
        if (mntbufsLen)
        {
            auto mntbufs = mntbufsPtr[0 .. mntbufsLen];

            foreach (buf; mntbufs)
            {
                auto type = fromStringz(buf.f_fstypename.ptr);
                auto fsName = fromStringz(buf.f_mntfromname.ptr);
                auto mountDir = fromStringz(buf.f_mntonname.ptr);

                if (mountDir == "/" || isSpecialFileSystem(mountDir, type))
                {
                    continue;
                }

                string label = getDeviceLabelFallback(type, fsName, mountDir);
                res ~= RootEntry(getDeviceRootEntryType(type), mountDir.idup, toUTF32(label));
            }
        }
    }

    version (Windows)
    {
        uint mask = GetLogicalDrives();
        foreach (int i; 0 .. 26)
        {
            if (mask & (1 << i))
            {
                char letter = cast(char)('A' + i);
                string path = "" ~ letter ~ ":\\";
                dstring display = ""d ~ letter ~ ":"d;
                // detect drive type
                RootEntryType type;
                const wtype = GetDriveTypeA(toStringz(path));
                switch (wtype)
                {
                case DRIVE_REMOVABLE:
                    type = RootEntryType.removable;
                    break;
                case DRIVE_REMOTE:
                    type = RootEntryType.network;
                    break;
                case DRIVE_CDROM:
                    type = RootEntryType.cdrom;
                    break;
                default:
                    type = RootEntryType.fixed;
                    break;
                }
                res ~= RootEntry(type, path, display);
            }
        }
    }
    return res;
}

version (Windows)
{
private:
    import core.sys.windows.windows;
    import core.sys.windows.objidl;
    import core.sys.windows.shlobj;
    import core.sys.windows.wtypes;

    pragma(lib, "Ole32");

    alias KNOWNFOLDERID = GUID;
    enum FOLDERID_Links = KNOWNFOLDERID(0xbfb9d5e0, 0xc6a9, 0x404c, [0xb2, 0xb2, 0xae, 0x6d, 0xb6, 0xaf, 0x49, 0x68]);
}

/// Returns array of user bookmarked directories
RootEntry[] getBookmarkPaths()
{
    RootEntry[] res;
    version (OSX)
    {
    }
    else version (Android)
    {
    }
    else version (Posix)
    {
        // Probably we should follow https://www.freedesktop.org/wiki/Specifications/desktop-bookmark-spec/ but it requires XML library.
        // So for now just try to read GTK3 bookmarks. Should be compatible with GTK file dialogs, Nautilus and other GTK file managers.

        import std.stdio : File;
        import std.uri : decode;

        try
        {
            enum fileProtocol = "file://";
            auto configPath = environment.get("XDG_CONFIG_HOME");
            if (!configPath.length)
            {
                configPath = buildPath(homePath(), ".config");
            }
            auto bookmarksFile = buildPath(configPath, "gtk-3.0/bookmarks");
            foreach (line; File(bookmarksFile, "r").byLineCopy())
            {
                if (!line.startsWith(fileProtocol))
                    continue;

                auto splitted = findSplit(line, " ");
                string path;
                if (splitted[1].length)
                {
                    path = splitted[0][fileProtocol.length .. $];
                }
                else
                {
                    path = line[fileProtocol.length .. $];
                }
                path = decode(path);
                if (isAbsolute(path))
                {
                    // Note: GTK supports regular files in bookmarks too, but we allow directories only.
                    bool dirExists;
                    collectException(isDir(path), dirExists);
                    if (dirExists)
                    {
                        dstring label;
                        if (splitted[1].length)
                        {
                            label = toUTF32(splitted[2]);
                        }
                        else
                        {
                            label = toUTF32(baseName(path));
                        }
                        res ~= RootEntry(RootEntryType.bookmark, path, label);
                    }
                }
            }
        }
        catch (Exception e)
        {
        }
    }
    else version (Windows)
    {
        // This will not include bookmarks of special items and virtual folders like Recent Files or Recycle bin.

        import core.stdc.wchar_ : wcslen;
        import std.utf : toUTF16z;

        try
        {
            auto shell = enforce(LoadLibraryA("Shell32"));
            scope (exit)
                FreeLibrary(shell);

            // dfmt off
            static extern (Windows) HRESULT func(
                const(KNOWNFOLDERID)* rfid,
                DWORD dwFlags,
                HANDLE hToken,
                wchar** ppszPath,
            ) nothrow @nogc @system;
            // dfmt on
            auto SHGetKnownFolderPath = cast(typeof(&func))enforce(GetProcAddress(shell, "SHGetKnownFolderPath"));

            wchar* linksFolderZ;
            const linksGuid = FOLDERID_Links;
            enforce(SHGetKnownFolderPath(&linksGuid, 0, null, &linksFolderZ) == S_OK);
            scope (exit)
                CoTaskMemFree(linksFolderZ);

            string linksFolder = linksFolderZ[0 .. wcslen(linksFolderZ)].toUTF8;

            enforce(SUCCEEDED(CoInitialize(null)));
            scope (exit)
                CoUninitialize();

            HRESULT hres;
            IShellLink psl;

            auto clsidShellLink = CLSID_ShellLink;
            auto iidShellLink = IID_IShellLinkW;
            hres = CoCreateInstance(&clsidShellLink, null, CLSCTX.CLSCTX_INPROC_SERVER, &iidShellLink, cast(LPVOID*)&psl);
            enforce(SUCCEEDED(hres), "Failed to create IShellLink instance");
            scope (exit)
                psl.Release();

            IPersistFile ppf;
            auto iidPersistFile = IID_IPersistFile;
            hres = psl.QueryInterface(cast(GUID*)&iidPersistFile, cast(void**)&ppf);
            enforce(SUCCEEDED(hres), "Failed to query IPersistFile interface");
            scope (exit)
                ppf.Release();

            foreach (linkFile; dirEntries(linksFolder, SpanMode.shallow))
            {
                if (!linkFile.name.endsWith(".lnk"))
                    continue;
                try
                {
                    wchar[MAX_PATH] szGotPath;
                    WIN32_FIND_DATA wfd;

                    hres = ppf.Load(linkFile.name.toUTF16z, STGM_READ);
                    enforce(SUCCEEDED(hres), "Failed to load link file");

                    hres = psl.Resolve(null, SLR_FLAGS.SLR_NO_UI);
                    enforce(SUCCEEDED(hres), "Failed to resolve link");

                    hres = psl.GetPath(szGotPath.ptr, szGotPath.length, &wfd, 0);
                    enforce(SUCCEEDED(hres), "Failed to get path of link target");

                    auto path = szGotPath[0 .. wcslen(szGotPath.ptr)];

                    if (path.length && isDir(toUTF8(path)))
                    {
                        const display = toUTF32(stripExtension(baseName(linkFile.name)));
                        res ~= RootEntry(RootEntryType.bookmark, toUTF8(path), display);
                    }
                }
                catch (Exception e)
                {
                }
            }
        }
        catch (Exception e)
        {
        }
    }
    return res;
}

/// Returns true if directory is root directory (e.g. / or C:\)
bool isRoot(string path)
{
    string root = rootName(path);
    return equal(path, root);
}

/// Check if path is hidden
bool isHidden(string path)
{
    version (Windows)
    {
        uint attrs;
        if (collectException(getAttributes(path), attrs) is null)
        {
            return (attrs & FILE_ATTRIBUTE_HIDDEN) != 0;
        }
        else
            return false;
    }
    else version (Posix)
    {
        //TODO: check for hidden attribute on macOS
        return baseName(path).startsWith(".");
    }
    else
        return false;
}

///
unittest
{
    version (Posix)
    {
        assert(!isHidden("path/to/normal_file"));
        assert(isHidden("path/to/.hidden_file"));
    }
}

private bool isReadable(string filePath)
{
    version (Posix)
    {
        import core.sys.posix.unistd : access, R_OK;

        return access(toStringz(filePath), R_OK) == 0;
    }
    else
    {
        // TODO: Windows version
        return true;
    }
}

private bool isWritable(string filePath)
{
    version (Posix)
    {
        import core.sys.posix.unistd : access, W_OK;

        return access(toStringz(filePath), W_OK) == 0;
    }
    else
    {
        // TODO: Windows version
        return true;
    }
}

private bool isExecutable(string filePath)
{
    version (Windows)
    {
        //TODO: Use GetEffectiveRightsFromAclW? For now just check extension
        string extension = filePath.extension;
        foreach (ext; [".exe", ".com", ".bat", ".cmd"])
        {
            if (filenameCmp(extension, ext) == 0)
                return true;
        }
        return false;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : access, X_OK;

        return access(toStringz(filePath), X_OK) == 0;
    }
    else
    {
        return false;
    }
}

/// Returns parent directory for specified path
string parentDir(string path)
{
    return buildNormalizedPath(path, "..");
}

/// Check filename with pattern
bool filterFilename(string filename, string pattern)
{
    return globMatch(filename.baseName, pattern);
}
/// Filters file name by pattern list
bool filterFilename(string filename, const string[] filters)
{
    if (filters.length == 0)
        return true; // no filters - show all
    foreach (pattern; filters)
    {
        if (filterFilename(filename, pattern))
            return true;
    }
    return false;
}

enum AttrFilter
{
    none = 0,
    files = 1 << 0, /// Include regular files that match the filters.
    dirs = 1 << 1, /// Include directories.
    hidden = 1 << 2, /// Include hidden files and directoroies.
    parent = 1 << 3, /// Include parent directory (..). Takes effect only with includeDirs.
    thisDir = 1 << 4, /// Include this directory (.). Takes effect only with  includeDirs.
    special = 1 << 5, /// Include special files (On Unix: socket and device files, FIFO) that match the filters.
    readable = 1 << 6, /// Listing only readable files and directories.
    writable = 1 << 7, /// Listing only writable files and directories.
    executable = 1 << 8, /// Include only executable files. This filter does not affect directories.
    allVisible = AttrFilter.files | AttrFilter.dirs, /// Include all non-hidden files and directories without parent directory, this directory and special files.
    all = AttrFilter.allVisible | AttrFilter.hidden /// Include all files and directories including hidden ones but without parent directory, this directory and special files.
}

/** List directory content.

    Optionally filters file names by filter (not applied to directories).

    Returns true if directory exists and listed successfully, false otherwise.
    Throws: Exception if $(D dir) is not directory or some error occured during directory listing.
*/
DirEntry[] listDirectory(string dir, AttrFilter attrFilter = AttrFilter.all, const string[] filters = null)
{
    DirEntry[] entries;

    DirEntry[] dirs;
    DirEntry[] files;
    foreach (DirEntry e; dirEntries(dir, SpanMode.shallow))
    {
        if (!(attrFilter & AttrFilter.hidden) && isHidden(e.name))
            continue;
        if ((attrFilter & AttrFilter.readable) && !isReadable(e.name))
            continue;
        if ((attrFilter & AttrFilter.writable) && !isWritable(e.name))
            continue;
        if (!e.isDir && (attrFilter & AttrFilter.executable) && !isExecutable(e.name))
            continue;
        if (e.isDir && (attrFilter & AttrFilter.dirs))
        {
            dirs ~= e;
        }
        else if ((attrFilter & AttrFilter.files) && filterFilename(e.name, filters))
        {
            if (e.isFile)
            {
                files ~= e;
            }
            else if (attrFilter & AttrFilter.special)
            {
                files ~= e;
            }
        }
    }
    if ((attrFilter & AttrFilter.dirs) && (attrFilter & AttrFilter.thisDir))
    {
        entries ~= DirEntry(appendPath(dir, ".")) ~ entries;
    }
    if (!isRoot(dir) && (attrFilter & AttrFilter.dirs) && (attrFilter & AttrFilter.parent))
    {
        entries ~= DirEntry(appendPath(dir, ".."));
    }
    dirs.sort!((a, b) => filenameCmp!(std.path.CaseSensitive.no)(a.name, b.name) < 0);
    files.sort!((a, b) => filenameCmp!(std.path.CaseSensitive.no)(a.name, b.name) < 0);
    entries ~= dirs;
    entries ~= files;
    return entries;
}

/// Returns true if char ch is / or \ slash
bool isPathDelimiter(char ch)
{
    return ch == '/' || ch == '\\';
}

/// Returns current directory
alias currentDir = std.file.getcwd;

/// Returns current executable path only, including last path delimiter - removes executable name from result of std.file.thisExePath()
string exePath()
{
    string path = thisExePath();
    int lastSlash = 0;
    for (int i = cast(int)path.length - 1; i >= 0; i--)
        if (path[i] == PATH_DELIMITER)
        {
            lastSlash = i;
            break;
        }
    return path[0 .. lastSlash + 1];
}

/// Returns current executable path and file name
string exeFilename()
{
    return thisExePath();
}

/** Returns application data directory.

    On unix, it will return path to subdirectory in home directory -
    e.g. /home/user/.subdir if ".subdir" is passed as a parameter.

    On windows, it will return path to subdir in APPDATA directory -
    e.g. C:\Users\User\AppData\Roaming\.subdir.
*/
string appDataPath(string subdir = null)
{
    string path;
    version (Windows)
    {
        path = environment.get("APPDATA");
    }
    if (path is null)
        path = homePath;
    if (subdir !is null)
    {
        path ~= PATH_DELIMITER;
        path ~= subdir;
    }
    return path;
}

/// Converts path delimiters to standard for platform inplace in buffer(e.g. / to \ on windows, \ to / on posix), returns buf
char[] convertPathDelimiters(char[] buf)
{
    foreach (ref ch; buf)
    {
        version (Windows)
        {
            if (ch == '/')
                ch = '\\';
        }
        else
        {
            if (ch == '\\')
                ch = '/';
        }
    }
    return buf;
}

/// Converts path delimiters to standard for platform (e.g. / to \ on windows, \ to / on posix)
string convertPathDelimiters(string src)
{
    char[] buf = src.dup;
    return cast(string)convertPathDelimiters(buf);
}

/// Appends file path parts with proper delimiters
/// e.g. `appendPath("/home/user", ".myapp", "config")` => `"/home/user/.myapp/config"`
string appendPath(string[] pathItems...)
{
    char[] buf;
    foreach (s; pathItems)
    {
        if (buf.length && !isPathDelimiter(buf[$ - 1]))
            buf ~= PATH_DELIMITER;
        buf ~= s;
    }
    return convertPathDelimiters(buf).dup;
}

/// Appends file path parts with proper delimiters (as well converts delimiters inside path to system) to buffer
/// e.g. `appendPath("/home/user", ".myapp", "config")` => `"/home/user/.myapp/config"`
char[] appendPath(char[] buf, string[] pathItems...)
{
    foreach (s; pathItems)
    {
        if (buf.length && !isPathDelimiter(buf[$ - 1]))
            buf ~= PATH_DELIMITER;
        buf ~= s;
    }
    return convertPathDelimiters(buf);
}

/// If pathName is not absolute path, convert it to absolute (assuming it is relative to current directory)
string toAbsolutePath(string pathName)
{
    if (isAbsolute(pathName))
        return pathName;
    return buildNormalizedPath(absolutePath(pathName));
}

/// For executable name w/o path, find absolute path to executable
string findExecutablePath(string executableName)
{
    version (Windows)
    {
        if (!executableName.endsWith(".exe"))
            executableName = executableName ~ ".exe";
    }
    string currentExeDir = dirName(thisExePath());
    string inCurrentExeDir = absolutePath(buildNormalizedPath(currentExeDir, executableName));
    if (exists(inCurrentExeDir) && isFile(inCurrentExeDir))
        return inCurrentExeDir; // found in current directory
    string pathVariable = environment.get("PATH");
    if (!pathVariable)
        return null;
    string[] paths = split(pathVariable, pathSeparator);
    foreach (path; paths)
    {
        string pathname = absolutePath(buildNormalizedPath(path, executableName));
        if (exists(pathname) && isFile(pathname))
            return pathname;
    }
    return null;
}

struct FileMonitor
{
    import std.datetime.systime : SysTime;

    enum Status
    {
        same,
        modified,
        missing,
    }

    private string _filename;
    private SysTime _lastModTS;
    private ulong _lastSizeInBytes;

    this(string filename)
    {
        _filename = filename;
    }

    Status check()
    {
        if (_filename.length && exists(_filename))
        {
            const ts = timeLastModified(_filename);
            const sz = getSize(_filename);
            if (_lastModTS < ts || _lastSizeInBytes != sz)
            {
                _lastModTS = ts;
                _lastSizeInBytes = sz;
                return Status.modified;
            }
            return Status.same;
        }
        return Status.missing;
    }
}
