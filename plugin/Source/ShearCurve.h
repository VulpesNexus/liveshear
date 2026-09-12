//  ShearCurve.h -- the exact extent of a cubic Bezier, and a box to collect it
//  into. Pure arithmetic: no suites, no art handles, nothing that needs a
//  running Illustrator.
//
//  This is here rather than inside ShearBounds.cpp because it is the part of
//  the bounds fallback that only runs when the host refuses to measure the art
//  itself -- which, on the versions tested, it does not always do. Code that
//  only runs in a situation you cannot reliably create is code nobody has
//  checked, so it lives in a header that a standalone test can include against
//  a handful of stub types. See tools/mathtest.

#ifndef __SHEARCURVE_H__
#define __SHEARCURVE_H__

#include "IllustratorSDK.h"
#include <cmath>

namespace shear
{
    /** A growing bounding box in Illustrator's y-up artwork space: top is
        greater than bottom. Empty until the first point is added. */
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
            if (r.left > r.right || r.bottom > r.top) return;
            AddPoint(r.left, r.bottom);
            AddPoint(r.right, r.top);
        }
    };

    namespace detail
    {
        /** Adds the exact extent of one cubic Bezier along one axis.

            Sampling the four control points would overstate it: a curve stays
            inside its control hull but rarely touches it. The extremes are at
            the two ends and wherever the derivative -- a quadratic -- crosses
            zero strictly inside the span.

            The coordinate on the other axis is passed in and is always one of
            the segment's endpoints, which the caller has already added, so
            feeding it here widens only the axis being measured. */
        inline void AddCubicAxis(Box* box, bool vertical,
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
                if (vertical) box->AddPoint(other, value);
                else          box->AddPoint(value, other);
            }
        }
    }

    /** Adds the exact extent of one cubic Bezier segment to a box. */
    inline void AddCubic(Box* box,
                         const AIRealPoint& p0, const AIRealPoint& p1,
                         const AIRealPoint& p2, const AIRealPoint& p3)
    {
        box->AddPoint(p0.h, p0.v);
        box->AddPoint(p3.h, p3.v);
        detail::AddCubicAxis(box, false, p0.h, p1.h, p2.h, p3.h, p0.v);
        detail::AddCubicAxis(box, true,  p0.v, p1.v, p2.v, p3.v, p0.h);
    }
}

#endif // __SHEARCURVE_H__
