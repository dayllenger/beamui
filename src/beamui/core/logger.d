/**
Logging utilities.

Log class provides several short static methods for writing logs.

You can choose more or less verbose logging level.
The levels have such importance order: fatal, error, warning, info, debug, trace.

Synopsis:
---
// setup:

// use stderr (standard error output stream) for logging
Log.setStderrLogger();
// set log level
Log.setLogLevel(LogLevel.debug_);

// usage:

// log debug message
Log.d("mouse clicked at ", x, ",", y);
// or with format string:
Log.fd("mouse clicked at %d,%d", x, y);
// log error message
Log.e("exception while reading file", e);
---


For Android, set log tag instead of setXXXLogger:

---
Log.setLogTag("myApp");
---

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.logger;

nothrow @safe:

import core.sync.mutex;
import std.stdio : File, printf, stdout, stderr, writef;
version (Android)
{
    import android.log;
}

/// Log levels
enum LogLevel : ubyte
{
    /// Fatal error, cannot resume
    fatal,
    /// Error
    error,
    /// Warning
    warn,
    /// Informational message
    info,
    /// Debug message
    debug_,
    /// Tracing message
    trace
}

/// Returns timestamp in milliseconds since 1970 UTC similar to Java System.currentTimeMillis()
@property long currentTimeMillis()
{
    import std.datetime : Clock;

    try
        return Clock.currStdTime / 10000;
    catch (Exception)
        assert(0);
}

shared static this()
{
    Log.mutex = new shared(Mutex);
}

class Log
{
    static nothrow:

    private
    {
        shared LogLevel logLevel = LogLevel.info;
        shared Mutex mutex;
        __gshared File* logFile;
    }

    /// Redirects output to stdout
    void setStdoutLogger() @trusted
    {
        try
        {
            synchronized (mutex)
            {
                logFile = &stdout();
            }
        }
        catch (Exception e)
            printException(e);
    }

    /// Redirects output to stderr
    void setStderrLogger() @trusted
    {
        try
        {
            synchronized (mutex)
            {
                logFile = &stderr();
            }
        }
        catch (Exception e)
            printException(e);
    }

    /// Redirects output to file
    void setFileLogger(File* file) @trusted
    {
        try
        {
            synchronized (mutex)
            {
                if (logFile !is null && *logFile != stdout && *logFile != stderr)
                {
                    logFile.close();
                    destroy(logFile);
                    logFile = null;
                }
                logFile = file;
                if (logFile !is null)
                    logFile.writeln("beamui log file");
            }
        }
        catch (Exception e)
            printException(e);
    }

    /// Set a log level
    void setLogLevel(LogLevel level)
    {
        logLevel = level;
        i("Log level changed to ", level);
    }

    /// Returns true if messages for level are enabled
    bool isLogLevelEnabled(LogLevel level)
    {
        return logLevel >= level;
    }

    /// Returns true if debug log level is enabled
    @property bool debugEnabled()
    {
        return logLevel >= LogLevel.debug_;
    }

    /// Returns true if trace log level is enabled
    @property bool traceEnabled()
    {
        return logLevel >= LogLevel.trace;
    }

    /// Returns true if warn log level is enabled
    @property bool warnEnabled()
    {
        return logLevel >= LogLevel.warn;
    }

    /// Log level to name helper function
    string logLevelName(LogLevel level)
    {
        final switch (level) with (LogLevel)
        {
        case fatal:
            return "F";
        case error:
            return "E";
        case warn:
            return "W";
        case info:
            return "I";
        case debug_:
            return "D";
        case trace:
            return "V";
        }
    }

    version (Android)
    {
        void setLogTag(const char* tag)
        {
            ANDROID_LOG_TAG = tag;
        }

        private android_LogPriority toAndroidLogPriority(LogLevel level)
        {
            final switch (level) with (LogLevel)
            {
            case fatal:
                return android_LogPriority.ANDROID_LOG_FATAL;
            case error:
                return android_LogPriority.ANDROID_LOG_ERROR;
            case warn:
                return android_LogPriority.ANDROID_LOG_WARN;
            case info:
                return android_LogPriority.ANDROID_LOG_INFO;
            case debug_:
                return android_LogPriority.ANDROID_LOG_DEBUG;
            case trace:
                return android_LogPriority.ANDROID_LOG_VERBOSE;
            }
        }
    }

    /// Log message with arbitrary log level
    void log(S...)(LogLevel level, S args)
    {
        logImpl(level, args);
    }
    /// Log message with arbitrary log level with format string
    void logf(S...)(LogLevel level, string fmt, S args)
    {
        logfImpl(level, fmt, args);
    }
    /// Log verbose / trace message
    void v(S...)(S args)
    {
        logImpl(LogLevel.trace, args);
    }
    /// Log verbose / trace message with format string
    void fv(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.trace, fmt, args);
    }
    /// Log debug message
    void d(S...)(S args)
    {
        logImpl(LogLevel.debug_, args);
    }
    /// Log debug message with format string
    void fd(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.debug_, fmt, args);
    }
    /// Log info message
    void i(S...)(S args)
    {
        logImpl(LogLevel.info, args);
    }
    /// Log info message
    void fi(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.info, fmt, args);
    }
    /// Log warn message
    void w(S...)(S args)
    {
        logImpl(LogLevel.warn, args);
    }
    /// Log warn message
    void fw(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.warn, fmt, args);
    }
    /// Log error message
    void e(S...)(S args)
    {
        logImpl(LogLevel.error, args);
    }
    /// Log error message
    void fe(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.error, fmt, args);
    }
    /// Log fatal error message
    void f(S...)(S args)
    {
        logImpl(LogLevel.fatal, args);
    }
    /// Log fatal error message
    void ff(S...)(string fmt, S args)
    {
        logfImpl(LogLevel.fatal, fmt, args);
    }

    private void logImpl(S...)(LogLevel level, ref const S args) @trusted
    {
        try
        {
            synchronized (mutex)
            {
                if (logLevel < level)
                    return;

                version (Android)
                {
                    import std.conv : to;

                    char[] msg;
                    foreach (arg; args)
                    {
                        msg ~= to!string(arg);
                    }
                    msg ~= '\0';
                    __android_log_write(toAndroidLogPriority(level), ANDROID_LOG_TAG, msg.ptr);
                }
                else
                {
                    import std.datetime : SysTime, Clock;

                    if (logFile !is null && logFile.isOpen)
                    {
                        SysTime ts = Clock.currTime();
                        logFile.writef("%04d-%02d-%02d %02d:%02d:%02d.%03d %s  ", ts.year, ts.month,
                                ts.day, ts.hour, ts.minute, ts.second, ts.fracSecs.split!("msecs")
                                .msecs, logLevelName(level));
                        logFile.writeln(args);
                        logFile.flush();
                    }
                }
            }
        }
        catch (Exception e)
            printException(e);
    }
    private void logfImpl(S...)(LogLevel level, string fmt, ref const S args) @trusted
    {
        try
        {
            synchronized (mutex)
            {
                if (logLevel < level)
                    return;

                version (Android)
                {
                    import std.format : format;

                    string msg = format(fmt, args);
                    __android_log_write(toAndroidLogPriority(level), ANDROID_LOG_TAG, toStringz(msg));
                }
                else
                {
                    import std.datetime : SysTime, Clock;

                    if (logFile !is null && logFile.isOpen)
                    {
                        SysTime ts = Clock.currTime();
                        logFile.writef("%04d-%02d-%02d %02d:%02d:%02d.%03d %s  ", ts.year, ts.month,
                                ts.day, ts.hour, ts.minute, ts.second, ts.fracSecs.split!("msecs")
                                .msecs, logLevelName(level));
                        logFile.writefln(fmt, args);
                        logFile.flush();
                    }
                }
            }
        }
        catch (Exception e)
            printException(e);
    }

    private void printException(Exception e) @trusted
    {
        printf("\nAn exception inside the logger: %.*s\n", e.msg.length, e.msg.ptr);
    }
}
