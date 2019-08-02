/**
Static bindings to XSync extension of Xlib. Should link with Xext.

Copyright 1991, 1993, 1994, 1998  The Open Group
Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
OPEN GROUP BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
Except as contained in this notice, the name of The Open Group shall not be
used in advertising or otherwise to promote the sale, use or other dealings
in this Software without prior written authorization from The Open Group.

Copyright 1991,1993 by Digital Equipment Corporation, Maynard, Massachusetts,
and Olivetti Research Limited, Cambridge, England.
                        All Rights Reserved
Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted,
provided that the above copyright notice appear in all copies and that
both that copyright notice and this permission notice appear in
supporting documentation, and that the names of Digital or Olivetti
not be used in advertising or publicity pertaining to distribution of the
software without specific, written prior permission.
DIGITAL AND OLIVETTI DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS, IN NO EVENT SHALL THEY BE LIABLE FOR ANY SPECIAL, INDIRECT OR
CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
*/
module xsync;

import core.stdc.config : c_ulong;
import x11.X : Drawable, Time, XID;
import x11.Xlib : Bool, Display, Status;

version (Posix):
extern (C) nothrow @nogc:

enum SYNC_NAME = "SYNC";
enum SYNC_MAJOR_VERSION = 3;
enum SYNC_MINOR_VERSION = 1;

enum XSyncCounterNotify = 0;
enum XSyncAlarmNotify = 1;
enum XSyncAlarmNotifyMask = 1L << XSyncAlarmNotify;
enum XSyncNumberEvents = 2L;
enum XSyncBadCounter = 0L;
enum XSyncBadAlarm = 1L;
enum XSyncBadFence = 2L;
enum XSyncNumberErrors = XSyncBadFence + 1;

/* Flags for Alarm Attributes */

enum XSyncCACounter = 1L << 0;
enum XSyncCAValueType = 1L << 1;
enum XSyncCAValue = 1L << 2;
enum XSyncCATestType = 1L << 3;
enum XSyncCADelta = 1L << 4;
enum XSyncCAEvents = 1L << 5;

/// Constants for the `value_type` argument of various requests
enum XSyncValueType
{
    absolute,
    relative
}

/// Alarm Test types
enum XSyncTestType
{
    positiveTransition,
    negativeTransition,
    positiveComparison,
    negativeComparison
}

/// Alarm state constants
enum XSyncAlarmState
{
    active,
    inactive,
    destroyed
}

alias XSyncCounter = XID;
alias XSyncAlarm = XID;
alias XSyncFence = XID;

struct XSyncValue
{
    int hi;
    uint lo;

nothrow @nogc:

    void intToValue(int i)
    {
        hi = i < 0 ? ~0 : 0;
        lo = i;
    }

    bool isNegative() const
    {
        return (hi & 0x80000000) != 0;
    }

    bool isZero() const
    {
        return lo == 0 && hi == 0;
    }

    bool isPositive() const
    {
        return (hi & 0x80000000) == 0;
    }

    void add(XSyncValue a, XSyncValue b, ref bool overflow)
    {
        const int t = a.lo;
        const signa = a.isNegative;
        const signb = b.isNegative;
        lo = a.lo + b.lo;
        hi = a.hi + b.hi;
        if (t > lo)
            hi++;
        overflow = signa == signb && signa != isNegative;
    }

    void subtract(XSyncValue a, XSyncValue b, ref bool overflow)
    {
        const int t = a.lo;
        const signa = a.isNegative;
        const signb = b.isNegative;
        lo = a.lo - b.lo;
        hi = a.hi - b.hi;
        if (t < lo)
            hi--;
        overflow = signa == signb && signa != isNegative;
    }

    void toMaxValue()
    {
        hi = 0x7fffffff;
        lo = 0xffffffff;
    }

    void toMinValue()
    {
        hi = 0x80000000;
        lo = 0;
    }

    int opCmp(XSyncValue v) const
    {
        if (hi < v.hi)
            return -1;
        if (hi > v.hi)
            return 1;
        if (lo < v.lo)
            return -1;
        if (lo > v.lo)
            return 1;
        return 0;
    }
}

struct XSyncSystemCounter
{
    char* name; /// null-terminated name of system counter
    XSyncCounter counter; /// counter id of this system counter
    XSyncValue resolution; /// resolution of this system counter
}

struct XSyncTrigger
{
    XSyncCounter counter; /// counter to trigger on
    XSyncValueType value_type; /// absolute/relative
    XSyncValue wait_value; /// value to compare counter to
    XSyncTestType test_type; /// pos/neg comparison/transtion
}

