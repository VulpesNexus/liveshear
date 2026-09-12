//  mathtest.cpp -- the arithmetic under the Shear effect, checked without
//  Illustrator.
//
//  The host is the authority on everything this plugin does, and the release
//  suite measures it there. Two things still want a test that does not need a
//  running Illustrator.
//
//  The first is the Bezier extent code, which only runs when the host refuses
//  to measure the art itself. That refusal cannot be arranged on demand, so
//  without this the code would ship having never been exercised.
//
//  The second is the sanitizing of angles. It is easy to check by measurement
//  that 90 degrees comes out as 89; it is not easy to arrange for a NaN to
//  arrive from Illustrator, and a release must not depend on a defence nobody
//  has ever seen work.
//
//  The real headers are compiled here, unmodified, against a stub that
//  supplies the four SDK types they mention. Nothing is reimplemented.

#include "ShearMath.h"
#include "ShearCurve.h"

#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

namespace
{
    int gFailures = 0;
    int gChecks = 0;

    void Check(bool ok, const std::string& what, const std::string& detail = "")
    {
        ++gChecks;
        if (ok) return;
        ++gFailures;
        std::printf("FAIL  %s%s%s\n", what.c_str(),
                    detail.empty() ? "" : "  --  ", detail.c_str());
    }

    void Near(double got, double want, double tolerance, const std::string& what)
    {
        char detail[128];
        std::snprintf(detail, sizeof(detail), "got %.12g, wanted %.12g", got, want);
        Check(std::fabs(got - want) <= tolerance, what, detail);
    }

    AIRealPoint P(double h, double v)
    {
        AIRealPoint p;
        p.h = h;
        p.v = v;
        return p;
    }

    /** Where a cubic actually goes, by brute force. Ten thousand samples of a
        smooth curve bound it to well under a millionth of a point, which is
        far tighter than the exact solution needs to be checked to. */
    void SampleCubic(const AIRealPoint& p0, const AIRealPoint& p1,
                     const AIRealPoint& p2, const AIRealPoint& p3,
                     double* left, double* right, double* bottom, double* top)
    {
        *left = *right = p0.h;
        *bottom = *top = p0.v;
        const int steps = 100000;
        for (int i = 0; i <= steps; ++i)
        {
            const double t = static_cast<double>(i) / steps;
            const double u = 1.0 - t;
            const double x = u * u * u * p0.h + 3 * u * u * t * p1.h +
                             3 * u * t * t * p2.h + t * t * t * p3.h;
            const double y = u * u * u * p0.v + 3 * u * u * t * p1.v +
                             3 * u * t * t * p2.v + t * t * t * p3.v;
            if (x < *left)   *left = x;
            if (x > *right)  *right = x;
            if (y < *bottom) *bottom = y;
            if (y > *top)    *top = y;
        }
    }

    void CheckCubic(const char* name,
                    const AIRealPoint& p0, const AIRealPoint& p1,
                    const AIRealPoint& p2, const AIRealPoint& p3)
    {
        shear::Box box;
        shear::AddCubic(&box, p0, p1, p2, p3);

        double left = 0, right = 0, bottom = 0, top = 0;
        SampleCubic(p0, p1, p2, p3, &left, &right, &bottom, &top);

        const std::string what = std::string("cubic extent: ") + name;
        Check(box.any, what + " produced a box");
        // A hundred-thousandth of a point: far below what Illustrator draws,
        // and comfortably above what sampling a smooth curve can miss.
        Near(box.rect.left, left, 1e-5, what + ", left");
        Near(box.rect.right, right, 1e-5, what + ", right");
        Near(box.rect.bottom, bottom, 1e-5, what + ", bottom");
        Near(box.rect.top, top, 1e-5, what + ", top");

        // The exact answer can never be smaller than what sampling found.
        Check(box.rect.left <= left + 1e-9, what + " does not cut the curve off on the left");
        Check(box.rect.right >= right - 1e-9, what + " does not cut the curve off on the right");
        Check(box.rect.bottom <= bottom + 1e-9, what + " does not cut the curve off at the bottom");
        Check(box.rect.top >= top - 1e-9, what + " does not cut the curve off at the top");
    }
}

