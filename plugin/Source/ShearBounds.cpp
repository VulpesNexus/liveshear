//  ShearBounds.cpp -- see ShearBounds.h.

#include "IllustratorSDK.h"
#include "ShearBounds.h"
#include "LiveShearSuites.h"
#include "ShearCurve.h"

#include <cmath>

namespace
{
    /** Strokes, effects, and the glyphs of area and path text excluded: the
        same box Illustrator's own transform commands take their reference
        point from.

        These three were chosen by asking the host what each combination
        returns rather than by reading the header, because the header is
        misleading about two of them. The table is in
        docs/evidence/bounds-flags.txt; the "bounds flags" script selector
        prints it for whatever is selected.

        kControlBounds must NOT be set. Combined with either of the other two
        it does not mean anything stricter -- it returns kBadParameterErr,
        error 1346458189. This was written as kControlBounds |
        kNoExtendedBounds, which is that error, so every call failed and the
        effect fell back to computing the box itself every single time. The
        release report explained those failures as the host declining to
        measure art outside the document tree. It was not: it was a bad
        parameter.

        kNoStrokeBounds must be set explicitly. The header says
        kNoExtendedBounds "implies kNoStrokeBounds"; it does not. On a mitered
        triangle, visible|noExtended still carries the 600 pt spike of the
        miter, and only visible|noStroke|noExtended gives the outline.

        With all three, GetArtTransformBounds returns exactly what Illustrator
        calls geometricBounds, on every fixture tried. */
    const ai::int32 kGeometricFlags = kVisibleBounds | kNoStrokeBounds | kNoExtendedBounds;

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
            // A clipping group is measured by its clip path alone, and nothing
            // else in it counts.
            //
            // This is worth spelling out because Illustrator contradicts
            // itself here and it cost a wrong answer. The geometric bounds the
            // host reports for a clipped group are the union of its children,
            // mask included; the shear command anchors somewhere else
            // entirely. Measured: an ellipse clipping a wider rectangle put
            // the native reference point 10 pt away in y and 20 pt in x from
            // the union's center, and exactly on the clip path's center both
            // times. The discriminating case is a clip path larger than what
            // it clips, where the mask's box and the visible result are not
            // the same rectangle -- and the native command follows the mask,
            // not the visible result (docs/evidence/artwork-anchor.txt).
            AIArtHandle child = nullptr;
            if (sAIArt->GetArtFirstChild(art, &child)) return;
            while (child != nullptr)
            {
                ai::int32 attr = 0;
                if (!sAIArt->GetArtUserAttr(child, kArtIsClipMask, &attr) &&
                    (attr & kArtIsClipMask) != 0)
                {
                    ComputeBounds(child, box, depth + 1);
                    return;
                }
                AIArtHandle next = nullptr;
                if (sAIArt->GetArtSibling(child, &next)) break;
                child = next;
            }

            // No mask: the union of the children, which is what an ordinary
            // group means.
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

    // Walking the art ourselves comes first, and deliberately.
    //
    // Asking the host for the whole tree is one call and it is the obvious
    // thing to do, but its answer is wrong for the one case where it matters:
    // for a clipping group it returns the union of the children, while the
    // shear command anchors on the clip path alone. The two differ by 10 pt on
    // the fixture here. The walk also measures paths from their segments, so a
    // curve's true extent is used rather than the hull of its control points.
    //
    // For everything the walk does not measure itself -- text, symbols,
    // rasters -- it asks the host one leaf at a time, with the same flags, and
    // gets the same answer the host would have given for the whole tree.
    Box box;
    ComputeBounds(art, &box, 0);
    if (box.any && !IsEmptyRect(box.rect))
    {
        *bounds = box.rect;
        return kBoundsComputed;
    }

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
