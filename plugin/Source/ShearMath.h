//  ShearMath.h -- the affine algebra behind the Shear effect.
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

#ifndef __SHEARMATH_H__
#define __SHEARMATH_H__

#include "IllustratorSDK.h"
#include <cmath>

namespace shear
{
    const double kPi = 3.14159265358979323846;

    inline double Radians(double degrees) { return degrees * kPi / 180.0; }

    /** Builds the shear matrix about the origin (0,0). */
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

    /** True when the parameters describe a transformation close enough to the
        identity that applying it would only add floating-point noise. */
    inline bool IsIdentity(double shearDegrees)
    {
        return std::fabs(shearDegrees) < 1.0e-6;
    }
}

#endif // __SHEARMATH_H__
