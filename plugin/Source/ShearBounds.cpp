//  ShearBounds.cpp -- see ShearBounds.h.

#include "IllustratorSDK.h"
#include "ShearBounds.h"
#include "LiveShearSuites.h"
#include "ShearCurve.h"

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

    using shear::Box;
    using shear::AddCubic;

    bool AddPath(AIArtHandle art, Box* box)
    {
        ai::int16 count = 0;
        if (sAIPath->GetPathSegmentCount(art, &count) || count <= 0) return false;

        AIBoolean closed = false;
        sAIPath->GetPathClosed(art, &closed);

        AIPathSegment previous = {};
        AIPathSegment first = {};
        bool havePrevious = false;

        for (ai::int16 i = 0; i < count; ++i)
        {
            AIPathSegment segment;
            if (sAIPath->GetPathSegments(art, i, 1, &segment)) return false;
            if (i == 0) first = segment;
            if (havePrevious) AddCubic(box, previous.p, previous.out, segment.in, segment.p);
            else              box->AddPoint(segment.p.h, segment.p.v);
            previous = segment;
            havePrevious = true;
        }
        if (closed && count > 1) AddCubic(box, previous.p, previous.out, first.in, first.p);
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
