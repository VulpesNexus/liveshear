//  ShearMath.h -- the affine algebra behind the Shear effect, and the one
//  place a shear angle is made safe.
//
//  Illustrator's AIRealMatrix is the PostScript convention:
//      x' = a*x + c*y + tx
//      y' = b*x + d*y + ty
//
//  A shear of angle theta along an axis at angle phi displaces points parallel
//  to the axis by an amount proportional to their signed perpendicular distance
//  from it, with k = tan(theta). In matrix form that is
//
//      M = R(phi) * Sh(k) * R(-phi)
//
//  with Sh(k) the axis-aligned shear [[1, k], [0, 1]]. Expanded:
//
//      a  = 1 - k*cos(phi)*sin(phi)      c = k*cos(phi)^2
//      b  = -k*sin(phi)^2                d = 1 + k*cos(phi)*sin(phi)
//
//  det(M) == 1 for every theta and phi, so shear preserves area.
//
//  Coordinates. Everything here works in Illustrator's artwork space, which is
//  y-up: in an AIRealRect, top is greater than bottom. The native shear
//  command's own dY parameter is measured the other way, downward, which is why
//  a positive "about dY" moves the anchor toward smaller y -- but that
//  convention belongs to the action's parameter block, not to the geometry, and
//  no sign is flipped anywhere below.

#ifndef __SHEARMATH_H__
#define __SHEARMATH_H__

#include "IllustratorSDK.h"
#include <cmath>

namespace shear
{
    const double kPi = 3.14159265358979323846;

    /** Largest shear angle the effect will ever hand to tan(). Illustrator
        itself becomes pathological as the angle approaches a right angle: a
        native shear of 89 degrees returns at once, while one of 89.9 degrees
        did not return at all in the host run that measured it. tan(89) is
        about 57, so a 100 pt object still becomes 5,700 pt wide -- well past
        anything anyone wants and still far inside Illustrator's coordinate
        range. See docs/evidence/limits.tsv. */
    const double kShearLimitDegrees = 89.0;

    /** Below this, the shear is treated as exactly nothing: tan(1e-6 degrees)
        is 1.7e-8, which over the largest artboard Illustrator allows moves a
        point by less than a millionth of a point. Returning early also means a
        zero-angle effect never calls TransformArt at all, so it cannot
        accumulate rounding from repeated evaluation. */
    const double kIdentityEpsilonDegrees = 1.0e-6;

    inline double Radians(double degrees) { return degrees * kPi / 180.0; }

    /** The one place a shear angle becomes safe to use, and the only one. Every
        route a value can arrive by -- the slider, the numeric field, a pasted
        or typed string, a parameter dictionary read back out of a saved
        document, another plugin writing the dictionary directly -- passes
        through here before it reaches tan().

        Anything that is not a finite number becomes zero rather than a
        pathological transform, and anything beyond the limit is clamped to it.
        Failing safe is deliberate: a document that somehow stores 90 degrees
        opens as a 89-degree shear, not as a hang. */
    inline double SanitizeShearAngle(double degrees)
    {
        if (!(degrees == degrees)) return 0.0;                 // NaN
        if (degrees > kShearLimitDegrees) return kShearLimitDegrees;
        if (degrees < -kShearLimitDegrees) return -kShearLimitDegrees;
        return degrees;
    }

    /** Wraps an axis angle into (-180, 180]. A shear along phi and one along
        phi + 180 are the same map -- the axis direction and its normal both
        flip, and their outer product does not -- so the wrap never changes what
        is rendered. It exists so that a value arriving from outside the
        slider's range still displays as something a person recognizes, and so
        that editing an effect repeatedly cannot walk the stored angle off to
        thousands of degrees. */
    inline double SanitizeAxisAngle(double degrees)
    {
        if (!(degrees == degrees)) return 0.0;                 // NaN
        if (degrees > 1.0e9 || degrees < -1.0e9) return 0.0;   // infinite, or absurd
        double wrapped = std::fmod(degrees, 360.0);
        if (wrapped > 180.0) wrapped -= 360.0;
        else if (wrapped <= -180.0) wrapped += 360.0;
        if (wrapped == 0.0) wrapped = 0.0;                     // fold -0.0 to 0.0
        return wrapped;
    }

    /** Interpolates between two axis angles along the shorter of the two ways
        round, treating them modulo 180 because that is the axis's true period.
        Interpolating 170 to -170 the naive way sweeps 340 degrees through zero
        and swings the artwork the wrong way across a blend; this sweeps the 10
        degrees that actually separate them. */
    inline double InterpolateAxisAngle(double start, double end, double t)
    {
        double delta = std::fmod(end - start, 180.0);
        if (delta > 90.0) delta -= 180.0;
        else if (delta < -90.0) delta += 180.0;
        return start + delta * t;
    }

    /** True when the parameters describe a transformation close enough to the
        identity that applying it would only add floating-point noise. */
    inline bool IsIdentity(double shearDegrees)
    {
        return std::fabs(shearDegrees) < kIdentityEpsilonDegrees;
    }

    /** Builds the shear matrix about the origin (0,0). The angles must already
        have been through SanitizeShearAngle and SanitizeAxisAngle. */
    inline AIRealMatrix MatrixAboutOrigin(double shearDegrees, double axisDegrees)
    {
        const double k = std::tan(Radians(shearDegrees));
        const double c = std::cos(Radians(axisDegrees));
        const double s = std::sin(Radians(axisDegrees));

        AIRealMatrix m;
        m.a  = static_cast<AIReal>(1.0 - k * c * s);
        m.b  = static_cast<AIReal>(-k * s * s);
        m.c  = static_cast<AIReal>(k * c * c);
        m.d  = static_cast<AIReal>(1.0 + k * c * s);
        m.tx = 0.0;
        m.ty = 0.0;
        return m;
    }

    /** Builds the shear matrix about an arbitrary anchor point:
        translate(-anchor), shear, translate(+anchor), pre-multiplied into the
        same six coefficients so a single TransformArt call does the whole job. */
    inline AIRealMatrix MatrixAbout(double shearDegrees, double axisDegrees,
                                    const AIRealPoint& anchor)
    {
        AIRealMatrix m = MatrixAboutOrigin(shearDegrees, axisDegrees);
        m.tx = anchor.h - (m.a * anchor.h + m.c * anchor.v);
        m.ty = anchor.v - (m.b * anchor.h + m.d * anchor.v);
        return m;
    }

    /** True when every coefficient of a matrix is a finite number. The last
        gate before TransformArt: sanitized angles cannot produce anything else,
        so a failure here means an assumption broke rather than that a user
        typed something odd. */
    inline bool IsFiniteMatrix(const AIRealMatrix& m)
    {
        const double values[6] = { m.a, m.b, m.c, m.d, m.tx, m.ty };
        for (int i = 0; i < 6; ++i)
        {
            const double v = values[i];
            if (!(v == v)) return false;
            if (v > 1.0e300 || v < -1.0e300) return false;
        }
        return true;
    }
}

#endif // __SHEARMATH_H__
