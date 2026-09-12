//  A stand-in for the Adobe SDK header, just large enough to compile the
//  plugin's pure-arithmetic headers outside Illustrator.
//
//  ShearMath.h and ShearCurve.h contain no host calls -- only the affine
//  algebra and the Bezier extremes -- but they include IllustratorSDK.h for
//  four small types. Putting this directory first on the include path lets a
//  standalone test compile the real headers, unmodified, against those four
//  types. Nothing here is a reimplementation of anything being tested.
//
//  The definitions match the SDK's: AIReal is a double in the Illustrator 2026
//  SDK, and AIRealRect is its AIDoubleRect, y-up with top above bottom.

#ifndef __ILLUSTRATORSDK_H_STUB__
#define __ILLUSTRATORSDK_H_STUB__

using AIReal = double;

struct AIRealPoint
{
    AIReal h = 0;
    AIReal v = 0;
};

struct AIRealRect
{
    AIReal left = 0;
    AIReal top = 0;
    AIReal right = 0;
    AIReal bottom = 0;
};

struct AIRealMatrix
{
    AIReal a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;
};

#endif // __ILLUSTRATORSDK_H_STUB__
