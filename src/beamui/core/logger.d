/**
Logging utilities.

Log class provides several short static methods for writing logs.

You can choose more or less verbose logging level.
The levels have such importance order: fatal, error, warning, info, debug, trace.

Synopsis:
---
import beamui.core.logger;

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

import core.sync.mutex;
import std.stdio;
version (Android)
{
    import android.log;
}

/// Log levels
enum LogLevel
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

    return Clock.currStdTime / 10000;
}

class Log
{
static:
    __gshared private
    {
        LogLevel logLevel = LogLevel.info;
        File* logFile;
        Mutex _mutex;
    }

    @property Mutex mutex()
    {
        if (_mutex is null)
            _mutex = new Mutex;
        return _mutex;
    }

    /// Redirects output to stdout
    void setStdoutLogger()
    {
        synchronized (mutex)
        {
            logFile = &stdout();
        }
    }

    /// Redirects output to stderr
    void setStderrLogger()
    {
        synchronized (mutex)
        {
            logFile = &stderr();
        }
    }

    /// Redirects output to file
    void setFileLogger(File* file)
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

    /// Set log level (one of LogLevel)
    void setLogLevel(LogLevel level)
    {
        synchronized (mutex)
        {
            logLevel = level;
            i("Log level changed to ", level);
        }
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
        if (logLevel >= level)
        {
            version (Android)
            {
                import std.conv : to;

                char[] msg;
                foreach (arg; args)
                {
                    msg ~= to!string(arg);
                }
                msg ~= cast(char)0;
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
    /// Log message with arbitrary log level with format string
    void logf(S...)(LogLevel level, string fmt, S args)
    {
        if (logLevel >= level)
        {
            version (Android)
            {
                import std.format : format;

                string msg = fmt.format(args);
                __android_log_write(toAndroidLogPriority(level), ANDROID_LOG_TAG, msg.toStringz);
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
    /// Log verbose / trace message
    void v(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.trace)
                log(LogLevel.trace, args);
        }
    }
    /// Log verbose / trace message with format string
    void fv(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.trace)
                logf(LogLevel.trace, args);
        }
    }
    /// Log debug message
    void d(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.debug_)
                log(LogLevel.debug_, args);
        }
    }
    /// Log debug message with format string
    void fd(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.debug_)
                logf(LogLevel.debug_, args);
        }
    }
    /// Log info message
    void i(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.info)
                log(LogLevel.info, args);
        }
    }
    /// Log info message
    void fi(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.info)
                logf(LogLevel.info, args);
        }
    }
    /// Log warn message
    void w(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.warn)
                log(LogLevel.warn, args);
        }
    }
    /// Log warn message
    void fw(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.warn)
                logf(LogLevel.warn, args);
        }
    }
    /// Log error message
    void e(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.error)
                log(LogLevel.error, args);
        }
    }
    /// Log error message
    void fe(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.error)
                logf(LogLevel.error, args);
        }
    }
    /// Log fatal error message
    void f(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.fatal)
                log(LogLevel.fatal, args);
        }
    }
    /// Log fatal error message
    void ff(S...)(S args)
    {
        synchronized (mutex)
        {
            if (logLevel >= LogLevel.fatal)
                logf(LogLevel.fatal, args);
        }
    }
}

debug
{
    /// Set to true when exiting main - to detect destructor calls for resources by GC
    __gshared bool APP_IS_SHUTTING_DOWN = false;

    void onResourceDestroyWhileShutdown(string resourceName, string objname = null)
    {
        Log.e("Resource leak: destroying resource while shutdown! ", resourceName, ", ", objname);
    }
}
