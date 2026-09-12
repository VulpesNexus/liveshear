//  ShearBounds.cpp -- see ShearBounds.h.

#include "IllustratorSDK.h"
#include "ShearBounds.h"
#include "LiveShearSuites.h"

#include <cmath>

namespace
{
    /** Control bounds with strokes, effects, and the glyphs of area and path
        text excluded: the same box Illustrator's own transform commands take
        their reference point from. */
    const ai::int32 kGeometricFlags = kControlBounds | kNoExtendedBounds;

    /** Deepest art tree the walk will follow. Illustrator's own nesting limit
        is far below this; the cap only exists so a malformed tree cannot
        recurse without end. */
    const int kMaxDepth = 64;

    bool IsEmptyRect(const AIRealRect& r)
    {
        return r.left > r.right || r.bottom > r.top;
    }

    struct Box
    {
        AIRealRect rect = { 0, 0, 0, 0 };
        bool any = false;

        void AddPoint(double h, double v)
        {
            const AIReal x = static_cast<AIReal>(h);
            const AIReal y = static_cast<AIReal>(v);
            if (!any)
            {
                rect.left = rect.right = x;
                rect.top = rect.bottom = y;
                any = true;
                return;
            }
            if (x < rect.left)   rect.left   = x;
            if (x > rect.right)  rect.right  = x;
            if (y < rect.bottom) rect.bottom = y;
            if (y > rect.top)    rect.top    = y;
        }

        void AddRect(const AIRealRect& r)
        {
            if (IsEmptyRect(r)) return;
            AddPoint(r.left, r.bottom);
            AddPoint(r.right, r.top);
        }
    };

    /** Adds the exact extent of one cubic Bezier segment along one axis.
        Sampling the four control points would overstate it: a curve stays
        inside its control hull but rarely touches it. The extremes are at the
        two ends and wherever the derivative -- a quadratic -- crosses zero
        strictly inside the span. */
    void AddCurveAxis(Box* box, bool vertical,
                      double v0, double v1, double v2, double v3,
                      double other)
    {
        const double a = -v0 + 3.0 * v1 - 3.0 * v2 + v3;
        const double b = 2.0 * (v0 - 2.0 * v1 + v2);
        const double c = v1 - v0;

        double roots[2] = { 0.0, 0.0 };
        int count = 0;
        if (std::fabs(a) < 1.0e-12)
        {
            if (std::fabs(b) > 1.0e-12) roots[count++] = -c / b;
        }
        else
        {
            const double disc = b * b - 4.0 * a * c;
            if (disc >= 0.0)
            {
                const double root = std::sqrt(disc);
                roots[count++] = (-b + root) / (2.0 * a);
                roots[count++] = (-b - root) / (2.0 * a);
            }
        }

        for (int i = 0; i < count; ++i)
        {
            const double t = roots[i];
            if (!(t > 0.0 && t < 1.0)) continue;
            const double u = 1.0 - t;
            const double value = u * u * u * v0 + 3.0 * u * u * t * v1 +
                                 3.0 * u * t * t * v2 + t * t * t * v3;
            // The other coordinate of this extremum lies somewhere between the
            // segment's endpoints, which are already in the box, so passing an
            // endpoint for it widens only the axis being measured.
            if (vertical) box->AddPoint(other, value);
            else          box->AddPoint(value, other);
        }
    }

    void AddCurve(Box* box,
                  const AIRealPoint& p0, const AIRealPoint& p1,
                  const AIRealPoint& p2, const AIRealPoint& p3)
    {
        box->AddPoint(p0.h, p0.v);
        box->AddPoint(p3.h, p3.v);
        AddCurveAxis(box, false, p0.h, p1.h, p2.h, p3.h, p0.v);
        AddCurveAxis(box, true,  p0.v, p1.v, p2.v, p3.v, p0.h);
    }

    bool AddPath(AIArtHandle art, Box* box)
    {
        ai::int16 count = 0;
        if (sAIPath->GetPathSegmentCount(art, &count) || count <= 0) return false;

        AIBoolean closed = false;
        sAIPath->GetPathClosed(art, &closed);

        AIPathSegment previous;
        AIPathSegment first;
        bool havePrevious = false;

        for (ai::int16 i = 0; i < count; ++i)
        {
            AIPathSegment segment;
            if (sAIPath->GetPathSegments(art, i, 1, &segment)) return false;
            if (i == 0) first = segment;
            if (havePrevious) AddCurve(box, previous.p, previous.out, segment.in, segment.p);
            else              box->AddPoint(segment.p.h, segment.p.v);
            previous = segment;
            havePrevious = true;
        }
        if (closed && count > 1) AddCurve(box, previous.p, previous.out, first.in, first.p);
        return true;
    }

