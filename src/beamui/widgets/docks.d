/**
Dockable windows.

DockHost is main layout for docking support - contains body widget and optional docked windows.

DockWindow is window to use with DockHost - can be docked on top, left, right or bottom side of DockHost.

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.docks;

import beamui.layout.linear : Resizer, ResizerEventType;
import beamui.widgets.controls;
import beamui.widgets.widget;
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
        DockWindow[] docks() { return _docks; }

        DockAlignment alignment() const { return _alignment; }

        Resizer resizer() { return _resizer; }

        int space() const { return _space; }
    }

    private
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
        _resizer.onResize ~= &handleResize;
        return _resizer;
    }

    private int _dragStartSpace;

    protected void handleResize(ResizerEventType event, int dragDelta)
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

    private int _minSpace;
    private int _maxSpace;
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
class DockHost : WidgetGroup
{
    @property
    {
        Widget bodyWidget() { return _bodyWidget; }
        /// ditto
        void bodyWidget(Widget widget)
        {
            if (_bodyWidget)
            {
                replaceChild(_bodyWidget, widget);
                destroy(_bodyWidget);
            }
            else
                addChild(widget);
            _bodyWidget = widget;
        }

        DockAlignment[4] layoutPriority() const { return _layoutPriority; }
        /// ditto
        void layoutPriority(DockAlignment[4] p)
        {
            _layoutPriority = p;
            requestLayout();
        }
    }

    private
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
        foreach (i; 0 .. childCount)
        {
            DockWindow item = cast(DockWindow)child(i);
            if (!item)
                continue; // not a docked window
            if (item.dockAlignment == alignType && item.visibility == Visibility.visible)
            {
                list ~= item;
            }
        }
        return list;
    }

    override void measure()
    {
        Boundaries bs;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            // TODO: fix
            if (item.visibility != Visibility.gone)
            {
                item.measure();
                bs.maximize(item.boundaries);
            }
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        setBox(geom);
        const inner = innerBox;

        foreach (a; _layoutPriority)
        {
            if (a == DockAlignment.top)
                _topSpace.beforeLayout(inner, getDockedWindowList(DockAlignment.top));
            if (a == DockAlignment.left)
                _leftSpace.beforeLayout(inner, getDockedWindowList(DockAlignment.left));
            if (a == DockAlignment.right)
                _rightSpace.beforeLayout(inner, getDockedWindowList(DockAlignment.right));
            if (a == DockAlignment.bottom)
                _bottomSpace.beforeLayout(inner, getDockedWindowList(DockAlignment.bottom));
        }
        Insets sp;
        foreach (a; _layoutPriority)
        {
            if (a == DockAlignment.top)
            {
                sp.top = _topSpace.space;
                _topSpace.layout(Box(inner.x + sp.left, inner.y,
                                     inner.w - sp.left - sp.right, sp.top));
            }
            if (a == DockAlignment.bottom)
            {
                sp.bottom = _bottomSpace.space;
                _bottomSpace.layout(Box(inner.x + sp.left, inner.y + inner.h - sp.bottom,
                                        inner.w - sp.left - sp.right, sp.bottom));
            }
            if (a == DockAlignment.left)
            {
                sp.left = _leftSpace.space;
                _leftSpace.layout(Box(inner.x, inner.y + sp.top,
                                      sp.left, inner.h - sp.top - sp.bottom));
            }
            if (a == DockAlignment.right)
            {
                sp.right = _rightSpace.space;
                _rightSpace.layout(Box(inner.x + inner.w - sp.right, inner.y + sp.top,
                                       sp.right, inner.h - sp.top - sp.bottom));
            }
        }
        _bodyWidget.maybe.layout(inner.shrinked(sp));
    }

    override protected void drawContent(Painter pr)
    {
        drawAllChildren(pr);
    }
}

/// Docked window
class DockWindow : WindowFrame
{
    @property DockAlignment dockAlignment() const { return _dockAlignment; }
    /// ditto
    @property void dockAlignment(DockAlignment a)
    {
        if (_dockAlignment != a)
        {
            _dockAlignment = a;
            requestLayout();
        }
    }

    private DockAlignment _dockAlignment;

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