struct XSyncWaitCondition
{
    XSyncTrigger trigger; /// trigger for await
    XSyncValue event_threshold; /// send event if past threshold
}

struct XSyncAlarmAttributes
{
    XSyncTrigger trigger;
    XSyncValue delta;
    Bool events;
    XSyncAlarmState state;
}

/* Events */

struct XSyncCounterNotifyEvent
{
    int type; /// event base + `XSyncCounterNotify`
    c_ulong serial; /// # of last request processed by server
    Bool send_event; /// true if this came from a SendEvent request
    Display* display; /// `Display` the event was read from
    XSyncCounter counter; /// counter involved in await
    XSyncValue wait_value; /// value being waited for
    XSyncValue counter_value; /// counter value when this event was sent
    Time time; /// milliseconds
    int count; /// how many more events to come
    Bool destroyed; /// `True` if counter was destroyed
}

struct XSyncAlarmNotifyEvent
{
    int type; /// event base + `XSyncAlarmNotify`
    c_ulong serial; /// # of last request processed by server
    Bool send_event; /// true if this came from a `SendEvent` request
    Display* display; /// `Display` the event was read from
    XSyncAlarm alarm; /// alarm that triggered
    XSyncValue counter_value; /// value that triggered the alarm
    XSyncValue alarm_value; /// test  value of trigger in alarm
    Time time; /// milliseconds
    XSyncAlarmState state; /// new state of alarm
}

/* Errors */

struct XSyncAlarmError
{
    int type;
    Display* display; /// `Display` the event was read from
    XSyncAlarm alarm; /// resource id
    c_ulong serial; /// serial number of failed request
    ubyte error_code; /// error base + `XSyncBadAlarm`
    ubyte request_code; /// Major op-code of failed request
    ubyte minor_code; /// Minor op-code of failed request
}

struct XSyncCounterError
{
    int type;
    Display* display; /// `Display` the event was read from
    XSyncCounter counter; /// resource id
    c_ulong serial; /// serial number of failed request
    ubyte error_code; /// error base + `XSyncBadCounter`
    ubyte request_code; /// Major op-code of failed request
    ubyte minor_code; /// Minor op-code of failed request
}

/* Prototypes */

Status XSyncQueryExtension(Display* dpy, int* event_base_return, int* error_base_return);
Status XSyncInitialize(Display* dpy, int* major_version_return, int* minor_version_return);
XSyncSystemCounter* XSyncListSystemCounters(Display* dpy, int* n_counters_return);
void XSyncFreeSystemCounterList(XSyncSystemCounter* list);
XSyncCounter XSyncCreateCounter(Display* dpy, XSyncValue initial_value);
Status XSyncSetCounter(Display* dpy, XSyncCounter counter, XSyncValue value);
Status XSyncChangeCounter(Display* dpy, XSyncCounter counter, XSyncValue value);
Status XSyncDestroyCounter(Display* dpy, XSyncCounter counter);
Status XSyncQueryCounter(Display* dpy, XSyncCounter counter, XSyncValue* value_return);
Status XSyncAwait(Display* dpy, XSyncWaitCondition* wait_list, int n_conditions);
XSyncAlarm XSyncCreateAlarm(Display* dpy, c_ulong values_mask, XSyncAlarmAttributes* values);
Status XSyncDestroyAlarm(Display* dpy, XSyncAlarm alarm);
Status XSyncQueryAlarm(Display* dpy, XSyncAlarm alarm, XSyncAlarmAttributes* values_return);
Status XSyncChangeAlarm(Display* dpy, XSyncAlarm alarm, c_ulong values_mask,
        XSyncAlarmAttributes* values);
Status XSyncSetPriority(Display* dpy, XID client_resource_id, int priority);
Status XSyncGetPriority(Display* dpy, XID client_resource_id, int* return_priority);
XSyncFence XSyncCreateFence(Display* dpy, Drawable d, Bool initially_triggered);
Bool XSyncTriggerFence(Display* dpy, XSyncFence fence);
Bool XSyncResetFence(Display* dpy, XSyncFence fence);
Bool XSyncDestroyFence(Display* dpy, XSyncFence fence);
Bool XSyncQueryFence(Display* dpy, XSyncFence fence, Bool* triggered);
Bool XSyncAwaitFence(Display* dpy, const XSyncFence* fence_list, int n_fences);
