// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vixen420
//
// Shear for Illustrator is free software: you may redistribute it and/or
// modify it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version. It comes with ABSOLUTELY NO WARRANTY. See the
// file LICENSE, or <https://www.gnu.org/licenses/>, for the full text.
//
// Additional permission under GPL-3.0 section 7: this file may be combined with
// the Adobe Illustrator SDK, whose sample framework sources are compiled into
// every plugin built from it. See LICENSE-EXCEPTION.

//  ShearBounds.h -- the reference box the shear is taken about.
//
//  Illustrator's own Object > Transform > Shear anchors on the center of the
//  selection's GEOMETRIC bounds: the Bezier outline, with strokes, effects and
//  other appearance attributes excluded. That was measured, not assumed --
//  docs/evidence/anchor.tsv fits the anchor out of the artwork a native shear
//  actually produced, for fixtures whose geometric and visible centers lie far
//  apart, and every discriminating case comes back geometric.
//
//  Matching that inside a live effect is harder than asking for it, because the
//  art handed to a Go callback is not in the document tree and the host refuses
//  some bounds queries for it. So GeometricBounds tries the host first and, if
//  the host will not answer, computes the same box itself.

#ifndef __SHEARBOUNDS_H__
#define __SHEARBOUNDS_H__

#include "IllustratorSDK.h"

namespace shear
{
    /** Which route produced the bounds. Traced, and reported by the "bounds"
        script selector, so the choice is never a matter of belief. */
    enum BoundsRoute
    {
        kBoundsFailed = 0,
        kBoundsHostPrecise,   /**< GetPreciseArtTransformBounds, control bounds */
        kBoundsHost,          /**< GetArtTransformBounds, control bounds */
        kBoundsComputed,      /**< walked the art ourselves */
        kBoundsVisible        /**< last resort: visible bounds */
    };

    const char* BoundsRouteName(BoundsRoute route);

    /** Geometric bounds of art, by whichever route the host allows. Returns
        kBoundsFailed and leaves bounds untouched if none of them does. */
    BoundsRoute GeometricBounds(AIArtHandle art, AIRealRect* bounds);

    /** Geometric bounds by one named route, whether or not GeometricBounds
        would have chosen it. The point is testability: when the host answers
        the first route, the fallback that walks the art itself never runs, and
        code that never runs is code nobody has checked. The "bounds" script
        selector reports all of them side by side so the computed one can be
        held against the host's own answer. */
    bool BoundsByRoute(AIArtHandle art, BoundsRoute route, AIRealRect* bounds);

    /** Center of a rectangle, computed in double precision. */
    AIRealPoint CenterOf(const AIRealRect& r);
}

#endif // __SHEARBOUNDS_H__
