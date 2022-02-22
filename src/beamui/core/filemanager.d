/**


Copyright: Roman Chistokhodov 2017
License:   Boost License 1.0
Authors:   Roman Chistokhodov
*/
module beamui.core.filemanager;

import std.file;
import std.path;
import beamui.core.logger;
import isfreedesktop;

/**
 * Show and select directory or file in OS file manager.
 *
 * On Windows this shows file in File Exporer.
 *
 * On macOS it reveals file in Finder.
 *
 * On Freedesktop systems this function finds user preferred program that used to open directories.
 *  If found file manager is known to this function, it uses file manager specific way to select file.
 *  Otherwise it fallbacks to opening $(D pathName) if it's directory or parent directory of $(D pathName) if it's file.
 */
bool showInFileManager(string pathName) {
    Log.i("showInFileManager(", pathName, ")");

    pathName = buildNormalizedPath(pathName);
    if (exists(pathName)) {
        try {
            return showInFileManagerImpl(pathName);
        } catch (Exception e) {
            Log.e("showInFileManager: exception while trying to open file browser");
            Log.e(e);
        }
    } else {
        Log.e("showInFileManager: file or directory does not exist");
    }
    return false;
}

private:
// dfmt off
version (Windows) {
// dfmt on
bool showInFileManagerImpl(string pathName) {
    import core.sys.windows.windows;
    import beamui.core.files;
    import std.utf : toUTF16z;

    string explorerPath = findExecutablePath("explorer.exe");
    if (!explorerPath.length) {
        Log.e("showInFileManager: cannot find explorer.exe");
        return false;
    }
    string arg = "/select,\"" ~ pathName ~ "\"";
    STARTUPINFO si;
    si.cb = si.sizeof;
    PROCESS_INFORMATION pi;
    Log.d("showInFileManager: ", explorerPath, " ", arg);
    arg = "\"" ~ explorerPath ~ "\" " ~ arg;
    const res = CreateProcessW(null, cast(wchar*)toUTF16z(arg), null, null,
        false, DETACHED_PROCESS, null, null, &si, &pi);
    if (!res) {
        Log.e("showInFileManager: failed to run explorer.exe");
        return false;
    }
    return true;
}
// dfmt off
} else version (OSX) {
// dfmt on
bool showInFileManagerImpl(string pathName) {
    import std.process;

    string exe = "/usr/bin/osascript";
    string[] args;
    args ~= exe;
    args ~= "-e";
    args ~= "tell application \"Finder\" to reveal (POSIX file \"" ~ pathName ~ "\")";
    Log.d("Executing command: ", args);
    auto pid = spawnProcess(args);
    wait(pid);
    args[2] = "tell application \"Finder\" to activate";
    Log.d("Executing command: ", args);
    pid = spawnProcess(args);
    wait(pid);
    return true;
}
// dfmt off
} else static if (isFreedesktop) {
// dfmt on
bool showInFileManagerImpl(string pathName) {
    import std.algorithm : map, filter, splitter, canFind, findSplit;
    import std.exception : collectException;
    import std.process;
    import std.range : array, chain, only;
    import std.string : toStringz;
    import xdgpaths;

    string toOpen = pathName;

    static bool isExecutable(string program) {
        import core.sys.posix.unistd;

        return access(toStringz(program), X_OK) == 0;
    }

    static string findExecutable(string program, const string[] binPaths) {
        if (isAbsolute(program) && isExecutable(program)) {
            return program;
        } else if (baseName(program) == program) {
            foreach (path; binPaths) {
                auto candidate = buildPath(path, program);
                if (isExecutable(candidate))
                    return candidate;
            }
        }
        return null;
    }

    static string[] findFileManagerCommand(string app, const(string)[] appDirs,
        const(string)[] binPaths) {
        foreach (appDir; appDirs) {
            bool fileExists;
            auto appPath = buildPath(appDir, app);
            collectException(isFile(appPath), fileExists);
            if (!fileExists) {
                //check if file in subdirectory exist. E.g. kde4-dolphin.desktop refers to kde4/dolphin.desktop
                auto appSplitted = findSplit(app, "-");
                if (appSplitted[1].length && appSplitted[2].length) {
                    appPath = buildPath(appDir, appSplitted[0], appSplitted[2]);
                    collectException(isFile(appPath), fileExists);
                }
            }
            if (!fileExists)
                continue;

            try {
                bool canOpenDirectory; //not used for now. Some file managers does not have MimeType in their .desktop file.
                string exec, tryExec, icon, displayName;

                parseConfigFile(appPath, "Desktop Entry", (string key, string value) {
                    if (key == "MimeType") {
                        canOpenDirectory = value.splitter(';').canFind("inode/directory");
                    } else if (key == "Exec") {
                        exec = value;
                    } else if (key == "TryExec") {
                        tryExec = value;
                    } else if (key == "Icon") {
                        icon = value;
                    } else if (key == "Name") {
                        displayName = value;
                    }
                    return true;
                });

                if (exec.length) {
                    if (tryExec.length) {
                        const program = findExecutable(tryExec, binPaths);
                        if (!program.length)
                            continue;
                    }
                    return expandExecArgs(unquoteExec(exec), null, icon, displayName, appPath);
                }
            } catch (Exception e) {
            }
        }
        return null;
    }

    static void execShowInFileManager(string[] fileManagerArgs, string toOpen) {
        import std.stdio : File, stderr, stdin, stdout;

        toOpen = absolutePath(toOpen);
        switch (baseName(fileManagerArgs[0])) {
            //nautilus and nemo select item if it's a file
        case "nautilus":
        case "nemo":
            fileManagerArgs ~= toOpen;
            break;
            //dolphin needs --select option
        case "dolphin":
        case "konqueror":
            fileManagerArgs ~= ["--select", toOpen];
            break;
        default: {
                bool pathIsDir;
                collectException(isDir(toOpen), pathIsDir);
                if (!pathIsDir) {
                    fileManagerArgs ~= toOpen.dirName;
                } else {
                    fileManagerArgs ~= toOpen;
                }
            }
            break;
        }

        File inFile, outFile, errFile;
        try {
            inFile = File("/dev/null", "rb");
        } catch (Exception) {
            inFile = stdin;
        }
        try {
            auto nullFile = File("/dev/null", "wb");
            outFile = nullFile;
            errFile = nullFile;
        } catch (Exception) {
            outFile = stdout;
            errFile = stderr;
        }

        auto processConfig = Config.none;
        static if (is(typeof(Config.detached))) {
            processConfig |= Config.detached;
        }
        spawnProcess(fileManagerArgs, inFile, outFile, errFile, null, processConfig);
    }

    string configHome = xdgConfigHome();
    string appHome = xdgDataHome("applications");

    auto configDirs = xdgConfigDirs();
    auto appDirs = xdgDataDirs("applications");

    auto allAppDirs = xdgAllDataDirs("applications");
    auto binPaths = environment.get("PATH").splitter(':').filter!(p => p.length > 0).array;

    string[] fileManagerArgs;
    foreach (mimeappsList; chain(only(configHome), only(appHome), configDirs, appDirs).map!(p => buildPath(p,
            "mimeapps.list"))) {
        try {
            parseConfigFile(mimeappsList, "Default Applications", (string key, string value) {
                if (key == "inode/directory" && value.length) {
                    auto app = value;
                    fileManagerArgs = findFileManagerCommand(app, allAppDirs, binPaths);
                    return false;
                }
                return true;
            });
        } catch (Exception e) {
        }

        if (fileManagerArgs.length) {
            execShowInFileManager(fileManagerArgs, toOpen);
            return true;
        }
    }

    foreach (mimeinfoCache; allAppDirs.map!(p => buildPath(p, "mimeinfo.cache"))) {
        try {
            parseConfigFile(mimeinfoCache, "MIME Cache", (string key, string value) {
                if (key > "inode/directory") // no need to proceed, since MIME types are sorted in alphabetical order.
                    return false;
                if (key == "inode/directory" && value.length) {
                    auto alternatives = value.splitter(';').filter!(p => p.length > 0);
                    foreach (alternative; alternatives) {
                        fileManagerArgs = findFileManagerCommand(alternative, allAppDirs, binPaths);
                        if (fileManagerArgs.length)
                            break;
                    }
                    return false;
                }
                return true;
            });
        } catch (Exception e) {
        }

        if (fileManagerArgs.length) {
            execShowInFileManager(fileManagerArgs, toOpen);
            return true;
        }
    }

    Log.e("showInFileManager: could not find application to open directory");
    return false;
}

void parseConfigFile(string fileName, string wantedGroup,
    scope bool delegate(string, string) onKeyValue) {
    import inilike.common;
    import inilike.range;

    auto r = iniLikeFileReader(fileName);
    foreach (group; r.byGroup()) {
        if (group.groupName != wantedGroup)
            continue;

        foreach (entry; group.byEntry()) {
            if (!entry.length || isComment(entry))
                continue;

            auto pair = parseKeyValue(entry);
            if (!isValidKey(pair.key))
                return;
            if (!onKeyValue(pair.key, pair.value.unescapeValue))
                return;
        }
        return;
    }
}

string[] expandExecArgs(const string[] unquotedArgs, const string[] urls = null,
    string iconName = null, string displayName = null, string fileName = null) {
    static string urlToFilePath(string url) {
        immutable protocol = "file://";
        if (url.length > protocol.length && url[0 .. protocol.length] == protocol)
            return url[protocol.length .. $];
        else
            return url;
    }

    string[] toReturn;
    foreach (token; unquotedArgs) {
        if (token == "%F") {
            foreach (url; urls)
                toReturn ~= urlToFilePath(url);
        } else if (token == "%U") {
            toReturn ~= urls;
        } else if (token == "%i") {
            if (iconName.length) {
                toReturn ~= "--icon";
                toReturn ~= iconName;
            }
        } else {
            static void expand(string token, ref string expanded,
                ref size_t restPos, ref size_t i, string insert) {
                if (token.length == 2) {
                    expanded = insert;
                } else {
                    expanded ~= token[restPos .. i] ~ insert;
                }
                restPos = i + 2;
                i++;
            }

            string expanded;
            size_t restPos;
            bool ignore;
            loop: foreach (i; 0 .. token.length) {
                if (token[i] == '%' && i + 1 < token.length) {
                    switch (token[i + 1]) {
                    case 'f':
                    case 'u':
                        if (urls.length) {
                            string arg = urls[0];
                            if (token[i + 1] == 'f') {
                                arg = urlToFilePath(arg);
                            }
                            expand(token, expanded, restPos, i, arg);
                        } else {
                            ignore = true;
                            break loop;
                        }
                        break;
                    case 'c':
                        expand(token, expanded, restPos, i, displayName);
                        break;
                    case 'k':
                        expand(token, expanded, restPos, i, fileName);
                        break;
                    case 'd':
                    case 'D':
                    case 'n':
                    case 'N':
                    case 'm':
                    case 'v':
                        ignore = true;
                        break loop;
                    case '%':
                        expand(token, expanded, restPos, i, "%");
                        break;
                    default:
                        throw new Exception("Unknown or misplaced field code: " ~ token);
                    }
                }
            }

            if (!ignore) {
                toReturn ~= expanded ~ token[restPos .. $];
            }
        }
    }
    return toReturn;
}

string[] unquoteExec(string unescapedValue) {
    import std.exception : assumeUnique;
    import std.typecons : Tuple, tuple;
    import inilike.common : doUnescape;

    auto value = unescapedValue;
    string[] result;
    size_t i;

    static string unescapeQuotedArgument(string value) {
        static immutable Tuple!(char, char)[] pairs = [
            tuple('`', '`'), tuple('$', '$'), tuple('"', '"'), tuple('\\', '\\')
        ];
        return doUnescape(value, pairs);
    }

    static string parseQuotedPart(ref size_t i, char delimeter, string value) {
        size_t start = ++i;
        bool inQuotes = true;

        while (i < value.length && inQuotes) {
            if (value[i] == '\\' && value.length > i + 1 && value[i + 1] == '\\') {
                i += 2;
                continue;
            }

            inQuotes = !(value[i] == delimeter && (value[i - 1] != '\\' || (i >= 2 &&
                    value[i - 1] == '\\' && value[i - 2] == '\\')));
            if (inQuotes) {
                i++;
            }
        }
        if (inQuotes) {
            throw new Exception("Missing pair quote");
        }
        return unescapeQuotedArgument(value[start .. i]);
    }

    char[] append;
    bool wasInQuotes;
    while (i < value.length) {
        if (value[i] == ' ' || value[i] == '\t') {
            if (!wasInQuotes && append.length >= 1 && append[$ - 1] == '\\') {
                append[$ - 1] = value[i];
            } else {
                if (append.length) {
                    result ~= assumeUnique(append);
                    append = null;
                }
            }
            wasInQuotes = false;
        } else if (value[i] == '"' || value[i] == '\'') {
            append ~= parseQuotedPart(i, value[i], value);
            wasInQuotes = true;
        } else {
            append ~= value[i];
            wasInQuotes = false;
        }
        i++;
    }
    if (append.length)
        result ~= assumeUnique(append);
    return result;
}
// dfmt off
} else {
// dfmt on
bool showInFileManagerImpl(string pathName) {
    Log.w("showInFileManager is not implemented for this platform");
    return false;
}
}