    /** Walks the art ourselves. Paths are measured exactly from their segments;
        anything else is asked of the host one leaf at a time, which is a
        smaller request than the one it refused for the whole tree. */
    void ComputeBounds(AIArtHandle art, Box* box, int depth)
    {
        if (art == nullptr || depth > kMaxDepth) return;

        short type = kUnknownArt;
        if (sAIArt->GetArtType(art, &type)) return;

        if (type == kGroupArt || type == kCompoundPathArt)
        {
            // The union of the children, clipping groups included. It is
            // tempting to intersect a clipping group's contents with its mask,
            // but Illustrator does not: the geometric bounds it reports for a
            // clipped group are the union, and matching the host is the whole
            // point of this function.
            AIArtHandle child = nullptr;
            if (sAIArt->GetArtFirstChild(art, &child)) return;
            while (child != nullptr)
            {
                ComputeBounds(child, box, depth + 1);
                AIArtHandle next = nullptr;
                if (sAIArt->GetArtSibling(child, &next)) break;
                child = next;
            }
            return;
        }

        if (type == kPathArt && AddPath(art, box)) return;

        AIRealRect leaf = { 0, 0, 0, 0 };
        if (!sAIArt->GetArtTransformBounds(art, nullptr, kGeometricFlags, &leaf))
        {
            box->AddRect(leaf);
            return;
        }
        if (!sAIArt->GetArtBounds(art, &leaf)) box->AddRect(leaf);
    }
}

namespace shear
{

const char* BoundsRouteName(BoundsRoute route)
{
    switch (route)
    {
        case kBoundsHostPrecise: return "host-precise";
        case kBoundsHost:        return "host";
        case kBoundsComputed:    return "computed";
        case kBoundsVisible:     return "visible";
        default:                 return "failed";
    }
}

BoundsRoute GeometricBounds(AIArtHandle art, AIRealRect* bounds)
{
    if (art == nullptr || bounds == nullptr) return kBoundsFailed;

    // AIReal is a double in this SDK and AIRealRect is AIDoubleRect, so the
    // two calls differ in which internal path they take rather than in
    // precision. Both are tried because the host answers them independently.
    AIRealRect precise = { 0, 0, 0, 0 };
    if (!sAIArt->GetPreciseArtTransformBounds(art, nullptr, kGeometricFlags, &precise) &&
        !IsEmptyRect(precise))
    {
        *bounds = precise;
        return kBoundsHostPrecise;
    }

    AIRealRect host = { 0, 0, 0, 0 };
    if (!sAIArt->GetArtTransformBounds(art, nullptr, kGeometricFlags, &host) && !IsEmptyRect(host))
    {
        *bounds = host;
        return kBoundsHost;
    }

    Box box;
    ComputeBounds(art, &box, 0);
    if (box.any && !IsEmptyRect(box.rect))
    {
        *bounds = box.rect;
        return kBoundsComputed;
    }

    AIRealRect visible = { 0, 0, 0, 0 };
    if (!sAIArt->GetArtBounds(art, &visible) && !IsEmptyRect(visible))
    {
        *bounds = visible;
        return kBoundsVisible;
    }
    return kBoundsFailed;
}

bool BoundsByRoute(AIArtHandle art, BoundsRoute route, AIRealRect* bounds)
{
    if (art == nullptr || bounds == nullptr) return false;
    AIRealRect r = { 0, 0, 0, 0 };
    switch (route)
    {
        case kBoundsHostPrecise:
            if (sAIArt->GetPreciseArtTransformBounds(art, nullptr, kGeometricFlags, &r)) return false;
            break;
        case kBoundsHost:
            if (sAIArt->GetArtTransformBounds(art, nullptr, kGeometricFlags, &r)) return false;
            break;
        case kBoundsComputed:
        {
            Box box;
            ComputeBounds(art, &box, 0);
            if (!box.any) return false;
            r = box.rect;
            break;
        }
        case kBoundsVisible:
            if (sAIArt->GetArtBounds(art, &r)) return false;
            break;
        default:
            return false;
    }
    if (IsEmptyRect(r)) return false;
    *bounds = r;
    return true;
}

AIRealPoint CenterOf(const AIRealRect& r)
{
    AIRealPoint c;
    c.h = static_cast<AIReal>((static_cast<double>(r.left) + static_cast<double>(r.right)) / 2.0);
    c.v = static_cast<AIReal>((static_cast<double>(r.top) + static_cast<double>(r.bottom)) / 2.0);
    return c;
}

} // namespace shear