int main()
{
    std::printf("Shear arithmetic, without Illustrator\n\n");

    // ---- the box ---------------------------------------------------------
    {
        shear::Box box;
        Check(!box.any, "a new box is empty");
        box.AddPoint(10, 20);
        Check(box.any, "a box with one point is not empty");
        Near(box.rect.left, 10, 0, "one point: left");
        Near(box.rect.right, 10, 0, "one point: right");
        Near(box.rect.top, 20, 0, "one point: top");
        Near(box.rect.bottom, 20, 0, "one point: bottom");
        box.AddPoint(-5, 100);
        Near(box.rect.left, -5, 0, "two points: left");
        Near(box.rect.top, 100, 0, "two points: top, which is the larger y");
        Near(box.rect.bottom, 20, 0, "two points: bottom, which is the smaller y");
    }

    // ---- Bezier extents --------------------------------------------------
    // A straight segment, where the derivative never crosses zero inside the
    // span and the answer is just the endpoints.
    CheckCubic("a straight segment",
               P(0, 0), P(10, 10), P(20, 20), P(30, 30));

    // A curve that overshoots its endpoints in both directions: the control
    // hull would be far too large and the endpoints far too small.
    CheckCubic("an S with handles well outside",
               P(0, 0), P(200, 300), P(-150, -250), P(50, 20));

    // One extremum on each axis, the ordinary case in real artwork.
    CheckCubic("a quarter circle",
               P(0, 100), P(55.228, 100), P(100, 55.228), P(100, 0));

    // A cusp: both handles on the same point.
    CheckCubic("a cusp",
               P(0, 0), P(100, 0), P(100, 0), P(0, 0));

    // Degenerate: every control point identical.
    CheckCubic("a segment with no length",
               P(42, -17), P(42, -17), P(42, -17), P(42, -17));

    // Handles that make the derivative's quadratic degenerate to a line.
    CheckCubic("a parabola-like segment",
               P(0, 0), P(0, 100), P(100, 100), P(100, 0));

    // ---- shear angles ----------------------------------------------------
    {
        using shear::SanitizeShearAngle;
        Near(SanitizeShearAngle(0), 0, 0, "0 degrees stays 0");
        Near(SanitizeShearAngle(30), 30, 0, "30 degrees stays 30");
        Near(SanitizeShearAngle(-30), -30, 0, "-30 degrees stays -30");
        Near(SanitizeShearAngle(89), 89, 0, "89 degrees is allowed");
        Near(SanitizeShearAngle(-89), -89, 0, "-89 degrees is allowed");
        Near(SanitizeShearAngle(89.0000001), 89, 0, "just past 89 is clamped");
        Near(SanitizeShearAngle(90), 89, 0, "90 degrees is clamped to 89");
        Near(SanitizeShearAngle(-90), -89, 0, "-90 degrees is clamped to -89");
        Near(SanitizeShearAngle(1e300), 89, 0, "an enormous angle is clamped");
        Near(SanitizeShearAngle(std::numeric_limits<double>::infinity()), 89, 0,
             "infinity is clamped");
        Near(SanitizeShearAngle(-std::numeric_limits<double>::infinity()), -89, 0,
             "negative infinity is clamped");
        Near(SanitizeShearAngle(std::numeric_limits<double>::quiet_NaN()), 0, 0,
             "a NaN becomes zero rather than a pathological transform");
    }

    // ---- axis angles -----------------------------------------------------
    {
        using shear::SanitizeAxisAngle;
        Near(SanitizeAxisAngle(0), 0, 0, "axis 0 stays 0");
        Near(SanitizeAxisAngle(45), 45, 0, "axis 45 stays 45");
        Near(SanitizeAxisAngle(180), 180, 0, "axis 180 stays 180");
        Near(SanitizeAxisAngle(-180), 180, 0, "axis -180 wraps to 180");
        Near(SanitizeAxisAngle(200), -160, 1e-12, "axis 200 wraps to -160");
        Near(SanitizeAxisAngle(360), 0, 1e-12, "axis 360 wraps to 0");
        Near(SanitizeAxisAngle(-360), 0, 1e-12, "axis -360 wraps to 0");
        Near(SanitizeAxisAngle(725), 5, 1e-12, "axis 725 wraps to 5");
        Near(SanitizeAxisAngle(std::numeric_limits<double>::quiet_NaN()), 0, 0,
             "a NaN axis becomes zero");
        Near(SanitizeAxisAngle(std::numeric_limits<double>::infinity()), 0, 0,
             "an infinite axis becomes zero");
        Check(!std::signbit(SanitizeAxisAngle(-0.0)), "negative zero folds to zero");
    }

    // ---- axis interpolation ---------------------------------------------
    {
        using shear::InterpolateAxisAngle;

        // Any two axis angles 180 apart describe the same shear, so an
        // interpolated axis is only ever right or wrong modulo 180.
        auto SameAxis = [](double got, double want) {
            double d = std::fmod(got - want, 180.0);
            if (d > 90.0) d -= 180.0;
            if (d < -90.0) d += 180.0;
            return std::fabs(d) < 1e-9;
        };

        Near(InterpolateAxisAngle(0, 90, 0.5), 45, 1e-12, "halfway from 0 to 90 is 45");
        Near(InterpolateAxisAngle(10, 10, 0.5), 10, 1e-12, "no change stays put");
        Check(SameAxis(InterpolateAxisAngle(0, 90, 1.0), 90), "the end of the sweep is the end angle");
        Check(SameAxis(InterpolateAxisAngle(0, 90, 0.0), 0), "the start of the sweep is the start angle");

        // The case that separates the two ways of doing this. Axis 10 and axis
        // 170 are the same as axis 10 and axis -10, which are twenty degrees
        // apart; halfway between them is axis 0. Interpolating the numbers
        // naively would sweep a hundred and sixty degrees and land on 90,
        // which is the one axis perpendicular to both.
        const double mid = InterpolateAxisAngle(10, 170, 0.5);
        Check(SameAxis(mid, 0), "10 to 170 passes through 0, not through 90", std::to_string(mid));
        Check(!SameAxis(mid, 90), "and is not the naive midpoint", std::to_string(mid));

        // 170 to -170 is the same twenty degrees, the other way round.
        Check(SameAxis(InterpolateAxisAngle(170, -170, 0.5), 0),
              "170 to -170 also passes through 0",
              std::to_string(InterpolateAxisAngle(170, -170, 0.5)));

        // Whatever route it takes, it must arrive.
        for (int start = -170; start <= 170; start += 37)
        {
            for (int end = -170; end <= 170; end += 53)
            {
                char what[96];
                std::snprintf(what, sizeof(what), "interpolating %d to %d arrives", start, end);
                Check(SameAxis(InterpolateAxisAngle(start, end, 1.0), end), what,
                      std::to_string(InterpolateAxisAngle(start, end, 1.0)));
                // And never sweeps more than a quarter turn, since no two axes
                // are further apart than that.
                const double swept = std::fabs(InterpolateAxisAngle(start, end, 1.0) - start);
                std::snprintf(what, sizeof(what), "%d to %d sweeps at most 90 degrees", start, end);
                Check(swept <= 90.0 + 1e-9, what, std::to_string(swept));
            }
        }
    }

    // ---- the matrix ------------------------------------------------------
    {
        using shear::MatrixAboutOrigin;
        using shear::MatrixAbout;
        using shear::IsFiniteMatrix;

        const AIRealMatrix identity = MatrixAboutOrigin(0, 0);
        Near(identity.a, 1, 1e-15, "zero shear: a");
        Near(identity.b, 0, 1e-15, "zero shear: b");
        Near(identity.c, 0, 1e-15, "zero shear: c");
        Near(identity.d, 1, 1e-15, "zero shear: d");

        // Horizontal shear: x gains k times y, y is untouched.
        const double k = std::tan(30.0 * shear::kPi / 180.0);
        const AIRealMatrix h = MatrixAboutOrigin(30, 0);
        Near(h.a, 1, 1e-12, "horizontal shear: a");
        Near(h.b, 0, 1e-12, "horizontal shear: b");
        Near(h.c, k, 1e-12, "horizontal shear: c is tan(theta)");
        Near(h.d, 1, 1e-12, "horizontal shear: d");

        // Area is preserved for every angle and axis.
        for (int theta = -89; theta <= 89; theta += 7)
        {
            for (int phi = -180; phi <= 180; phi += 13)
            {
                const AIRealMatrix m = MatrixAboutOrigin(theta, phi);
                const double det = m.a * m.d - m.b * m.c;
                char what[96];
                std::snprintf(what, sizeof(what),
                              "determinant is 1 at shear %d, axis %d", theta, phi);
                Near(det, 1.0, 1e-9, what);
                Check(IsFiniteMatrix(m), std::string("matrix is finite at ") + what);
            }
        }

        // The anchor is a fixed point of the transform.
        for (int theta = -89; theta <= 89; theta += 11)
        {
            for (int phi = -180; phi <= 180; phi += 29)
            {
                const AIRealPoint anchor = P(137.5, -412.25);
                const AIRealMatrix m = MatrixAbout(theta, phi, anchor);
                const double x = m.a * anchor.h + m.c * anchor.v + m.tx;
                const double y = m.b * anchor.h + m.d * anchor.v + m.ty;
                char what[96];
                std::snprintf(what, sizeof(what),
                              "the anchor does not move at shear %d, axis %d", theta, phi);
                Near(x, anchor.h, 1e-9, std::string(what) + ", x");
                Near(y, anchor.v, 1e-9, std::string(what) + ", y");
            }
        }

        // An axis and that axis plus 180 degrees describe the same map, which
        // is what makes wrapping the stored value harmless.
        for (int theta = -80; theta <= 80; theta += 20)
        {
            for (int phi = -170; phi <= 0; phi += 17)
            {
                const AIRealMatrix a = MatrixAboutOrigin(theta, phi);
                const AIRealMatrix b = MatrixAboutOrigin(theta, phi + 180);
                char what[96];
                std::snprintf(what, sizeof(what),
                              "axis %d and axis %d agree at shear %d", phi, phi + 180, theta);
                Near(a.a, b.a, 1e-12, std::string(what) + ", a");
                Near(a.b, b.b, 1e-12, std::string(what) + ", b");
                Near(a.c, b.c, 1e-12, std::string(what) + ", c");
                Near(a.d, b.d, 1e-12, std::string(what) + ", d");
            }
        }

        // The worked example the report quotes: a 200 by 120 rectangle at
        // (100, 480) to (300, 600), sheared 30 degrees about its center.
        const AIRealMatrix m = MatrixAbout(30, 0, P(200, 540));
        const double leftAtBottom = m.a * 100 + m.c * 480 + m.tx;
        const double rightAtTop = m.a * 300 + m.c * 600 + m.tx;
        Near(leftAtBottom, 65.3589838486225, 1e-9,
             "the worked example: bottom-left corner");
        Near(rightAtTop, 334.641016151378, 1e-9,
             "the worked example: top-right corner");
    }

    // ---- the identity threshold -----------------------------------------
    {
        Check(shear::IsIdentity(0), "zero is the identity");
        Check(shear::IsIdentity(1e-9), "a billionth of a degree is the identity");
        Check(!shear::IsIdentity(1e-5), "a hundred-thousandth of a degree is not");
        Check(!shear::IsIdentity(-1e-5), "and neither is its negative");
    }

    std::printf("\n%d checks, %d failed\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
