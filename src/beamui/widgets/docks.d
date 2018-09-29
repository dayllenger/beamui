/**
This module implements dockable windows UI support.

DockHost is main layout for docking support - contains body widget and optional docked windows.

DockWindow is window to use with DockHost - can be docked on top, left, right or bottom side of DockHost.

Synopsis:
---
import beamui.widgets.docks;
---

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.docks;

import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.winframe;

/// Dock alignment types
enum DockAlignment
{
    /// At left of body
    left,
    /// At right of body
    right,
    /// Above body
    top,
    /// Below body
    bottom
}

struct DockSpace
{
    @property
    {
        DockWindow[] docks()
        {
            return _docks;
        }

        DockAlignment alignment() const
        {
            return _alignment;
        }

        Resizer resizer()
        {
            return _resizer;
        }

        int space() const
        {
            return _space;
        }
    }

    protected
    {
        Box _box;
        DockWindow[] _docks;
        DockHost _host;
        DockAlignment _alignment;
        Resizer _resizer;
        int _space;
    }

    Resizer initialize(DockHost host, DockAlignment a)
    {
        _host = host;
        _alignment = a;
        final switch (a) with (DockAlignment)
        {
        case top:
            _resizer = new Resizer(Orientation.vertical);
            break;
        case bottom:
            _resizer = new Resizer(Orientation.vertical);
            break;
        case left:
            _resizer = new Resizer(Orientation.horizontal);
            break;
        case right:
            _resizer = new Resizer(Orientation.horizontal);
            break;
        }
        _resizer.visibility = Visibility.gone;
        _resizer.resized = &onResize;
        return _resizer;
    }

    protected int _dragStartSpace;

    protected void onResize(Resizer source, ResizerEventType event, int dragDelta)
    {
        if (!_space)
            return;
        if (event == ResizerEventType.startDragging)
        {
            _dragStartSpace = _space;
        }
        else if (event == ResizerEventType.dragging)
        {
            int dir = _alignment == DockAlignment.left || _alignment == DockAlignment.top ? 1 : -1;
            _space = _dragStartSpace + dir * dragDelta;
        }
    }

    protected int _minSpace;
    protected int _maxSpace;
    /// Host to be layed out
    void beforeLayout(Box box, DockWindow[] docks)
    {
        _docks = docks;
        if (docks.length)
        {
            int baseSize = _resizer.orientation == Orientation.horizontal ? box.w : box.h;
            _space = clamp(_space, baseSize * 1 / 10, baseSize * 4 / 10);
            _resizer.visibility = Visibility.visible;
        }
        else
        {
            _space = 0;
            _resizer.visibility = Visibility.gone;
        }
    }

    void layout(Box geom)
    {
        if (_space)
        {
            Box b = geom;

            Box rb = geom;
            int rsz = 3; // resizer width or height
            final switch (_alignment) with (DockAlignment)
            {
            case top:
                rb.y = rb.y + rb.h - rsz;
                rb.h = rsz;
                b.h -= rsz;
                break;
            case bottom:
                rb.h = rsz;
                b.y += rsz;
                b.h -= rsz;
                break;
            case left:
                rb.x = rb.x + rb.w - rsz;
                rb.w = rsz;
                b.w -= rsz;
                break;
            case right:
                rb.w = rsz;
                b.x += rsz;
                b.w -= rsz;
                break;
            }

            // lay out resizer
            _resizer.layout(rb);

            // lay out docked windows
            int len = cast(int)_docks.length;
            foreach (i; 0 .. len)
            {
                Box ibox = b;
                if (len > 1)
                {
                    if (_resizer.orientation == Orientation.horizontal)
                    {
                        ibox.y = b.y + b.h * i / len;
                        ibox.h = b.h / len;
                    }
                    else
                    {
                        ibox.x = b.x + b.w * i / len;
                        ibox.w = b.w / len;
                    }
                }
                _docks[i].layout(ibox);
            }
        }
    }
}

/// Layout for docking support - contains body widget and optional docked windows
class DockHost : WidgetGroupDefaultDrawing
{
    @property
    {
        Widget bodyWidget()
        {
            return _bodyWidget;
        }

        void bodyWidget(Widget widget)
        {
            _children.replace(widget, _bodyWidget);
            _bodyWidget = widget;
            _bodyWidget.fillWH();
            _bodyWidget.parent = this;
        }

        DockAlignment[4] layoutPriority() const
        {
            return _layoutPriority;
        }
        void layoutPriority(DockAlignment[4] p)
        {
            _layoutPriority = p;
            requestLayout();
        }
    }

    protected
    {
        DockSpace _topSpace;
        DockSpace _bottomSpace;
        DockSpace _rightSpace;
        DockSpace _leftSpace;
        Widget _bodyWidget;

        DockAlignment[4] _layoutPriority = [
            DockAlignment.top, DockAlignment.left, DockAlignment.right, DockAlignment.bottom
        ];
    }

    this()
    {
        addChild(_topSpace.initialize(this, DockAlignment.top));
        addChild(_bottomSpace.initialize(this, DockAlignment.bottom));
        addChild(_leftSpace.initialize(this, DockAlignment.left));
        addChild(_rightSpace.initialize(this, DockAlignment.right));
    }

    void addDockedWindow(DockWindow dockWin)
    {
        addChild(dockWin);
    }

    DockWindow removeDockedWindow(string id)
    {
        DockWindow res = childByID!DockWindow(id);
        if (res)
            removeChild(id);
        return res;
    }

    protected DockWindow[] getDockedWindowList(DockAlignment alignType)
    {
        DockWindow[] list;
        foreach (i; 0 .. _children.count)
        {
            DockWindow item = cast(DockWindow)_children.get(i);
            if (!item)
                continue; // not a docked window
            if (item.dockAlignment == alignType && item.visibility == Visibility.visible)
            {
                list ~= item;
            }
        }
        return list;
    }

    override Boundaries computeBoundaries()
    {
        Boundaries bs;
        foreach (i; 0 .. _children.count)
        {
            Widget item = _children.get(i);
            // TODO: fix
            if (item.visibility != Visibility.gone)
            {
                Boundaries wbs = item.computeBoundaries();
                bs.maximizeWidth(wbs);
                bs.maximizeHeight(wbs);
            }
        }
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geom;
        applyPadding(geom);

        foreach (a; _layoutPriority)
        {
            if (a == DockAlignment.top)
                _topSpace.beforeLayout(geom, getDockedWindowList(DockAlignment.top));
            if (a == DockAlignment.left)
                _leftSpace.beforeLayout(geom, getDockedWindowList(DockAlignment.left));
            if (a == DockAlignment.right)
                _rightSpace.beforeLayout(geom, getDockedWindowList(DockAlignment.right));
            if (a == DockAlignment.bottom)
                _bottomSpace.beforeLayout(geom, getDockedWindowList(DockAlignment.bottom));
        }
        Insets sp;
        foreach (a; _layoutPriority)
        {
            Box b = geom;
            if (a == DockAlignment.top)
            {
                sp.top = _topSpace.space;
                _topSpace.layout(Box(geom.x + sp.left, geom.y,
                                     geom.w - sp.left - sp.right, sp.top));
            }
            if (a == DockAlignment.bottom)
            {
                sp.bottom = _bottomSpace.space;
                _bottomSpace.layout(Box(geom.x + sp.left, geom.y + geom.h - sp.bottom,
                                        geom.w - sp.left - sp.right, sp.bottom));
            }
            if (a == DockAlignment.left)
            {
                sp.left = _leftSpace.space;
                _leftSpace.layout(Box(geom.x, geom.y + sp.top,
                                      sp.left, geom.h - sp.top - sp.bottom));
            }
            if (a == DockAlignment.right)
            {
                sp.right = _rightSpace.space;
                _rightSpace.layout(Box(geom.x + geom.w - sp.right, geom.y + sp.top,
                                       sp.right, geom.h - sp.top - sp.bottom));
            }
        }
        geom.shrink(sp);
        _bodyWidget.maybe.layout(geom);
    }
}

/// Docked window
class DockWindow : WindowFrame
{
    @property DockAlignment dockAlignment()
    {
        return _dockAlignment;
    }

    @property DockWindow dockAlignment(DockAlignment a)
    {
        if (_dockAlignment != a)
        {
            _dockAlignment = a;
            requestLayout();
        }
        return this;
    }

    protected DockAlignment _dockAlignment;

    this()
    {
        focusGroup = true;
    }

    override protected void initialize()
    {
        super.initialize();
        _dockAlignment = DockAlignment.right; // default alignment is right
    }

    //protected Widget createBodyWidget() {
    //    return new Widget("DOCK_WINDOW_BODY");
    //}
}
